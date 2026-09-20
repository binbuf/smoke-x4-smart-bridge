/// A24.1 — the shell's live session (design 13 §13.3.2-§13.3.3).
///
/// The four tabs share **one** connection and **one** [BridgeSession]: the race
/// runs once at boot, not once per tab, so switching Cook → History → Bridge
/// never re-dials the bridge and every tab reads the same immutable
/// [DashboardSnapshot]. This is the object `dashboard_route.dart` and
/// `cook_preview_route.dart` each stood up privately; the shell hoists it to a
/// single [ChangeNotifier] the whole tree listens to.
///
/// It boots exactly like those routes did (`AppEnv.newConnection().start()` →
/// `BridgeSession`), exposes the latest snapshot, the [LaunchState], a computed
/// [ProbeFreshness] (the freshness ladder lifted verbatim from
/// `cook_preview_route.dart:106`), and a [control] passthrough — including
/// [ackAlarm], so the shared [AlarmBar] can silence the ringing alarm from any
/// tab without a tab change (§13.3.3).
///
/// The `AppEnv`-null path is a first-class outcome, not an error: a bare widget
/// test mounts the shell with no environment, and [start] then no-ops, leaving
/// the shell in its `LaunchConnecting` (or seeded) state rather than throwing.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../app/app_env.dart';
import '../../app/bridge_session.dart';
import '../../app/connection.dart';
import '../../app/connection_supervisor.dart';
import '../../data/dto/dto.dart' as dto;
import '../../data/repos/cook_repository.dart';
import '../../data/repos/repositories.dart';
import '../../data/transport/ble_transport.dart'
    show BleTransport, BridgeControlException, BridgeUnsupportedException;
import '../../data/transport/bridge_transport.dart';
import '../../data/transport/http_transport.dart' show BridgeApiException;
import '../../domain/plan/plan.dart';
import '../../domain/situation/situation.dart';
import '../../features/dashboard/dashboard_snapshot.dart';
import '../../ui/probe/probe_freshness.dart';
import 'situation_probe_platform.dart';
import 'situation_resolver.dart';

/// A26 — why the last pull-to-refresh could not produce a new reading.
///
/// A refresh that fails **must say so**. Leaving the previous number on screen
/// is indistinguishable from a successful refresh that found nothing new, and
/// on this app the difference is "your brisket is at 165 °F" versus "your
/// brisket was at 165 °F an hour ago and the bridge has been off since".
///
/// [notConnected] separates the two failures that need different words and a
/// different action: the bridge was never reached (retry, check power/range)
/// versus it answered and then refused or stalled (wait, try again).
@immutable
class RefreshFailure {
  const RefreshFailure({
    required this.title,
    required this.detail,
    this.notConnected = false,
  });

  final String title;
  final String detail;
  final bool notConnected;
}

class ShellSession extends ChangeNotifier {
  /// The production session: reads the ambient [AppEnv] and boots on [start].
  ///
  /// The stored cook plan is read **in the constructor**, not in [start]:
  /// the shell picks instrument-versus-guided on its very first frame, and a
  /// plan that landed one await later would render the wrong mode and snap.
  ShellSession({AppEnv? env, int Function()? now, SituationProbe? probe})
    : _env = env ?? AppEnv.instance,
      _now = now ?? _wallClock,
      // A named parameter cannot be a private initializing formal, and the
      // field is private because only the resolver build reads it.
      // ignore: prefer_initializing_formals
      _probe = probe,
      _seededCelsius = false {
    _plan = _readStoredPlan();
    _startAgeTicker();
  }

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  /// Test seam: a session that never boots, pre-loaded with a snapshot and a
  /// launch state. `start()` is a no-op, so no radio, socket or database is
  /// touched and the shell renders the seeded truth immediately.
  ShellSession.seeded({
    DashboardSnapshot? snapshot,
    LaunchState launch = const LaunchConnecting(),
    CookPlan? plan,
    bool celsius = false,
    int Function()? now,
    SituationResolver? resolver,
  }) : _env = null,
       _now = now ?? _wallClock,
       _probe = null,
       _booted = true,
       _seededCelsius = celsius {
    _snapshot = snapshot;
    _launch = launch;
    _plan = plan;
    // A seeded session never boots, so nothing would build one — a test that
    // wants to drive the reader's banner hands one in already wired to its
    // own fake probe and shell.
    _resolver = resolver?..addListener(_onSituation);
  }

