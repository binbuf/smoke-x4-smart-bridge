/// N2.16–N2.30 — the mock repository behaviour.
library;

import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

const int _now = 1700000000000;

MockBridgeRepository _repo([String scenario = 'running']) =>
    MockBridgeRepository(nowMs: _now, initialScenario: scenario);

void main() {
  group('scenario fixtures reproduce the prototype numbers', () {
    test('running', () async {
      final repo = _repo();
      addTearDown(repo.dispose);
      final s = await repo.snapshot().first;

      expect(s.connection.phase, ConnectionPhase.connected);
      expect(s.connection.primary, LinkPrimary.wifi);
      expect(s.connection.batteryPct, 71);
      expect(s.connection.bt.warm, isTrue);
      expect(s.connection.wifi.ssid, 'HomeNet-5G');

      expect(s.cook.active, isTrue);
      expect(s.cook.name, 'Sunday Brisket & Ribs');
      expect(s.cook.items, hasLength(3));
      expect(s.cook.items.first.presetId, 'beef_brisket');
      expect(s.cook.grateTargetF10, 2500);
      expect(s.cook.pitBandMinF10, 2250);

      expect(s.probes, hasLength(4));
      expect(s.probes[0].tempF10, 1642);
      expect(s.probes[0].targetF10, 2010);
      expect(s.probes[0].pullF10, 1930);
      expect(s.probes[0].stalled, isTrue);
      expect(s.probes[0].etaMin, isNull);
      expect(s.probes[0].etaNote, contains('stall'));
      expect(s.probes[2].etaMin, 11);
      expect(s.probes[3].role, ProbeRole.pit);
      expect(s.probes[3].tempF10, 2486);

      expect(s.alarms, hasLength(2));
      expect(s.alarms.first.tier, AlarmTier.device);
      expect(s.alarms.first.severity, AlarmSeverity.critical);
      expect(s.alarms.last.tier, AlarmTier.app);

      expect(s.marks, hasLength(5));
      expect(s.marks.first.kind, MarkKind.phaseChange);
      expect(s.marks[2].kind, MarkKind.wrapped);
    });

    test('idle is instrument mode', () async {
      final repo = _repo('idle');
      addTearDown(repo.dispose);
      final s = await repo.snapshot().first;
      expect(s.cook.active, isFalse);
      expect(s.probes[0].targetF10, isNull);
      expect(s.probes[1].attached, isFalse);
      expect(s.alarms, isEmpty);
    });

    test('existing carries an unadopted session', () async {
      final repo = _repo('existing');
      addTearDown(repo.dispose);
      final s = await repo.snapshot().first;
      expect(s.connection.primary, LinkPrimary.bt);
      expect(s.pendingSession, isNotNull);
      expect(s.pendingSession!.samples, 253);
      expect(s.pendingSession!.attachedJacks, [1, 4]);
      expect(s.pendingSession!.startedAtMs, _now - (2 * 3600 + 5 * 60) * 1000);
    });

    test('offline is frozen and removes derived values (I4)', () async {
      final repo = _repo('offline');
      addTearDown(repo.dispose);
      final s = await repo.snapshot().first;
      expect(s.connection.phase, ConnectionPhase.offline);
      expect(s.connection.primary, isNull);
      expect(s.probes[0].freshness, Freshness.frozen);
      expect(s.probes[0].reading.trendFPerHr, isNull);
      expect(s.probes[0].reading.eta, isNull);
      expect(s.probes[0].reading.temp.f10, 1763);
      expect(s.alarms.single.ruleId, 'bridge_unreachable');
    });

    test('every connection-matrix scenario loads', () async {
      for (final key in [
        'bt_only',
        'sta_connecting',
        'sta_wrong_password',
        'sta_router_unreachable',
        'ap_broadcasting',
        'ap_joined',
        'switch_rollback',
      ]) {
        final repo = _repo(key);
        addTearDown(repo.dispose);
        final s = await repo.snapshot().first;
        expect(s.probes, hasLength(4), reason: key);
        expect(s.connection.phase, isA<ConnectionPhase>(), reason: key);
      }
    });
  });

  group('mutations', () {
    test('resync clears the sync ages and the notice', () async {
      final repo = _repo('offline');
      addTearDown(repo.dispose);
      await repo.resync();
      final s = await repo.snapshot().first;
      expect(s.connection.phase, ConnectionPhase.connected);
      expect(s.connection.bt.lastSyncS, 0);
      expect(s.connection.wifi.lastSyncS, 0);
    });

    test('ble-dropped on BLE-only goes offline', () async {
      final repo = _repo('bt_only');
      addTearDown(repo.dispose);
      await repo.fireEvent('ble-dropped');
      final s = await repo.snapshot().first;
      expect(s.connection.primary, isNull);
      expect(s.connection.phase, ConnectionPhase.offline);
      expect(s.connection.bt.connected, isFalse);
    });

    test('alarm events append and ackAlarm marks acked', () async {
      final repo = _repo('idle');
      addTearDown(repo.dispose);
      await repo.fireEvent('alarm-target');
      var s = await repo.snapshot().first;
      expect(s.alarms, hasLength(1));
      expect(s.alarms.single.ruleId, 'target_reached');
      await repo.ackAlarm(s.alarms.single.id);
      s = await repo.snapshot().first;
      expect(s.alarms.single.acked, isTrue);
    });

    test('adoptSession clears the pending session and starts a cook', () async {
      final repo = _repo('existing');
      addTearDown(repo.dispose);
      await repo.adoptSession();
      final s = await repo.snapshot().first;
      expect(s.pendingSession, isNull);
      expect(s.cook.active, isTrue);
      expect(s.cook.startedAtMs, _now - (2 * 3600 + 5 * 60) * 1000);
      expect(s.notice, contains('253'));
      expect(s.probes[0].role, ProbeRole.food);
      expect(s.probes[3].role, ProbeRole.pit);
    });

    test('startCook sets a safe pull temperature', () async {
      final repo = _repo('idle');
      addTearDown(repo.dispose);
      await repo.startCook(presetId: 'beef_brisket', jack: ProbeJack.one);
      final s = await repo.snapshot().first;
      expect(s.cook.active, isTrue);
      expect(s.cook.items.single.presetId, 'beef_brisket');
      final probe = s.probes[0];
      expect(probe.role, ProbeRole.food);
      expect(probe.targetF10, 2010);
      expect(probe.pullF10, lessThanOrEqualTo(probe.targetF10!));
      expect(probe.tempF10, 681); // idle jack 1 already reads 68.1°F
    });

    test('applyMode("sta") enters the connecting phase', () async {
      final repo = _repo('bt_only');
      addTearDown(repo.dispose);
      await repo.applyMode('sta');
      final s = await repo.snapshot().first;
      expect(s.connection.phase, ConnectionPhase.connecting);
      expect(s.connection.wifi.mode, WifiMode.sta);
      expect(s.connection.wifi.ssid, 'HomeNet-5G');
    });

    test('factory reset clears the cook and the links', () async {
      final repo = _repo();
      addTearDown(repo.dispose);
      await repo.performVerb(DeviceVerb.factoryReset);
      final s = await repo.snapshot().first;
      expect(s.cook.active, isFalse);
      expect(s.cook.items, isEmpty);
      expect(s.alarms, isEmpty);
      expect(s.connection.phase, ConnectionPhase.offline);
      expect(s.notice, contains('setup mode'));
    });

    test('selectScenario swaps the active fixture and resets it', () async {
      final repo = _repo();
      addTearDown(repo.dispose);
      await repo.selectScenario('offline');
      expect(repo.activeScenarioKey, 'offline');
      final s = await repo.snapshot().first;
      expect(s.connection.phase, ConnectionPhase.offline);
    });
  });

  group('streams', () {
    test('snapshot() emits the current value then every change', () async {
      final repo = _repo('idle');
      addTearDown(repo.dispose);
      final seen = <BridgeSnapshot>[];
      final sub = repo.snapshot().listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      await repo.connect();
      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(2));
      expect(seen.last.connection.bt.connected, isTrue);
      await sub.cancel();
    });

    test('history is the 7 past cooks and setFavourite updates it', () async {
      final repo = _repo();
      addTearDown(repo.dispose);
      expect(repo.history, hasLength(7));
      expect(repo.history.first.id, 'c1');
      expect(repo.history.first.startedAtMs, _now - 8640 * 60 * 1000);
      await repo.setFavourite('c2', true);
      expect(repo.history.firstWhere((h) => h.id == 'c2').favourite, isTrue);
    });
  });

  group('static content', () {
    test('the repository exposes the whole content library', () async {
      final repo = _repo();
      addTearDown(repo.dispose);
      expect(repo.catalog.entries, hasLength(139));
      expect(repo.connectionModes, hasLength(3));
      expect(repo.alarmRules, hasLength(12));
      expect(
        repo.alarmRules.where((r) => r.tier == AlarmTier.device),
        hasLength(9),
      );
      expect(
        repo.alarmRules.where((r) => r.tier == AlarmTier.app),
        hasLength(3),
      );
      expect(repo.mockEvents, hasLength(12));
      expect(repo.device.id, 'A4F2-9C71');
      expect(repo.firmware.latest, 'v1.5.0');
    });
  });
}
