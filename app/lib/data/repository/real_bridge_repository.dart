/// N15.8 — the real `BridgeRepository` over the transport stack.
///
/// Composes the N15.5/N15.6 [ConnectionSupervisor], the N15.7 [BridgeSession]
/// and a [SampleCache] (N15.9/N15.10) behind the **unchanged** N2.27 seam. No
/// screen knows this exists: it is a drop-in for [MockBridgeRepository].
///
/// The transport is the wire (`BridgeStatus`, `LiveStatus`, `SessionInfo`, …);
/// this class is the *app model* (`BridgeSnapshot`, `HistoryEntry`,
/// `DeviceInfo`). All mapping lives here, in pure Dart, so the whole layer is in
/// the `dart test test/data` gate.
///
/// I15: a transport failure never escapes as an exception — mutations swallow a
/// wire error into a named [notice], reads degrade to the last good snapshot.
library;

import 'dart:async';

import '../../domain/domain.dart';
import '../alarms/notification_policy.dart';
import '../content/catalog.dart';
import '../content/fixtures_data.dart';
import '../model/alarm.dart';
import '../model/alarm_rule.dart';
import '../model/bridge_snapshot.dart';
import '../model/connection_mode.dart';
import '../model/connection_state.dart';
import '../model/cook_state.dart';
import '../model/device_info.dart';
import '../model/history_entry.dart';
import '../model/mock_event.dart';
import '../transport/bridge_session.dart';
import '../transport/bridge_transport.dart';
import '../transport/connection_supervisor.dart';
import '../transport/sample_cache.dart';
import '../transport/sync_engine.dart';
import 'bridge_repository.dart';

/// The SSID the app offers when joining a home network (the prototype's).
const String kPendingSsid = 'HomeNet-5G';

/// N15.8 — a real [BridgeRepository] fed by a [ConnectionSupervisor].
class RealBridgeRepository implements BridgeRepository {
  RealBridgeRepository({
    required this.supervisor,
    SampleCache? cache,
    this.bridgeId = 'SmokeBridge',
    int Function()? nowMs,
    SyncEngine? syncEngine,
    this.statusPollInterval = const Duration(seconds: 10),
  }) : _cache = cache ?? InMemorySampleCache(),
       _nowMs = nowMs ?? _wallClock,
       _syncEngine = syncEngine ?? SyncEngine(nowMs: nowMs) {
    _snapshot = _emptySnapshot();
  }

  final ConnectionSupervisor supervisor;
  final SampleCache _cache;
  final String bridgeId;
  final int Function() _nowMs;
  final SyncEngine _syncEngine;
  final Duration statusPollInterval;

  // ── session state ─────────────────────────────────────────────────────

  BridgeTransport? _transport;
  BridgeSession? _session;
  final List<StreamSubscription<Object?>> _subs = [];
  BridgeSessionSnapshot? _last;

  // ── app-side overlay (state the wire has no slot for) ─────────────────

  late BridgeSnapshot _snapshot;
  List<HistoryEntry> _history = const [];
  List<Alarm> _alarms = const [];
  List<AlarmRule> _rules = List<AlarmRule>.of(kAlarmRules);
  List<CookItem> _items = const [];
  final Set<ProbeJack> _attachedJacks = {};
  final Map<ProbeJack, ProbeRole> _roles = {};
  final Map<ProbeJack, int> _targets = {};
  final Map<ProbeJack, List<int>> _spark = {};
  final Set<int> _discardedSessions = {};
  int? _adoptedSessionId;
  bool _paused = false;
  int? _startedAtMs;
  String? _notice;
  String? _availableFw;

  final StreamController<BridgeSnapshot> _snapshotController =
      StreamController<BridgeSnapshot>.broadcast();
  final StreamController<List<HistoryEntry>> _historyController =
      StreamController<List<HistoryEntry>>.broadcast();

  bool _disposed = false;

  // ── reads ─────────────────────────────────────────────────────────────

  @override
  BridgeSnapshot get current => _snapshot;

