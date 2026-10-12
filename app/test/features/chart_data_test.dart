/// The chart's viewport and decimation are pure, so every rule above the
/// gesture is asserted here directly — no fake gesture, no golden.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/graph/chart_data.dart';
import 'package:smoke_bridge/features/graph/temp_chart.dart';

Sample _s(int t, List<int?> temps) => Sample(t: t, tempsF10: temps);

void main() {
  group('ChartViewport', () {
    test('full covers the whole span', () {
      final v = ChartViewport.full(0, 100);
      expect(v.min, 0);
      expect(v.max, 100);
      expect(v.isFull, isTrue);
      expect(v.span, 100);
    });

    test('a degenerate span is widened so zoom cannot divide by zero', () {
      final v = ChartViewport.full(42, 42);
      expect(v.span, ChartViewport.minSpan);
    });

    test('pan slides the window and clamps at both edges', () {
      final v = ChartViewport.full(0, 100).window(20); // [80, 100]
      expect(v.min, 80);
      expect(v.pan(50).max, 100, reason: 'cannot pan past the newest edge');
      expect(v.pan(-100).min, 0, reason: 'cannot pan past the oldest edge');
      expect(v.pan(-10).min, 70);
    });

    test('zoom in shrinks the span and keeps the focus pinned', () {
      final v = ChartViewport.full(0, 100);
      final z = v.zoom(2, 50);
      expect(z.span, closeTo(50, 1e-9));
      expect(z.min, closeTo(25, 1e-9));
      expect(z.max, closeTo(75, 1e-9));
    });

    test('zoom out cannot exceed the full span', () {
      final v = ChartViewport.full(0, 100).window(20);
      final z = v.zoom(0.01, 90);
      expect(z.span, closeTo(100, 1e-9));
      expect(z.min, 0);
    });

    test('zoom in cannot go below the minimum span', () {
      final v = ChartViewport.full(0, 100);
      final z = v.zoom(1000, 50);
      expect(z.span, closeTo(ChartViewport.minSpan, 1e-9));
    });

    test('a window is anchored to the newest data', () {
      final v = ChartViewport.full(0, 900).window(60);
      expect(v.min, 840);
      expect(v.max, 900);
    });

    test('jumpToEnd keeps the width but moves to the newest data', () {
      final v = ChartViewport.full(0, 900).window(60).pan(-500);
      expect(v.max, lessThan(900));
      final end = v.jumpToEnd();
      expect(end.max, 900);
      expect(end.span, closeTo(60, 1e-9));
    });
  });

  group('buildSegments', () {
    test('a null reading is a break, not a line across it', () {
      final samples = [
        _s(0, [2000, null, null, null]),
        _s(30, [null, null, null, null]),
        _s(60, [2020, null, null, null]),
      ];
      final segs = buildSegments(samples);
      expect(segs[0].length, 2, reason: 'the hole splits the run');
    });

    test('a gap wider than the cadence is a break', () {
      final samples = [
        _s(0, [2000, null, null, null]),
        _s(30, [2010, null, null, null]),
        _s(60, [2020, null, null, null]),
        // A long hole: 1 h on a 30 s cadence is far past 2.5×.
        _s(3660, [2100, null, null, null]),
      ];
      final segs = buildSegments(samples);
      expect(segs[0].length, 2);
    });

    test('probes are independent', () {
      final samples = [
        _s(0, [2000, 1600, null, 900]),
        _s(30, [2010, 1601, null, 901]),
      ];
      final segs = buildSegments(samples);
      expect(segs[0].length, 1);
      expect(segs[1].length, 1);
      expect(segs[2], isEmpty, reason: 'detached probe 3 has no run');
      expect(segs[3].length, 1);
    });
  });

  group('clipToViewport', () {
    test('keeps one point outside each edge for line continuity', () {
      final run = [
        for (var i = 0; i < 10; i++) FlSpot(i.toDouble(), 100),
      ];
      final clipped = clipToViewport(run, 3, 6);
      expect(clipped.first.x, 2);
      expect(clipped.last.x, 7);
    });
  });

  group('decimation', () {
    test('LTTB returns the budget and keeps the endpoints', () {
      final data = [for (var i = 0; i < 500; i++) FlSpot(i.toDouble(), i % 7)];
      final out = lttb(data, 50);
      expect(out.length, 50);
      expect(out.first.x, data.first.x);
      expect(out.last.x, data.last.x);
    });

    test('the min/max envelope preserves both extremes', () {
      final data = [
        for (var i = 0; i < 1000; i++) FlSpot(i.toDouble(), 200.0),
      ];
      data[500] = const FlSpot(500, 900); // a one-sample spike
      final out = minMaxEnvelope(data, 50);
      expect(out.any((p) => p.y == 900), isTrue);
      expect(out.length, lessThanOrEqualTo(100));
    });

    test('a fifteen-hour cook (1800 samples) fits a pixel budget', () {
      final run = [
        for (var i = 0; i < 1800; i++)
          FlSpot((i * 30 / 60).toDouble(), 200 + (i % 400)),
      ];
      const budget = 600; // 300 px × 2 pts/px
      final out = decimate(run, budget);
      expect(out.length, lessThanOrEqualTo(budget));
    });

    test('a run already within budget is returned untouched', () {
      final run = [for (var i = 0; i < 10; i++) FlSpot(i.toDouble(), 100)];
      expect(identical(decimate(run, 600), run), isTrue);
    });
  });

  testWidgets('a long session renders the chart and its viewport controls', (
    tester,
  ) async {
    final samples = [
      for (var i = 0; i < 1800; i++)
        _s(i * 30, [2000 + (i % 400), 1600, null, 900]),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildSmokeTheme(),
        home: Scaffold(body: TempChart(samples: samples)),
      ),
    );
    await tester.pump();

    expect(find.text('All'), findsOneWidget);
    expect(find.text('15m'), findsOneWidget);
    expect(find.text('Probe 1'), findsOneWidget);
  });
}
