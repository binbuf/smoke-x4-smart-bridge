/// `/device` — "Is my bridge healthy, and how do I control it?" (design 16
/// §16.6, newapp §C.5).
///
/// **The lead card IS the situation.** That is the whole of this rebuild. The
/// app has always had a connection *supervisor* that reconnects; what it never
/// had was a layer that **reconciles** — that compares what the phone
/// remembers against what it can observe and what the device says when
/// reached, and turns the difference into a named cause with a remedy. Without
/// one, every mismatch in the world collapsed into "Offline · retry 6": on the
/// bench, a reflashed bridge came up hosting its own network and the app — which
/// knew its Bluetooth bond, its device id and its last address — sat on a retry
/// counter indefinitely, telling the user nothing and doing nothing.
///
/// So this screen leads with [SituationCard], fed by [SituationResolver], and
/// the rule underneath it is §16.3's: **act, then report.** Anything the app
/// can fix, it fixes — re-learning a moved address, adopting a bridge the phone
/// forgot but is still bonded to, setting the clock, retrying — and the card
/// then says what was done, in the past tense. It never offers to do something
/// it could simply have done. The one exception is identity: a bridge that has
/// been reset is never adopted automatically, because attaching a phone's
/// history to a device that did not record it is not the app's decision to
/// make.
///
/// Below the lead card, in §C.5's order: how it connects (§E.1's three plain
/// choices, switched through §E.3's rollback wizard), the bridge's own facts,
/// the way in to alarms and every settings page, and the four disruptive verbs
/// — each still behind a cost sheet that spells out what it keeps and what it
/// loses, and each still verified by watching the bridge actually go down.
///
/// **Never a wall of dashes.** A phone that has never met a bridge gets one
/// card and one action; a bridge that cannot be reached says when it was last
/// seen rather than showing a page of "—" where facts used to be.
///
/// **Signal (A26), unchanged.** Two hops, never conflated: only Bluetooth can
/// measure phone↔bridge, only the bridge can measure bridge↔router, and on the
/// bridge's own network neither end can see the other's radio — so that state
/// says so and shows the client count instead of inventing bars. The rows poll
/// only while this tab is the visible one.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'connection_mode_card.dart';
import 'netmode_sheet.dart';
import 'situation_card.dart';
import 'verb_progress.dart';

import '../../app/app_env.dart';
import '../../app/router.dart';
import '../../core/core.dart';
import '../../data/dto/dto.dart' as dto;
import '../../data/prefs/bridge_prefs.dart';
import '../../data/transport/ble_transport.dart' show BleTransport;
import '../../data/transport/bridge_transport.dart';
import '../../design/design.dart';
import '../../domain/entities/entities.dart';
import '../../domain/situation/situation.dart';
import '../../ui/ui.dart';
import '../alarms/delivery_banner.dart';
import '../dashboard/dashboard_snapshot.dart';
import '../settings/netmode_switch.dart' show kNetModeRevertS;
import '../settings/settings_screen.dart' show SettingsSection;
import '../shell/connection_sheet.dart';
import '../shell/shell_scope.dart';
import '../shell/shell_session.dart';
import '../shell/situation_probe_platform.dart';
import '../shell/situation_resolver.dart';

class BridgeTab extends StatefulWidget {
  /// Every seam is optional so the shell's `const BridgeTab()` keeps
  /// compiling; tests inject a seeded session, prefs, a stub transport and a
  /// fake [SituationProbe].
  const BridgeTab({
    super.key,
    this.session,
    this.prefs,
    this.transport,
    this.active,
    this.probe,
  });

  /// Injected by tests. In the app it is null and the tab reads the one live
  /// session from [ShellScope] — the router builds this widget, so it can no
  /// longer be handed a session through its constructor.
  final ShellSession? session;
  final BridgePrefs? prefs;

  /// Test seam: the transport the identity, signal and reconciliation reads
  /// go through. Production passes nothing and the tab reaches through the
  /// session (or, failing that, the remembered address).
  final BridgeTransport? transport;

  /// Whether this tab is the one on screen. All branches stay mounted, so
  /// "mounted" is not "visible" — and the signal poll must not run against a
  /// bridge nobody is looking at. Null reads it from [ShellScope] (and is true
  /// with no shell above, as in a bare test).
  final bool? active;

  /// The observable middle column of §16.3 — the radio, the permission, the
  /// surviving bond. Null builds the real one on a bootstrapped app and
  /// [UnknownSituationProbe] everywhere else, which knows nothing and
  /// therefore claims nothing.
  final SituationProbe? probe;

  @override
  State<BridgeTab> createState() => _BridgeTabState();
}

class _BridgeTabState extends State<BridgeTab> {
  /// Fetched for the firmware and device-id rows; null until it lands.
  BridgeStatus? _status;

  /// A26 — the live signal, or null when it has not landed (or the last read
  /// failed). Never carried over from a previous link: a dBm from the Wi-Fi
  /// lane rendered under a Bluetooth heading is the same class of lie as the
  /// stale-IP bug this screen was rebuilt to kill.
  LinkSignal? _signal;

  /// Distinguishes "we have not measured this yet" from "we tried and could
  /// not" — two states that must never read the same.
  bool _signalFailed = false;