  final AppEnv? _env;

  /// Injected by tests that want a known phone (radio off, permission
  /// missing, a bond present). Null in production, where the resolver takes
  /// the real platform probe.
  final SituationProbe? _probe;

  /// The wall clock the freshness ladder ages against. Injectable so a test
  /// can assert a rung without sleeping for it.
  final int Function() _now;

  /// Re-notifies listeners so ages advance with no new data.
  ///
  /// Staleness is the one piece of state that becomes true by the passage of
  /// time rather than by an event, so nothing else will ever wake the screen
  /// to say so: when a bridge goes quiet, the *absence* of packets is the
  /// signal, and an absence fires no callback. Without this the veil only
  /// ever appeared on the next reading — which is exactly the reading that
  /// would have made it unnecessary.
  ///
  /// 15 s keeps every rung of the ladder (45 s / 90 s / 600 s) accurate to
  /// well within its own resolution, at one no-op rebuild per quarter minute.
  Timer? _ageTicker;
  static const Duration _agePulse = Duration(seconds: 15);

  void _startAgeTicker() {
    _ageTicker = Timer.periodic(_agePulse, (_) {
      if (_disposed) {
        return;
      }
      notifyListeners();
      // §16.3 #11: an unreachable bridge "keeps trying, and says so". The
      // resolver is otherwise only driven by a link change — and while the
      // bridge is off, the link never changes, so the auto-retry fired once
      // and then sat there. Every other pulse (30 s) it re-reconciles, which
      // is also what keeps "last seen 12 minutes ago" counting up.
      _agePulses++;
      if (_agePulses.isEven && !situation.isHealthy) {
        unawaited(reconcile());
      }
    });
  }

  AppConnection? _connection;
  ConnectionSupervisor? _supervisor;
  BridgeSession? _session;
  StreamSubscription<DashboardSnapshot>? _sub;
  StreamSubscription<LiveLink>? _linkSub;

  LaunchState _launch = const LaunchConnecting();
  DashboardSnapshot? _snapshot;
  LiveLink? _liveLink;
  bool _booted = false;
  bool _disposed = false;

  /// True when nothing was ever remembered — so an all-lanes-fail boot means
  /// "needs onboarding", not "a known bridge is off" (A9.5).
  bool _neverMet = false;

  /// The newest link from the supervisor, applied one-at-a-time so
  /// [BridgeSession.start] finishes before a [BridgeSession.switchTransport]
  /// (a BLE→Wi-Fi upgrade that lands during boot) touches the same streams.
  LiveLink? _pendingLink;
  bool _applyingLink = false;

  LaunchState get launch => _launch;
  DashboardSnapshot? get snapshot => _snapshot;

  // ── reconciliation (16 §16.3) ────────────────────────────────────────
  //
  // One resolver, owned by the shell, for the whole app.
  //
  // It used to be built inside `BridgeTab.initState`, which meant the entire
  // recovery layer only existed while the Device tab was on screen. Branches
  // of a `StatefulShellRoute` are not preloaded, so on launch — and forever,
  // for anyone who never tapped Device — no OS fact was ever gathered and no
  // automatic remedy ever ran. `/live` fell back to a weaker reconciler that
  // could only diagnose, and every mismatch in the world still collapsed into
  // "Offline · retry 6". That is the bug 16 §16.3 opens by naming.
  //
  // Living here it starts with the app, survives every tab switch, and gives
  // `/live` and `/device` the *same* situation — which §16.3 requires, and
  // which two separate engines could never guarantee.

  SituationResolver? _resolver;

  /// The resolver, or null on a seeded session that was given no probe.
  SituationResolver? get situationResolver => _resolver;

  /// The one situation, highest-priority first. [Situation.ok] before the
  /// first reconciliation, and on a test session with no resolver.
  Situation get situation => _resolver?.situation ?? Situation.ok;