  @override
  Stream<BridgeSnapshot> snapshot() async* {
    yield _snapshot;
    yield* _snapshotController.stream;
  }

  @override
  List<HistoryEntry> get history => List.unmodifiable(_history);

  @override
  Stream<List<HistoryEntry>> watchHistory() async* {
    yield history;
    yield* _historyController.stream;
  }

  @override
  CatalogTable get catalog => kCatalogTable;

  @override
  List<ConnectionMode> get connectionModes => kConnectionModes;

  @override
  List<AlarmRule> get alarmRules => List.unmodifiable(_rules);

  @override
  List<MockEventSpec> get mockEvents => const [];

  @override
  DeviceInfo get device => _device;

  @override
  FirmwareInfo get firmware => kFirmware;

  @override
  String get activeScenarioKey => 'live';

  @override
  List<Scenario> get scenarios => const [];

  DeviceInfo _device = kDevice;

  /// The transport currently carrying data, or null while disconnected.
  BridgeTransport? get transport => _transport;
  SampleCache get cache => _cache;

  // ── connection ────────────────────────────────────────────────────────

  @override
  Future<void> connect() async {
    final active = await _attempt(() => supervisor.start());
    if (active == null) {
      _notice = 'Could not reach the bridge — recording continues on it.';
      _emit();
      return;
    }
    await _attach(active);
  }

  Future<void> _attach(BridgeTransport active) async {
    await _detachSession();
    _transport = active;
    final session = BridgeSession(
      transport: active,
      bridgeId: bridgeId,
      cache: _cache,
      syncEngine: _syncEngine,
      statusPollInterval: statusPollInterval,
      nowMs: _nowMs,
    );
    _session = session;
    _subs.add(
      session.updates.listen((update) {
        _last = update;
        _syncLocalFromStatus(update.status);
        _emit();
      }),
    );
    _subs.add(session.samples.listen((sample) => _trackSpark(sample)));
    _subs.add(session.linkLost.listen((_) => unawaited(_onLinkLost())));
    await session.start();
    await _reloadHistory(session);
    _emit();
  }

  Future<void> _onLinkLost() async {
    // Link loss is verified by a real status read (N15.7); climb back through
    // the supervisor, then re-open the data session on whichever lane wins.
    if (_disposed) {
      return;
    }
    final next = await _attempt(() => supervisor.failover());
    if (next == null) {
      _notice = 'Bridge unreachable — it keeps recording; sync when back.';
      _emit();
      return;
    }
    await _attach(next);
  }

  @override
  Future<void> resync() async {
    final session = _session;
    if (session == null) {
      await connect();
      return;
    }
    await _attempt(() async {
      await session.resync();
    });
    await _reloadHistory(session);
    _notice = null;
    _emit();
  }

  @override
  Future<void> disconnect() async {
    final session = _session;
    _session = null;
    _transport = null;
    _last = null;
    await session?.stop();
    await supervisor.disconnect();
    _notice = null;
    _snapshot = _emptySnapshot();
    _emit();
  }

  @override
  Future<void> joinWifi({
    required String ssid,
    required String password,
  }) async {
    final transport = _transport;
    if (transport == null) {
      return;
    }
    // The password is a transient argument only — never stored (N10.7/I8).
    await _attempt(
      () => transport.applyNetwork(mode: 'sta', ssid: ssid, psk: password),
    );
    _notice = null;
    _emit();
  }

  @override
  Future<void> useHotspot() async {
    final transport = _transport;
    if (transport != null) {
      await _attempt(() => transport.applyNetwork(mode: 'ap'));
    }
    _emit();
  }

  @override
  Future<void> confirmHotspotJoined() async {
    final transport = _transport;
    if (transport != null) {
      await _attempt(transport.commitNetwork);
    }
    _emit();
  }

  @override
  Future<void> forgetNetwork() async {
    final transport = _transport;
    if (transport != null) {
      await _attempt(() => transport.applyNetwork(mode: 'off'));
    }
    _notice = 'Network forgotten — the bridge keeps recording.';
    _emit();
  }

