/// A13.1 — the notification policy (design 09 §9.5).
///
/// The claim under test is the one §9.1 makes and §9.5 delivers: the app
/// MIRRORS the device's alarm state. It posts once, it does not re-decide,
/// it withdraws when the device says acknowledged, and it never silences
/// a critical alarm — because overcooking a brisket at 3 a.m. is precisely
/// the thing worth waking up for.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/alarms/notification_policy.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';

Alarm _alarm({
  int id = 1,
  String rule = 'target_reached',
  AlarmSeverity severity = AlarmSeverity.critical,
  int probe = 2,
  bool acked = false,
  int? valueF10 = 2031,
}) => Alarm(
  id: id,
  rule: rule,
  probe: probe,
  severity: severity,
  acked: acked,
  valueF10: valueF10,
);

final _night = DateTime(2026, 7, 23, 3, 40);
final _day = DateTime(2026, 7, 23, 14, 0);

void main() {
  group('quiet hours', () {
    test('the default window wraps midnight', () {
      const q = QuietHours();
      expect(q.contains(DateTime(2026, 1, 1, 22, 0)), isTrue);
      expect(q.contains(DateTime(2026, 1, 1, 23, 59)), isTrue);
      expect(q.contains(DateTime(2026, 1, 1, 0, 0)), isTrue);
      expect(q.contains(DateTime(2026, 1, 1, 5, 59)), isTrue);
      expect(q.contains(DateTime(2026, 1, 1, 6, 0)), isFalse);
      expect(q.contains(DateTime(2026, 1, 1, 21, 59)), isFalse);
    });

    test('a same-day window does not wrap', () {
      const q = QuietHours(startHour: 9, endHour: 17);
      expect(q.contains(DateTime(2026, 1, 1, 12)), isTrue);
      expect(q.contains(DateTime(2026, 1, 1, 3)), isFalse);
    });

    test('disabled means never quiet, and a degenerate window is never '
        'quiet either', () {
      expect(const QuietHours(enabled: false).contains(_night), isFalse);
      expect(
        const QuietHours(startHour: 5, endHour: 5).contains(_night),
        isFalse,
      );
    });
  });

  group('planNotifications', () {
    test('a critical alarm posts, and SOUNDS through quiet hours', () {
      final plan = planNotifications(
        alarms: [_alarm()],
        alreadyPosted: const {},
        now: _night,
      );
      expect(plan.post, hasLength(1));
      expect(plan.post.single.channel, NotificationChannel.critical);
      // The whole argument for `target_reached` being critical.
      expect(plan.post.single.silent, isFalse);
    });

    test('a warning is SILENCED but still posted during quiet hours', () {
      final plan = planNotifications(
        alarms: [_alarm(severity: AlarmSeverity.warning, rule: 'base_lost')],
        alreadyPosted: const {},
        now: _night,
      );
      expect(plan.post.single.channel, NotificationChannel.warning);
      // Silencing is not suppressing: it is still in the shade at 07:00.
      expect(plan.post.single.silent, isTrue);
    });

    test('the same warning sounds in daylight', () {
      final plan = planNotifications(
        alarms: [_alarm(severity: AlarmSeverity.warning)],
        alreadyPosted: const {},
        now: _day,
      );
      expect(plan.post.single.silent, isFalse);
    });

    test('an already-posted alarm is not re-posted on every poll', () {
      final a = _alarm();
      final plan = planNotifications(
        alarms: [a],
        alreadyPosted: {alarmKey(a)},
        now: _day,
      );
      expect(plan.post, isEmpty);
      expect(plan.withdraw, isEmpty);
    });

    test('acknowledging on the DEVICE withdraws the notification', () {
      final a = _alarm(acked: true);
      final plan = planNotifications(
        alarms: [a],
        alreadyPosted: {alarmKey(a)},
        now: _day,
      );
      expect(plan.post, isEmpty);
      expect(plan.withdraw, [alarmKey(a)]);
    });

    test('an alarm that fired while the app was dead is posted once on '
        'reconnect', () {
      // 09 §9.1's exact scenario: it fired at 03:40 while the phone was
      // face-down, and it is still latched and unacknowledged at 07:00.
      final a = _alarm();
      var posted = <String>{};
      final first = planNotifications(
        alarms: [a],
        alreadyPosted: posted,
        now: DateTime(2026, 7, 23, 7, 0),
      );
      expect(first.post, hasLength(1));
      posted = {for (final n in first.post) n.key};
      final second = planNotifications(
        alarms: [a],
        alreadyPosted: posted,
        now: DateTime(2026, 7, 23, 7, 0, 30),
      );
      expect(second.post, isEmpty);
    });

    test('an alarm the device no longer reports is withdrawn', () {
      final plan = planNotifications(
        alarms: const [],
        alreadyPosted: {'alarm:4'},
        now: _day,
      );
      expect(plan.withdraw, ['alarm:4']);
    });

    test('monitoring off takes everything down', () {
      final plan = planNotifications(
        alarms: [_alarm()],
        alreadyPosted: {'alarm:1', 'finding:etaSoon'},
        now: _day,
        monitoringEnabled: false,
      );
      expect(plan.post, isEmpty);
      // Leaving them on screen would imply monitoring is still running.
      expect(plan.withdraw, ['alarm:1', 'finding:etaSoon']);
    });

    test('quiet hours disabled entirely leaves everything audible', () {
      final plan = planNotifications(
        alarms: [_alarm(severity: AlarmSeverity.warning)],
        alreadyPosted: const {},
        now: _night,
        quiet: const QuietHours(enabled: false),
      );
      expect(plan.post.single.silent, isFalse);
    });

    test('findings are advisory: info or warning, never critical', () {
      final plan = planNotifications(
        alarms: const [],
        alreadyPosted: const {},
        now: _day,
        findings: AppFinding.values,
      );
      expect(plan.post, hasLength(AppFinding.values.length));
      expect(
        plan.post.every((n) => n.channel != NotificationChannel.critical),
        isTrue,
      );
      // And every one of them says something, rather than repeating its
      // own title.
      for (final n in plan.post) {
        expect(n.body, isNotEmpty);
        expect(n.body, isNot(n.title));
      }
    });

    test('the probe name reaches the body, and falls back honestly', () {
      final named = planNotifications(
        alarms: [_alarm(probe: 2)],
        alreadyPosted: const {},
        now: _day,
        probeName: (n) => 'Brisket',
      );
      expect(named.post.single.body, contains('Brisket'));
      expect(named.post.single.body, contains('203.1'));

      final unnamed = planNotifications(
        alarms: [_alarm(probe: 3)],
        alreadyPosted: const {},
        now: _day,
      );
      expect(unnamed.post.single.body, contains('Probe 3'));

      // A whole-cook alarm has no probe at all.
      final bridge = planNotifications(
        alarms: [_alarm(probe: 0, rule: 'battery_low', valueF10: null)],
        alreadyPosted: const {},
        now: _day,
      );
      expect(bridge.post.single.body, 'Bridge');
    });

    test('every generated rule name has human copy', () {
      // The firmware can raise any of these (protocol/records.yaml's
      // alarm_rule). A rule the bridge raises and the phone stays silent
      // about is the worst possible outcome, so the fallback is the raw
      // name rather than a drop.
      const rules = [
        'smoke_x_alarm',
        'target_reached',
        'pit_out_of_band',
        'pit_crash',
        'probe_detached',
        'base_lost',
        'battery_low',
        'storage_low',
        'system_fault',
      ];
      for (final r in rules) {
        expect(alarmTitle(r), isNotEmpty);
        expect(alarmTitle(r), isNot(r), reason: '$r has no human title');
      }
      expect(alarmTitle('a_rule_from_the_future'), 'a_rule_from_the_future');
    });
  });
}
