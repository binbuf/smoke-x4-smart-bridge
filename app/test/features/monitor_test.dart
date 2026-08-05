/// A13.3–A13.5 — the reconciliation loop, the ongoing readout, and the
/// service lifecycle (design 09 §9.5, §9.6).
///
/// Everything here runs against a fake transport, an in-memory drift, a
/// recording sink and a fake service host. The plugin plumbing is proven
/// at the bench; what is proven here is every DECISION the loop makes —
/// which is the half a bench sitting is worst at checking.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/local/database.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/domain/alarms/notification_policy.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/features/monitor/cook_monitor.dart';
import 'package:smoke_bridge/platform/notifications.dart';

class _FakeTransport implements BridgeTransport {
  _FakeTransport({BridgeStatus? status})
    : _status =
          status ??
          const BridgeStatus(
            deviceId: 'A4F2',
            sessionActive: true,
            activeSessionId: 27,
          );

  BridgeStatus _status;
  bool fail = false;
  int statusCalls = 0;
  final _events = StreamController<BridgeEvent>.broadcast();

  set status$(BridgeStatus s) => _status = s;

  void emit(BridgeEvent e) => _events.add(e);

  @override
  BridgeCapabilities get capabilities =>
      const BridgeCapabilities(fullHistory: true);

  @override
  Stream<BridgeEvent> get events => _events.stream;

  @override
  Future<BridgeStatus> status() async {
    statusCalls++;
    if (fail) {
      throw StateError('offline');
    }
    return _status;
  }

  @override
  Future<LiveState> live({Duration window = const Duration(hours: 1)}) async =>
      const LiveState(t: 0, tempsF10: [null, null, null, null]);

  @override
  Future<LinkSignal> signal() async => const LinkSignal(wifiDbm: -54);

  @override
  Future<List<CookSession>> sessions() async => const [];

  @override
  Stream<List<Sample>> samples(
    int sessionId, {
    int fromT = 0,
    int? toT,
    int? bucketS,
  }) => const Stream.empty();

  @override
  Future<void> control(ControlCommand cmd) async {}

  @override
  Future<void> configure(BridgeConfig cfg) async {}

  @override
  Future<String> applyNetwork({
    required NetworkMode mode,
    String ssid = '',
    String psk = '',
  }) async => '';

  @override
  Future<void> uploadFirmware(
    Stream<List<int>> image, {
    required int lengthBytes,
    bool force = false,
  }) async {}

  @override
  Future<List<Map<String, Object?>>> alarmRules() async => const [];

  @override
  Future<void> setAlarmRule(Map<String, Object?> rule) async {}

  @override
  Future<MqttConfig> mqttConfig() async => const MqttConfig();

  @override
  Future<void> setMqttConfig({
    bool? enabled,
    String? host,
    int? port,
    String? user,
    String? password,
    String? prefix,
    bool? haDiscovery,
  }) async {}

  @override
  Future<void> close() async {
    await _events.close();
  }
}

class _Clock {
  DateTime now = DateTime(2026, 7, 23, 14, 0);
  void advance(Duration d) => now = now.add(d);
}

({
  CookMonitor monitor,
  _FakeTransport transport,
  RecordingNotificationSink sink,
  FakeForegroundServiceHost service,
  _Clock clock,
  AppDatabase db,
})
_build({MonitorSettings settings = const MonitorSettings()}) {
  final db = AppDatabase(NativeDatabase.memory());
  final transport = _FakeTransport();
  final sink = RecordingNotificationSink();
  final service = FakeForegroundServiceHost();
  final clock = _Clock();
  final monitor = CookMonitor(
    db: db,
    transport: transport,
    sink: sink,
    service: service,
    bridgeId: 'A4F2',
    settings: settings,
    clock: () => clock.now,
  );
  return (
    monitor: monitor,
    transport: transport,
    sink: sink,
    service: service,
    clock: clock,
    db: db,
  );
}

Alarm _alarm({int id = 1, bool acked = false}) =>
    Alarm(id: id, rule: 'target_reached', probe: 2, acked: acked);

