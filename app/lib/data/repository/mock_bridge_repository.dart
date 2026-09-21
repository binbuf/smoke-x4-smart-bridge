/// N2.28 — the mock implementation.
///
/// Runs entirely over the scenario fixtures plus the [MockEventBus]. Every
/// screen in Waves 1–3 is built against this; N15 swaps it for the real bridge
/// without touching a widget.
library;

import 'dart:async';

import '../../domain/domain.dart';
import '../content/catalog.dart';
import '../content/fixtures_data.dart';
import '../content/scenarios.dart';
import '../model/alarm.dart';
import '../model/alarm_rule.dart';
import '../model/bridge_snapshot.dart';
import '../model/connection_mode.dart';
import '../model/connection_state.dart';
import '../model/cook_state.dart';
import '../model/device_info.dart';
import '../model/history_entry.dart';
import '../model/mock_event.dart';
import 'bridge_repository.dart';
import 'mock_event_bus.dart';

/// The id of the Wi-Fi network the dev panel's provisioning flows target.
const String _pendingSsid = 'HomeNet-5G';

/// Every screen's source of truth until the real bridge lands.
class MockBridgeRepository implements BridgeRepository {
  MockBridgeRepository({int? nowMs, String initialScenario = 'running'})
    : _now = nowMs ?? DateTime.now().millisecondsSinceEpoch {
    _templates = allScenarios(nowMs: _now);
    _activeKey = _templates.containsKey(initialScenario)
        ? initialScenario
        : 'running';
    _snapshot = _templates[_activeKey]!.snapshot;
    _history = [
      for (final seed in kHistorySeeds) HistoryEntry.fromSeed(seed, _now),
    ];
    _bus = MockEventBus(onEvent: _applyEvent);
  }

  late final Map<String, Scenario> _templates;
  late final MockEventBus _bus;
  late final int _now;

  late String _activeKey;
  late BridgeSnapshot _snapshot;
  late List<HistoryEntry> _history;
  DeviceInfo _deviceFixture = kDevice;

  final StreamController<BridgeSnapshot> _snapshotController =
      StreamController<BridgeSnapshot>.broadcast();
  final StreamController<List<HistoryEntry>> _historyController =
      StreamController<List<HistoryEntry>>.broadcast();

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
  List<AlarmRule> get alarmRules => kAlarmRules;

  @override
  List<MockEventSpec> get mockEvents => kMockEvents;

  @override
  DeviceInfo get device => _deviceFixture;

  @override
  FirmwareInfo get firmware => kFirmware;

  @override
  String get activeScenarioKey => _activeKey;

  @override
  List<Scenario> get scenarios => List.unmodifiable(_templates.values);

  // ── connection ────────────────────────────────────────────────────────

  @override
  Future<void> resync() async {
    _set(
      _snapshot.copyWith(
        connection: _snapshot.connection.copyWith(
          phase: ConnectionPhase.connected,
          error: null,
          bt: _snapshot.connection.bt.copyWith(lastSyncS: 0),
          wifi: _snapshot.connection.wifi.copyWith(lastSyncS: 0),
        ),
        notice: null,
      ),
    );
  }

