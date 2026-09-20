/// A10.3 / A10.5 — the chart's rendering and its readouts.
///
/// The interesting assertions here are structural rather than visual:
/// how many bar segments a gap produces, whether an overlay is present,
/// and whether the capability notice is driven by the *flag* rather than
/// by a type check on the transport.
///
/// §17.3 D added four things — an area fill, a legend, labelled target lines
/// and a channel-dot selector — and each of them is a way for the colour rule
/// to break, so each is pinned here **negatively as well as positively**: not
/// only "the fill exists" but "the fill is 16 %, comes from `ProbePalette`, and
/// stops at a gap boundary".
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/chart/chart.dart';
import 'package:smoke_bridge/ui/ui.dart';

import '../support/shapes.dart';

Widget _wrap(
  Widget child, {
  Brightness brightness = Brightness.dark,
  double height = 320,
  double? width,
  double textScale = 1,
  bool reducedMotion = false,
}) => MaterialApp(
  theme: brightness == Brightness.dark ? SmokeTheme.dark : SmokeTheme.daylight,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reducedMotion,
      ),
      child: Scaffold(
        body: Center(
          child: SizedBox(height: height, width: width, child: child),
        ),
      ),
    ),
  ),
);

LineChartData _dataOf(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

/// Every bar that carries a stroke — i.e. not the envelope, which is drawn at
/// `barWidth: 0` and is a fill rather than a line.
Iterable<LineChartBarData> _strokes(WidgetTester tester) =>
    _dataOf(tester).lineBarsData.where((b) => b.barWidth > 0);

Widget _chart(
  List<Sample> cook, {
  bool fullHistory = true,
  List<Mark> marks = const [],
  List<Probe> probes = pitAndFood,
  int? startedUnixMs = 1784755815000,
  double height = 320,
  double? width,
  double textScale = 1,
  bool reducedMotion = false,
  bool celsius = false,
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
      celsius: celsius,
    ),
    height: height,
    width: width,
    textScale: textScale,
    reducedMotion: reducedMotion,
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
      // The name and the value are two `Text`s now — the value is `mono`, so
      // the digits stay tabular while the crosshair drags. The claim is
      // unchanged: a detached jack reads as nothing, never as zero.
      await tester.pumpWidget(readout(1800, syntheticCook(hours: 4)));
      expect(find.text('Point'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      expect(find.text('0.0°'), findsNothing);
    });

    testWidgets('inside a gap every probe refuses', (tester) async {
      await tester.pumpWidget(
        readout(4500, withGap(syntheticCook(hours: 4), fromT: 3600, toT: 5400)),
      );
      // Four probes, four em dashes: nothing is interpolated across the hole.
      expect(find.text('—'), findsNWidgets(4));
    });

    testWidgets('it sits on `well` in mono — the token set says so', (
      tester,
    ) async {
      await tester.pumpWidget(readout(1800, syntheticCook(hours: 4)));
      final box = tester.widget<Container>(
        find.byKey(const Key('chart-crosshair-readout')),
      );
      final d = box.decoration! as BoxDecoration;
      expect(
        d.color,
        SmokeTokens.dark.well,
        reason: '`well` is documented as "mono readouts only — passkey, AP '
            'password, device id, chart crosshair"',
      );
      expect(
        (d.borderRadius! as BorderRadius).topLeft.x,
        SmokeTokens.radiusControl,
        reason: 'the design system has four radii and 10 is not one of them',
      );
      final monos = tester
          .widgetList<Text>(find.byType(Text))
          .where((w) => w.style?.fontFamily == SmokeFonts.mono);
      expect(
        monos,
        hasLength(4),
        reason: 'one tabular value per probe — proportional figures make the '
            'whole card twitch as the crosshair drags',
      );
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
      // `SegmentedChips` now, not five raw `ChoiceChip`s — it is the component
      // whose own doc names "chart windows" first, and it had never been
      // called from here.
      expect(find.byType(SegmentedChips<ChartWindow>), findsOneWidget);
      await tester.tap(find.text('1h'));
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

  // ── §17.3 D — the four things the teardown asked for ──────────────────

  group('the area fill (17 §17.2, FireBoard-1)', () {
    testWidgets('every stroke carries a 16 % tint of its own hue', (
      tester,
    ) async {
      await tester.pumpWidget(_chart(syntheticCook(hours: 3)));
      final strokes = _strokes(tester).toList();
      expect(strokes, isNotEmpty);
      for (final bar in strokes) {
        expect(bar.belowBarData.show, isTrue);
        expect(
          bar.belowBarData.color,
          ProbePalette.tint(bar.color!),
          reason: '§17.2 sanctions the fill "through ProbePalette.tint and '
              'nothing else"',
        );
        expect(bar.belowBarData.color!.a, closeTo(0.16, 0.001));
      }
    });

    testWidgets('the fill stops at a gap, exactly as the stroke does', (
      tester,
    ) async {
      // The whole point of splitting a run is that a 30-minute dropout looks
      // like a 30-minute dropout. A fill attached to the *series* rather than
      // to the run would paint a solid slab straight across the hole and undo
      // the split above it — so the fill lives on the run, and every filled
      // bar's spots must therefore respect the hole.
      final cook = withGap(syntheticCook(hours: 4), fromT: 3600, toT: 5400);
      await tester.pumpWidget(_chart(cook));
      for (final bar in _strokes(tester)) {
        expect(bar.belowBarData.show, isTrue);
        for (final spot in bar.spots) {
          expect(spot.x > 3600 && spot.x < 5400, isFalse);
        }
      }
    });

    testWidgets('where there is an envelope, the band is the fill', (
      tester,
    ) async {
      // Two fills of one series stacked over one region composite to 26 %,
      // which is over §17.2's ceiling however each was declared. So a series
      // carries exactly one: the envelope where it has one, the area otherwise.
      final cook = syntheticCook(hours: 54 * 24, periodS: 300, probes: 1);
      await tester.pumpWidget(_chart(cook));
      final bands = _dataOf(tester).lineBarsData.where((b) => b.barWidth == 0);
      expect(bands, isNotEmpty, reason: 'this window decimates');
      for (final band in bands) {
        expect(band.belowBarData.show, isTrue);
        expect(band.belowBarData.color!.a, closeTo(0.16, 0.001));
      }
      for (final bar in _strokes(tester)) {
        expect(
          bar.belowBarData.show,
          isFalse,
          reason: 'the envelope already is this series fill',
        );
      }
    });

    testWidgets('the pit alarm band is the same helper at half strength', (
      tester,
    ) async {
      await tester.pumpWidget(_chart(syntheticCook(hours: 3)));
      final band =
          _dataOf(tester).rangeAnnotations.horizontalRangeAnnotations.single;
      expect(
        band.color,
        ProbePalette.tint(ProbePalette.hue(1), SeriesFill.band),
        reason: 'the 0.08 that used to be typed inline here',
      );
    });
  });

  group('the target lines are labelled, on the line (TemProBBQ-3)', () {
    testWidgets('each names its probe and prints its value', (tester) async {
      await tester.pumpWidget(_chart(syntheticCook(hours: 3)));
      final lines = _dataOf(tester).extraLinesData.horizontalLines;
      expect(lines, hasLength(2));
      final labels = [for (final l in lines) l.label.labelResolver(l)];
      // `pitAndFood`: pit 250°, brisket 203°. A target line you cannot read
      // the value of is decoration.
      expect(labels, contains('Pit 250°'));
      expect(labels, contains('Brisket 203°'));
      for (final l in lines) {
        expect(l.label.show, isTrue);
      }
    });

    testWidgets('the label is ink, never the series hue', (tester) async {
      // TempPro prints `150°F` in its line's blue. §16.5: a series hue "never
      // carries a word", and §17.4 rejects MEATER's coloured readouts for
      // exactly this. The rule carries identity; the text carries the value.
      await tester.pumpWidget(_chart(syntheticCook(hours: 3)));
      for (final l in _dataOf(tester).extraLinesData.horizontalLines) {
        expect(l.label.style!.color, SmokeTokens.dark.textBody);
      }
    });

    testWidgets('it converts with the unit', (tester) async {
      await tester.pumpWidget(_chart(syntheticCook(hours: 3), celsius: true));
      final lines = _dataOf(tester).extraLinesData.horizontalLines;
      final labels = [for (final l in lines) l.label.labelResolver(l)];
      expect(labels.any((s) => s.contains('250°')), isFalse);
      expect(labels, contains('Pit 121.1°'));
    });
  });

  group('the legend, finally wired (17 §17.3 D)', () {
    testWidgets('it renders under the chart, one entry per drawn series', (
      tester,
    ) async {
      await tester.pumpWidget(_chart(syntheticCook(hours: 3)));
      expect(find.byKey(const Key('chart-legend')), findsOneWidget);
      // Probes 3 and 4 contributed no points to this window, so they are not
      // series and there is nothing for an entry to key.
      expect(find.byKey(const Key('legend-1')), findsOneWidget);
      expect(find.byKey(const Key('legend-2')), findsOneWidget);
      expect(find.byKey(const Key('legend-3')), findsNothing);
      expect(find.text('Pit'), findsOneWidget);
      expect(find.text('Brisket'), findsOneWidget);
    });

    testWidgets('every entry is more than a hue — glyph, stroke, word', (
      tester,
    ) async {
      // §H.2's accessibility requirement, and the reason it is not optional is
      // measured: P1 ember and P4 blue sit 0.018 apart in luminance.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_chart(syntheticCook(hours: 3)));
      final label = tester.getSemantics(find.byKey(const Key('legend-1'))).label;
      expect(label, contains(ProbePalette.glyphFor(1).label));
      expect(label, contains('solid'));
      expect(find.byType(SeriesGlyphMark), findsWidgets);
      handle.dispose();
    });
  });

  group('the channel-dot selector (TemProBBQ-3)', () {
    testWidgets('one dot per drawn series, and none below two', (tester) async {
      await tester.pumpWidget(_chart(syntheticCook(hours: 3)));
      expect(find.byKey(const Key('chart-dot-1')), findsOneWidget);
      expect(find.byKey(const Key('chart-dot-2')), findsOneWidget);
      expect(find.byKey(const Key('chart-dot-3')), findsNothing);

      // Isolating one of one is a control with nothing to do — but the legend
      // still names the line, which is a different question.
      await tester.pumpWidget(_chart(syntheticCook(hours: 3, probes: 1)));
      expect(find.byKey(const Key('chart-dot-1')), findsNothing);
      expect(find.byKey(const Key('chart-legend')), findsOneWidget);
    });

    testWidgets('a tap isolates, and a second tap restores', (tester) async {
      await tester.pumpWidget(_chart(syntheticCook(hours: 3)));
      final full = {for (final b in _strokes(tester)) b.color};
      expect(full, contains(ProbePalette.hue(1)));
      expect(full, contains(ProbePalette.hue(2)));

      await tester.tap(find.byKey(const Key('chart-dot-1')));
      await tester.pumpAndSettle();
      final isolated = {for (final b in _strokes(tester)) b.color};
      expect(
        isolated,
        contains(ProbePalette.hue(1)),
        reason: 'the isolated series keeps full ink',
      );
      expect(
        isolated,
        contains(ProbePalette.dim(ProbePalette.hue(2))),
        reason: 'the rest recede to a mark, they do not disappear — isolating '
            'the pit to read it against nothing is a worse chart',
      );
      for (final b in _strokes(tester)) {
        if (b.color != ProbePalette.hue(1)) {
          expect(b.belowBarData.show, isFalse, reason: 'and give up the fill');
        }
      }

      // The key follows the chart. A legend still drawn at full ink beside a
      // receded series is a key that disagrees with the thing it keys — which
      // is why both spend `ProbePalette.dim` rather than two literals.
      final entries = tester.widgetList<SeriesGlyphMark>(
        find.descendant(
          of: find.byKey(const Key('chart-legend')),
          matching: find.byType(SeriesGlyphMark),
        ),
      );
      expect(entries.map((e) => e.dimmed), [false, true]);

      await tester.tap(find.byKey(const Key('chart-dot-1')));
      await tester.pumpAndSettle();
      expect({for (final b in _strokes(tester)) b.color}, full);
    });

    testWidgets('an isolated probe being unplugged restores the rest', (
      tester,
    ) async {
      // A chart that dimmed all four series because the isolated jack was
      // pulled would look broken rather than empty.
      await tester.pumpWidget(_chart(syntheticCook(hours: 3)));
      await tester.tap(find.byKey(const Key('chart-dot-2')));
      await tester.pumpAndSettle();
      expect(
        {for (final b in _strokes(tester)) b.color},
        contains(ProbePalette.dim(ProbePalette.hue(1))),
      );

      await tester.pumpWidget(
        _chart(syntheticCook(hours: 3, probes: 1), probes: pitAndFood),
      );
      await tester.pumpAndSettle();
      expect(
        {for (final b in _strokes(tester)) b.color},
        contains(ProbePalette.hue(1)),
      );
    });

    testWidgets('the dot wears its hue filled — §17.2/§17.5 say it may', (
      tester,
    ) async {
      // A control that says *which probe* makes no claim about temperature, so
      // §17.5's guard has nothing to guard and §17.2's badge exception governs:
      // "the hue IS the probe's identity … it is a legend, not a claim".
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_chart(syntheticCook(hours: 3)));
      final dot = find.byKey(const Key('chart-dot-1'));
      expect(tester.getSize(dot).height, greaterThanOrEqualTo(44));

      BoxDecoration decorationOf(Finder f) =>
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: f,
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;

      expect(decorationOf(dot).color, ProbePalette.hue(1));
      expect(decorationOf(dot).shape, BoxShape.circle);

      // …and never by hue alone: the glyph is knocked out of the disc, so the
      // selector survives the monochrome screenshot that makes P1 and P4 the
      // same grey.
      final glyph = tester.widget<SeriesGlyphMark>(
        find.descendant(of: dot, matching: find.byType(SeriesGlyphMark)),
      );
      expect(glyph.color, SmokeTokens.dark.bg);
      expect(glyph.style.glyph, ProbePalette.glyphFor(1));

      expect(
        tester.getSemantics(dot).hint,
        'Show only this series',
        reason: 'a filter with no visible way out is a screen people get '
            'stuck on',
      );

      // Switched off looks switched off: hollow, in the same hue.
      await tester.tap(find.byKey(const Key('chart-dot-2')));
      await tester.pumpAndSettle();
      expect(decorationOf(dot).color, isNull);
      expect(
        decorationOf(dot).border!.top.color,
        ProbePalette.dim(ProbePalette.hue(1)),
      );
      // The isolated one is ringed in ink — hue is already spent naming the
      // probe, and a second meaning laid over it is how a mark starts making
      // claims.
      expect(
        decorationOf(find.byKey(const Key('chart-dot-2'))).border!.top.color,
        SmokeTokens.dark.textHi,
      );
      handle.dispose();
    });
  });

  group('the chrome is budgeted against the height it was given', () {
    testWidgets('a 240 dp chart gets both the dots and the legend', (
      tester,
    ) async {
      await tester.pumpWidget(_chart(syntheticCook(hours: 3), height: 240));
      expect(find.byKey(const Key('chart-dot-1')), findsOneWidget);
      expect(find.byKey(const Key('chart-legend')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 120 dp pane keeps the plot and drops the chrome', (
      tester,
    ) async {
      // `live_tab` hands the chart 120 dp on a half-open Fold. Chrome that
      // squeezes the plot under its floor cost more than it bought.
      await tester.pumpWidget(_chart(syntheticCook(hours: 3), height: 120));
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.byKey(const Key('chart-dot-1')), findsNothing);
      expect(find.byKey(const Key('chart-legend')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final width in [360.0, 600.0, 840.0]) {
      testWidgets('$width dp carries the whole set at normal text', (
        tester,
      ) async {
        await tester.pumpWidget(
          _chart(syntheticCook(hours: 3), height: 240, width: width),
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('chart-legend')), findsOneWidget);
        expect(find.byKey(const Key('chart-dot-1')), findsOneWidget);
      });

      testWidgets('$width dp at 200 % text keeps the key, not the filter', (
        tester,
      ) async {
        // At 200 % a legend row is 39 dp and the entries start wrapping, so
        // something has to give out of 240 dp. The order is stated in
        // `_ChromeBudget`: the legend outranks the selector, because a key
        // that names the lines is worth more than a control that hides some
        // of them, and because the selector's fallback is "do nothing" while
        // the legend's fallback is guessing.
        await tester.pumpWidget(
          _chart(
            syntheticCook(hours: 3),
            height: 240,
            width: width,
            textScale: 2,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('chart-legend')), findsOneWidget);
        expect(find.byType(LineChart), findsOneWidget);
      });
    }

    testWidgets('the capability notice is paid for out of the same budget', (
      tester,
    ) async {
      await tester.pumpWidget(
        _chart(syntheticCook(hours: 2), height: 240, fullHistory: false),
      );
      expect(find.byKey(const Key('chart-capability-notice')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the design system reaches the chart at last', () {
    testWidgets('no status hue enters a series — the property, pinned', (
      tester,
    ) async {
      // An audit found this file already clean and it is worth keeping exactly
      // so: every stroke, band, fill and rule resolves through `ProbePalette`.
      // A probe drawn in warning-amber would impersonate an alarm on a screen
      // whose whole job is alarms.
      await tester.pumpWidget(_chart(syntheticCook(hours: 3)));
      final data = _dataOf(tester);
      final status = {
        StatusPalette.warning,
        StatusPalette.critical,
        StatusPalette.positive,
      };
      bool isStatus(Color? c) =>
          c != null && status.any((s) => s.r == c.r && s.g == c.g && s.b == c.b);
      for (final bar in data.lineBarsData) {
        expect(isStatus(bar.color), isFalse);
        expect(isStatus(bar.belowBarData.color), isFalse);
      }
      for (final l in data.extraLinesData.horizontalLines) {
        expect(isStatus(l.color), isFalse);
      }
      for (final a in data.rangeAnnotations.horizontalRangeAnnotations) {
        expect(isStatus(a.color), isFalse);
      }
    });

    testWidgets('the grid and the axis are tokens, not a warm-grey ramp', (
      tester,
    ) async {
      await tester.pumpWidget(_chart(syntheticCook(hours: 3)));
      final data = _dataOf(tester);
      expect(
        data.gridData.getDrawingHorizontalLine(0).color,
        SmokeTokens.dark.hairline,
      );
      final tick = tester.widgetList<Text>(find.text('250')).first;
      expect(tick.style?.color, SmokeTokens.dark.textMuted);
      expect(tick.style?.fontSize, SmokeType.labelSm.fontSize);
    });

    testWidgets('reduced motion reaches fl_chart, which had its own default', (
      tester,
    ) async {
      await tester.pumpWidget(_chart(syntheticCook(hours: 3)));
      expect(
        tester.widget<LineChart>(find.byType(LineChart)).duration,
        SmokeMotionValues.full.quick,
      );

      await tester.pumpWidget(
        _chart(syntheticCook(hours: 3), reducedMotion: true),
      );
      expect(
        tester.widget<LineChart>(find.byType(LineChart)).duration,
        Duration.zero,
        reason: 'isolating a channel repaints every bar, and fl_chart tweens '
            'that over a hard-coded 150 ms the OS setting cannot reach',
      );
    });

    testWidgets('the notice is a component, not a slab', (tester) async {
      await tester.pumpWidget(_chart(const [], fullHistory: false));
      expect(find.byType(CapabilityNotice), findsOneWidget);
    });
  });

  group('the empty chart is warm — 17 §17.5', () {
    testWidgets('it is an ember medallion and a sentence, not a grey line', (
      tester,
    ) async {
      // §17.5: the discipline exists to stop colour lying about how the cook
      // is going, and "that failure requires live state to fail about". There
      // is none here — no series, no reading, no claim.
      await tester.pumpWidget(_chart(const [], height: 320));
      final empty = tester.widget<Text>(find.byKey(const Key('chart-empty')));
      expect(empty.style?.color, SmokeTokens.dark.textHi);
      expect(empty.style?.fontSize, SmokeType.displayS.fontSize);
      expect(
        find.text('The cook draws itself here as soon as a probe reports.'),
        findsOneWidget,
      );

      final medallion = tester.widget<Container>(
        find
            .byWidgetPredicate(
              (w) =>
                  w is Container &&
                  (w.decoration as BoxDecoration?)?.shape == BoxShape.circle,
            )
            .first,
      );
      expect(
        (medallion.decoration! as BoxDecoration).color,
        ProbePalette.hue(1),
        reason: '§14.6.4 pins slot 1 to the brand ember precisely so this is '
            'one hue rather than two similar ones — and reading it from '
            '`ProbePalette` keeps this file at zero `StatusPalette` '
            'references',
      );
      expect(find.byIcon(Icons.outdoor_grill_rounded), findsOneWidget);
    });

    testWidgets('no invented trace — the one illustration it may not draw', (
      tester,
    ) async {
      // A ghost sample line is the obvious warm illustration for an empty
      // chart and the single worst thing that could go on this surface: an
      // invented plot, on a chart whose whole contract is that it never
      // invents a reading.
      await tester.pumpWidget(_chart(const [], height: 320));
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('a short pane gets the same warmth on one line', (
      tester,
    ) async {
      await tester.pumpWidget(_chart(const [], height: 120));
      expect(find.byKey(const Key('chart-empty')), findsOneWidget);
      expect(find.byIcon(Icons.outdoor_grill_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('all four jacks detached lands on the same surface', (
      tester,
    ) async {
      await tester.pumpWidget(_chart(allDetached(hours: 2), height: 320));
      expect(find.byKey(const Key('chart-empty')), findsOneWidget);
    });

    for (final width in [360.0, 600.0, 840.0]) {
      testWidgets('$width dp at 200 % text reflows rather than clipping', (
        tester,
      ) async {
        // The medallion does not scale but the title and the sentence do, so
        // a pane that comfortably held the illustration at 1.0 cannot hold it
        // at 2.0. §14.10's answer is to reflow.
        for (final height in [120.0, 240.0, 320.0]) {
          await tester.pumpWidget(
            _chart(const [], height: height, width: width, textScale: 2),
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$width x $height at 200 %',
          );
          expect(find.byKey(const Key('chart-empty')), findsOneWidget);
          expect(find.byIcon(Icons.outdoor_grill_rounded), findsOneWidget);
        }
      });
    }
  });
}
