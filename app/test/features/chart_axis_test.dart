/// A10.3 — axis labels must not collide.
///
/// Board-found during the A15.5 bench sitting: the 15 h overnight cook drew
/// `5:30` and `6:29` as one smear on the time axis, and `59` over `60` on
/// the temperature axis. The cause is in fl_chart, not in our data —
/// `AxisChartHelper.iterateThroughAxis` yields a label at each axis *bound*
/// in addition to the interval ticks and never checks whether the two land
/// in the same place. Every real session has ragged bounds, so this fired
/// on the very first cook shown to a human.
///
/// The golden suite could not have caught it: it fixes `targetPoints` and a
/// 320 px box precisely so goldens describe data rather than layout, and at
/// that size the bounds happened to fall on tick multiples.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/features/chart/chart.dart';

import '../support/shapes.dart';

/// The rect each axis label actually paints into, in global coordinates.
List<(String, Rect)> _labels(WidgetTester tester) => [
  for (final e in find.byType(Text).evaluate())
    if ((e.widget as Text).data != null)
      (
        (e.widget as Text).data!,
        (e.renderObject! as RenderBox).localToGlobal(Offset.zero) &
            (e.renderObject! as RenderBox).size,
      ),
];

/// Labels sharing an axis must not paint over one another. Horizontal for
/// the time axis (same dy, differing dx), vertical for the temperature
/// axis (same dx, differing dy).
void _expectNoOverlap(List<(String, Rect)> labels, {required bool vertical}) {
  for (var i = 0; i < labels.length; i++) {
    for (var j = i + 1; j < labels.length; j++) {
      final (aText, a) = labels[i];
      final (bText, b) = labels[j];
      if (!a.overlaps(b)) {
        continue;
      }
      fail(
        'axis labels "$aText" $a and "$bText" $b overlap '
        '(${vertical ? "temperature" : "time"} axis)',
      );
    }
  }
}

void main() {
  group('showAxisLabel', () {
    // The bench geometry: a 360 dp phone leaves the chart 316 dp wide.
    TitleMeta meta(
      double min,
      double max,
      double interval, {
      double axisSize = 316,
      AxisSide side = AxisSide.bottom,
    }) => TitleMeta(
      min: min,
      max: max,
      parentAxisSize: axisSize,
      axisPosition: 0,
      appliedInterval: interval,
      sideTitles: const SideTitles(),
      formattedValue: '',
      axisSide: side,
      rotationQuarterTurns: 0,
    );

    // labelSmall: a "5:30" is about 30x14, a "60" about 24x14. The rule
    // measures every label it compares, so these stand in for both sides.
    Size Function(double) sized(Size s) =>
        (_) => s;
    final time = sized(const Size(30, 14));
    final temp = sized(const Size(24, 14));

    test('interior ticks are always drawn', () {
      final m = meta(12540, 66540, 10800);
      expect(showAxisLabel(21600, m, measure: time), isTrue);
      expect(showAxisLabel(43200, m, measure: time), isTrue);
    });

    test('the bench cook: a crowded end bound is dropped', () {
      // 3:29 -> 6:29 at a 3 h interval. The last tick is 5:30, so the end
      // bound has 59 min of room out of 180 and would have collided.
      final m = meta(12540, 66540, 10800);
      expect(showAxisLabel(66540, m, measure: time), isFalse);
      // The start bound has 2 h 01 of room and did not collide, so it stays.
      expect(showAxisLabel(12540, m, measure: time), isTrue);
    });

    test('the bench cook: crowded temperature bounds are dropped', () {
      final m = meta(59.4, 106.2, 5, axisSize: 292, side: AxisSide.left);
      expect(showAxisLabel(59.4, m, measure: temp), isFalse);
      expect(showAxisLabel(106.2, m, measure: temp), isFalse);
    });

    test('a bound that is itself a tick is kept', () {
      final m = meta(0, 54000, 10800);
      expect(showAxisLabel(0, m, measure: time), isTrue);
      expect(showAxisLabel(54000, m, measure: time), isTrue);
    });

    test('a span too short to hold a tick still labels its start', () {
      // The empty-axis trap: fl_chart's own iterator yields nothing here
      // once both bounds are suppressed, which would leave a bare axis.
      final m = meta(120, 180, 60);
      expect(showAxisLabel(120, m, measure: time), isTrue);
    });

    test('a degenerate interval is not divided by', () {
      expect(showAxisLabel(5, meta(0, 10, 0), measure: time), isTrue);
    });
  });

  testWidgets('the 15 h bench cook draws no overlapping axis labels', (
    tester,
  ) async {
    // The shape that failed on the phone: ~15 h, ragged bounds, at the
    // real device size rather than the goldens' fixed 320 px box.
    const spanS = 54000;
    const startT = 12540;
    final cook = syntheticCook(hours: 16, probes: 4);

    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final vp = ChartViewport.forSession(
      fromT: startT,
      toT: startT + spanS,
      window: ChartWindow.all,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: SizedBox(
            height: 420,
            child: CookChart(
              model: buildChartSeries(cook, fromT: vp.minX, toT: vp.maxX),
              viewport: vp,
              probes: pitAndFood,
              startedUnixMs: 1784755815000,
              fullHistory: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final labels = _labels(tester);
    expect(labels, isNotEmpty, reason: 'the axes must not come out bare');

    final byRow = <double, List<(String, Rect)>>{};
    final byCol = <double, List<(String, Rect)>>{};
    for (final l in labels) {
      (byRow[l.$2.top] ??= []).add(l);
      (byCol[l.$2.left] ??= []).add(l);
    }
    for (final row in byRow.values) {
      _expectNoOverlap(row, vertical: false);
    }
    for (final col in byCol.values) {
      _expectNoOverlap(col, vertical: true);
    }
  });

  testWidgets('every window keeps at least one label on each axis', (
    tester,
  ) async {
    // Suppression must never be able to empty an axis, at any zoom.
    final cook = syntheticCook(hours: 16, probes: 4);
    for (final w in ChartWindow.values) {
      final vp = ChartViewport.forSession(
        fromT: 137,
        toT: 137 + 57600,
        window: w,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 320,
              child: CookChart(
                model: buildChartSeries(cook, fromT: vp.minX, toT: vp.maxX),
                viewport: vp,
                probes: pitAndFood,
                startedUnixMs: 1784755815000,
                fullHistory: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        _labels(tester),
        isNotEmpty,
        reason: 'window ${w.name} left the axes bare',
      );
    }
  });
}
