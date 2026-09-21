/// N11.11–N11.13 — the notification policy (design 09 §9.5, research §6.4).
///
/// The claim under test is the one §9.1 makes and §9.5 delivers: the app
/// MIRRORS the device's alarm state. It posts once, it does not re-decide, it
/// withdraws when the device says acknowledged, and it never silences a
/// critical alarm — because overcooking a brisket at 3 a.m. is precisely the
/// thing worth waking up for.
///
/// Pure Dart (`package:test`), so `dart test test/domain test/data` runs it.
library;

import 'package:smoke_bridge/data/alarms/notification_policy.dart';
import 'package:smoke_bridge/data/model/alarm.dart';
import 'package:test/test.dart';

Alarm _alarm({
  String id = 'a1',
  String rule = 'target_reached',
  AlarmTier tier = AlarmTier.device,
  AlarmSeverity severity = AlarmSeverity.critical,
  bool acked = false,
  int? valueF10 = 2031,
  int atMs = 0,
  int? snoozedUntilMs,
}) => Alarm(
  id: id,
  tier: tier,
  severity: severity,
  rule: rule,
  detail: 'A probe crossed its target.',
  valueF10: valueF10,
  atMs: atMs,
  acked: acked,
  ruleId: rule,
  snoozedUntilMs: snoozedUntilMs,
);

final _night = DateTime(2026, 7, 23, 3, 40);
final _day = DateTime(2026, 7, 23, 14);