  /// The link the value in [_signal] was measured on. A swap discards it.
  LinkKind? _signalLink;

  /// What the **bridge** says its own network mode is, as opposed to what the
  /// link can infer. Null until it answers. This is the fact that ends the
  /// bench failure: over Bluetooth the snapshot knows nothing about Wi-Fi, and
  /// "the bridge is hosting its own network" is only discoverable by asking.
  String? _deviceNetMode;

  bool _fetching = false;
  Timer? _poll;

  /// A signal that is older than this is not worth showing; the poll keeps it
  /// fresher than that whenever the tab is visible.
  static const Duration _pollEvery = Duration(seconds: 20);

  /// The resolver this screen is reading, and whether it owns it.
  ///
  /// **Normally it does not.** The shell owns one resolver for the whole app
  /// (16 §16.3), because a reconciliation layer that only exists while this
  /// tab is mounted is a reconciliation layer that never runs for anyone who
  /// stays on the reader — which is what it used to be. This screen borrows
  /// that one so `/live` and `/device` state the *same* situation.
  ///
  /// It builds its own only when there is no shell above it (a direct-mount
  /// test) or when a test injected a [SituationProbe] to describe a
  /// particular phone. [_ownsResolver] is what dispose keys off, so a
  /// borrowed resolver outlives this screen and an owned one does not leak.
  SituationResolver? _bound;
  bool _ownsResolver = false;

  SituationResolver get _resolver => _bound!;

  /// The link the last reconciliation ran against, so a supervisor swap
  /// (offline → Bluetooth, Bluetooth → Wi-Fi) re-reconciles exactly once.
  ({LinkKind? link, String? netMode})? _reconciledAt;

  BridgePrefs? get _prefs => widget.prefs ?? AppEnv.instance?.prefs;

  /// The live session: injected (tests) or the shell's. Resolved per build
  /// because the scope is only reachable from a [BuildContext].
  ShellSession? _session;
  ShellSession? get _live => widget.session ?? _session;
  DashboardSnapshot? get _snapshot => _live?.snapshot;

  /// Visible right now — the poll's gate. Null until first resolved, which is
  /// what lets the initial arm happen exactly once whichever way it lands.
  bool? _activeResolved;
  bool get _active => _activeResolved ?? true;

  /// The one question every section of this screen keys off.
  bool get _connected =>
      _snapshot != null && _snapshot!.link != LinkKind.offline;

  @override
  void initState() {
    super.initState();
    unawaited(_fetchDeviceInfo());
  }

  /// Attach to the shell's resolver, or build one if there is nothing to
  /// borrow. Runs from [didChangeDependencies], which is the first point a
  /// [ShellScope] is reachable.
  void _bindResolver() {
    // An injected probe means a test is describing a specific phone, so it
    // gets its own resolver rather than the shell's real one.
    final shared = widget.probe == null ? _live?.situationResolver : null;
    final next = shared ?? _bound ?? _buildOwnResolver();
    if (identical(next, _bound)) {
      return;
    }
    _releaseResolver();
    _bound = next;
    _ownsResolver = shared == null;
    next.addListener(_onResolved);
  }

  SituationResolver _buildOwnResolver() => SituationResolver(
    prefs: _prefs,
    probe: widget.probe ?? _buildProbe(),
    shell: LiveSituationShell(
      snapshotOf: () => _snapshot,
      transportOf: () => _open,
      runningCook: () => _live?.plan != null,
      netStatusOf: _readDeviceNetStatus,
      onRetry: _retryNow,
    ),
  );

  void _releaseResolver() {
    final old = _bound;
    if (old == null) {
      return;
    }
    old.removeListener(_onResolved);
    if (_ownsResolver) {
      old.dispose();
    }
    _bound = null;
  }

  /// The real probe only on a bootstrapped app. A widget test has no
  /// `AppEnv`, no channels and no radio, and a probe that reached for them
  /// would be answering questions about a phone that is not there.
  SituationProbe _buildProbe() => AppEnv.instance == null
      ? const UnknownSituationProbe()
      : DeferredSituationProbe(PlatformSituationProbe.create());