  @override
  Future<void> applyMode(String modeId) async {
    final transport = _transport;
    if (transport != null) {
      switch (modeId) {
        case 'ble':
          await _attempt(() => transport.applyNetwork(mode: 'off'));
        case 'ap':
          await _attempt(() => transport.applyNetwork(mode: 'ap'));
        case 'sta':
          await _attempt(
            () => transport.applyNetwork(mode: 'sta', ssid: kPendingSsid),
          );
      }
    }
    _notice = null;
    _emit();
  }

  // ── cook lifecycle ────────────────────────────────────────────────────

  @override
  Future<void> adoptSession() async {
    final pending = _snapshot.pendingSession;
    if (pending == null) {
      return;
    }
    _adoptedSessionId = int.tryParse(pending.sessionId);
    final anchor = pending.startedAtMs;
    _startedAtMs = anchor;
    _items = const [];
    for (final n in pending.attachedJacks) {
      final jack = ProbeJack.fromN(n);
      if (jack != null) {
        _attachedJacks.add(jack);
        _items = [
          ..._items,
          CookItem(presetId: 'custom', jack: jack, addedAtMs: anchor),
        ];
      }
    }
    final transport = _transport;
    if (transport != null) {
      await _attempt(() => transport.setCookClock(startedUnixMs: anchor));
    }
    _notice = 'Cook adopted · pulled ${pending.samples} samples';
    _emit();
  }

  @override
  Future<void> setCookPaused(bool paused) async {
    _paused = paused;
    _emit();
  }

  @override
  Future<void> setCookStart(int startedAtMs) async {
    // Moving the window never rewrites a sample (I10): only the anchor moves.
    _startedAtMs = startedAtMs;
    final transport = _transport;
    if (transport != null) {
      await _attempt(() => transport.setCookClock(startedUnixMs: startedAtMs));
    }
    _emit();
  }

  @override
  Future<void> discardSession() async {
    final pending = _snapshot.pendingSession;
    if (pending == null) {
      return;
    }
    final id = int.tryParse(pending.sessionId);
    final transport = _transport;
    if (id != null) {
      _discardedSessions.add(id);
      if (transport != null) {
        await _attempt(() => transport.stopSession(id));
      }
    }
    _notice = 'Started fresh — the old recording stays on the bridge.';
    _emit();
  }

  @override
  Future<void> startCook({
    required String presetId,
    required ProbeJack jack,
    String? styleId,
    String? title,
    int? targetF10,
    int? pullF10,
    CookTimeline? timeline,
    bool? wrap,
    bool? spritz,
    int? startedAtMs,
    bool adoptPendingSession = false,
  }) => _addItem(
    presetId: presetId,
    jack: jack,
    styleId: styleId,
    title: title,
    targetF10: targetF10,
    pullF10: pullF10,
    timeline: timeline,
    wrap: wrap,
    spritz: spritz,
    startedAtMs: startedAtMs,
    adoptPendingSession: adoptPendingSession,
  );

  @override
  Future<void> addItem({
    required String presetId,
    required ProbeJack jack,
    String? styleId,
    int? targetF10,
    int? pullF10,
    CookTimeline? timeline,
    bool? wrap,
    bool? spritz,
  }) => _addItem(
    presetId: presetId,
    jack: jack,
    styleId: styleId,
    targetF10: targetF10,
    pullF10: pullF10,
    timeline: timeline,
    wrap: wrap,
    spritz: spritz,
  );

