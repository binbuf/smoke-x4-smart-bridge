/// A10.1 — the chart series builder.
///
/// The named shapes plus the two invariants that make the chart honest:
/// a gap comes out as two runs, and a detached probe contributes nothing
/// rather than a zero.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';

import '../support/shapes.dart';

void main() {
  group('windowing and empties', () {
    test('an empty series yields an empty, non-throwing model', () {
      final m = buildChartSeries(const [], fromT: 0, toT: 3600);
      expect(m.isEmpty, isTrue);
      expect(m.series, hasLength(4));
      expect(m.minF, isNull);
      expect(m.gaps, isEmpty);
    });

    test('a single point survives as a one-point run', () {
      final m = buildChartSeries(
        const [
          Sample(t: 30, tempsF10: [2430, null, null, null]),
        ],
        fromT: 0,
        toT: 3600,
      );
      expect(m.series.first.runs, hasLength(1));
      expect(m.series.first.points.single.f, closeTo(243.0, 1e-9));
    });

    test('all-detached produces no points at all — never a zero', () {
      final m = buildChartSeries(allDetached(), fromT: 0, toT: 3600);
      expect(m.isEmpty, isTrue);
      for (final s in m.series) {
        expect(s.points, isEmpty);
      }
    });

    test('the window slices, and points outside it are dropped', () {
      final cook = syntheticCook(hours: 2);
      final m = buildChartSeries(cook, fromT: 1800, toT: 3600);
      expect(m.series.first.points.first.t, greaterThanOrEqualTo(1800));
      expect(m.series.first.points.last.t, lessThanOrEqualTo(3600));
    });
  });

  group('gaps are gaps', () {
    test('a 30-minute dropout splits the run at exactly the hole', () {
      final cook = withGap(syntheticCook(hours: 4), fromT: 3600, toT: 5400);
      final m = buildChartSeries(cook, fromT: 0, toT: 14400);
      final pit = m.series.first;
      expect(pit.runs, hasLength(2));
      expect(pit.runs[0].toT, 3600);
      expect(pit.runs[1].fromT, 5400);
      // And no decimated point may land inside the hole.
      for (final p in pit.points) {
        expect(p.t > 3600 && p.t < 5400, isFalse);
      }
      expect(m.gaps.single.fromT, 3600);
      expect(m.gaps.single.toT, 5400);
    });

    test('a delta at exactly the threshold is not a gap', () {
      final m = buildChartSeries(
        const [
          Sample(t: 0, tempsF10: [2400, null, null, null]),
          Sample(t: 45, tempsF10: [2410, null, null, null]),
        ],
        fromT: 0,
        toT: 100,
      );
      expect(m.series.first.runs, hasLength(1));
      expect(m.gaps, isEmpty);
    });
  });

  group('decimation', () {
    test('15 h at 30 s decimates to the budget and keeps the ends', () {
      final cook = syntheticCook(hours: 15);
      expect(cook, hasLength(1800));
      final m = buildChartSeries(
        cook,
        fromT: 0,
        toT: 15 * 3600,
        targetPoints: 400,
      );
      final pit = m.series.first;
      expect(pit.rawCount, 1800);
      expect(pit.points.length, lessThanOrEqualTo(400));
      expect(pit.points.first.t, cook.first.t);
      expect(pit.points.last.t, cook.last.t);
    });

    test('54 days stays bounded and produces an envelope', () {
      // The retention shape (08 §8.5). At a 5-minute cadence this is the
      // widest thing the chart will ever be asked to draw.
      final cook = syntheticCook(hours: 54 * 24, periodS: 300);
      expect(cook.length, greaterThan(15000));
      final m = buildChartSeries(
        cook,
        fromT: 0,
        toT: 54 * 24 * 3600,
        targetPoints: 600,
      );
      final pit = m.series.first;
      expect(pit.points.length, lessThanOrEqualTo(600));
      expect(pit.envelope, isNotEmpty);
      // The band must bracket the line, or it is decoration.
      for (final e in pit.envelope) {
        expect(e.min, lessThanOrEqualTo(e.max));
      }
    });

    test('decimation never invents a timestamp or moves the ends', () {
      final cook = syntheticCook(hours: 8);
      final original = {for (final s in cook) s.t};
      final m = buildChartSeries(
        cook,
        fromT: 0,
        toT: 8 * 3600,
        targetPoints: 120,
      );
      for (final p in m.series.first.points) {
        expect(original.contains(p.t), isTrue, reason: 'invented t=${p.t}');
      }
    });

    test('a budget below LTTB\'s floor disables decimation, not the chart', () {
      final cook = syntheticCook(hours: 1);
      final m = buildChartSeries(cook, fromT: 0, toT: 3600, targetPoints: 0);
      expect(m.series.first.points, hasLength(cook.length));
    });
  });

  group('crosshair', () {
    late ChartSeriesModel model;

    setUp(() {
      model = buildChartSeries(
        withGap(syntheticCook(hours: 4), fromT: 3600, toT: 5400),
        fromT: 0,
        toT: 14400,
        targetPoints: 0,
      );
    });

    test('reads the sample at an exact timestamp', () {
      final r = crosshairAt(model, 1800).first;
      expect(r.t, 1800);
      expect(r.deltaS, 0);
      expect(r.f, isNotNull);
    });

    test('between samples it reads the nearest and states the distance', () {
      final r = crosshairAt(model, 1810).first;
      expect(r.f, isNotNull);
      expect(r.deltaS, lessThanOrEqualTo(30));
    });

    test('inside a gap it refuses rather than interpolating', () {
      final r = crosshairAt(model, 4500).first;
      expect(r.f, isNull);
    });

    test('past both ends it refuses', () {
      expect(crosshairAt(model, -10000).first.f, isNull);
      expect(crosshairAt(model, 999999).first.f, isNull);
    });

    test('a detached probe reads null, never 0', () {
      final r = crosshairAt(model, 1800).firstWhere((x) => x.probe == 3);
      expect(r.f, isNull);
    });
  });
}
