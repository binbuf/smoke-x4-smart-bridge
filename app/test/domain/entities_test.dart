/// N1.2/N1.3/N1.4/N1.18 — jacks and roles, the freshness ladder, the live
/// reading value object, and the two kinds of gap.
library;

import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('N1.2 probe jacks and roles', () {
    test('jack 4 is the pit by default; the others start unused', () {
      expect(ProbeJack.four.defaultRole, ProbeRole.pit);
      for (final j in [ProbeJack.one, ProbeJack.two, ProbeJack.three]) {
        expect(j.defaultRole, ProbeRole.unused);
      }
    });

    test('jack parsing is 1..4', () {
      expect(ProbeJack.fromN(1), ProbeJack.one);
      expect(ProbeJack.fromN(4), ProbeJack.four);
      expect(ProbeJack.fromN(0), isNull);
      expect(ProbeJack.fromN(5), isNull);
    });
  });

  group('N1.3 freshness ladder', () {
    test('boundaries are live ≤45, aging ≤90, stale ≤600, frozen beyond', () {
      expect(Freshness.fromAge(0), Freshness.live);
      expect(Freshness.fromAge(45), Freshness.live);
      expect(Freshness.fromAge(46), Freshness.aging);
      expect(Freshness.fromAge(90), Freshness.aging);
      expect(Freshness.fromAge(91), Freshness.stale);
      expect(Freshness.fromAge(600), Freshness.stale);
      expect(Freshness.fromAge(601), Freshness.frozen);
      expect(Freshness.fromAge(null), Freshness.unknown);
    });

    test('baseLost outranks the arithmetic', () {
      expect(Freshness.fromAge(0, baseLost: true), Freshness.frozen);
    });

    test('derived values are removed from stale down (I4)', () {
      expect(Freshness.live.showsDerived, isTrue);
      expect(Freshness.aging.showsDerived, isTrue);
      expect(Freshness.live.canShowDerived, isTrue);
      expect(Freshness.stale.showsDerived, isFalse);
      expect(Freshness.stale.canShowDerived, isFalse);
      expect(Freshness.frozen.showsDerived, isFalse);
      expect(Freshness.unknown.showsDerived, isFalse);
      expect(Freshness.stale.isDim, isTrue);
      expect(Freshness.frozen.isDim, isTrue);
      expect(Freshness.live.isDim, isFalse);
    });
  });

  group('N1.4 probe reading', () {
    test('a detached reading has no temp and no derived values', () {
      final r = detachedReading(ProbeJack.two);
      expect(r.attached, isFalse);
      expect(r.temp.isAbsent, isTrue);
      expect(r.temp.toF, isNull);
      expect(r.trendFPerHr, isNull);
      expect(r.eta, isNull);
      expect(r.peakF10, isNull);
      expect(r.stalled, isFalse);
    });

    test('freezed value equality and copyWith', () {
      const a = ProbeReading(jack: ProbeJack.one, attached: true);
      const b = ProbeReading(jack: ProbeJack.one, attached: true);
      expect(a, b);
      expect(a.copyWith(attached: false).attached, isFalse);
    });

    test('a live reading can carry a trend and a range', () {
      final r = ProbeReading(
        jack: ProbeJack.one,
        attached: true,
        temp: TempValue.ofF10(1642),
        freshness: Freshness.live,
        trendFPerHr: 0.4,
        stalled: true,
        peakF10: 1642,
        lowF10: 580,
        avgF10: 1284,
        eta: const EtaRange(Duration.zero, Duration.zero),
        spark: const [700, 1642],
      );
      expect(r.temp.toF, closeTo(164.2, 1e-9));
      expect(r.freshness.showsDerived, isTrue);
      expect(r.spark, hasLength(2));
    });
  });

  group('N1.18 gaps', () {
    test('findGaps marks a delta over the cadence threshold', () {
      final gaps = findGaps([0, 30, 60, 300, 330]);
      expect(gaps, hasLength(1));
      expect(gaps.single.fromT, 60);
      expect(gaps.single.toT, 300);
    });

    test('rollover is permanent; connectivity is recoverable', () {
      final rollover = detectRollover(
        highWaterT: 90,
        deviceMinT: 200,
        deviceMaxT: 400,
      );
      expect(rollover, isNotNull);
      expect(rollover!.reason, GapReason.bufferRollover);
      expect(rollover.reason.isPermanent, isTrue);

      final contiguous = detectRollover(
        highWaterT: 90,
        deviceMinT: 91,
        deviceMaxT: 400,
      );
      expect(contiguous, isNull);

      final noClaim = detectRollover(
        highWaterT: -1,
        deviceMinT: 200,
        deviceMaxT: 400,
      );
      expect(noClaim, isNull);

      final connectivity = detectConnectivityGaps([
        const Sample(t: 0, tempsF10: [1000]),
        const Sample(t: 30, tempsF10: [1000]),
        const Sample(t: 500, tempsF10: [1000]),
      ]);
      expect(connectivity, hasLength(1));
      expect(connectivity.single.reason, GapReason.connectivity);
      expect(connectivity.single.reason.isPermanent, isFalse);
    });
  });
}