void main() {
  group('quiet hours', () {
    test('the default window wraps midnight', () {
      const q = QuietHours();
      expect(q.contains(DateTime(2026, 1, 1, 22)), isTrue);
      expect(q.contains(DateTime(2026, 1, 1, 23, 59)), isTrue);
      expect(q.contains(DateTime(2026)), isTrue);
      expect(q.contains(DateTime(2026, 1, 1, 5, 59)), isTrue);
      expect(q.contains(DateTime(2026, 1, 1, 6)), isFalse);
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
        alarms: <Alarm>[_alarm()],
        alreadyPosted: const <String>{},
        now: _night,
      );
      expect(plan.post, hasLength(1));
      expect(plan.post.single.channel, NotificationChannel.critical);
      expect(plan.post.single.silent, isFalse);
    });

    test('a warning is SILENCED but still posted during quiet hours', () {
      final plan = planNotifications(
        alarms: <Alarm>[
          _alarm(severity: AlarmSeverity.warning, rule: 'base_lost'),
        ],
        alreadyPosted: const <String>{},
        now: _night,
      );
      expect(plan.post.single.channel, NotificationChannel.warning);
      // Silencing is not suppressing: it is still in the shade at 07:00.
      expect(plan.post.single.silent, isTrue);
    });

    test('the same warning sounds in daylight', () {
      final plan = planNotifications(
        alarms: <Alarm>[
          _alarm(severity: AlarmSeverity.warning, rule: 'base_lost'),
        ],
        alreadyPosted: const <String>{},
        now: _day,
      );
      expect(plan.post.single.silent, isFalse);
    });

    test('an already-posted alarm is not re-posted on every poll', () {
      final a = _alarm(atMs: _day.millisecondsSinceEpoch);
      final plan = planNotifications(
        alarms: <Alarm>[a],
        alreadyPosted: <String>{alarmKey(a)},
        now: _day,
        escalatedTo: <String, int>{alarmKey(a): 0},
      );
      expect(plan.post, isEmpty);
      expect(plan.withdraw, isEmpty);
    });

    test('acknowledging withdraws the notification but not the alarm', () {
      final a = _alarm(acked: true);
      final plan = planNotifications(
        alarms: <Alarm>[a],
        alreadyPosted: <String>{alarmKey(a)},
        now: _day,
      );
      expect(plan.post, isEmpty);
      expect(plan.withdraw, <String>[alarmKey(a)]);
    });

    test(
      'an alarm that fired while the app was dead posts once on reconnect',
      () {
        final a = _alarm(atMs: DateTime(2026, 7, 23, 7).millisecondsSinceEpoch);
        var posted = <String>{};
        var rungs = <String, int>{};
        final first = planNotifications(
          alarms: <Alarm>[a],
          alreadyPosted: posted,
          now: DateTime(2026, 7, 23, 7),
          escalatedTo: rungs,
        );
        expect(first.post, hasLength(1));
        posted = <String>{for (final n in first.post) n.key};
        rungs = <String, int>{for (final n in first.post) n.key: n.escalation};
        final second = planNotifications(
          alarms: <Alarm>[a],
          alreadyPosted: posted,
          now: DateTime(2026, 7, 23, 7, 0, 30),
          escalatedTo: rungs,
        );
        expect(second.post, isEmpty);
      },
    );

    test('monitoring off takes everything down', () {
      final plan = planNotifications(
        alarms: <Alarm>[_alarm()],
        alreadyPosted: const <String>{'alarm:a1', 'finding:etaSoon'},
        now: _day,
        monitoringEnabled: false,
      );
      expect(plan.post, isEmpty);
      expect(plan.withdraw, <String>['alarm:a1', 'finding:etaSoon']);
    });

    test('findings are advisory: info or warning, never critical', () {
      final plan = planNotifications(
        alarms: const <Alarm>[],
        alreadyPosted: const <String>{},
        now: _day,
        findings: AppFinding.values,
      );
      expect(plan.post, hasLength(AppFinding.values.length));
      expect(
        plan.post.every((n) => n.channel != NotificationChannel.critical),
        isTrue,
      );
      for (final n in plan.post) {
        expect(n.body, isNotEmpty);
        expect(n.body, isNot(n.title));
      }
    });

    test('the reading reaches the body', () {
      final plan = planNotifications(
        alarms: <Alarm>[_alarm()],
        alreadyPosted: const <String>{},
        now: _day,
      );
      expect(plan.post.single.body, contains('203.1'));
    });
  });

  group('the escalation ladder (N11.13)', () {
    test('rungs are first-post, repeat at 5 min, full screen at 10 min', () {
      final start = DateTime(2026, 7, 23, 3);
      final at = start.millisecondsSinceEpoch;
      expect(escalationRung(start, at), 0);
      expect(escalationRung(start.add(const Duration(minutes: 5)), at), 1);
      expect(escalationRung(start.add(const Duration(minutes: 10)), at), 2);
      // A missing timestamp never escalates.
      expect(escalationRung(start, null), 0);
    });

    test('an unacknowledged critical alarm climbs the ladder exactly once '
        'per rung', () {
      final start = DateTime(2026, 7, 23, 3);
      final a = _alarm(atMs: start.millisecondsSinceEpoch);

      var posted = <String>{};
      var rungs = <String, int>{};

      final first = planNotifications(
        alarms: <Alarm>[a],
        alreadyPosted: posted,
        now: start,
        escalatedTo: rungs,
      );
      expect(first.post.single.escalation, 0);
      expect(first.post.single.fullScreen, isFalse);
      posted = <String>{for (final n in first.post) n.key};
      rungs = <String, int>{for (final n in first.post) n.key: n.escalation};

      // Polling at 4 min must NOT re-post.
      final unchanged = planNotifications(
        alarms: <Alarm>[a],
        alreadyPosted: posted,
        now: start.add(const Duration(minutes: 4)),
        escalatedTo: rungs,
      );
      expect(unchanged.post, isEmpty);

      // At 5 min it repeats once.
      final repeat = planNotifications(
        alarms: <Alarm>[a],
        alreadyPosted: posted,
        now: start.add(const Duration(minutes: 5)),
        escalatedTo: rungs,
      );
      expect(repeat.post.single.escalation, 1);
      expect(repeat.post.single.repost, isTrue);
      expect(repeat.post.single.fullScreen, isFalse);
      rungs = <String, int>{for (final n in repeat.post) n.key: n.escalation};

      // At 10 min it lights the screen.
      final full = planNotifications(
        alarms: <Alarm>[a],
        alreadyPosted: posted,
        now: start.add(const Duration(minutes: 10)),
        escalatedTo: rungs,
      );
      expect(full.post.single.escalation, 2);
      expect(full.post.single.fullScreen, isTrue);
      rungs = <String, int>{for (final n in full.post) n.key: n.escalation};

      // And never again after that.
      final after = planNotifications(
        alarms: <Alarm>[a],
        alreadyPosted: posted,
        now: start.add(const Duration(minutes: 30)),
        escalatedTo: rungs,
      );
      expect(after.post, isEmpty);
    });

    test('a warning never escalates', () {
      final start = DateTime(2026, 7, 23, 3);
      final a = _alarm(
        rule: 'base_lost',
        severity: AlarmSeverity.warning,
        atMs: start.millisecondsSinceEpoch,
      );
      final plan = planNotifications(
        alarms: <Alarm>[a],
        alreadyPosted: const <String>{},
        now: start.add(const Duration(minutes: 30)),
        quiet: const QuietHours(enabled: false),
      );
      expect(plan.post.single.escalation, 0);
      expect(plan.post.single.fullScreen, isFalse);
    });
  });

  group('snooze (N11.8)', () {
    test('a snoozed alarm withdraws its notification but stays raised', () {
      final nowMs = DateTime(2026, 7, 23, 14).millisecondsSinceEpoch;
      final a = _alarm(snoozedUntilMs: nowMs + 5 * 60 * 1000);
      final plan = planNotifications(
        alarms: <Alarm>[a],
        alreadyPosted: <String>{alarmKey(a)},
        now: DateTime.fromMillisecondsSinceEpoch(nowMs),
      );
      expect(plan.post, isEmpty);
      // Withdrawing the sound is not acknowledging: the alarm is still live.
      expect(plan.withdraw, isEmpty);
    });

    test('the snooze expires and the alarm re-notifies', () {
      final nowMs = DateTime(2026, 7, 23, 14).millisecondsSinceEpoch;
      final a = _alarm(snoozedUntilMs: nowMs - 1);
      final plan = planNotifications(
        alarms: <Alarm>[a],
        alreadyPosted: const <String>{},
        now: DateTime.fromMillisecondsSinceEpoch(nowMs),
      );
      expect(plan.post, hasLength(1));
    });

    test('snoozeUntilMs clamps to 1..60 minutes', () {
      final nowMs = 1000;
      expect(snoozeUntilMs(nowMs: nowMs, minutes: 0), nowMs + 60000);
      expect(snoozeUntilMs(nowMs: nowMs, minutes: 999), nowMs + 60 * 60000);
    });
  });

  group('prefer my own alarms (N11.10)', () {
    test('a user insight silences a non-critical device alarm, never a '
        'critical one', () {
      final device = _alarm(
        id: 'd1',
        rule: 'pit_out_of_band',
        severity: AlarmSeverity.warning,
      );
      final critical = _alarm(id: 'd2');
      final app = _alarm(
        id: 'i1',
        tier: AlarmTier.app,
        severity: AlarmSeverity.info,
        rule: 'eta_soon',
      );

      final off = planNotifications(
        alarms: <Alarm>[device, critical, app],
        alreadyPosted: const <String>{},
        now: _day,
      );
      expect(off.post.firstWhere((n) => n.alarmId == 'd1').silent, isFalse);

      final on = planNotifications(
        alarms: <Alarm>[device, critical, app],
        alreadyPosted: const <String>{},
        now: _day,
        preferManualAlarm: true,
      );
      // The own alarm wins the sound for the warning...
      expect(on.post.firstWhere((n) => n.alarmId == 'd1').silent, isTrue);
      // ...but a critical device alarm never defers (I2).
      expect(on.post.firstWhere((n) => n.alarmId == 'd2').silent, isFalse);
      // And the app alarm itself still sounds.
      expect(on.post.firstWhere((n) => n.alarmId == 'i1').silent, isFalse);
    });

    test('with nothing of the user\'s own active, nothing is silenced', () {
      final device = _alarm(
        rule: 'pit_out_of_band',
        severity: AlarmSeverity.warning,
      );
      final plan = planNotifications(
        alarms: <Alarm>[device],
        alreadyPosted: const <String>{},
        now: _day,
        preferManualAlarm: true,
      );
      expect(plan.post.single.silent, isFalse);
    });
  });

  group('human copy', () {
    test('every generated rule name has human copy, and falls back to the '
        'raw name', () {
      const rules = <String>[
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

  group('Q4 — pause never suppresses alarms', () {
    test('the policy reads only the wall clock and device state, not the '
        'stopwatch', () {
      // The device is authoritative and records (and alarms) with no phone
      // (I2); whether the app is displaying a paused clock cannot change what
      // the bridge reports. The plan is a function of alarms + clock only.
      final a = _alarm(atMs: _day.millisecondsSinceEpoch);
      final plan = planNotifications(
        alarms: <Alarm>[a],
        alreadyPosted: const <String>{},
        now: _day,
      );
      expect(plan.post, hasLength(1));
    });
  });
}