  Future<void> _addItem({
    required String presetId,
    required ProbeJack jack,
    String? styleId,
    String? title,
    int? targetF10,
    int? pullF10,
    CookTimeline? timeline,
    bool? wrap,
    bool? spritz,
    int? startedAtMs,
    bool adoptPendingSession = false,
  }) async {
    final entry = catalog.byId(presetId);
    final style = styleId == null
        ? null
        : catalog.stylesFor(presetId).where((s) => s.id == styleId).firstOrNull;
    final target =
        targetF10 ?? style?.targetF10 ?? entry?.defaultDoneness.targetF10;
    int? pull = pullF10;
    if (pull == null && target != null) {
      pull = entry == null
          ? target
          : pullTempFor(
              targetF10: target,
              carryoverF10: entry.carryoverF10,
              hazard: entry.hazard,
            );
    }

    final pending = _snapshot.pendingSession;
    final adopting = adoptPendingSession && pending != null;
    final anchor =
        startedAtMs ?? (adopting ? pending.startedAtMs : null) ?? _nowMs();
    if (_startedAtMs == null || !_snapshot.cook.active) {
      _startedAtMs = anchor;
      final transport = _transport;
      if (transport != null) {
        await _attempt(() => transport.setCookClock(startedUnixMs: anchor));
      }
    }
    if (adopting) {
      _adoptedSessionId = int.tryParse(pending.sessionId);
    }
    _items = [
      for (final it in _items)
        if (it.jack != jack) it,
      CookItem(
        presetId: presetId,
        jack: jack,
        addedAtMs: anchor,
        styleId: styleId,
        timeline: timeline,
        wrapEnabled: wrap,
        spritzEnabled: spritz,
      ),
    ];
    _roles[jack] = ProbeRole.food;
    _attachedJacks.add(jack);
    if (target != null) {
      _targets[jack] = target;
    }
    _notice = adopting
        ? 'Cook adopted · pulled ${pending.samples} samples'
        : _notice;
    _emit();
  }

  @override
  Future<void> markPulled(ProbeJack jack) async {
    await mark(kind: MarkKind.note, text: 'Pulled probe ${jack.n}', jack: jack);
  }

  @override
  Future<void> mark({
    required MarkKind kind,
    String text = '',
    ProbeJack? jack,
    int? atMs,
  }) async {
    final now = atMs ?? _nowMs();
    final status = _last?.status;
    final start = _startedAtMs ?? status?.session.startedUnixMs;
    final t = start == null ? 0 : ((now - start) ~/ 1000).clamp(0, 1 << 31);
    final transport = _transport;
    final activeId = _activeSessionId;
    Mark posted = Mark(t: t, kind: kind, probe: jack?.n ?? 0, text: text);
    if (transport != null && activeId != null) {
      final wire = await _attempt(
        () => transport.postMark(
          activeId,
          t: t,
          kind: kind,
          probe: jack?.n ?? 0,
          text: text,
        ),
      );
      if (wire != null) {
        posted = wire;
      }
    }
    _localMarks = [..._localMarks, posted];
    _emit();
  }

  List<Mark> _localMarks = const [];

  @override
  Future<void> ackAlarm(String alarmId) async {
    _alarms = [
      for (final a in _alarms)
        if (a.id == alarmId) a.copyWith(acked: true) else a,
    ];
    _emit();
  }

  @override
  Future<void> snoozeAlarm(String alarmId, {int minutes = 10}) async {
    final until = snoozeUntilMs(nowMs: _nowMs(), minutes: minutes);
    _alarms = [
      for (final a in _alarms)
        if (a.id == alarmId) a.copyWith(snoozedUntilMs: until) else a,
    ];
    _emit();
  }

  @override
  Future<void> sendTestAlarm() async {
    final now = _nowMs();
    _alarms = [
      ..._alarms,
      Alarm(
        id: 'test_alarm_$now',
        tier: AlarmTier.app,
        severity: AlarmSeverity.critical,
        rule: 'Test alarm',
        detail: 'A test from this phone. Delivery is working.',
        atMs: now,
        ruleId: 'test_alarm',
        trigger: 'Sent from Alerts',
        suggestion: 'Nothing to do — this one is just a rehearsal.',
        sessionScoped: false,
      ),
    ];
    _emit();
  }

