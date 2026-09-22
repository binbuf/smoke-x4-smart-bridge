/// N15.17 — the background cook monitor, driven by the pure seams.
///
/// The repository is the real [MockBridgeRepository] (pure Dart), the sink and
/// service are the recording fakes, and the clock is injected. No plugin, no
/// channel, no timer.
library;

import 'package:smoke_bridge/data/alarms/notification_policy.dart';
import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/features/monitor/monitor.dart';
import 'package:smoke_bridge/platform/notifications.dart';
import 'package:test/test.dart';

const int _t0 = 1700000000000;

MockBridgeRepository _repo({String scenario = 'running'}) =>
    MockBridgeRepository(nowMs: _t0, initialScenario: scenario);

(CookMonitor, RecordingNotificationSink, FakeForegroundServiceHost) _monitor({
  MockBridgeRepository? repository,
  DateTime Function()? clock,
  MonitorSettings settings = const MonitorSettings(
    quiet: QuietHours(enabled: false),
  ),
}) {
  final sink = RecordingNotificationSink();
  final service = FakeForegroundServiceHost();
  final monitor = CookMonitor(
    repository: repository ?? _repo(),
    sink: sink,
    service: service,
    settings: settings,
    clock: clock ?? () => DateTime.fromMillisecondsSinceEpoch(_t0),
  );
  return (monitor, sink, service);
}

void main() {
  test(
    'starts the foreground service and offers battery opt-in once',
    () async {
      final (monitor, _, service) = _monitor();
      addTearDown(monitor.dispose);

      await monitor.start();
      await monitor.tick();
      expect(service.running, isTrue);
      expect(service.starts, 1);
      expect(service.optimizationPrompts, 1);

      // A second tick does not re-offer.
      await monitor.tick();
      expect(service.starts, 1);
      expect(service.optimizationPrompts, 1);
    },
  );

  test(
    'posts a device alarm once and does not re-post on every poll',
    () async {
      final (monitor, sink, _) = _monitor();
      addTearDown(monitor.dispose);

      await monitor.start();
      await monitor.tick();

      final pitCrash = sink.posted.where((n) => n.key == 'alarm:pit_crash');
      expect(pitCrash, hasLength(1));
      expect(pitCrash.single.channel.name, 'critical');

      final before = sink.posted.length;
      await monitor.refresh();
      await monitor.tick();
      expect(
        sink.posted.length,
        before,
        reason: 'a poll must not stack alarms',
      );
    },
  );

  test(
    'the escalation ladder reposts a critical alarm at the next rung',
    () async {
      var now = _t0;
      final (monitor, sink, _) = _monitor(
        clock: () => DateTime.fromMillisecondsSinceEpoch(now),
      );
      addTearDown(monitor.dispose);

      await monitor.start();
      await monitor.tick();
      final first = sink.posted.singleWhere((n) => n.key == 'alarm:pit_crash');
      expect(first.escalation, 0);
      expect(first.fullScreen, isFalse);

      // Ten minutes later the unacknowledged alarm lights the screen.
      now = _t0 + 10 * 60 * 1000;
      await monitor.tick();
      final last = sink.posted.lastWhere((n) => n.key == 'alarm:pit_crash');
      expect(last.escalation, 2);
      expect(last.fullScreen, isTrue);
      expect(last.repost, isTrue);
    },
  );

  test(
    'monitoring off withdraws notifications and stops the service',
    () async {
      final (monitor, sink, service) = _monitor();
      addTearDown(monitor.dispose);

      await monitor.start();
      await monitor.tick();
      expect(service.running, isTrue);
      expect(sink.posted, isNotEmpty);

      await monitor.setSettings(
        const MonitorSettings(
          monitoringEnabled: false,
          quiet: QuietHours(enabled: false),
        ),
      );
      expect(service.running, isFalse);
      expect(sink.cancelled, contains('alarm:pit_crash'));
      expect(sink.ongoingTitle, isNull);
    },
  );

  test('a stall raises the advisory stall finding', () async {
    // A clean running snapshot with the already-app alarm removed, so the
    // finding is the only signal (the repository raised no stall alarm).
    final repository = _repo();
    final clean = repository.current.copyWith(alarms: const []);
    final (monitor, sink, _) = _monitor(repository: repository);
    addTearDown(monitor.dispose);

    // Drive the monitor with the cleaned snapshot directly.
    monitor.handleSnapshot(clean);
    await monitor.settle();

    expect(sink.posted.any((n) => n.key == 'finding:stallStarted'), isTrue);
  });

  test(
    'unreachable mid-cook raises the advisory finding after three minutes',
    () async {
      var now = _t0;
      final repository = _repo();
      final (monitor, sink, _) = _monitor(
        repository: repository,
        clock: () => DateTime.fromMillisecondsSinceEpoch(now),
      );
      addTearDown(monitor.dispose);

      final connected = repository.current.copyWith(alarms: const []);
      monitor.handleSnapshot(connected);
      await monitor.settle();
      expect(
        sink.posted.any((n) => n.key == 'finding:bridgeUnreachable'),
        isFalse,
      );

      now = _t0 + 4 * 60 * 1000;
      final offline = connected.copyWith(
        connection: const ConnectionState(phase: ConnectionPhase.offline),
      );
      monitor.handleSnapshot(offline);
      await monitor.settle();
      expect(
        sink.posted.any((n) => n.key == 'finding:bridgeUnreachable'),
        isTrue,
      );

      // Reflection on the same pass does not stack it (I2).
      final count = sink.posted
          .where((n) => n.key == 'finding:bridgeUnreachable')
          .length;
      monitor.handleSnapshot(offline);
      await monitor.settle();
      expect(
        sink.posted.where((n) => n.key == 'finding:bridgeUnreachable').length,
        count,
      );
    },
  );

  test(
    'the ongoing readout appears for an active cook and refreshes on tick',
    () async {
      var now = _t0;
      final (monitor, sink, _) = _monitor(
        clock: () => DateTime.fromMillisecondsSinceEpoch(now),
      );
      addTearDown(monitor.dispose);

      await monitor.start();
      expect(sink.ongoingTitle, contains('Smoke Bridge'));
      expect(sink.ongoingBody, contains('Pit'));

      final updates = sink.ongoingUpdates;
      now = _t0 + 31 * 1000;
      await monitor.tick();
      expect(sink.ongoingUpdates, greaterThan(updates));
    },
  );
}