  /// When this phone last actually reached the bridge, from the store.
  ///
  /// The store rather than the snapshot, because this is wanted exactly when
  /// no snapshot is arriving. §16.3: *"can't reach it" is a state; "can't
  /// reach it, last seen 12 minutes ago" is information.*
  int? get lastSeenUnixMs => _connection?.prefs.lastSeenUnixMs ?? _env?.prefs.lastSeenUnixMs;

  /// Which reconciliation tick we are on, so the unhealthy re-check runs at
  /// half the age ticker's rate rather than every pulse.
  int _agePulses = 0;

  /// The device's own answer about its network, over whichever lane is up.
  ///
  /// Wi-Fi already carries it in the snapshot. **Bluetooth is the case that
  /// matters**: `net_status` is readable over GATT, so a bridge that failed
  /// to join your Wi-Fi and came up hosting its own can say so on the only
  /// lane that can still reach it. This is the read that ends the bench
  /// failure §16.3 was written from.
  Future<({String? mode, String? ssid})> _readDeviceNetStatus() async {
    final t = _session?.transport;
    String? mode;
    String? ssid;
    if (t is BleTransport) {
      try {
        final net = await t.readNetStatus();
        ssid = net.ssid;
        mode = switch (net.modeEnum) {
          dto.NetMode.ap => 'ap',
          dto.NetMode.sta => 'sta',
          // `off` is the radio down, which is neither of the two modes a user
          // picks between — so it stays unknown rather than being rounded.
          dto.NetMode.off || null => null,
        };
      } on Object {
        mode = null;
      }
    }
    return (mode: mode ?? _snapshot?.netMode, ssid: ssid);
  }

  /// The bridge the running cook was recorded against.
  ///
  /// Read off the annotation itself rather than off what the phone currently
  /// remembers, because the two diverging is precisely the condition
  /// [SituationKind.staleCook] reports: adopting a different bridge moves the
  /// remembered id and leaves the cook where it was.
  Future<String?> _runningCookBridgeId() async {
    if (_plan == null) {
      return null;
    }
    try {
      return (await runningCook())?.bridgeId;
    } on Object {
      return null;
    }
  }

  /// Race every lane again. True when a link came up.
  Future<bool> retryNow() async {
    final supervisor = _supervisor;
    if (supervisor == null) {
      return false;
    }
    return supervisor.retryNow();
  }

  /// Reconcile now. Safe to call at any time; the resolver coalesces.
  Future<void> reconcile() async {
    final r = _resolver;
    if (r == null || _disposed) {
      return;
    }
    await r.evaluate();
  }

  // ── the guided cook (13 §13.3.1) ─────────────────────────────────────

  CookPlan? _plan;

  /// Only consulted on a seeded (test) session, which has no [AppEnv] to read
  /// the real preference from.
  final bool _seededCelsius;

  /// The running guided cook, or null for instrument mode. Survives a process
  /// death: it is read from prefs in the constructor and written on every
  /// change, so an OS kill at hour nine of an eighteen-hour brisket comes back
  /// to the same gauges rather than silently to instrument mode.
  CookPlan? get plan => _plan;

  /// Whether to render temperatures in °C. Read from the one pref the setup
  /// flow already writes (`finish_screens.dart`) so a user who picked Celsius
  /// gets Celsius everywhere the shell feeds, not only on the bridge's OLED.
  bool get celsius =>
      _env == null ? _seededCelsius : _env.prefs.displayUnits == 'C';

