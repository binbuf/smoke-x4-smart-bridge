/// A10.3 / A10.5 — the chart's rendering and its readouts.
///
/// The interesting assertions here are structural rather than visual:
/// how many bar segments a gap produces, whether an overlay is present,
/// and whether the capability notice is driven by the *flag* rather than
/// by a type check on the transport.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/chart/chart.dart';

import '../support/shapes.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: SizedBox(height: 320, child: child)),
    );

LineChartData _dataOf(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

Widget _chart(
  List<Sample> cook, {
  bool fullHistory = true,
  List<Mark> marks = const [],
  List<Probe> probes = pitAndFood,
  int? startedUnixMs = 1784755815000,
}) {
  final vp = ChartViewport.forSession(
    fromT: cook.isEmpty ? 0 : cook.first.t,
    toT: cook.isEmpty ? 60 : cook.last.t,
    window: ChartWindow.all,
  );
  return _wrap(
    CookChart(
      model: buildChartSeries(cook, fromT: vp.minX, toT: vp.maxX),
      viewport: vp,
      probes: probes,
      marks: marks,
      startedUnixMs: startedUnixMs,
      fullHistory: fullHistory,
    ),
  );
}

void main() {
  testWidgets('an empty series renders a state, not an exception', (
    tester,
  ) async {
    await tester.pumpWidget(_chart(const []));
    expect(find.byKey(const Key('chart-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all-detached renders the same empty state', (tester) async {
    await tester.pumpWidget(_chart(allDetached(hours: 2)));
    expect(find.byKey(const Key('chart-empty')), findsOneWidget);
  });

  testWidgets('a gap becomes more than one bar, with no spot inside it', (
    tester,
  ) async {
    final cook = withGap(syntheticCook(hours: 4), fromT: 3600, toT: 5400);
    await tester.pumpWidget(_chart(cook));
    final data = _dataOf(tester);
    // Probe 1 alone contributes two segments.
    expect(data.lineBarsData.length, greaterThanOrEqualTo(4));
    for (final bar in data.lineBarsData) {
      for (final spot in bar.spots) {
        expect(spot.x > 3600 && spot.x < 5400, isFalse);
      }
    }
  });

  testWidgets('target lines appear for configured probes only', (tester) async {
    await tester.pumpWidget(_chart(syntheticCook(hours: 3)));
    // Probes 1 and 2 have targets; 3 and 4 do not and are detached.
    expect(_dataOf(tester).extraLinesData.horizontalLines, hasLength(2));

    await tester.pumpWidget(
      _chart(
        syntheticCook(hours: 3),
        probes: const [Probe(n: 1, role: ProbeRole.pit)],
      ),
    );
    expect(_dataOf(tester).extraLinesData.horizontalLines, isEmpty);
  });

  testWidgets('the pit alarm band renders, and disappears without one', (
    tester,
  ) async {
    await tester.pumpWidget(_chart(syntheticCook(hours: 3)));
    expect(
      _dataOf(tester).rangeAnnotations.horizontalRangeAnnotations,
      hasLength(1),
    );

    await tester.pumpWidget(
      _chart(
        syntheticCook(hours: 3),
        probes: const [Probe(n: 1, role: ProbeRole.pit)],
      ),
    );
    expect(
      _dataOf(tester).rangeAnnotations.horizontalRangeAnnotations,
      isEmpty,
    );
  });

  testWidgets('marks become vertical lines inside the window', (tester) async {
    await tester.pumpWidget(
      _chart(
        syntheticCook(hours: 3),
        marks: const [
          Mark(t: 1800, kind: MarkKind.wrapped),
          // Outside the window: must not be drawn.
          Mark(t: 999999, kind: MarkKind.lidOpen),
        ],
      ),
    );
    expect(_dataOf(tester).extraLinesData.verticalLines, hasLength(1));
  });

  testWidgets('54 days draws an envelope behind the line', (tester) async {
    final cook = syntheticCook(hours: 54 * 24, periodS: 300, probes: 1);
    await tester.pumpWidget(_chart(cook, probes: pitAndFood));
    final data = _dataOf(tester);
    // The envelope bar is a filled area with no stroke.
    expect(data.lineBarsData.any((b) => b.barWidth == 0), isTrue);
  });

  group('the capability notice', () {
    testWidgets('appears when fullHistory is false', (tester) async {
      await tester.pumpWidget(
        _chart(syntheticCook(hours: 2), fullHistory: false),
      );
      expect(find.byKey(const Key('chart-capability-notice')), findsOneWidget);
      expect(find.textContaining('full history needs Wi-Fi'), findsOneWidget);
    });

    testWidgets('is absent when it is true', (tester) async {
      await tester.pumpWidget(_chart(syntheticCook(hours: 2)));
      expect(find.byKey(const Key('chart-capability-notice')), findsNothing);
    });

    testWidgets('shows even when there is nothing to plot', (tester) async {
      await tester.pumpWidget(_chart(const [], fullHistory: false));
      expect(find.byKey(const Key('chart-capability-notice')), findsOneWidget);
    });
  });

  group('the axis', () {
    test('reads wall clock when the session has one', () {
      final s = formatAxisTime(
        3600,
        DateTime.utc(2026, 7, 21, 12).millisecondsSinceEpoch,
      );
      expect(RegExp(r'^\d{1,2}(:\d{2})?[ap]$').hasMatch(s), isTrue);
    });

    test('reads elapsed time when it does not — never 1970', () {
      expect(formatAxisTime(0, null), '0m');
      expect(formatAxisTime(3600, null), '1h00');
      expect(formatAxisTime(5400, null), '1h30');
      expect(formatAxisTime(1800, null), '30m');
    });
  });

  group('the crosshair readout', () {
    Widget readout(int atT, List<Sample> cook) {
      final model = buildChartSeries(
        cook,
        fromT: 0,
        toT: 14400,
        targetPoints: 0,
      );
      return _wrap(
        CrosshairReadout(
          readings: crosshairAt(model, atT),
          atT: atT,
          probes: pitAndFood,
        ),
      );
    }

    testWidgets('at a sample it names every probe', (tester) async {
      await tester.pumpWidget(readout(1800, syntheticCook(hours: 4)));
      expect(find.byKey(const Key('chart-crosshair-readout')), findsOneWidget);
      expect(find.textContaining('Pit'), findsOneWidget);
      expect(find.textContaining('Brisket'), findsOneWidget);
    });

    testWidgets('a detached probe reads as an em dash, not 0', (tester) async {
      await tester.pumpWidget(readout(1800, syntheticCook(hours: 4)));
      expect(find.textContaining('Point  —'), findsOneWidget);
    });

    testWidgets('inside a gap every probe refuses', (tester) async {
      await tester.pumpWidget(
        readout(4500, withGap(syntheticCook(hours: 4), fromT: 3600, toT: 5400)),
      );
      expect(find.textContaining('Pit  —'), findsOneWidget);
    });
  });

  testWidgets('the chart owns its gestures rather than fl_chart', (
    tester,
  ) async {
    await tester.pumpWidget(_chart(syntheticCook(hours: 3)));
    expect(find.byKey(const Key('chart-gestures')), findsOneWidget);
    // Two things fighting over a drag is how a chart becomes unusable.
    expect(_dataOf(tester).lineTouchData.enabled, isFalse);
  });

  group('the controls', () {
    testWidgets('chips select a window', (tester) async {
      ChartViewport? got;
      final vp = ChartViewport.forSession(fromT: 0, toT: 54000);
      await tester.pumpWidget(
        _wrap(ChartControls(viewport: vp, onViewport: (v) => got = v)),
      );
      await tester.tap(find.byKey(const Key('chart-chip-h1')));
      await tester.pump();
      expect(got!.window, ChartWindow.h1);
      expect(got!.spanS, 3600);
    });

    testWidgets('jump-to-now appears only once it has something to do', (
      tester,
    ) async {
      final following = ChartViewport.forSession(fromT: 0, toT: 54000);
      await tester.pumpWidget(
        _wrap(ChartControls(viewport: following, onViewport: (_) {})),
      );
      expect(find.byKey(const Key('chart-jump-to-now')), findsNothing);

      await tester.pumpWidget(
        _wrap(
          ChartControls(viewport: following.pan(-10000), onViewport: (_) {}),
        ),
      );
      expect(find.byKey(const Key('chart-jump-to-now')), findsOneWidget);
    });
  });
}
