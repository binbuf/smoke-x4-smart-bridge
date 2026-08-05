/// §G.5's escalation ladder: silent → heads-up → full-screen + repeat.
///
/// The three properties that decide whether this feature helps or gets the
/// app's notifications switched off:
///
///  1. **The first post is never a full-screen takeover**, even for a critical
///     alarm. Lighting the screen for something the user is already looking at
///     is the fastest way to lose `USE_FULL_SCREEN_INTENT` — and losing it
///     costs the 3 a.m. case the whole declaration exists for.
///  2. **Only critical climbs.** A warning repeating every five minutes is an
///     app nobody leaves notifications on for.
///  3. **An alarm on screen at its current rung does not re-post.** The poll
///     runs every 30 s; re-posting an unchanged alarm 120 times an hour is the
///     other way to get switched off.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/alarms/notification_policy.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';

final DateTime _now = DateTime(2026, 8, 5, 3, 40);

Alarm _alarm({
  int id = 1,
  AlarmSeverity severity = AlarmSeverity.critical,
  Duration age = Duration.zero,
  bool acked = false,
}) => Alarm(
  id: id,
  rule: 'pit_crash',
  severity: severity,
  acked: acked,
  sinceUnixMs: _now.subtract(age).millisecondsSinceEpoch,
);

NotificationPlan _plan(
  List<Alarm> alarms, {
  Set<String> posted = const {},
  Map<String, int> rungs = const {},
}) => planNotifications(
  alarms: alarms,
  alreadyPosted: posted,
  escalatedTo: rungs,
  now: _now,
);