  void _onResolved() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Both the session and the visibility come from [ShellScope], which is only
  /// reachable once dependencies are available.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = ShellScope.maybeOf(context);
    _bindResolver();
    _syncActive();
  }

  @override
  void didUpdateWidget(BridgeTab old) {
    super.didUpdateWidget(old);
    _syncActive();
  }

  void _syncActive() {
    final active = widget.active ?? ShellScope.isActive(context, 2);
    if (active == _activeResolved) {
      return;
    }
    final first = _activeResolved == null;
    _activeResolved = active;
    _syncPoll();
    // Whatever is on screen was last measured while the tab was hidden; land
    // a fresh reading before the first tick. Not on the first resolve —
    // `initState` already asked once.
    if (active && !first) {
      unawaited(_fetchDeviceInfo());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _releaseResolver();
    super.dispose();
  }

  /// The signal poll runs only while this tab is the visible one.
  void _syncPoll() {
    _poll?.cancel();
    _poll = _active
        ? Timer.periodic(_pollEvery, (_) => unawaited(_fetchDeviceInfo()))
        : null;
  }

  /// The transport this screen asks, in preference order: an injected one
  /// (tests), the shell session's open link (no second socket), then nothing.
  BridgeTransport? get _open => widget.transport ?? _live?.bridge?.transport;

  void _maybeRefetch() {
    if (_status == null && !_fetching && _open != null) {
      unawaited(_fetchDeviceInfo());
    }
  }

  /// One `status()` + one `signal()` read, for the identity rows and the
  /// signal rows. Reuses the shell session's open transport when present.
  Future<void> _fetchDeviceInfo() async {
    if (_fetching) {
      return; // a pull landing on top of a tick must not double the reads
    }
    _fetching = true;
    try {
      final live = _open;
      if (live != null) {
        await _readInto(live, close: false);
        return;
      }
      final env = AppEnv.instance;
      final url = env?.prefs.lastBaseUrl;
      if (env == null || url == null || url.isEmpty) {
        // Bluetooth, a fresh install, or a bare test — the rows fall back to
        // prefs and the signal block stays absent rather than showing a stale
        // reading.
        return;
      }
      await _readInto(env.transportFor(url), close: true);
    } finally {
      _fetching = false;
    }
  }

  Future<void> _readInto(BridgeTransport t, {required bool close}) async {
    try {
      final s = await t.status();
      if (mounted) {
        setState(() => _status = s);
      }
    } on Object {
      // The device page still renders; the rows that needed it say `—`.
    }
    try {
      final sig = await t.signal();
      if (mounted) {
        setState(() {
          _signal = sig;
          _signalFailed = false;
          _signalLink = _snapshot?.link;
        });
      }
    } on Object {
      // Unreachable, or a link that dropped between the two reads. Drop the
      // old reading rather than keep presenting it as current.
      if (mounted) {
        setState(() {
          _signal = null;
          _signalFailed = true;
        });
      }
    }
    if (close) {
      await t.close();
    }
  }

  /// What the device says about its own network, over whichever lane is up.
  ///
  /// Wi-Fi already carries it in the snapshot. **Bluetooth is the case that
  /// matters**: `net_status` is readable over GATT, so a bridge that failed to
  /// join your Wi-Fi and came up hosting its own can say so on the only lane
  /// that can still reach it.
  /// The SSID rides along because it comes from the same frame and it is what
  /// lets the hosting copy name the network.
  Future<({String? mode, String? ssid})> _readDeviceNetStatus() async {
    final t = _open;
    String? mode;
    String? ssid;
    if (t is BleTransport) {
      try {
        final net = await t.readNetStatus();
        ssid = net.ssid;
        mode = switch (net.modeEnum) {
          dto.NetMode.ap => 'ap',
          dto.NetMode.sta => 'sta',
          // `off` is the radio down, which is neither of the two modes a
          // user picks between — so it stays unknown rather than being
          // rounded to one of them.
          dto.NetMode.off || null => null,
        };
      } on Object {
        mode = null;
      }
    }
    mode ??= _snapshot?.netMode;
    if (mounted && mode != _deviceNetMode) {
      setState(() => _deviceNetMode = mode);
    }
    return (mode: mode, ssid: ssid);
  }

  /// Race every lane again. True when a link came up.
  Future<bool> _retryNow() async {
    final session = _live;
    if (session == null) {
      return false;
    }
    await session.refresh();
    return !(session.liveLink?.offline ?? true);
  }

  /// Pull-to-refresh (13 §13.5.2): ask the unit for a new value, re-read this
  /// screen's own rows, then reconcile against what came back.
  Future<void> _onRefresh() async {
    await _live?.refresh();
    await _fetchDeviceInfo();
    await _resolver.evaluate();
  }

  // ── the situation ─────────────────────────────────────────────────────

  /// The lead card's subject.
  ///
  /// Renders from what the phone already knows **on the first frame** —
  /// `reconcile` is pure, so a remembered-but-unreachable bridge says "last
  /// seen 12 minutes ago" before any read lands, and a phone with no bridge
  /// says so instead of showing an empty page. Once the resolver has gathered
  /// real facts, its answer takes over.
  Situation get _situation {
    if (_resolver.facts != null) {
      final s = _resolver.situation;
      // A phone that is talking to a bridge *right now* does not have "no
      // bridge set up", whatever the store says. That pair of facts happens
      // for the few seconds between a first successful connection and the
      // write that records it, and rendering it would put a card on screen
      // that the connection card underneath immediately contradicts.
      if (s.kind == SituationKind.neverSetUp && _connected) {
        return Situation.ok;
      }
      return s;
    }
    if (_connected) {
      // Reached, and nothing has yet said anything is wrong. Guessing at a
      // cause here is how a healthy bridge gets accused of being reset.
      return Situation.ok;
    }
    return reconcile(
      SituationFacts(
        rememberedBridgeId: _blank(_prefs?.lastBridgeId),
        rememberedBaseUrl: _blank(_prefs?.lastBaseUrl),
        rememberedBleDeviceId: _blank(_prefs?.lastBleDeviceId),
        lastSeenUnixMs: _prefs?.lastSeenUnixMs,
        hasRunningCook: _live?.plan != null,
        nowUnixMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  static String? _blank(String? v) => v == null || v.isEmpty ? null : v;

  /// Reconcile again whenever the link changes underneath us.
  void _reconcileIfLinkMoved() {
    final now = (link: _snapshot?.link, netMode: _snapshot?.netMode);
    if (_reconciledAt == now) {
      return;
    }
    _reconciledAt = now;
    unawaited(_resolver.evaluate());
  }

  /// The single action the lead card offers. Null when nothing can perform it
  /// right now, which renders the button disabled **with its reason beneath**
  /// rather than live-and-inert.
  /// A past-tense report normally carries no label at all, so there is nothing
  /// to wire; the one that does — "Put it back on your Wi-Fi" after the app
  /// joined the bridge's own network — is a real next step and stays live.
  VoidCallback? _situationAction(Situation s) {
    final act = actFor(s.kind);
    if (act == SituationAct.none || s.actionLabel.isEmpty) {
      return null;
    }
    if (_actionBlockedReason(act).isNotEmpty) {
      return null;
    }
    return () => unawaited(_runAct(act));
  }

  /// Why the lead card's action cannot run, in the user's terms.
  String _actionBlockedReason(SituationAct act) => switch (act) {
    SituationAct.switchNetwork || SituationAct.updateFirmware => _connected
        ? ''
        : 'The bridge has to be reachable before this can change.',
    SituationAct.adoptBridge => _connected
        ? ''
        : 'The bridge has to be reachable before this can change.',
    _ => '',
  };

  Future<void> _runAct(SituationAct act) async {
    switch (act) {
      case SituationAct.none:
        return;
      case SituationAct.openBluetooth:
      case SituationAct.grantPermission:
        await _resolver.runOsAct();
        await _resolver.evaluate();
      case SituationAct.runSetup:
      case SituationAct.pairBase:
        if (mounted) {
          context.go(AppRoutes.setup);
        }
      case SituationAct.adoptBridge:
        await _confirmAdopt();
      case SituationAct.switchNetwork:
        await _switchMode(NetworkMode.sta);
      case SituationAct.updateFirmware:
        if (mounted) {
          context.push(AppRoutes.settingsSection(SettingsSection.firmware));
        }
      case SituationAct.endCook:
        await _live?.endCook();
        await _resolver.evaluate();
    }
  }

  /// #7 — identity, and the one thing the resolver refuses to do by itself.
  Future<void> _confirmAdopt() async {
    final reached = _resolver.facts?.reachedDeviceId ?? _deviceId;
    final ok = await showCostSheet(
      context,
      title: 'Use this bridge instead?',
      body:
          'The bridge answering is $reached. This phone was set up with a '
          'different one. From now on, readings and settings go to this one.',
      keeps: 'Every cook already saved on this phone.',
      loses: 'The link to the bridge this phone used to use.',
      confirmLabel: 'Use this bridge',
      cancelLabel: 'Keep looking for the old one',
    );
    if (ok) {
      await _resolver.adoptReachedBridge();
    }
  }

  // ── §E.1 / §E.3: changing how it connects ─────────────────────────────

  Future<void> _choose(ConnectionChoice choice) async {
    switch (choice) {
      case ConnectionChoice.bluetooth:
        await _preferBluetooth();
      case ConnectionChoice.bridgeHosts:
        await _switchMode(NetworkMode.ap);
      case ConnectionChoice.joinsYours:
        await _switchMode(NetworkMode.sta);
    }
  }

  /// Bluetooth is a *phone-side* preference, not a device change — so it does
  /// not go through the rollback wizard. It is still confirmed by read-back:
  /// nothing on this screen claims a write it has not read back.
  Future<void> _preferBluetooth() async {
    final session = _live;
    if (session == null) {
      return;
    }
    await session.setPreferredTransport(PreferredTransport.ble);
    if (!mounted) {
      return;
    }
    if (session.preferredTransport == PreferredTransport.ble) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Set to prefer Bluetooth. Wi-Fi stays as a backup.'),
        ),
      );
    }
  }

  /// §E.3 — the mode switch that kills the link carrying it.
  ///
  /// The protocol lives in `netmode_switch.dart` and the four screens in
  /// `netmode_sheet.dart`; this only supplies the three seams they need. The
  /// probe and the commit deliberately share one transport: a commit sent down
  /// a *different* connection than the one that proved the bridge is serving
  /// would be confirming something we never verified.
  Future<void> _switchMode(NetworkMode target) async {
    final transport = _open;
    final env = AppEnv.instance;
    if (transport == null) {
      return;
    }
    final expected = target == NetworkMode.ap
        ? 'http://192.168.4.1'
        : 'http://smokebridge.local';
    BridgeTransport? found;

    await showNetModeSheet(
      context,
      target: target,
      knownSsid: (_snapshot?.netMode == 'sta' && _signal != null)
          ? _signal!.ssid
          : '',
      apply: (mode, ssid, psk) => transport.applyNetwork(
        mode: mode,
        ssid: ssid,
        psk: psk,
        revertAfterS: kNetModeRevertS,
      ),
      probe: () async {
        if (env == null) {
          return false;
        }
        final t = found ??= env.transportFor(expected);
        try {
          final s = await t.status();
          return s.deviceId.isNotEmpty;
        } on Object {
          return false;
        }
      },
      commit: () async {
        final t = found;
        if (t == null) {
          // Nothing proved the bridge is serving on the new network, so there
          // is nothing to confirm. Throwing keeps the wizard hunting rather
          // than letting it report a success with a two-minute fuse on it.
          throw StateError('no verified link to commit on');
        }
        await t.commitNetworkMode();
        await _prefs?.recordConnection(expected);
      },
    );
    await found?.close();
    if (mounted) {
      await _onRefresh();
    }
  }

  // ── verbs ─────────────────────────────────────────────────────────────

  /// Runs a disruptive verb inside the completion sheet (A24.9): send, then
  /// verify by watching the bridge actually go down, then a done state.
  Future<void> _runVerb(DisruptiveVerb verb, ControlCommand cmd) async {
    final session = _live;
    final bridge = session?.bridge;
    Future<void> Function() send;
    Future<void> Function() probe;
    BridgeTransport? fallback;
    if (session != null && bridge != null) {
      send = () => session.control(cmd);
      // Reads the CURRENT active transport each poll, so a supervisor swap
      // mid-verify still probes the live link.
      probe = () => bridge.transport.status();
    } else {
      final env = AppEnv.instance;
      final url = env?.prefs.lastBaseUrl;
      if (env == null || url == null || url.isEmpty) {
        return;
      }
      final t = env.transportFor(url);
      fallback = t;
      send = () => t.control(cmd);
      probe = () => t.status();
    }
    if (!mounted) {
      await fallback?.close();
      return;
    }
    await showVerbProgressSheet(
      context,
      verb: verb,
      send: send,
      probe: probe,
      // A confirmed factory reset forgets the bridge on this phone at the
      // same moment — the app must never keep claiming a bridge the reset
      // just erased. (Warned in the cost sheet before the user confirms.)
      onCompleted: verb == DisruptiveVerb.factoryReset
          ? () => unawaited(_prefs?.forgetBridge() ?? Future<void>.value())
          : null,
      onSetUpAgain: verb == DisruptiveVerb.factoryReset
          ? () {
              if (mounted) {
                context.go(AppRoutes.setup);
              }
            }
          : null,
    );
    await fallback?.close();
  }

  /// The diagnostics gate. Five taps on the device-id row — the convention
  /// every Android user already knows from Build number.
  ///
  /// It used to live on the firmware row, which now has a real destination of
  /// its own (the update page §C.5 asks for). A row cannot both navigate on
  /// the first tap and count to five.
  int _idTaps = 0;

  void _tapDeviceId() {
    _idTaps++;
    if (_idTaps < 5) {
      return;
    }
    _idTaps = 0;
    context.push(AppRoutes.settingsSection(SettingsSection.advanced));
  }

  Future<void> _forget() async {
    await _prefs?.forgetBridge();
    if (mounted) {
      // Nothing remembered → the guided setup flow, where a phone with no
      // bridge belongs (A9.5/§13.5.1).
      context.go(AppRoutes.setup);
    }
  }

  // ── identity values ───────────────────────────────────────────────────

  String get _deviceId => _status?.deviceId.isNotEmpty == true
      ? _status!.deviceId
      : (_live?.bridge?.bridgeId.isNotEmpty == true
            ? _live!.bridge!.bridgeId
            : (_prefs?.lastBridgeId ?? noValue));

  /// The address the app is USING, never a stale one presented as live.
  String get _address {
    if (_connected && _snapshot!.link == LinkKind.ble) {
      return 'none — via Bluetooth';
    }
    final url = (_snapshot?.address.isNotEmpty == true)
        ? _snapshot!.address
        : (_prefs?.lastBaseUrl ?? '');
    if (url.isEmpty) {
      return noValue;
    }
    return url
        .replaceFirst(RegExp('^https?://'), '')
        .replaceFirst(RegExp(r'/$'), '');
  }

  String get _firmware =>
      _status?.fw.isNotEmpty == true ? _status!.fw : noValue;

  String get _lastReading {
    final ago = _snapshot?.lastPacketSAgo;
    if (ago != null) {
      return '${formatDuration(ago)} ago';
    }
    final when = formatSessionDate(_prefs?.lastSeenUnixMs);
    return when.isEmpty ? noValue : when;
  }

  /// **Absent is not zero.** Null battery with `batteryKnown` false means this
  /// device cannot report one, which is a different fact from a flat one.
  String get _battery {
    final s = _snapshot;
    if (s == null || !s.batteryKnown || s.socPct == null) {
      return noValue;
    }
    return s.charging ? '${s.socPct}% · charging' : '${s.socPct}%';
  }

  /// Why the battery reads `—`, told apart the way [_storageWhy] already
  /// tells storage apart.
  ///
  /// "This bridge does not report a battery level" is a claim about the
  /// *hardware*, and it was being made about a bridge that was merely
  /// unreachable, or reachable but not yet read — because
  /// `DashboardSnapshot.batteryKnown` is false in all three cases. Accusing a
  /// device of lacking a sensor because a read has not come back yet is the
  /// same class of lie as rendering a default as a fact.
  String get _batteryWhy {
    if (_battery != noValue) {
      return '';
    }
    if (_snapshot == null) {
      return 'Not read yet.';
    }
    return _snapshot!.batteryKnown
        ? 'Not read yet.'
        : 'This bridge does not report a battery level.';
  }

  /// Storage, or an honest absence. `BridgeStatus.storageFreePct` defaults to
  /// 0 and the Bluetooth lane leaves it there, so a bare 0 would read as "the
  /// bridge is full" on the one transport that cannot know.
  String get _storage {
    if (_snapshot?.link == LinkKind.ble || _status == null) {
      return noValue;
    }
    return '${_status!.storageFreePct}% free';
  }

  String get _storageWhy {
    if (_snapshot?.link == LinkKind.ble) {
      return 'The bridge only reports its storage over Wi-Fi.';
    }
    return _status == null ? 'Not read yet.' : '';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    _maybeRefetch();
    _reconcileIfLinkMoved();

    final situation = _situation;
    // A phone with no bridge at all gets ONE card and its one action — not a
    // page of dashes pretending there is something to manage.
    final onlySituation = situation.kind == SituationKind.neverSetUp;

    return SafeArea(
      top: false,
      child: RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          key: const Key('bridge-tab'),
          // The short "no bridge yet" page has nothing to scroll, and a page
          // that cannot scroll cannot be pulled.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(SmokeTokens.s4),
          children: [
            Text('Device', style: SmokeType.displayS.copyWith(color: t.textHi)),
            const SizedBox(height: SmokeTokens.s4),
            // §B.2 puts the "will this phone wake you?" verdict on `/live`
            // **and** `/device`; it was mounted only on the reader, so a user
            // whose notifications are blocked saw nothing on the one screen
            // whose job is "how do I control this?".
            const DeliveryBanner(),
            if (!situation.isHealthy) ...[
              SituationCard(
                situation: situation,
                onAct: _situationAction(situation),
                disabledReason: _actionBlockedReason(actFor(situation.kind)),
                busy: _resolver.acting,
              ),
              const SizedBox(height: SmokeTokens.s4),
            ],
            if (!onlySituation) ...[
              ConnectionModeCard(
                link: _snapshot?.link ?? LinkKind.offline,
                netMode: _snapshot?.netMode,
                deviceNetMode:
                    _deviceNetMode ?? _resolver.facts?.reachedNetMode,
                address: _snapshot?.address ?? '',
                // A transport swap makes the last reading a fact about a
                // different radio. Hide it until the next poll rather than
                // relabel it.
                signal: _signalLink == _snapshot?.link ? _signal : null,
                signalFailed: _signalFailed,
                disabledReason: _connected
                    ? ''
                    : 'The bridge has to be reachable before this can change.',
                onChoose: (c) => unawaited(_choose(c)),
                onManageConnection: _live == null
                    ? null
                    : () => unawaited(showConnectionSheet(context, _live!)),
              ),
              const SizedBox(height: SmokeTokens.s4),
              _bridgeCard(t),
              const SizedBox(height: SmokeTokens.s3),
              // §16.6's order: the bridge's own state and its power controls
              // sit together, above the way-in to the settings tree. Power off
              // is a peer of "is it healthy?", not a footnote after ten
              // navigation rows.
              _dangerCard(t),
              const SizedBox(height: SmokeTokens.s3),
              _controlsGroups(t),
            ],
          ],
        ),
      ),
    );
  }

  // ── the bridge's own facts ────────────────────────────────────────────

  Widget _bridgeCard(SmokeTokens t) => SmokeCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'YOUR BRIDGE',
          style: SmokeType.label.copyWith(color: t.textMuted),
        ),
        if (!_connected) ...[
          const SizedBox(height: SmokeTokens.s2),
          Text(
            'Not connected — these are the last known details.',
            key: const Key('bridge-last-known'),
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          ),
        ],
        const SizedBox(height: SmokeTokens.s2),
        _FactRow(label: 'Battery', value: _battery),
        if (_batteryWhy.isNotEmpty)
          _Because(key: const Key('bridge-battery-why'), text: _batteryWhy),
        _FactRow(label: 'Storage', value: _storage),
        if (_storageWhy.isNotEmpty)
          _Because(key: const Key('bridge-storage-why'), text: _storageWhy),
        // Five taps opens the diagnostics console — packet log, novelty log,
        // app log. A real support tool that must stay reachable in the field
        // without a cable (08 §8.2), but not a peer of "Probes" in a
        // production settings list.
        GestureDetector(
          key: const Key('bridge-diagnostics-gate'),
          behavior: HitTestBehavior.opaque,
          onTap: _tapDeviceId,
          child: _FactRow(label: 'Device ID', value: _deviceId, mono: true),
        ),
        _FactRow(label: 'Address', value: _address, mono: true),
        _FactRow(label: 'Last reading', value: _lastReading),
        // `DashboardSnapshot.paired` defaults to **true** so an offline cache
        // read does not cry wolf — which is right for the snapshot and wrong
        // for a row that states it as a fact. `_status` is the only source
        // that has actually been asked, so a connected-but-not-yet-read
        // bridge reads `—` rather than the word "Paired". (The Identity
        // settings row already gets this right by keeping `paired` nullable
        // all the way down; this one did not.)
        _FactRow(
          label: 'Smoke X base',
          value: !_connected || _status == null
              ? noValue
              : (_status!.paired ? 'Paired' : 'Not paired'),
        ),
        const SizedBox(height: SmokeTokens.s2),
        Divider(height: 1, color: t.hairline),
        _TileRow(
          key: const Key('bridge-firmware'),
          icon: Icons.system_update_alt_rounded,
          title: 'Firmware',
          subtitle: _firmware == noValue
              ? 'Version not read yet. Updates install over Wi-Fi.'
              : '$_firmware — updates install over Wi-Fi.',
          onTap: () =>
              context.push(AppRoutes.settingsSection(SettingsSection.firmware)),
        ),
      ],
    ),
  );

  /// The way in to every device page, and the safe actions.
  ///
  /// **Three labelled cards, not one card of twelve rows.** §16.5 says a card
  /// "groups rows that share a subject", and a single list spanning a rule
  /// editor, ten settings pages and a setup re-run shares only "things you can
  /// tap" — which is what made this screen read as a wall rather than a
  /// considered page. The groups answer the three questions someone actually
  /// arrives with: *what is it watching?*, *how is it set up?*, *where is my
  /// data?*
  Widget _controlsGroups(SmokeTokens t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _group(t, 'THE COOK', [
        // The rule editor is a different page from the delivery settings in
        // "Notifications on this phone" — one is what the bridge shouts
        // about, the other is how loudly this phone repeats it.
        _TileRow(
          key: const Key('bridge-alarms'),
          icon: Icons.notifications_active_outlined,
          title: 'Alarm rules',
          subtitle: 'What the bridge watches for, and how hard it shouts.',
          onTap: () => context.push(AppRoutes.deviceAlarms),
        ),
        ..._sectionRows(const [
          SettingsSection.probes,
          SettingsSection.alarms,
          SettingsSection.display,
        ]),
      ]),
      const SizedBox(height: SmokeTokens.s3),
      _group(t, 'THE BRIDGE', [
        ..._sectionRows(const [
          SettingsSection.network,
          SettingsSection.power,
          SettingsSection.led,
          SettingsSection.firmware,
          SettingsSection.homeAssistant,
          SettingsSection.identity,
        ]),
        _TileRow(
          key: const Key('bridge-rerun-wifi'),
          // Not `restart_alt`: that glyph is "Restart the bridge" two cards
          // down, which takes the device off the air mid-cook. One icon for
          // a wizard and for a power action is a coin toss at 3 a.m.
          icon: Icons.auto_fix_high_rounded,
          title: 'Run setup again',
          subtitle:
              'Change Wi-Fi or re-pair. Keeps your cooks and this phone’s '
              'Bluetooth bond.',
          onTap: () => context.go(AppRoutes.setup),
        ),
      ]),
      const SizedBox(height: SmokeTokens.s3),
      _group(t, 'YOUR DATA', _sectionRows(const [SettingsSection.data])),
    ],
  );

  List<Widget> _sectionRows(List<SettingsSection> sections) => [
    for (final s in sections)
      _TileRow(
        key: Key('bridge-section-${s.name}'),
        icon: s.icon,
        title: s.title,
        subtitle: s.subtitle,
        onTap: () => context.push(AppRoutes.settingsSection(s)),
      ),
  ];

  /// A labelled card, with the label *outside* it.
  ///
  /// Three treatments of one element were in play on this screen —
  /// 'YOUR BRIDGE' inside its card, 'RESET AND POWER' outside its own, and
  /// this group with no label at all. §16.5 puts the section label above the
  /// card, so that is the one that wins everywhere.
  Widget _group(SmokeTokens t, String label, List<Widget> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(
          left: SmokeTokens.s2,
          bottom: SmokeTokens.s2,
        ),
        child: Text(label, style: SmokeType.label.copyWith(color: t.textMuted)),
      ),
      SmokeCard(
        padding: const EdgeInsets.symmetric(vertical: SmokeTokens.s1),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: t.hairline),
              rows[i],
            ],
          ],
        ),
      ),
    ],
  );

  Widget _dangerCard(SmokeTokens t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(
          left: SmokeTokens.s2,
          bottom: SmokeTokens.s2,
        ),
        // "DANGER ZONE" is a sysadmin idiom, shouted. The four cost sheets
        // underneath already carry the weight, and they do it calmly.
        child: Text(
          'RESET AND POWER',
          style: SmokeType.label.copyWith(color: t.textMuted),
        ),
      ),
      SmokeCard(
        padding: const EdgeInsets.symmetric(vertical: SmokeTokens.s1),
        child: Column(
          children: [
            _TileRow(
              key: const Key('bridge-restart'),
              icon: Icons.restart_alt_rounded,
              title: 'Restart the bridge',
              subtitle: _connected
                  ? 'Keeps everything — it reconnects on its own.'
                  : 'Needs a connection to the bridge.',
              onTap: !_connected
                  ? null
                  : () => _confirmThen(
                      title: 'Restart the bridge?',
                      body:
                          'It goes unreachable for a few seconds while it '
                          'reboots, then reconnects by itself.',
                      keeps: 'Everything.',
                      confirmLabel: 'Restart',
                      cancelLabel: 'Leave it running',
                      run: () => _runVerb(
                        DisruptiveVerb.restart,
                        const ControlCommand.reboot(),
                      ),
                    ),
            ),
            Divider(height: 1, color: t.hairline),
            _TileRow(
              key: const Key('bridge-forget'),
              icon: Icons.link_off_rounded,
              title: 'Forget this bridge',
              subtitle: 'This phone stops connecting to it.',
              onTap: () => _confirmThen(
                title: 'Forget this bridge on this phone?',
                body:
                    'Only this phone forgets it — the bridge keeps its '
                    'pairing, its network and every cook. You can add it '
                    'again later.',
                loses: 'The cooks cached on this phone.',
                confirmLabel: 'Forget',
                cancelLabel: 'Keep this bridge',
                run: _forget,
              ),
            ),
            Divider(height: 1, color: t.hairline),
            _TileRow(
              key: const Key('bridge-factory-reset'),
              icon: Icons.delete_forever_rounded,
              title: 'Factory reset',
              subtitle: _connected
                  ? 'Wipes the bridge back to how it shipped.'
                  : 'Needs a connection to the bridge.',
              danger: true,
              onTap: !_connected
                  ? null
                  : () => _confirmThen(
                      title: 'Erase everything on the bridge?',
                      body:
                          'This wipes the bridge back to how it shipped and '
                          'cannot be undone. This phone will forget it too — '
                          'afterwards you set it up again like new.',
                      loses:
                          'Its pairing, its Wi-Fi, every cook on the bridge, '
                          'and this phone’s saved connection to it.',
                      confirmLabel: 'Erase everything',
                      cancelLabel: 'Don’t erase',
                      run: () => _runVerb(
                        DisruptiveVerb.factoryReset,
                        const ControlCommand.factoryReset(),
                      ),
                    ),
            ),
            Divider(height: 1, color: t.hairline),
            _TileRow(
              key: const Key('bridge-power-off'),
              icon: Icons.power_settings_new_rounded,
              title: 'Power off',
              subtitle: _connected
                  ? 'Only the button on the bridge can turn it back on.'
                  : 'Needs a connection to the bridge.',
              danger: true,
              onTap: !_connected
                  ? null
                  : () => _confirmThen(
                      title: 'Power off the bridge?',
                      body:
                          'It stops answering on Wi-Fi and Bluetooth, and '
                          'nothing in this app can wake it. To turn it back '
                          'on you must physically hold the PRG button on the '
                          'bridge for about five seconds.',
                      loses: 'Remote access until someone walks over to it.',
                      confirmLabel: 'Power off',
                      cancelLabel: 'Leave it on',
                      run: () => _runVerb(
                        DisruptiveVerb.powerOff,
                        const ControlCommand.powerOff(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    ],
  );

  /// Open the cost sheet; run [run] only if the user confirms.
  Future<void> _confirmThen({
    required String title,
    required String body,
    String? keeps,
    String? loses,
    required String confirmLabel,
    required String cancelLabel,
    required Future<void> Function() run,
  }) async {
    final ok = await showCostSheet(
      context,
      title: title,
      body: body,
      keeps: keeps,
      loses: loses,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    );
    if (ok) {
      await run();
    }
  }
}

/// A label and the fact it names: §16.5's row, at every text scale.
///
/// Visually the shared `StatRow`, but with both halves [Flexible]. `StatRow`'s
/// two `Text`s are rigid children of a `spaceBetween` `Row`, which overflows by
/// 45 dp on this page at 200% text — a control that cannot be read is the same
/// failure as one that cannot be used, and §16.7 asks for 200%. The shared
/// component wants the same treatment; this page could not wait for it.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      // §16.5's row minimum. This was `vertical: 6` — off the 4 dp scale, and
      // about 30 dp tall, so six of the seven rows on this card sat at under
      // two-thirds the mandated height. One of them carries the five-tap
      // diagnostics gate, which made it a ~30 dp target for a deliberate
      // gesture.
      constraints: const BoxConstraints(minHeight: 52),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(vertical: SmokeTokens.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: SmokeType.body.copyWith(color: t.textMuted),
            ),
          ),
          const SizedBox(width: SmokeTokens.s3),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: (mono ? SmokeType.mono : SmokeType.body).copyWith(
                color: t.textHi,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The reason a value is absent, directly beneath the row it belongs to
/// (§16.5). "—" on its own is a shrug; "—" with a sentence is information.
class _Because extends StatelessWidget {
  const _Because({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: SmokeType.bodySm.copyWith(color: context.tokens.textMuted),
    ),
  );
}

/// One device-page row: an icon, a title, a supporting line, and (when
/// tappable) a chevron. A null [onTap] renders it dimmed — the honest look of
/// a control that cannot act, kept visible with its reason rather than hidden.
class _TileRow extends StatelessWidget {
  const _TileRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = onTap != null;
    final tint = danger ? StatusPalette.critical : t.textBody;
    final titleColor = !enabled
        ? t.textMuted
        : (danger ? StatusPalette.critical : t.textHi);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SmokeTokens.s4,
          vertical: SmokeTokens.s3,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: enabled ? tint : t.chromeDim),
            const SizedBox(width: SmokeTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: SmokeType.title.copyWith(color: titleColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: SmokeType.bodySm.copyWith(color: t.textMuted),
                  ),
                ],
              ),
            ),
            if (enabled) ...[
              const SizedBox(width: SmokeTokens.s2),
              Icon(Icons.chevron_right_rounded, size: 20, color: t.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}