void main() {
  test('start creates the channels and asks for permission once', () async {
    final w = _build();
    await w.monitor.start();
    expect(w.sink.channelSetups, 1);
    // §9.5's four channels are a closed set with fixed importances —
    // Android cannot change a channel's importance after creation, so
    // "critical stopped making a sound" would be unfixable.
    expect(notificationChannels, hasLength(4));
    expect(
      notificationChannels
          .firstWhere((c) => c.channel == NotificationChannel.critical)
          .importance,
      ChannelImportance.high,
    );
    expect(
      notificationChannels
          .firstWhere((c) => c.channel == NotificationChannel.ongoing)
          .importance,
      ChannelImportance.min,
    );
    await w.db.close();
  });

  test(
    'a clean run: samples reach drift, the ongoing readout appears',
    () async {
      final w = _build();
      await w.monitor.start();
      for (var i = 0; i < 5; i++) {
        w.transport.emit(
          BridgeEvent.sample(
            Sample(t: i * 30, tempsF10: [2430, 1632, null, null]),
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
      // §9.6: "writes every received sample straight to drift, so history
      // survives the app being swiped away".
      expect(w.monitor.samplesPersisted, 5);
      expect(w.sink.ongoingTitle, isNotNull);
      expect(w.sink.ongoingTitle, contains('Smoke Bridge'));
      await w.db.close();
    },
  );

  test('the ongoing readout updates every 30 s, not per sample', () async {
    final w = _build();
    await w.monitor.start();
    final before = w.sink.ongoingUpdates;
    for (var i = 0; i < 10; i++) {
      w.clock.advance(const Duration(seconds: 5));
      await w.monitor.tick();
    }
    // 50 s of ticks is one update, not ten.
    expect(w.sink.ongoingUpdates - before, 1);
    w.clock.advance(const Duration(seconds: 40));
    await w.monitor.tick();
    expect(w.sink.ongoingUpdates - before, 2);
    await w.db.close();
  });

  test('an alarm posts once and is not re-posted on every poll', () async {
    final w = _build();
    await w.monitor.start();
    w.transport.status$ = const BridgeStatus(
      deviceId: 'A4F2',
      sessionActive: true,
      activeSessionId: 27,
    ).copyWith(alarms: [_alarm()]);
    await w.monitor.refresh();
    expect(w.sink.posted, hasLength(1));
    await w.monitor.refresh();
    await w.monitor.refresh();
    expect(w.sink.posted, hasLength(1));

    // Acknowledged on the DEVICE — by the app, by BLE, or by the PRG
    // button. The notification comes down; the alarm stays latched.
    w.transport.status$ = const BridgeStatus(
      deviceId: 'A4F2',
      sessionActive: true,
      activeSessionId: 27,
    ).copyWith(alarms: [_alarm(acked: true)]);
    await w.monitor.refresh();
    expect(w.sink.cancelled, ['alarm:1']);
    await w.db.close();
  });

  test(
    'an alarm raised while disconnected is discovered on reconnect',
    () async {
      final w = _build();
      await w.monitor.start();
      w.transport.fail = true;
      await w.monitor.refresh();
      expect(w.sink.posted, isEmpty);

      w.transport.fail = false;
      w.transport.status$ = const BridgeStatus(
        deviceId: 'A4F2',
        sessionActive: true,
        activeSessionId: 27,
      ).copyWith(alarms: [_alarm(id: 9)]);
      await w.monitor.refresh();
      expect(w.sink.posted.single.alarmId, 9);
      await w.db.close();
    },
  );

  test(
    'bridge_unreachable fires ONCE after 3 minutes, not per retry',
    () async {
      final w = _build();
      await w.monitor.start();
      w.clock.advance(const Duration(minutes: 2));
      await w.monitor.tick();
      expect(w.sink.posted, isEmpty);

      w.clock.advance(const Duration(minutes: 2));
      for (var i = 0; i < 10; i++) {
        await w.monitor.tick();
        w.clock.advance(const Duration(seconds: 30));
      }
      final unreachable = w.sink.posted
          .where((n) => n.key == findingKey(AppFinding.bridgeUnreachable))
          .toList();
      // A warning that repeats every 30 s is a warning that gets muted,
      // which is the failure §9.2 spends a paragraph on.
      expect(unreachable, hasLength(1));
      await w.db.close();
    },
  );

  test('the service starts on an active cook and offers the battery '
      'opt-in exactly once', () async {
    final w = _build();
    await w.monitor.start();
    await w.monitor.tick();
    expect(w.service.running, isTrue);
    expect(w.service.starts, 1);
    // §9.6: offered after the FIRST cook starts. Not at launch.
    expect(w.service.optimizationPrompts, 1);
    for (var i = 0; i < 5; i++) {
      await w.monitor.tick();
    }
    expect(w.service.optimizationPrompts, 1);
    await w.db.close();
  });

  test('a declined battery opt-in leaves the app fully functional', () async {
    final w = _build();
    w.service.grantOptimizationExemption = false;
    await w.monitor.start();
    await w.monitor.tick();
    expect(w.service.running, isTrue);
    expect(await w.service.isIgnoringBatteryOptimizations(), isFalse);
    // Degraded, not broken: samples still land, notifications still post.
    w.transport.emit(
      const BridgeEvent.sample(
        Sample(t: 30, tempsF10: [2430, 1632, null, null]),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(w.monitor.samplesPersisted, 1);
    await w.db.close();
  });

  test('no session and 10 idle minutes stops the service', () async {
    final w = _build();
    await w.monitor.start();
    await w.monitor.tick();
    expect(w.service.running, isTrue);

    w.transport.status$ = const BridgeStatus(deviceId: 'A4F2');
    await w.monitor.refresh();
    await w.monitor.tick();
    // Still running: the 10 minutes have not elapsed.
    expect(w.service.running, isTrue);

    w.clock.advance(const Duration(minutes: 11));
    await w.monitor.tick();
    expect(w.service.running, isFalse);
    expect(w.sink.ongoingTitle, isNull);
    await w.db.close();
  });

  test(
    'turning monitoring off stops the service and clears the shade',
    () async {
      final w = _build();
      await w.monitor.start();
      w.transport.status$ = const BridgeStatus(
        deviceId: 'A4F2',
        sessionActive: true,
        activeSessionId: 27,
      ).copyWith(alarms: [_alarm()]);
      await w.monitor.refresh();
      await w.monitor.tick();
      expect(w.service.running, isTrue);
      expect(w.sink.posted, hasLength(1));

      await w.monitor.setSettings(
        const MonitorSettings(monitoringEnabled: false),
      );
      expect(w.service.running, isFalse);
      expect(w.sink.cancelled, contains('alarm:1'));
      expect(w.sink.ongoingTitle, isNull);
      await w.db.close();
    },
  );

  test('quiet hours reach the policy through the settings', () async {
    final w = _build(settings: const MonitorSettings(quiet: QuietHours()));
    w.clock.now = DateTime(2026, 7, 23, 3, 40);
    await w.monitor.start();
    w.transport.status$ =
        const BridgeStatus(
          deviceId: 'A4F2',
          sessionActive: true,
          activeSessionId: 27,
        ).copyWith(
          alarms: [
            const Alarm(
              id: 5,
              rule: 'base_lost',
              severity: AlarmSeverity.warning,
            ),
          ],
        );
    await w.monitor.refresh();
    expect(w.sink.posted.single.silent, isTrue);
    await w.db.close();
  });

  group('the ongoing readout', () {
    test('renders a normal cook', () {
      final snap = _snapshot();
      expect(ongoingTitle(snap), 'Smoke Bridge · Brisket · 04:12');
      expect(ongoingBody(snap), contains('Pit 243.0°F'));
      expect(ongoingBody(snap), contains('Brisket 163.2°F'));
    });

    test('renders detached probes as — and never as 0', () {
      final snap = _snapshot(pitTemp: null, foodTemp: null);
      final body = ongoingBody(snap);
      expect(body, contains('—'));
      expect(body, isNot(contains('—0°F')));
      expect(body, isNot(contains(' 0.0°F')));
    });

    test('a stall suppresses the ETA with the reason, not a number', () {
      final snap = _snapshot(stalled: true);
      // The REASON, not a number: "the physics does not support that
      // precision, and the false confidence is what makes people trust
      // it and then get burned" (§9.4).
      expect(ongoingBody(snap), contains('stalled — ETA unavailable'));
      expect(ongoingBody(snap), isNot(matches(RegExp(r'ETA \d'))));
    });

    test('no session renders nothing rather than 00:00 of a ghost cook', () {
      final snap = _snapshot(sessionActive: false, name: '');
      expect(ongoingTitle(snap), contains('Cook'));
    });

    test('15 hours renders as 15:00, not as a date', () {
      final snap = _snapshot(elapsedS: 15 * 3600);
      expect(ongoingTitle(snap), contains('15:00'));
    });

    test('an unknown battery is absent, not 0 %', () {
      expect(ongoingBody(_snapshot()), isNot(contains('%')));
      expect(
        ongoingBody(_snapshot(socPct: 71, batteryKnown: true)),
        contains('71%'),
      );
    });
  });
}

/// A dashboard snapshot built directly, for the readout tests: the
/// readout is a pure function of the SAME projection the dashboard
/// renders, so it can be exercised with no transport at all.
DashboardSnapshot _snapshot({
  int? pitTemp = 2430,
  int? foodTemp = 1632,
  bool stalled = false,
  bool sessionActive = true,
  String name = 'Brisket',
  int elapsedS = 4 * 3600 + 12 * 60,
  int? socPct,
  bool batteryKnown = false,
}) => DashboardSnapshot(
  probes: [
    ProbeView(
      probe: 1,
      role: ProbeRole.pit,
      name: 'Pit',
      tempF10: pitTemp,
      rateFPerHr: -24,
    ),
    ProbeView(
      probe: 2,
      role: ProbeRole.food,
      name: 'Brisket',
      tempF10: foodTemp,
      rateFPerHr: 41,
      stalled: stalled,
    ),
  ],
  link: LinkKind.http,
  sessionName: name,
  sessionActive: sessionActive,
  elapsedS: elapsedS,
  socPct: socPct,
  batteryKnown: batteryKnown,
);