void main() {
  group('the rungs', () {
    test('a fresh alarm is rung 0', () {
      expect(escalationRung(_now, _now.millisecondsSinceEpoch), 0);
    });

    test('five minutes unacknowledged is rung 1 — repeat the sound', () {
      expect(
        escalationRung(
          _now,
          _now.subtract(kEscalateToRepeat).millisecondsSinceEpoch,
        ),
        1,
      );
    });

    test('ten minutes unacknowledged is rung 2 — light the screen', () {
      expect(
        escalationRung(
          _now,
          _now.subtract(kEscalateToFullScreen).millisecondsSinceEpoch,
        ),
        2,
      );
    });

    test('a missing timestamp stays at rung 0, never assumed old', () {
      expect(
        escalationRung(_now, null),
        0,
        reason:
            'escalating on an absent field would let one firmware quirk light '
            'the screen',
      );
    });

    test('the rungs are far enough apart to be worth having', () {
      expect(kEscalateToRepeat.inMinutes, greaterThanOrEqualTo(3));
      expect(
        kEscalateToFullScreen,
        greaterThan(kEscalateToRepeat),
        reason: 'the ladder has to go up',
      );
      expect(
        kEscalateToFullScreen.inMinutes,
        lessThanOrEqualTo(15),
        reason: 'a brisket must still be a brisket when the screen lights',
      );
    });
  });

  group('property 1 — the first post never takes the screen', () {
    test('a brand-new critical alarm is a heads-up, not a takeover', () {
      final plan = _plan([_alarm()]);
      expect(plan.post, hasLength(1));
      expect(plan.post.single.channel, NotificationChannel.critical);
      expect(
        plan.post.single.fullScreen,
        isFalse,
        reason:
            'a full-screen takeover for something the user is already looking '
            'at is how the permission gets revoked',
      );
      expect(plan.post.single.escalation, 0);
    });

    test('an alarm that has been ringing ten minutes DOES take the screen', () {
      final plan = _plan([_alarm(age: kEscalateToFullScreen)]);
      expect(plan.post.single.fullScreen, isTrue);
      expect(plan.post.single.escalation, 2);
    });
  });

  group('property 2 — only critical climbs', () {
    for (final severity in [AlarmSeverity.warning, AlarmSeverity.info]) {
      test('a ${severity.name} alarm never escalates, however old', () {
        final plan = _plan([
          _alarm(severity: severity, age: const Duration(hours: 3)),
        ]);
        expect(plan.post.single.escalation, 0);
        expect(plan.post.single.fullScreen, isFalse);
      });

      test('and never re-posts once on screen', () {
        final plan = _plan(
          [_alarm(severity: severity, age: const Duration(hours: 3))],
          posted: {'alarm:1'},
        );
        expect(
          plan.post,
          isEmpty,
          reason:
              'a warning repeating every five minutes is an app nobody leaves '
              'notifications on for',
        );
      });
    }
  });

  group('property 3 — it climbs once per rung, not once per poll', () {
    test('on screen at the same rung: nothing is posted', () {
      final plan = _plan(
        [_alarm(age: const Duration(minutes: 1))],
        posted: {'alarm:1'},
        rungs: {'alarm:1': 0},
      );
      expect(plan.post, isEmpty);
      expect(plan.withdraw, isEmpty, reason: 'it is still live');
    });

    test('crossing into rung 1 re-posts exactly once', () {
      final atFive = _plan(
        [_alarm(age: kEscalateToRepeat)],
        posted: {'alarm:1'},
        rungs: {'alarm:1': 0},
      );
      expect(atFive.post, hasLength(1));
      expect(atFive.post.single.escalation, 1);
      expect(atFive.post.single.repost, isTrue);
      expect(atFive.post.single.fullScreen, isFalse);

      // The next poll, still at rung 1: silence.
      final nextPoll = _plan(
        [_alarm(age: kEscalateToRepeat + const Duration(seconds: 30))],
        posted: {'alarm:1'},
        rungs: {'alarm:1': 1},
      );
      expect(nextPoll.post, isEmpty);
    });

    test('crossing into rung 2 re-posts exactly once, with the screen', () {
      final atTen = _plan(
        [_alarm(age: kEscalateToFullScreen)],
        posted: {'alarm:1'},
        rungs: {'alarm:1': 1},
      );
      expect(atTen.post, hasLength(1));
      expect(atTen.post.single.escalation, 2);
      expect(atTen.post.single.fullScreen, isTrue);

      final nextPoll = _plan(
        [_alarm(age: const Duration(hours: 2))],
        posted: {'alarm:1'},
        rungs: {'alarm:1': 2},
      );
      expect(
        nextPoll.post,
        isEmpty,
        reason: 'rung 2 is the top — it does not keep taking the screen',
      );
    });
  });

  group('acknowledging still ends it', () {
    test('an acked alarm comes down whatever rung it reached', () {
      final plan = _plan(
        [_alarm(age: const Duration(hours: 1), acked: true)],
        posted: {'alarm:1'},
        rungs: {'alarm:1': 2},
      );
      expect(plan.post, isEmpty);
      expect(plan.withdraw, ['alarm:1']);
    });

    test('turning monitoring off withdraws an escalated alarm too', () {
      final plan = planNotifications(
        alarms: [_alarm(age: kEscalateToFullScreen)],
        alreadyPosted: const {'alarm:1'},
        escalatedTo: const {'alarm:1': 2},
        now: _now,
        monitoringEnabled: false,
      );
      expect(plan.post, isEmpty);
      expect(plan.withdraw, ['alarm:1']);
    });
  });

  group('quiet hours and escalation do not fight', () {
    test('critical is never silenced, at any rung', () {
      // 03:40 is inside 22:00–06:00. Overcooking a brisket at 3 a.m. is
      // precisely what is worth waking up for (§9.5).
      final plan = _plan([_alarm(age: kEscalateToFullScreen)]);
      expect(plan.post.single.silent, isFalse);
      expect(plan.post.single.fullScreen, isTrue);
    });

    test('a warning inside quiet hours is still silent', () {
      final plan = _plan([_alarm(severity: AlarmSeverity.warning)]);
      expect(plan.post.single.silent, isTrue);
    });
  });
}