  CookPlan? _readStoredPlan() {
    final raw = _env?.prefs.cookPlanJson;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?>
          ? CookPlan.fromJson(decoded)
          : null;
    } on Object {
      return null; // unreadable → instrument mode, never a failed launch
    }
  }

  /// Start, replace, or end the guided cook. Null ends it.
  ///
  /// **Prefs is a first-frame cache, not the truth.** The truth is the `cooks`
  /// row (§D.1) — that is what History reads, what backdating edits and what
  /// survives a reinstall of the running plan. Prefs keeps its copy because
  /// the shell has to pick instrument-versus-guided on its *very first frame*,
  /// and a database read one await later would render the wrong mode and snap.
  Future<void> setPlan(CookPlan? plan) async {
    _plan = plan;
    notifyListeners();
    await _env?.prefs.setCookPlanJson(
      plan == null ? null : jsonEncode(plan.toJson()),
    );
  }

  /// The cook-annotation repository for the bridge this session is talking to,
  /// or null before one is known.
  CookRepository? get cookRepo {
    final env = _env;
    final id = _bridgeId;
    if (env == null || id == null) {
      return null;
    }
    return _cookRepo ??= CookRepository(env.db, bridgeId: id);
  }

  CookRepository? _cookRepo;
  String? _bridgeId;

  /// §D.1 — start a cook. Writes the annotation **and** the first-frame cache.
  ///
  /// Reuses the running row when the plan already carries a `cookId`, so
  /// editing a running cook retargets it rather than starting a second one
  /// over the same readings.
  Future<void> startCook(CookPlan plan) async {
    await _ensureBridgeId();
    final repo = cookRepo;
    if (repo != null) {
      try {
        final saved = await repo.startFromPlan(plan);
        plan.cookId = saved.id;
      } on Object {
        // The annotation could not be written (no cache yet, a locked
        // database). The guided overlay still runs from prefs — degrading to
        // the old behaviour is far better than refusing to start a cook.
      }
    }
    await setPlan(plan);
  }

  /// §D.1 — end the annotation. **The bridge keeps recording**, and the cook
  /// stays in History where it can be renamed, backdated or reopened.
  Future<void> endCook() async {
    final repo = cookRepo;
    final id = _plan?.cookId;
    if (repo != null && id != null) {
      try {
        final cook = await repo.cook(id);
        if (cook != null) {
          await repo.end(cook);
        }
      } on Object {
        // Same reasoning as startCook: the on-screen state must still change.
      }
    }
    await setPlan(null);
  }

  /// §D.5 — the user says the food came off the heat. The one input the phase
  /// engine may not infer.
  Future<void> markPulled() async {
    final repo = cookRepo;
    final id = _plan?.cookId;
    if (repo == null || id == null) {
      return;
    }
    final cook = await repo.cook(id);
    if (cook != null) {
      await repo.markPulled(cook);
      notifyListeners();
    }
  }

  /// The running annotation, for screens that need more than the plan carries
  /// (notes, favourite, the pull time). Null when there is no cook or no cache.
  Future<CookAnnotation?> runningCook() async {
    await _ensureBridgeId();
    final id = _plan?.cookId;
    if (id != null) {
      return cookRepo?.cook(id);
    }
    return cookRepo?.running();
  }

  Future<void> _ensureBridgeId() async {
    _bridgeId ??= await _env?.db.sessionDao.knownBridgeId();
  }

  /// The supervisor's latest link, for the header chip's live health: which
  /// transport, whether it is degraded (on BLE), and the background-upgrade
  /// retry count. Null before the first link (or with no environment).
  LiveLink? get liveLink => _liveLink;

  /// The active bridge session, or null before it connects. Exposed so a tab
  /// that needs the cache repositories (History's export) can reach them.
  BridgeSession? get bridge => _session;

  /// Freshness from how long ago the reading on screen actually reached this
  /// phone (13 §13.6.1), so a stale reading is visibly stale rather than a
  /// frozen number under a green chip.
  ///
  /// **This is a getter, not a stored value, on purpose.** It is recomputed
  /// against the wall clock every time it is read, so a screen nobody is
  /// pushing data to still ages: the veil arrives on its own, without needing
  /// a packet to arrive first. [ShellSession] runs a ticker so the frame
  /// showing it keeps up.
  ///
  /// It deliberately does not use the device's `last_packet_s_ago`. That
  /// counter measures the *base station's* silence, not ours; it is re-read
  /// only when an alarm, session or pairing frame happens to arrive, so a
  /// quiet fourteen-hour cook would read it once and call the screen live for
  /// the duration; and the BLE lane has no `/status` to carry it at all,
  /// where the old code read absent age as *live*. Absent is now unknown.
  ProbeFreshness get freshness {
    final s = _snapshot;
    if (s == null) {
      return ProbeFreshness.unknown;
    }
    // The bridge itself says the base station went quiet. That outranks our
    // own arithmetic: we may be hearing the bridge perfectly and still be
    // looking at numbers no longer being measured.
    if (s.baseLost) {
      return ProbeFreshness.frozen;
    }
    final at = s.readingAtUnixMs;
    if (at == null) {
      return ProbeFreshness.unknown;
    }
    final ageS = (_now() - at) ~/ 1000;
    if (ageS <= 45) return ProbeFreshness.live;
    if (ageS <= 90) return ProbeFreshness.aging;
    if (ageS <= 600) return ProbeFreshness.stale;
    return ProbeFreshness.frozen;
  }

  /// Boots the connection supervisor once (05 §5.7): lead with Bluetooth,
  /// upgrade to Wi-Fi, hold BLE as a warm standby, fail over seamlessly. Safe
  /// to call repeatedly (guarded) and safe with no environment (returns,
  /// leaving the current state).
  Future<void> start() async {
    if (_booted) {
      return;
    }
    _booted = true;
    final env = _env;
    if (env == null) {
      return; // not bootstrapped (a bare widget test) — wait, do not throw
    }
    final connection = env.newConnection();
    _connection = connection;
    // A25: "met a bridge" means ANY lane — a Bluetooth-only setup has no base
    // URL, and keying this on the URL alone bounced those users back into
    // onboarding on every launch (the board-found setup loop).
    _neverMet = !connection.prefs.hasBridge;
    // The reader renders from drift *before* a lane is raced, not after
    // (§B.3). A `BridgeSession` is only built once the supervisor yields a
    // transport, so waiting for one meant an out-of-range cold start showed
    // four dashes and "No readings yet." over a database holding fourteen
    // hours of the cook.
    await _renderFromCache();
    final supervisor = ConnectionSupervisor(connection: connection);
    _supervisor = supervisor;
    _resolver = SituationResolver(
      prefs: connection.prefs,
      probe: _probe ?? DeferredSituationProbe(PlatformSituationProbe.create()),
      shell: LiveSituationShell(
        snapshotOf: () => _snapshot,
        transportOf: () => _session?.transport,
        runningCook: () => _plan != null,
        cookBridgeOf: _runningCookBridgeId,
        netStatusOf: _readDeviceNetStatus,
        onRetry: retryNow,
      ),
    )..addListener(_onSituation);
    // Subscribe before starting so no link update is missed.
    _linkSub = supervisor.links.listen(_onLink);
    await supervisor.start();
  }

  void _onSituation() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// §B.3's first frame: the reader's real layout, filled from drift, before
  /// any lane has been raced.
  ///
  /// The values are the last ones this phone stored and they are dated by
  /// [SampleDao.newestUnixMs], so a six-minute-old reading arrives already
  /// wearing its age and a fourteen-hour-old one arrives frozen. The link is
  /// [LinkKind.offline] because at this instant it genuinely is — the race
  /// has not started — and the first real snapshot replaces this wholesale a
  /// moment later.
  ///
  /// Probe *names* are not cached, so the jacks read "Probe 1"…"Probe 4" until
  /// a lane answers. That is a known, honest degradation: the contract is that
  /// the temperatures are on screen instantly, not that every label is.
  ///
  /// Never throws. A cold start that cannot read drift still gets the shell.
  Future<void> _renderFromCache() async {
    if (_snapshot != null) {
      return;
    }
    try {
      final db = _env?.db;
      if (db == null) {
        return;
      }
      final bridgeId = await db.sessionDao.knownBridgeId();
      if (bridgeId == null || bridgeId.isEmpty) {
        return; // nothing was ever recorded — the empty state is the truth
      }
      final repo = SessionRepository(db, bridgeId: bridgeId);
      final sessions = await repo.sessions();
      final newest = sessions.firstOrNull;
      if (newest == null) {
        return;
      }
      final samples = await repo.samples(newest.id);
      if (samples.isEmpty) {
        return;
      }
      if (_disposed || _snapshot != null) {
        return; // a lane won the race while drift was reading — it wins
      }
      _snapshot = buildDashboard(
        status: null,
        live: null,
        history: samples,
        link: LinkKind.offline,
        marks: await repo.marks(newest.id),
        session: newest,
        readingAtUnixMs: await db.sampleDao.newestUnixMs(bridgeId),
      );
      notifyListeners();
    } on Object {
      // Drift is unavailable or mid-migration. The shell renders its empty
      // state, which is the same thing this method would have produced.
    }
  }

  /// The supervisor changed the active transport (first connect, a Wi-Fi
  /// upgrade, a failover, or offline). Coalesce to the newest and apply one at
  /// a time.
  void _onLink(LiveLink link) {
    if (_disposed) {
      return;
    }
    _pendingLink = link;
    unawaited(_applyPendingLink());
  }

  Future<void> _applyPendingLink() async {
    if (_applyingLink) {
      return; // a run is in flight; it will pick up [_pendingLink]
    }
    _applyingLink = true;
    try {
      while (!_disposed) {
        final link = _pendingLink;
        if (link == null) {
          break;
        }
        _pendingLink = null;
        await _handleLink(link);
      }
    } finally {
      _applyingLink = false;
    }
    // The link settled — coming up, going down, or swapping lanes. Every one
    // of those changes the answer to "what is actually wrong?", so reconcile
    // once here rather than leaving it to whichever screen happens to be
    // mounted. Deliberately after the loop, so a burst of supervisor updates
    // reconciles once at the end instead of once per step.
    unawaited(reconcile());
  }

  Future<void> _handleLink(LiveLink link) async {
    _liveLink = link;
    final t = link.transport;
    if (t != null) {
      // A "not connected" banner over a screen that just reconnected is its
      // own lie — the link coming back retires the last failure.
      _refreshFailure = null;
    }
    // The supervisor re-emits on every health change — upgrade retries, the
    // attempt counter, degraded/upgrading flips — usually with the SAME
    // transport. Those are chip updates, not switches: rebinding the session
    // (status read + delta sync + cache reload) on every backoff tick would
    // churn the radio and the battery for nothing.
    if (t != null && identical(t, _session?.transport)) {
      _launch = LaunchConnected(
        transport: t,
        link: link.link,
        address: link.address,
      );
      notifyListeners();
      return;
    }
    if (t == null) {
      // Offline — the cache still renders. Onboarding only when nothing was
      // ever remembered and no session was ever built.
      _launch = _neverMet && _session == null
          ? const LaunchNeedsOnboarding()
          : const LaunchOffline();
      // Say so in the snapshot too, not just in the launch state. The chip,
      // the pulse dot and every control that asks "is there a link?" read
      // `snapshot.link`; leaving it on its last value is how a screen ends up
      // claiming live Wi-Fi with a breathing dot while the masthead beside it
      // says the bridge cannot be reached.
      final last = _snapshot;
      if (last != null && last.link != LinkKind.offline) {
        _snapshot = last.disconnected();
      }
      notifyListeners();
      return;
    }
    _launch = LaunchConnected(
      transport: t,
      link: link.link,
      address: link.address,
    );
    final existing = _session;
    if (existing == null) {
      final session = BridgeSession(
        db: _env!.db,
        transport: t,
        link: link.link,
        address: link.address,
        // The supervisor owns every transport's lifecycle and holds the BLE
        // standby, so the session must neither close a swapped-out link nor
        // close its transport on dispose.
        onLinkLost: _supervisor!.reportLinkLost,
        ownsTransport: false,
      );
      _session = session;
      _sub = session.snapshots.listen((s) {
        if (_disposed) {
          return;
        }
        _snapshot = s;
        notifyListeners();
      });
      notifyListeners();
      await session.start();
    } else {
      notifyListeners();
      await existing.switchTransport(
        t,
        link: link.link,
        address: link.address,
        closeOld: link.closePrevious,
      );
    }
  }

  // ── pull-to-refresh (A26, 13 §13.5.2) ────────────────────────────────

  bool _refreshing = false;
  RefreshFailure? _refreshFailure;

  /// True while a pull is in flight. The [RefreshIndicator] owns its own
  /// spinner; this exists so the banner can say "trying again…" instead of
  /// leaving the previous failure on screen while we work.
  bool get refreshing => _refreshing;

  /// The last pull's failure, or null when the last one worked (or none has
  /// run). Cleared automatically the moment a link comes back — a stale
  /// "not connected" over a live screen is its own lie.
  RefreshFailure? get refreshFailure => _refreshFailure;

  void dismissRefreshFailure() {
    if (_refreshFailure != null) {
      _refreshFailure = null;
      notifyListeners();
    }
  }

  /// The gesture: **get a new value from the unit**, or say why not.
  ///
  /// Disconnected, it is a reconnect first ([ConnectionSupervisor.retryNow] —
  /// both radios, no backoff wait) and only then a read. Connected, it goes
  /// straight to [BridgeSession.refreshNow], whose throw becomes the banner.
  ///
  /// Never throws: the caller is a [RefreshIndicator], whose future ending in
  /// an error would leave the spinner spinning forever.
  Future<void> refresh() async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    _refreshFailure = null;
    notifyListeners();
    try {
      await _refreshOnce();
    } on Object catch (e) {
      _refreshFailure = _classify(e);
    } finally {
      _refreshing = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> _refreshOnce() async {
    if (_session == null || (_liveLink?.offline ?? true)) {
      final supervisor = _supervisor;
      final up = supervisor == null ? false : await supervisor.retryNow();
      if (!up) {
        _refreshFailure = const RefreshFailure(
          title: 'Not connected',
          detail:
              'Couldn’t reach your bridge. Check it is powered on and in '
              'range — the app keeps trying on its own.',
          notConnected: true,
        );
        return;
      }
      // The link is up but [_handleLink] builds/rebinds the session on its
      // own turn. That path already reads status, history and live, so
      // there is nothing left for this pull to ask for.
      if (_session == null) {
        return;
      }
    }
    try {
      await _session!.refreshNow();
    } on Object catch (e) {
      _refreshFailure = _classify(e);
    }
  }

  /// Failures the user can act on get their own words; everything else gets
  /// one honest sentence rather than a stack trace or an error code.
  RefreshFailure _classify(Object e) => switch (e) {
    BridgeApiException(:final message, :final code) => RefreshFailure(
      title: 'The bridge refused',
      detail: message.isEmpty ? code : message,
    ),
    BridgeControlException(:final detail) => RefreshFailure(
      title: 'The bridge refused',
      detail: detail.isEmpty ? 'It could not answer that right now.' : detail,
    ),
    BridgeUnsupportedException(:final what) => RefreshFailure(
      title: 'Not over Bluetooth',
      detail:
          '$what needs Wi-Fi. Connect the bridge to your network for the '
          'full picture.',
    ),
    TimeoutException() => const RefreshFailure(
      title: 'The bridge didn’t answer',
      detail: 'It is there but slow to reply. Try again in a moment.',
    ),
    _ => const RefreshFailure(
      title: 'Couldn’t refresh',
      detail:
          'The bridge stopped answering. The app keeps trying and reconnects '
          'on its own.',
      notConnected: true,
    ),
  };

  /// Passes a control command to the device and refreshes status. A no-op
  /// before the session connects (an offline tab has nothing to command).
  Future<void> control(ControlCommand cmd) async {
    await _session?.control(cmd);
  }

  /// Acknowledge the ringing alarm — the one call the shared [AlarmBar] needs.
  Future<void> ackAlarm(int alarmId) =>
      control(ControlCommand.ackAlarm(alarmId: alarmId));

  /// The connection-sheet controls (05 §5.7). Reads fall back to the defaults
  /// before boot; writes persist the choice and apply the safe, instant part
  /// live through the supervisor.
  PreferredTransport get preferredTransport =>
      _connection?.prefs.preferredTransport ?? PreferredTransport.auto;

  bool get holdBleWhenOnWifi => _connection?.prefs.holdBleWhenOnWifi ?? true;

  Future<void> setPreferredTransport(PreferredTransport t) async {
    await _connection?.prefs.setPreferredTransport(t);
    _supervisor?.applyPreference(t);
    notifyListeners();
  }

  Future<void> setHoldBleWhenOnWifi(bool value) async {
    await _connection?.prefs.setHoldBleWhenOnWifi(value);
    _supervisor?.applyHoldBle(value);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ageTicker?.cancel();
    _resolver
      ?..removeListener(_onSituation)
      ..dispose();
    unawaited(_linkSub?.cancel());
    unawaited(_sub?.cancel());
    // Session first (cancels its event subscriptions), then the supervisor
    // (closes the active + standby transports), then the connection.
    unawaited(_session?.dispose());
    unawaited(_supervisor?.dispose());
    unawaited(_connection?.dispose());
    super.dispose();
  }
}
