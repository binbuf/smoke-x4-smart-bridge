/// The guided four-phase progression (newapp §D.5).
///
/// The tests that matter here are the three honesty rules, not the happy path:
/// the app must never *infer* a pull, must label the rest as an estimate, and
/// must let a real reading beat the countdown.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/plan/plan.dart';

const int _min = 60 * 1000;

void main() {
  group('approaching → pull now', () {
    test('below the pull temperature it is approaching', () {
      final s = cookPhaseFor(
        tempF10: 1600,
        targetF10: 2030,
        pullF10: 1950,
        nowUnixMs: 0,
      );
      expect(s.phase, CookPhase.approaching);
      expect(s.detail, contains('195'));
    });

    test('at the pull temperature it says pull, not "reached"', () {
      final s = cookPhaseFor(
        tempF10: 1950,
        targetF10: 2030,
        pullF10: 1950,
        nowUnixMs: 0,
      );
      expect(s.phase, CookPhase.pullNow);
      expect(s.detail, contains('off the heat'));
    });

    test('a cut with no carryover says it has reached target, not "pull"', () {
      final s = cookPhaseFor(
        tempF10: 1650,
        targetF10: 1650,
        pullF10: 1650,
        nowUnixMs: 0,
      );
      expect(s.phase, CookPhase.pullNow);
      expect(
        s.detail,
        contains('165'),
        reason: 'poultry has no carryover, so there is nothing to coast up to',
      );
    });

    test('a detached probe holds at approaching and says why', () {
      final s = cookPhaseFor(
        tempF10: null,
        targetF10: 2030,
        pullF10: 1950,
        nowUnixMs: 0,
      );
      expect(s.phase, CookPhase.approaching);
      expect(s.detail, contains('Waiting'));
    });
  });

  group('rule 1 — the app never infers a pull', () {
    test('a probe far past target still says pull until the user taps', () {
      final s = cookPhaseFor(
        tempF10: 2200,
        targetF10: 2030,
        pullF10: 1950,
        nowUnixMs: 100 * _min,
      );
      expect(
        s.phase,
        CookPhase.pullNow,
        reason:
            'a cooling probe could be a pull, a lid, or a probe knocked into '
            'the fire — moving to Resting on a guess would say a brisket was '
            'off the smoker while it was still on it',
      );
    });
  });

  group('rule 2 — the rest is an estimate, and says so', () {
    test('resting counts down and is flagged estimated', () {
      final s = cookPhaseFor(
        tempF10: 1960,
        targetF10: 2030,
        pullF10: 1950,
        pulledAtUnixMs: 0,
        nowUnixMs: 5 * _min,
      );
      expect(s.phase, CookPhase.resting);
      expect(s.estimated, isTrue);
      expect(s.restRemainingS, 15 * 60);
      expect(s.detail, contains('estimate'));
    });

    test('rest length follows the mass, via the carryover', () {
      // Thin (2 °F of coast) → 5 min; thick (8 °F) → 20 min.
      expect(restSecondsFor(carryoverF10: 20), 5 * 60);
      expect(restSecondsFor(carryoverF10: 50), 10 * 60);
      expect(restSecondsFor(carryoverF10: 80), 20 * 60);
    });

    test('no carryover means no coast, only the safety rest', () {
      expect(restSecondsFor(carryoverF10: 0), 0);
      expect(restSecondsFor(carryoverF10: 0, safetyRestS: 180), 180);
    });

    test('the USDA rest is a floor, never a ceiling', () {
      expect(restSecondsFor(carryoverF10: 80, safetyRestS: 180), 20 * 60);
    });

    test('a zero-carryover rest does not promise a temperature climb', () {
      final s = cookPhaseFor(
        tempF10: 1600,
        targetF10: 1650,
        pullF10: 1650,
        pulledAtUnixMs: 0,
        nowUnixMs: 1 * _min,
        safetyRestS: 180,
      );
      expect(s.phase, CookPhase.resting);
      expect(s.detail, contains('does not carry over'));
    });

    test('restProgress is a fraction, or null when there is nothing to fract',
        () {
      final resting = cookPhaseFor(
        tempF10: 1960,
        targetF10: 2030,
        pullF10: 1950,
        pulledAtUnixMs: 0,
        nowUnixMs: 10 * _min,
      );
      expect(resting.restProgress, closeTo(0.5, 0.01));
      expect(
        cookPhaseFor(
          tempF10: 1600,
          targetF10: 2030,
          pullF10: 1950,
          nowUnixMs: 0,
        ).restProgress,
        isNull,
      );
    });
  });

  group('rule 3 — the sensor outranks the clock', () {
    test('a probe that reached target ends the rest early', () {
      final s = cookPhaseFor(
        tempF10: 2030,
        targetF10: 2030,
        pullF10: 1950,
        pulledAtUnixMs: 0,
        nowUnixMs: 1 * _min,
      );
      expect(s.phase, CookPhase.ready);
      expect(s.estimated, isFalse);
    });

    test('a rest that runs out under target says so plainly', () {
      final s = cookPhaseFor(
        tempF10: 1980,
        targetF10: 2030,
        pullF10: 1950,
        pulledAtUnixMs: 0,
        nowUnixMs: 60 * _min,
      );
      expect(s.phase, CookPhase.ready);
      expect(s.estimated, isTrue);
      expect(s.detail, contains('check it'));
    });

    test('a rest that runs out with the probe pulled is simply ready', () {
      final s = cookPhaseFor(
        tempF10: null,
        targetF10: 2030,
        pullF10: 1950,
        pulledAtUnixMs: 0,
        nowUnixMs: 60 * _min,
      );
      expect(s.phase, CookPhase.ready);
    });
  });

  group('no target is not a phase', () {
    test('it is the set-a-target affordance instead', () {
      final s = cookPhaseFor(
        tempF10: 1600,
        targetF10: null,
        pullF10: null,
        nowUnixMs: 0,
      );
      expect(s.phase, CookPhase.approaching);
      expect(s.detail, contains('No target'));
      expect(s.restTotalS, 0);
    });
  });
}