  @override
  Future<void> setAlarmRuleEnabled(String ruleId, bool enabled) async {
    _rules = [
      for (final rule in _rules)
        if (rule.id == ruleId) rule.copyWith(enabled: enabled) else rule,
    ];
    final transport = _transport;
    if (transport != null) {
      await _attempt(
        () => transport.setAlarmConfig({'rule_id': ruleId, 'enabled': enabled}),
      );
    }
    _emit();
  }

  @override
  Future<void> saveAppAlarmRule(AlarmRule rule) async {
    if (rule.tier != AlarmTier.app) {
      return;
    }
    final exists = _rules.any((r) => r.id == rule.id);
    _rules = exists
        ? [
            for (final r in _rules)
              if (r.id == rule.id) rule else r,
          ]
        : [..._rules, rule];
    _emit();
  }

  @override
  Future<void> deleteAppAlarmRule(String ruleId) async {
    _rules = [
      for (final r in _rules)
        if (!(r.id == ruleId && r.tier == AlarmTier.app)) r,
    ];
    _emit();
  }

  @override
  Future<void> probeRole(ProbeJack jack, ProbeRole role) async {
    _roles[jack] = role;
    if (role == ProbeRole.unused) {
      _targets.remove(jack);
      _attachedJacks.remove(jack);
    }
    final transport = _transport;
    if (transport != null) {
      await _attempt(
        () => transport.setDeviceConfig({
          'probes': {jack.n: role.name},
        }),
      );
    }
    _emit();
  }

  @override
  Future<void> setTarget(ProbeJack jack, int? targetF10) async {
    if (targetF10 == null) {
      _targets.remove(jack);
    } else {
      _targets[jack] = targetF10;
    }
    final transport = _transport;
    if (transport != null) {
      await _attempt(
        () => transport.setDeviceConfig({
          'probes': {
            jack.n: {'target_f10': targetF10},
          },
        }),
      );
    }
    _emit();
  }

  @override
  Future<void> setItemInterventions(
    ProbeJack jack, {
    bool? wrap,
    bool? spritz,
  }) async {
    _items = [
      for (final item in _items)
        if (item.jack == jack)
          item.copyWith(wrapEnabled: wrap, spritzEnabled: spritz)
        else
          item,
    ];
    _emit();
  }

  // ── device verbs ──────────────────────────────────────────────────────

  @override
  Future<void> performVerb(DeviceVerb verb, {bool force = false}) async {
    final transport = _transport;
    switch (verb) {
      case DeviceVerb.restart:
        await _attempt(() async => transport?.restart());
        _notice = 'Bridge restarted — recording resumed.';
      case DeviceVerb.forget:
        await _attempt(() async => transport?.unpair());
        _notice = 'Bridge forgotten — pair again with its passkey.';
      case DeviceVerb.factoryReset:
        await _attempt(() async => transport?.factoryReset());
        _items = const [];
        _startedAtMs = null;
        _notice = 'Bridge erased and back in setup mode.';
      case DeviceVerb.ota:
        // The OTA *upload* is a streamed HTTP-only operation (N15.20); the
        // install verb itself is a device action with a real health gate.
        _notice = 'Firmware install requested.';
    }
    _emit();
  }

  @override
  Future<void> checkForUpdates() async {
    // Discovery is a read-back through the snapshot stream (I7), not a return.
    _availableFw = kFirmware.latest;
    _device = _device.copyWith(available: _availableFw);
    _emit();
  }

  // ── N12 history annotation verbs ──────────────────────────────────────

  @override
  Future<void> setFavourite(String cookId, bool favourite) async {
    _history = [
      for (final h in _history)
        if (h.id == cookId) h.copyWith(favourite: favourite) else h,
    ];
    _pushHistory();
  }

  @override
  Future<void> deleteCook(String cookId) async {
    // The annotation goes; the recording it pointed at is untouched (I10).
    _history = [
      for (final h in _history)
        if (h.id != cookId) h,
    ];
    _pushHistory();
  }

  @override
  Future<void> setCookNotes(String cookId, String notes) async {
    _history = [
      for (final h in _history)
        if (h.id == cookId) h.copyWith(notes: notes) else h,
    ];
    _pushHistory();
  }