  @override
  Future<void> connect() async {
    final c = _snapshot.connection;
    _set(
      _snapshot.copyWith(
        connection: c.copyWith(
          phase: ConnectionPhase.connected,
          error: null,
          primary: c.primary ?? LinkPrimary.bt,
          bt: c.bt.copyWith(
            available: true,
            connected: true,
            bars: c.bt.bars ?? 3,
            lastSyncS: 0,
          ),
        ),
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    final c = _snapshot.connection;
    _set(
      _snapshot.copyWith(
        connection: c.copyWith(
          phase: ConnectionPhase.offline,
          error: null,
          primary: null,
          bt: c.bt.copyWith(connected: false, bars: 0, warm: false),
          wifi: c.wifi.copyWith(connected: false, bars: 0),
        ),
      ),
    );
  }

  @override
  Future<void> adoptSession() async {
    final pending = _snapshot.pendingSession;
    if (pending == null) {
      return;
    }
    var probes = _snapshot.probes;
    for (final n in pending.attachedJacks) {
      final jack = ProbeJack.fromN(n);
      if (jack == null) {
        continue;
      }
      probes = _replaceProbe(
        probes,
        jack,
        _probeAt(probes, jack).copyWith(
          role: jack == ProbeJack.four ? ProbeRole.pit : ProbeRole.food,
          attached: true,
          freshness: Freshness.live,
        ),
      );
    }
    _set(
      _snapshot.copyWith(
        cook: CookState(
          active: true,
          name: 'Adopted cook',
          startedAtMs: pending.startedAtMs,
          pitBandMinF10: 2250,
          pitBandMaxF10: 2750,
          items: [
            for (final n in pending.attachedJacks)
              if (ProbeJack.fromN(n) case final jack?)
                CookItem(
                  presetId: 'custom',
                  jack: jack,
                  addedAtMs: pending.startedAtMs,
                ),
          ],
        ),
        probes: probes,
        pendingSession: null,
        marks: [
          ..._snapshot.marks,
          Mark(t: 0, kind: MarkKind.phaseChange, text: 'Cook adopted'),
        ],
        notice: 'Cook adopted · pulled ${pending.samples} samples',
      ),
    );
  }

  // ── cook lifecycle ────────────────────────────────────────────────────

  @override
  Future<void> setCookPaused(bool paused) async {
    // Display-only: `startedAtMs` is untouched, so recording is unaffected (I2).
    _set(_snapshot.copyWith(cook: _snapshot.cook.copyWith(paused: paused)));
  }

  @override
  Future<void> setCookStart(int startedAtMs) async {
    // Moving the window never rewrites samples (I10): only the anchor moves.
    _set(
      _snapshot.copyWith(
        cook: _snapshot.cook.copyWith(startedAtMs: startedAtMs),
      ),
    );
  }

  @override
  Future<void> discardSession() async {
    if (_snapshot.pendingSession == null) {
      return;
    }
    _set(
      _snapshot.copyWith(
        pendingSession: null,
        notice: 'Started fresh — the old recording stays on the bridge.',
      ),
    );
  }

  @override
  Future<void> startCook({
    required String presetId,
    required ProbeJack jack,
    String? styleId,
    String? title,
    int? targetF10,
  }) => _addItem(
    presetId: presetId,
    jack: jack,
    styleId: styleId,
    title: title,
    targetF10: targetF10,
  );

  @override
  Future<void> addItem({
    required String presetId,
    required ProbeJack jack,
    String? styleId,
    int? targetF10,
  }) => _addItem(
    presetId: presetId,
    jack: jack,
    styleId: styleId,
    targetF10: targetF10,
  );

  Future<void> _addItem({
    required String presetId,
    required ProbeJack jack,
    String? styleId,
    String? title,
    int? targetF10,
  }) async {
    final entry = catalog.byId(presetId);
    final style = styleId == null
        ? null
        : catalog.stylesFor(presetId).where((s) => s.id == styleId).firstOrNull;
    final target =
        targetF10 ?? style?.targetF10 ?? entry?.defaultDoneness.targetF10;

    int? pull;
    if (target != null) {
      pull = entry == null
          ? target
          : pullTempFor(
              targetF10: target,
              carryoverF10: entry.carryoverF10,
              hazard: entry.hazard,
            );
    }

    var cook = _snapshot.cook;
    if (!cook.active) {
      cook = CookState(
        active: true,
        name: title ?? '${entry?.name ?? 'Cook'} cook',
        startedAtMs: DateTime.now().millisecondsSinceEpoch,
        pitBandMinF10: entry?.pitBandMinF10 ?? 2250,
        pitBandMaxF10: entry?.pitBandMaxF10 ?? 2750,
        grateTargetF10: 2500,
      );
    } else if (title != null) {
      cook = cook.copyWith(name: title);
    }
    if (style != null) {
      cook = cook.copyWith(
        pitBandMinF10: style.pitBandMinF10,
        pitBandMaxF10: style.pitBandMaxF10,
      );
    }
    final items = [
      for (final it in cook.items)
        if (it.jack != jack) it,
      CookItem(
        presetId: presetId,
        jack: jack,
        addedAtMs: DateTime.now().millisecondsSinceEpoch,
        styleId: styleId,
      ),
    ];
    cook = cook.copyWith(styleId: styleId ?? cook.styleId, items: items);

    final before = _probeAt(_snapshot.probes, jack);
    final probe = before.copyWith(
      role: ProbeRole.food,
      attached: true,
      freshness: Freshness.live,
      targetF10: target,
      pullF10: pull,
      tempF10: before.tempF10 ?? 600,
    );

    _set(
      _snapshot.copyWith(
        cook: cook,
        probes: _replaceProbe(_snapshot.probes, jack, probe),
      ),
    );
  }

  @override
  Future<void> markPulled(ProbeJack jack) async {
    await mark(kind: MarkKind.note, text: 'Pulled probe ${jack.n}', jack: jack);
    final probe = _probeAt(_snapshot.probes, jack).copyWith(etaMin: null);
    _set(
      _snapshot.copyWith(probes: _replaceProbe(_snapshot.probes, jack, probe)),
    );
  }

  @override
  Future<void> mark({
    required MarkKind kind,
    String text = '',
    ProbeJack? jack,
    int? atMs,
  }) async {
    final now = atMs ?? DateTime.now().millisecondsSinceEpoch;
    final start = _snapshot.cook.startedAtMs ?? now;
    final t = ((now - start) ~/ 1000).clamp(0, 1 << 31).toInt();
    _set(
      _snapshot.copyWith(
        marks: [
          ..._snapshot.marks,
          Mark(kind: kind, probe: jack?.n ?? 0, text: text, t: t),
        ],
      ),
    );
  }

  @override
  Future<void> ackAlarm(String alarmId) async {
    _set(
      _snapshot.copyWith(
        alarms: [
          for (final a in _snapshot.alarms)
            if (a.id == alarmId) a.copyWith(acked: true) else a,
        ],
      ),
    );
  }

  @override
  Future<void> probeRole(ProbeJack jack, ProbeRole role) async {
    var probe = _probeAt(_snapshot.probes, jack).copyWith(role: role);
    if (role == ProbeRole.unused) {
      probe = probe.copyWith(
        attached: false,
        freshness: Freshness.unknown,
        tempF10: null,
        etaMin: null,
      );
    }
    _set(
      _snapshot.copyWith(probes: _replaceProbe(_snapshot.probes, jack, probe)),
    );
  }

  @override
  Future<void> setTarget(ProbeJack jack, int? targetF10) async {
    var probe = _probeAt(_snapshot.probes, jack).copyWith(targetF10: targetF10);
    final item = _snapshot.cook.items
        .where((it) => it.jack == jack)
        .firstOrNull;
    final entry = item == null ? null : catalog.byId(item.presetId);
    final pull = (targetF10 == null || entry == null)
        ? targetF10
        : pullTempFor(
            targetF10: targetF10,
            carryoverF10: entry.carryoverF10,
            hazard: entry.hazard,
          );
    probe = probe.copyWith(pullF10: pull);
    _set(
      _snapshot.copyWith(probes: _replaceProbe(_snapshot.probes, jack, probe)),
    );
  }

  @override
  Future<void> setItemInterventions(
    ProbeJack jack, {
    bool? wrap,
    bool? spritz,
  }) async {
    final items = <CookItem>[
      for (final item in _snapshot.cook.items)
        if (item.jack == jack)
          item.copyWith(wrapEnabled: wrap, spritzEnabled: spritz)
        else
          item,
    ];
    _set(_snapshot.copyWith(cook: _snapshot.cook.copyWith(items: items)));
  }

  // ── modes / device verbs ──────────────────────────────────────────────

  @override
  Future<void> applyMode(String modeId) async {
    final c = _snapshot.connection;
    switch (modeId) {
      case 'ble':
        _set(
          _snapshot.copyWith(
            connection: c.copyWith(
              phase: ConnectionPhase.connected,
              error: null,
              primary: LinkPrimary.bt,
              bt: c.bt.copyWith(connected: true, warm: true, lastSyncS: 0),
              wifi: c.wifi.copyWith(mode: WifiMode.off, connected: false),
            ),
            notice: null,
          ),
        );
      case 'ap':
        _set(
          _snapshot.copyWith(
            connection: c.copyWith(
              phase: ConnectionPhase.provisioning,
              error: null,
              primary: LinkPrimary.bt,
              bt: c.bt.copyWith(connected: true, lastSyncS: 0),
              wifi: const LinkState(
                mode: WifiMode.ap,
                ssid: 'SmokeBridge-A4F2',
                passkey: 'smoke-4471',
              ),
            ),
          ),
        );
      case 'sta':
        _set(
          _snapshot.copyWith(
            connection: c.copyWith(
              phase: ConnectionPhase.connecting,
              error: null,
              primary: LinkPrimary.bt,
              bt: c.bt.copyWith(connected: true, lastSyncS: 0),
              wifi: _linkForSta(),
            ),
          ),
        );
    }
  }

  LinkState _linkForSta() =>
      const LinkState(mode: WifiMode.sta, ssid: _pendingSsid);

  @override
  Future<void> performVerb(DeviceVerb verb, {bool force = false}) async {
    final c = _snapshot.connection;
    switch (verb) {
      case DeviceVerb.restart:
        _set(
          _snapshot.copyWith(
            connection: c.copyWith(
              phase: ConnectionPhase.connected,
              error: null,
              primary: c.primary ?? LinkPrimary.bt,
              bt: c.bt.copyWith(
                connected: true,
                bars: c.bt.bars ?? 3,
                lastSyncS: 0,
              ),
            ),
            notice: 'Bridge restarted — recording resumed.',
          ),
        );
      case DeviceVerb.forget:
        _set(
          _snapshot.copyWith(
            connection: c.copyWith(
              phase: ConnectionPhase.offline,
              primary: null,
              bt: c.bt.copyWith(connected: false, bars: 0, warm: false),
              wifi: c.wifi.copyWith(
                mode: WifiMode.off,
                connected: false,
                ssid: null,
                ip: null,
                bars: null,
              ),
            ),
            notice: 'Bridge forgotten — pair again with its passkey.',
          ),
        );
      case DeviceVerb.factoryReset:
        _set(
          BridgeSnapshot(
            connection: c.copyWith(
              phase: ConnectionPhase.offline,
              primary: null,
              bt: c.bt.copyWith(connected: false, bars: 0, warm: false),
              wifi: c.wifi.copyWith(
                mode: WifiMode.off,
                connected: false,
                ssid: null,
                ip: null,
                bars: null,
              ),
            ),
            cook: const CookState(pitBandMinF10: 2250, pitBandMaxF10: 2750),
            probes: _snapshot.probes,
            notice: 'Bridge erased and back in setup mode.',
          ),
        );
      case DeviceVerb.ota:
        _deviceFixture = _deviceFixture.copyWith(
          version: _deviceFixture.available ?? _deviceFixture.version,
          available: null,
          lastCrash: null,
        );
        _set(
          _snapshot.copyWith(
            notice: 'Firmware updated to ${_deviceFixture.version}.',
          ),
        );
    }
  }

  @override
  Future<void> checkForUpdates() async {
    _deviceFixture = _deviceFixture.copyWith(available: kFirmware.latest);
  }

  @override
  Future<void> setFavourite(String cookId, bool favourite) async {
    _history = [
      for (final h in _history)
        if (h.id == cookId) h.copyWith(favourite: favourite) else h,
    ];
    _historyController.add(history);
  }

  // ── dev panel ─────────────────────────────────────────────────────────

  @override
  Future<void> selectScenario(String key) async {
    final template = _templates[key];
    if (template == null) {
      return;
    }
    _activeKey = key;
    _set(template.snapshot);
  }

  @override
  Future<void> fireEvent(String eventId) async => _bus.fire(eventId);

  void _applyEvent(String id) {
    final c = _snapshot.connection;
    switch (id) {
      case 'ble-connected':
        _set(
          _snapshot.copyWith(
            connection: c.copyWith(
              phase: ConnectionPhase.connected,
              error: null,
              primary: c.primary ?? LinkPrimary.bt,
              bt: c.bt.copyWith(
                available: true,
                connected: true,
                bars: 3,
                rssi: -60,
                lastSyncS: 0,
              ),
            ),
          ),
        );
      case 'ble-dropped':
        final primary = c.primary == LinkPrimary.bt
            ? (c.wifi.connected ? LinkPrimary.wifi : null)
            : c.primary;
        _set(
          _snapshot.copyWith(
            connection: c.copyWith(
              phase: primary == null ? ConnectionPhase.offline : c.phase,
              primary: primary,
              bt: c.bt.copyWith(
                connected: false,
                bars: 0,
                lastSyncS: 60,
                warm: false,
              ),
            ),
          ),
        );
      case 'wifi-connecting':
        _set(
          _snapshot.copyWith(
            connection: c.copyWith(
              phase: ConnectionPhase.connecting,
              error: null,
              primary: LinkPrimary.bt,
              bt: c.bt.copyWith(
                connected: true,
                bars: c.bt.bars ?? 3,
                lastSyncS: 0,
              ),
              wifi: _linkForSta(),
            ),
          ),
        );
      case 'wifi-wrong-password':
        _set(
          _snapshot.copyWith(
            connection: c.copyWith(
              phase: ConnectionPhase.error,
              error: 'wrong_password',
              primary: LinkPrimary.bt,
              bt: c.bt.copyWith(connected: true, bars: c.bt.bars ?? 3),
              wifi: _linkForSta(),
            ),
          ),
        );
      case 'wifi-router-unreachable':
        _set(
          _snapshot.copyWith(
            connection: c.copyWith(
              phase: ConnectionPhase.error,
              error: 'router_unreachable',
              primary: LinkPrimary.bt,
              bt: c.bt.copyWith(connected: true, bars: c.bt.bars ?? 3),
              wifi: const LinkState(
                mode: WifiMode.sta,
                ssid: _pendingSsid,
                bars: 0,
                rssi: -92,
              ),
            ),
          ),
        );
      case 'wifi-connected':
        _set(
          _snapshot.copyWith(
            connection: c.copyWith(
              phase: ConnectionPhase.connected,
              error: null,
              primary: LinkPrimary.wifi,
              wifi: const LinkState(
                mode: WifiMode.sta,
                connected: true,
                ssid: _pendingSsid,
                ip: '192.168.1.42',
                bars: 4,
                rssi: -48,
                lastSyncS: 0,
              ),
              bt: c.bt.copyWith(
                connected: true,
                warm: true,
                bars: c.bt.bars ?? 3,
                lastSyncS: 0,
              ),
            ),
          ),
        );
      case 'ap-broadcasting':
        _set(
          _snapshot.copyWith(
            connection: c.copyWith(
              phase: ConnectionPhase.provisioning,
              error: null,
              primary: LinkPrimary.bt,
              bt: c.bt.copyWith(connected: true, bars: c.bt.bars ?? 3),
              wifi: const LinkState(
                mode: WifiMode.ap,
                ssid: 'SmokeBridge-A4F2',
                passkey: 'smoke-4471',
              ),
            ),
          ),
        );
      case 'ap-joined':
        _set(
          _snapshot.copyWith(
            connection: c.copyWith(
              phase: ConnectionPhase.connected,
              error: null,
              primary: LinkPrimary.wifi,
              wifi: const LinkState(
                mode: WifiMode.ap,
                connected: true,
                ssid: 'SmokeBridge-A4F2',
                passkey: 'smoke-4471',
                ip: '192.168.4.1',
                bars: 4,
                rssi: -40,
                lastSyncS: 0,
              ),
            ),
          ),
        );
      case 'switch-rollback':
        _set(
          _snapshot.copyWith(
            connection: c.copyWith(
              phase: ConnectionPhase.rollback,
              error: 'switch_failed',
              primary: LinkPrimary.bt,
              bt: c.bt.copyWith(
                connected: true,
                bars: c.bt.bars ?? 3,
                lastSyncS: 0,
              ),
              wifi: c.wifi.copyWith(connected: false),
            ),
            notice:
                'The bridge could not join that network, so it kept Bluetooth. '
                'Nothing was lost.',
          ),
        );
      case 'resync-complete':
        _set(
          _snapshot.copyWith(
            connection: c.copyWith(
              phase: ConnectionPhase.connected,
              error: null,
              bt: c.bt.copyWith(lastSyncS: 0),
              wifi: c.wifi.copyWith(lastSyncS: 0),
            ),
            notice: null,
          ),
        );
      case 'alarm-target':
        _set(
          _snapshot.copyWith(
            alarms: [
              ..._snapshot.alarms,
              Alarm(
                id: 'evt_target_${DateTime.now().millisecondsSinceEpoch}',
                tier: AlarmTier.device,
                severity: AlarmSeverity.critical,
                rule: 'Target reached',
                detail: 'A probe crossed its target going up.',
                valueF10: 2010,
                atMs: DateTime.now().millisecondsSinceEpoch,
                ruleId: 'target_reached',
                trigger: 'Crossed target upward',
                suggestion: 'Pull it now and rest.',
              ),
            ],
          ),
        );
      case 'alarm-pit-crash':
        _set(
          _snapshot.copyWith(
            alarms: [
              ..._snapshot.alarms,
              Alarm(
                id: 'evt_crash_${DateTime.now().millisecondsSinceEpoch}',
                tier: AlarmTier.device,
                severity: AlarmSeverity.critical,
                rule: 'Pit temperature falling fast',
                detail: 'Down 18°F in 12 min. Check fuel and vents.',
                valueF10: 2486,
                atMs: DateTime.now().millisecondsSinceEpoch,
                ruleId: 'pit_crash',
                trigger: 'Fell 18°F in 12 min',
                suggestion: 'Open a vent or add a lit chimney.',
              ),
            ],
          ),
        );
    }
  }

  // ── internals ─────────────────────────────────────────────────────────

  ProbeState _probeAt(List<ProbeState> probes, ProbeJack jack) {
    for (final p in probes) {
      if (p.jack == jack) {
        return p;
      }
    }
    return ProbeState(jack: jack);
  }

  List<ProbeState> _replaceProbe(
    List<ProbeState> probes,
    ProbeJack jack,
    ProbeState next,
  ) {
    final out = [
      for (final p in probes)
        if (p.jack == jack) next else p,
    ];
    if (!out.any((p) => p.jack == jack)) {
      out.add(next);
    }
    out.sort((a, b) => a.jack.n.compareTo(b.jack.n));
    return out;
  }

  void _set(BridgeSnapshot next) {
    _snapshot = next;
    if (!_snapshotController.isClosed) {
      _snapshotController.add(next);
    }
  }

  @override
  Future<void> dispose() async {
    await _snapshotController.close();
    await _historyController.close();
    await _bus.dispose();
  }
}
