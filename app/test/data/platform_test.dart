/// N15.15/N15.16/N15.21/N15.22 — the host-testable platform seams.
///
/// Pure Dart (`package:test`), so this runs in both `flutter test` and
/// `dart test test/data`. The plugin-backed halves live in the `*_plugin.dart`
/// files and are proven at the bench; what is exercised here is the channel
/// table, the sink contract and the release lifecycle.
library;

import 'package:smoke_bridge/data/alarms/notification_policy.dart';
import 'package:smoke_bridge/platform/device_facts.dart';
import 'package:smoke_bridge/platform/notifications.dart';
import 'package:smoke_bridge/platform/share.dart';
import 'package:test/test.dart';

void main() {
  group('notification channels (N15.15)', () {
    test('all four channels are declared with unique ids and importances', () {
      expect(notificationChannels, hasLength(4));
      expect(
        notificationChannels.map((c) => c.channel).toSet(),
        NotificationChannel.values.toSet(),
      );
      expect(notificationChannels.map((c) => c.id).toSet(), hasLength(4));
      final critical = notificationChannels.firstWhere(
        (c) => c.channel == NotificationChannel.critical,
      );
      final ongoing = notificationChannels.firstWhere(
        (c) => c.channel == NotificationChannel.ongoing,
      );
      expect(critical.importance, ChannelImportance.high);
      expect(ongoing.importance, ChannelImportance.min);
    });

    test(
      'the recording sink posts, cancels and updates the ongoing readout',
      () async {
        final sink = RecordingNotificationSink();
        await sink.ensureChannels();
        await sink.ensureChannels();
        expect(sink.channelSetups, 2);

        const n = PendingNotification(
          key: 'alarm_1',
          channel: NotificationChannel.critical,
          title: 'Target reached',
          body: 'Pull the brisket',
          silent: false,
        );
        await sink.post(n);
        expect(sink.posted.single.key, 'alarm_1');
        await sink.cancel('alarm_1');
        expect(sink.cancelled, ['alarm_1']);

        await sink.showOngoing('Smoke Bridge', 'Monitoring your cook');
        await sink.showOngoing('Smoke Bridge', 'Monitoring your cook');
        expect(sink.ongoingUpdates, 2);
        expect(sink.ongoingTitle, 'Smoke Bridge');
        await sink.hideOngoing();
        expect(sink.ongoingTitle, isNull);
      },
    );

    test('a denied permission is an answer, not an exception', () async {
      final sink = RecordingNotificationSink(permissionGranted: false);
      expect(await sink.requestPermission(), isFalse);
      expect(await sink.hasPermission(), isFalse);
    });
  });

  group('foreground service host (N15.16)', () {
    test(
      'start/stop are idempotent and the battery opt-in is optional',
      () async {
        final host = FakeForegroundServiceHost();
        expect(host.running, isFalse);
        await host.start();
        await host.start();
        expect(host.running, isTrue);
        expect(host.starts, 1);
        await host.stop();
        await host.stop();
        expect(host.running, isFalse);
        expect(host.stops, 1);

        expect(await host.isIgnoringBatteryOptimizations(), isFalse);
        expect(await host.requestIgnoreBatteryOptimizations(), isTrue);
        expect(host.optimizationPrompts, 1);
        expect(await host.isIgnoringBatteryOptimizations(), isTrue);
      },
    );

    test('declining the battery opt-in still leaves a working host', () async {
      final host = FakeForegroundServiceHost(grantOptimizationExemption: false);
      expect(await host.requestIgnoreBatteryOptimizations(), isFalse);
      expect(await host.isIgnoringBatteryOptimizations(), isFalse);
    });
  });

  group('share sheet (N15.21)', () {
    test('records the file and subject it was handed', () async {
      final sheet = RecordingShareSheet();
      await sheet.shareFile('cook-7.csv', subject: 'Cook 7');
      expect(sheet.shared.single.path, 'cook-7.csv');
      expect(sheet.shared.single.subject, 'Cook 7');
    });
  });

  group('device facts (N15.22)', () {
    test('reports at least the platform, never throwing', () {
      final facts = deviceFacts();
      expect(facts['platform'], isA<String>());
      expect(facts['platform'], isNotEmpty);
    });
  });
}