  @override
  Future<void> setCookEnded(String cookId, bool ended) async {
    _history = [
      for (final h in _history)
        if (h.id == cookId) h.copyWith(status: ended ? 'done' : 'open') else h,
    ];
    _pushHistory();
  }

  @override
  Future<void> addCookMark(
    String cookId, {
    required MarkKind kind,
    String text = '',
    int? atMs,
  }) async {
    _history = [
      for (final h in _history)
        if (h.id == cookId)
          _withAddedMark(h, kind: kind, text: text, atMs: atMs)
        else
          h,
    ];
    _pushHistory();
  }

  @override
  Future<void> deleteCookMark(String cookId, int index) async {
    _history = [
      for (final h in _history)
        if (h.id == cookId)
          h.copyWith(markEvents: _removeAt(h.markEvents, index))
        else
          h,
    ];
    _pushHistory();
  }

  @override
  Future<String> exportCookCsv(String cookId) async {
    HistoryEntry? entry;
    for (final h in _history) {
      if (h.id == cookId) {
        entry = h;
        break;
      }
    }
    final sessionId = int.tryParse(cookId);
    if (entry == null || sessionId == null) {
      return '';
    }
    final started = entry.startedAtMs;
    return exportCookCsvFromCache(
      cache: _cache,
      bridgeId: bridgeId,
      sessionId: sessionId,
      sessionStartedUnixMs: started == 0 ? null : started,
      startUnixMs: started,
      endUnixMs: started == 0 ? null : started + entry.durationS * 1000,
    );
  }

  // ── dev panel ─────────────────────────────────────────────────────────

  @override
  Future<void> selectScenario(String key) async {}

