/// A2.3 — both models, the boundary between them, and every guard rail.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';

List<TempPoint> series(
  int fromT,
  int toT,
  double? Function(int t) f, {
  int stepS = 30,
}) =>
    [for (var t = fromT; t <= toT; t += stepS) (t: t, f: f(t))];

List<TempPoint> flatPit(int toT, [double f = 250]) =>
    series(0, toT, (_) => f);

void main() {
  group('guard rails', () {
    test('under 30 minutes of history refuses', () {
      final food = series(0, 1500, (t) => 100 + t / 120);
      final r = etaToTarget(
          food: food, pit: flatPit(1500), targetF: 203);
      expect(r, isA<EtaUnavailable>());
      expect((r as EtaUnavailable).reason,
          EtaUnavailableReason.insufficientHistory);
    });

    test('a stall suppresses the ETA entirely', () {
      final food = series(0, 7200, (t) => 100 + 30 * t / 3600);
      final r = etaToTarget(
          food: food, pit: flatPit(7200), targetF: 203, stalled: true);
      expect((r as EtaUnavailable).reason, EtaUnavailableReason.stalled);
    });

    test('target at or above pit: "not at this pit temperature"', () {
      final food = series(0, 7200, (t) => 100 + 30 * t / 3600);
      for (final target in [250.0, 260.0]) {
        final r = etaToTarget(
            food: food, pit: flatPit(7200), targetF: target);
        expect((r as EtaUnavailable).reason,
            EtaUnavailableReason.targetAtOrAbovePit);
      }
    });

    test('|slope| under 1 °F/hr refuses to project noise', () {
      final food = series(0, 7200, (t) => 150 + 0.5 * t / 3600);
      final r =
          etaToTarget(food: food, pit: flatPit(7200), targetF: 203);
      expect((r as EtaUnavailable).reason, EtaUnavailableReason.slopeTooFlat);
    });

    test('cooling away from an upward target is notApproaching', () {
      final food = series(0, 7200, (t) => 180 - 5 * t / 3600);
      final r =
          etaToTarget(food: food, pit: flatPit(7200), targetF: 203);
      expect(
          (r as EtaUnavailable).reason, EtaUnavailableReason.notApproaching);
    });

    test('already at target is a zero range, not an error', () {
      final food = series(0, 7200, (t) => 100 + 30 * t / 3600); // ends 160
      final r =
          etaToTarget(food: food, pit: flatPit(7200), targetF: 155);
      expect(r, const EtaRange(Duration.zero, Duration.zero));
    });
  });

  group('linear model (early cook, > 60 °F below pit)', () {
    test('projects the OLS slope and rounds to 15 minutes', () {
      // 30 °F/hr from 100 °F: at t = 7200 the probe reads 160 °F,
      // 90 °F below the pit → linear. 43 °F to go ≈ 1 h 26 m → 1 h 30 m.
      final food = series(0, 7200, (t) => 100 + 30 * t / 3600);
      final r = etaToTarget(
          food: food, pit: flatPit(7200), targetF: 203);
      expect(r, isA<EtaRange>());
      final range = r as EtaRange;
      expect(range.low, const Duration(minutes: 90));
      expect(range.high, const Duration(minutes: 90));
      expect(range.low.inSeconds % 900, 0);
    });

    test('noisy data widens the range instead of faking precision', () {
      final rand = Random(7);
      final food = series(
          0, 7200, (t) => 100 + 30 * t / 3600 + (rand.nextDouble() - 0.5) * 4);
      final r = etaToTarget(
          food: food, pit: flatPit(7200), targetF: 203);
      final range = r as EtaRange;
      expect(range.high, greaterThanOrEqualTo(range.low));
      expect(range.low.inSeconds % 900, 0);
      expect(range.high.inSeconds % 900, 0);
      // The true answer (~86 min) is inside the range.
      expect(range.low, lessThanOrEqualTo(const Duration(minutes: 105)));
      expect(range.high, greaterThanOrEqualTo(const Duration(minutes: 75)));
    });
  });

  group('Newton model (within 60 °F of pit)', () {
    // Exact Newton data: T(t) = 250 − 190·e^(−k·t), k = 0.5/hr.
    const kPerS = 0.5 / 3600;
    double newtonT(int t) => 250 - 190 * exp(-kPerS * t);

    test('recovers k and matches the analytic remaining time', () {
      final food = series(0, 10800, newtonT); // ends ≈ 207.6 °F, gap ≈ 42 °F
      final r = etaToTarget(
          food: food, pit: flatPit(10800), targetF: 215);
      // Analytic: (1/k)·ln((250−215)/(250−207.6)) ≈ 1381 s → 15-min
      // rounding lands on 30 minutes.
      final range = r as EtaRange;
      expect(range.low, const Duration(minutes: 30));
      expect(range.high, const Duration(minutes: 30));
    });

    test('never returns the naive linear answer near the asymptote', () {
      final food = series(0, 10800, newtonT);
      final current = newtonT(10800);
      final slope = rateOfChange(food)!; // °F/hr, decaying
      final naiveS = (215 - current) / slope * 3600;
      // Newton knows the approach keeps slowing: its answer must be
      // meaningfully longer than the naive projection.
      final range =
          etaToTarget(food: food, pit: flatPit(10800), targetF: 215)
              as EtaRange;
      expect(range.low.inSeconds, greaterThan(naiveS.round()));
    });

    test('the model boundary at 60 °F picks a model on both sides', () {
      // Same exponential; evaluate earlier (gap > 60 → linear) and later
      // (gap < 60 → Newton). Both must produce a finite range.
      final early = series(0, 6000, newtonT); // gap ≈ 74 °F
      final late = series(0, 10800, newtonT); // gap ≈ 42 °F
      expect(
        etaToTarget(food: early, pit: flatPit(6000), targetF: 230),
        isA<EtaRange>(),
      );
      expect(
        etaToTarget(food: late, pit: flatPit(10800), targetF: 230),
        isA<EtaRange>(),
      );
    });
  });
}
