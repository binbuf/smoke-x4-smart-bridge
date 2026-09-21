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

    test('N11.8 snoozeAlarm silences without acknowledging', () async {
      final repo = _repo();
      addTearDown(repo.dispose);
      await repo.snoozeAlarm('pit_crash');
      final a = repo.current.alarms.firstWhere((x) => x.id == 'pit_crash');
      expect(a.acked, isFalse);
      expect(a.snoozedUntilMs, isNotNull);

      // The next alarm is untouched.
      final other = repo.current.alarms.firstWhere((x) => x.id == 'eta_soon');
      expect(other.snoozedUntilMs, isNull);
    });

    test('N11.3 sendTestAlarm adds a critical app alarm', () async {
      final repo = _repo('idle');
      addTearDown(repo.dispose);
      final before = repo.current.alarms.length;
      await repo.sendTestAlarm();
      final alarms = repo.current.alarms;
      expect(alarms, hasLength(before + 1));
      final test = alarms.last;
      expect(test.ruleId, 'test_alarm');
      expect(test.tier, AlarmTier.app);
      expect(test.severity, AlarmSeverity.critical);
    });

    test('N11.4/N11.16 rule toggles and the app-rule editor', () async {
      final repo = _repo('idle');
      addTearDown(repo.dispose);
      expect(repo.alarmRules, hasLength(12));

      await repo.setAlarmRuleEnabled('target_reached', false);
      expect(
        repo.alarmRules.firstWhere((r) => r.id == 'target_reached').enabled,
        isFalse,
      );

      // A device rule cannot be invented (I2): save refuses a non-app tier.
      await repo.saveAppAlarmRule(
        const AlarmRule(
          id: 'sneaky',
          tier: AlarmTier.device,
          name: 'Sneaky device rule',
          desc: 'nope',
          severity: AlarmSeverity.critical,
          scope: AlarmScope.device,
        ),
      );
      expect(repo.alarmRules.any((r) => r.id == 'sneaky'), isFalse);

      await repo.saveAppAlarmRule(
        const AlarmRule(
          id: 'sauce_split',
          tier: AlarmTier.app,
          name: 'Sauce split',
          desc: 'Insight added on this phone.',
          severity: AlarmSeverity.info,
          scope: AlarmScope.perProbe,
        ),
      );
      expect(
        repo.alarmRules.where((r) => r.tier == AlarmTier.app),
        hasLength(4),
      );

      await repo.saveAppAlarmRule(
        const AlarmRule(
          id: 'sauce_split',
          tier: AlarmTier.app,
          name: 'Sauce split (edited)',
          desc: 'Insight added on this phone.',
          severity: AlarmSeverity.warning,
          scope: AlarmScope.perProbe,
        ),
      );
      expect(
        repo.alarmRules.firstWhere((r) => r.id == 'sauce_split').name,
        'Sauce split (edited)',
      );

      await repo.deleteAppAlarmRule('sauce_split');
      expect(
        repo.alarmRules.where((r) => r.tier == AlarmTier.app),
        hasLength(3),
      );
      // The nine device rules survive an app-rule edit.
      expect(
        repo.alarmRules.where((r) => r.tier == AlarmTier.device),
        hasLength(9),
      );
    });

    test('N11.15 disconnect mid-cook raises bridge_unreachable once', () async {
      final repo = _repo();
      addTearDown(repo.dispose);
      await repo.disconnect();
      final first = repo.current.alarms
          .where((a) => a.ruleId == 'bridge_unreachable')
          .toList();
      expect(first, hasLength(1));
      expect(first.single.tier, AlarmTier.app);

      // A second drop does not stack another insight.
      await repo.disconnect();
      expect(
        repo.current.alarms
            .where((a) => a.ruleId == 'bridge_unreachable')
            .length,
        1,
      );
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

    test('setCookPaused freezes only the flag, never the start (I2)', () async {
      final repo = _repo();
      addTearDown(repo.dispose);
      final before = await repo.snapshot().first;
      await repo.setCookPaused(true);
      var s = await repo.snapshot().first;
      expect(s.cook.paused, isTrue);
      expect(s.cook.startedAtMs, before.cook.startedAtMs);
      await repo.setCookPaused(false);
      s = await repo.snapshot().first;
      expect(s.cook.paused, isFalse);
    });

    test(
      'setCookStart moves the window and keeps every sample (I10)',
      () async {
        final repo = _repo();
        addTearDown(repo.dispose);
        final before = await repo.snapshot().first;
        await repo.setCookStart(_now - 60 * 60 * 1000);
        final s = await repo.snapshot().first;
        expect(s.cook.startedAtMs, _now - 60 * 60 * 1000);
        expect(s.probes, before.probes);
        expect(s.marks, before.marks);
      },
    );

    test('discardSession drops the pending session', () async {
      final repo = _repo('existing');
      addTearDown(repo.dispose);
      await repo.discardSession();
      final s = await repo.snapshot().first;
      expect(s.pendingSession, isNull);
      expect(s.cook.active, isFalse);
      expect(s.notice, contains('Started fresh'));
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

    test(
      'setTarget is metadata only — no sample is rewritten (N6.13, I10)',
      () async {
        final repo = _repo();
        addTearDown(repo.dispose);
        final before = await repo.snapshot().first;
        final beforeProbe = before.probes.firstWhere(
          (p) => p.jack == ProbeJack.one,
        );

        await repo.setTarget(ProbeJack.one, 1950);
        final after = await repo.snapshot().first;
        final afterProbe = after.probes.firstWhere(
          (p) => p.jack == ProbeJack.one,
        );

        expect(afterProbe.targetF10, 1950);
        // Whole-muscle brisket: 195 °F target − 8 °F carryover, no floor.
        expect(afterProbe.pullF10, 1870);
        // The recorded reading, its history and every mark are untouched.
        expect(afterProbe.tempF10, beforeProbe.tempF10);
        expect(afterProbe.spark, beforeProbe.spark);
        expect(afterProbe.peakF10, beforeProbe.peakF10);
        expect(afterProbe.lowF10, beforeProbe.lowF10);
        expect(afterProbe.avgF10, beforeProbe.avgF10);
        expect(after.marks, before.marks);
      },
    );

    test(
      'probeRole("unused") clears the reading, never zeroes it (I3)',
      () async {
        final repo = _repo();
        addTearDown(repo.dispose);
        await repo.probeRole(ProbeJack.one, ProbeRole.unused);
        final s = await repo.snapshot().first;
        final probe = s.probes.firstWhere((p) => p.jack == ProbeJack.one);
        expect(probe.role, ProbeRole.unused);
        expect(probe.attached, isFalse);
        expect(probe.tempF10, isNull);
      },
    );

    test(
      'setItemInterventions toggles one item and leaves the rest (N8.10)',
      () async {
        final repo = _repo();
        addTearDown(repo.dispose);
        final before = await repo.snapshot().first;
        expect(before.cook.items.first.wrapEnabled, isNull);
        expect(before.cook.items.first.spritzEnabled, isNull);

        await repo.setItemInterventions(ProbeJack.one, wrap: false);
        var items = (await repo.snapshot().first).cook.items;
        expect(items.first.wrapEnabled, isFalse);
        // A null flag leaves the other override untouched.
        expect(items.first.spritzEnabled, isNull);
        // Other items are unchanged.
        expect(items[1].wrapEnabled, isNull);

        await repo.setItemInterventions(ProbeJack.one, spritz: true);
        items = (await repo.snapshot().first).cook.items;
        expect(items.first.wrapEnabled, isFalse);
        expect(items.first.spritzEnabled, isTrue);
        // The recorded samples/marks are never touched (I10).
        expect((await repo.snapshot().first).marks, before.marks);
      },
    );

    test('applyMode("sta") enters the connecting phase', () async {
      final repo = _repo('bt_only');
      addTearDown(repo.dispose);
      await repo.applyMode('sta');
      final s = await repo.snapshot().first;
      expect(s.connection.phase, ConnectionPhase.connecting);
      expect(s.connection.wifi.mode, WifiMode.sta);
      expect(s.connection.wifi.ssid, 'HomeNet-5G');
    });

    test(
      'joinWifi sends the credential over BLE and never stores it',
      () async {
        final repo = _repo('bt_only');
        addTearDown(repo.dispose);
        await repo.joinWifi(ssid: 'HomeNet-2.4G', password: 'hunter2');
        final s = await repo.snapshot().first;
        expect(s.connection.phase, ConnectionPhase.connecting);
        expect(s.connection.primary, LinkPrimary.bt);
        expect(s.connection.bt.connected, isTrue);
        expect(s.connection.wifi.mode, WifiMode.sta);
        expect(s.connection.wifi.ssid, 'HomeNet-2.4G');
        // Nothing anywhere in the snapshot carries the password.
        expect(s.toString(), isNot(contains('hunter2')));
      },
    );

    test('useHotspot broadcasts; confirmHotspotJoined completes it', () async {
      final repo = _repo('bt_only');
      addTearDown(repo.dispose);
      await repo.useHotspot();
      var s = await repo.snapshot().first;
      expect(s.connection.phase, ConnectionPhase.provisioning);
      expect(s.connection.primary, LinkPrimary.bt);
      expect(s.connection.wifi.mode, WifiMode.ap);
      expect(s.connection.wifi.passkey, 'smoke-4471');

      await repo.confirmHotspotJoined();
      s = await repo.snapshot().first;
      expect(s.connection.phase, ConnectionPhase.connected);
      expect(s.connection.primary, LinkPrimary.wifi);
      expect(s.connection.wifi.mode, WifiMode.ap);
      expect(s.connection.wifi.connected, isTrue);
      expect(s.connection.wifi.ip, '192.168.4.1');
    });

    test('forgetNetwork clears the SSID and falls back to Bluetooth', () async {
      final repo = _repo();
      addTearDown(repo.dispose);
      await repo.forgetNetwork();
      final s = await repo.snapshot().first;
      expect(s.connection.wifi.mode, WifiMode.off);
      expect(s.connection.wifi.ssid, isNull);
      expect(s.connection.wifi.connected, isFalse);
      expect(s.connection.primary, LinkPrimary.bt);
      expect(s.notice, contains('forgotten'));
    });

    test('resync recovers a rollback to the connected phase', () async {
      final repo = _repo('switch_rollback');
      addTearDown(repo.dispose);
      await repo.resync();
      final s = await repo.snapshot().first;
      expect(s.connection.phase, ConnectionPhase.connected);
      expect(s.connection.error, isNull);
      expect(s.connection.bt.lastSyncS, 0);
      expect(s.connection.wifi.lastSyncS, 0);
    });

    test(
      'startCook stores a custom timeline and its reminders (N9.11/N9.18)',
      () async {
        final repo = _repo('idle');
        addTearDown(repo.dispose);
        const timeline = CookTimeline(
          totalMin: MinuteRange(90, 150),
          restMin: 10,
        );
        await repo.startCook(
          presetId: 'custom_seam',
          jack: ProbeJack.two,
          targetF10: 1450,
          pullF10: 1430,
          timeline: timeline,
          wrap: true,
          spritz: false,
        );
        final item = (await repo.snapshot().first).cook.items.single;
        expect(item.presetId, 'custom_seam');
        expect(item.timeline, timeline);
        expect(item.wrapEnabled, isTrue);
        expect(item.spritzEnabled, isFalse);
      },
    );

    test(
      'startCook adopts a pending session, backdated (N9.15, I10)',
      () async {
        final repo = _repo('existing');
        addTearDown(repo.dispose);
        final pending = (await repo.snapshot().first).pendingSession!;
        await repo.startCook(
          presetId: 'beef_brisket',
          jack: ProbeJack.two,
          adoptPendingSession: true,
        );
        final s = await repo.snapshot().first;
        expect(s.pendingSession, isNull);
        expect(s.cook.startedAtMs, pending.startedAtMs);
        expect(s.cook.items.single.presetId, 'beef_brisket');
        expect(s.notice, contains('${pending.samples}'));
      },
    );

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