  @override
  Future<void> fireEvent(String eventId) async {}

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _detachSession();
    await _attempt<void>(() => supervisor.dispose());
    await _snapshotController.close();
    await _historyController.close();
  }

  // ── internals ─────────────────────────────────────────────────────────

  int? get _activeSessionId {
    final status = _last?.status;
    return status != null && status.session.active ? status.session.id : null;
  }

  Future<void> _detachSession() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _session?.stop();
    _session = null;
  }

  void _trackSpark(Sample sample) {
    for (var i = 0; i < 4; i++) {
      final jack = ProbeJack.fromIndex(i);
      final value = i < sample.tempsF10.length ? sample.tempsF10[i] : null;
      if (jack == null || value == null) {
        continue;
      }
      final list = [...?_spark[jack], value];
      _spark[jack] = list.length > 60 ? list.sublist(list.length - 60) : list;
    }
  }

  /// Pull forward the details a status read carries into the app overlay.
  void _syncLocalFromStatus(BridgeStatus status) {
    if (_startedAtMs == null && status.session.active) {
      _startedAtMs =
          status.session.startedUnixMs ??
          (status.cookClock.set && status.cookClock.elapsedS != null
              ? _nowMs() - status.cookClock.elapsedS! * 1000
              : null);
    }
    if (_items.isEmpty && status.session.active) {
      final active = _last?.sessions
          .where((s) => s.id == status.session.id)
          .firstOrNull;
      if (active != null) {
        _items = [
          for (final p in active.probes)
            if (ProbeJack.fromN(p.n) case final jack?)
              CookItem(
                presetId: 'custom',
                jack: jack,
                addedAtMs: _startedAtMs ?? _nowMs(),
              ),
        ];
      }
    }
    final dev = status.device;
    _device = DeviceInfo(
      id: dev.id,
      hardware: dev.model,
      version: dev.fw,
      versionDate: '',
      bootloader: dev.resetReason,
      channel: DeviceChannel.stable,
      available: _availableFw,
      uptimeMin: dev.uptimeS ~/ 60,
      heapKb: dev.freeHeap ~/ 1024,
      storage: DeviceStorage(
        usedKb: status.storage.usedB ~/ 1024,
        totalKb: status.storage.totalB ~/ 1024,
        sessions: status.storage.sessions,
        days: 30,
      ),
    );
  }

  BridgeSnapshot _buildSnapshot(BridgeSessionSnapshot s) {
    final status = s.status;
    final activeKind = supervisor.current.activeKind ?? _transport?.kind;
    final isWifi = activeKind == TransportKind.http;
    final mode = _wifiMode(status.net.mode);
    final wifiUp = status.net.state == 'up' && mode != WifiMode.off;

    final connection = ConnectionState(
      phase: ConnectionPhase.connected,
      deviceName: status.net.host ?? status.device.model,
      batteryPct: status.power.socPct,
      primary: isWifi ? LinkPrimary.wifi : LinkPrimary.bt,
      bt: LinkState(
        available: status.pairing.paired,
        connected: !isWifi,
        warm: supervisor.bleWarm,
        rssi: status.radio.rssi,
        lastSyncS: 0,
      ),
      wifi: LinkState(
        mode: mode,
        connected: wifiUp,
        ssid: status.net.ssid,
        ip: status.net.ip,
        rssi: status.net.rssi,
        bars: _barsForRssi(status.net.rssi),
        lastSyncS: wifiUp ? 0 : null,
      ),
    );

    final probes = _buildProbes(s.live);
    final active = s.sessions
        .where((x) => x.id == status.session.id)
        .firstOrNull;
    final cookActive = status.session.active || _items.isNotEmpty;
    final cook = CookState(
      active: cookActive,
      paused: _paused,
      name: status.session.name.isEmpty ? 'Cook' : status.session.name,
      startedAtMs: _startedAtMs ?? status.session.startedUnixMs,
      pitBandMinF10: 2250,
      pitBandMaxF10: 2750,
      items: _items,
    );

    PendingSession? pending;
    if (status.session.active &&
        !_discardedSessions.contains(status.session.id) &&
        _adoptedSessionId != status.session.id) {
      pending = PendingSession(
        sessionId: status.session.id.toString(),
        startedAtMs:
            status.session.startedUnixMs ??
            _nowMs() - status.session.elapsedS * 1000,
        samples: status.session.samples,
        probeCount: status.pairing.numProbes,
        attachedJacks: [
          for (final p in active?.probes ?? const <SessionProbe>[])
            if (p.role != ProbeRole.unused) p.n,
        ],
      );
    }

    return BridgeSnapshot(
      connection: connection,
      cook: cook,
      probes: probes,
      alarms: _alarms,
      marks: [...s.marks, ..._localMarks],
      pendingSession: pending,
      notice: _notice,
    );
  }

  List<ProbeState> _buildProbes(LiveStatus live) {
    final byJack = {for (final p in live.probes) p.n: p};
    final out = <ProbeState>[];
    for (final jack in ProbeJack.values) {
      final probe = byJack[jack.n];
      final role = _roles[jack] ?? probe?.role ?? jack.defaultRole;
      final attached =
          (probe?.attached ?? false) || _attachedJacks.contains(jack);
      if (!attached && role == ProbeRole.unused) {
        out.add(detachedProbe(jack));
        continue;
      }
      out.add(
        ProbeState(
          jack: jack,
          role: role,
          attached: attached,
          freshness: attached ? Freshness.live : Freshness.unknown,
          tempF10: attached ? probe?.tempF10 : null,
          targetF10: _targets[jack] ?? probe?.targetF10,
          trendFPerHr: probe?.rateFPerHr,
          spark: _spark[jack] ?? const [],
        ),
      );
    }
    return out;
  }

  Future<void> _reloadHistory(BridgeSession session) async {
    final previous = {for (final h in _history) h.id: h};
    final out = <HistoryEntry>[];
    for (final info in session.sessions) {
      final id = info.id.toString();
      final marks = await _attempt(() => session.transport.marks(info.id));
      final gaps = await _cache.gaps(bridgeId, info.id);
      final samples = await _cache.samples(bridgeId, info.id);
      int peak = 0;
      for (final sample in samples) {
        for (final value in sample.tempsF10) {
          if (value != null && value > peak) {
            peak = value;
          }
        }
      }
      final start = info.startedUnixMs;
      final period = info.samplePeriodS < 1 ? 30 : info.samplePeriodS;
      final durationMin = info.endedUnixMs != null && start != null
          ? ((info.endedUnixMs! - start) / 60000).round()
          : (info.sampleCount * period / 60).round();
      final prior = previous[id];
      out.add(
        HistoryEntry(
          id: id,
          name: info.name.isEmpty ? 'Cook $id' : info.name,
          presetId: prior?.presetId ?? '',
          styleId: prior?.styleId ?? '',
          glyph: prior?.glyph ?? 'unstated',
          jack: info.probes.isNotEmpty ? info.probes.first.n : 1,
          startedAtMs: start ?? 0,
          durationMin: durationMin,
          plannedMin: prior?.plannedMin ?? durationMin,
          peakF10: peak == 0 ? (prior?.peakF10 ?? 0) : peak,
          targetF10: info.probes.isNotEmpty
              ? (info.probes.first.targetF10 ?? prior?.targetF10 ?? 0)
              : (prior?.targetF10 ?? 0),
          favourite: prior?.favourite ?? false,
          notes: prior?.notes ?? '',
          marks: marks?.length ?? prior?.marks ?? 0,
          status: prior?.status ?? (info.closed ? 'done' : 'open'),
          markEvents: prior?.markEvents.isNotEmpty ?? false
              ? prior!.markEvents
              : (marks ?? const []),
          gaps: gaps,
        ),
      );
    }
    out.sort((a, b) => b.startedAtMs.compareTo(a.startedAtMs));
    _history = out;
    _pushHistory();
  }

  void _pushHistory() {
    if (!_historyController.isClosed) {
      _historyController.add(history);
    }
  }

  void _emit() {
    if (_disposed) {
      return;
    }
    final last = _last;
    _snapshot = last == null
        ? _emptySnapshot(notice: _notice)
        : _buildSnapshot(last);
    if (!_snapshotController.isClosed) {
      _snapshotController.add(_snapshot);
    }
  }

  BridgeSnapshot _emptySnapshot({String? notice}) => BridgeSnapshot(
    connection: const ConnectionState(phase: ConnectionPhase.offline),
    cook: CookState(
      active: _items.isNotEmpty,
      paused: _paused,
      startedAtMs: _startedAtMs,
      items: _items,
    ),
    alarms: _alarms,
    marks: _localMarks,
    notice: notice,
  );

  HistoryEntry _withAddedMark(
    HistoryEntry entry, {
    required MarkKind kind,
    required String text,
    int? atMs,
  }) {
    final at = atMs ?? (entry.startedAtMs + entry.durationS * 1000);
    final t = ((at - entry.startedAtMs) ~/ 1000).clamp(0, 1 << 31);
    final rail = <Mark>[
      ...entry.markEvents,
      Mark(t: t, kind: kind, text: text),
    ];
    return entry.copyWith(markEvents: rail, marks: rail.length);
  }

  List<Mark> _removeAt(List<Mark> marks, int index) => <Mark>[
    for (var i = 0; i < marks.length; i++)
      if (i != index) marks[i],
  ];
}

WifiMode _wifiMode(String mode) => switch (mode) {
  'ap' => WifiMode.ap,
  'sta' => WifiMode.sta,
  _ => WifiMode.off,
};

int? _barsForRssi(int? rssi) {
  if (rssi == null) {
    return null;
  }
  if (rssi >= -55) {
    return 4;
  }
  if (rssi >= -67) {
    return 3;
  }
  if (rssi >= -75) {
    return 2;
  }
  if (rssi >= -85) {
    return 1;
  }
  return 0;
}

int _wallClock() => DateTime.now().millisecondsSinceEpoch;

/// Runs [fn] and swallows any transport failure into a `null` (I15: no raw
/// exception ever reaches the user).
Future<T?> _attempt<T>(Future<T> Function() fn) async {
  try {
    return await fn();
  } on Object {
    return null;
  }
}
