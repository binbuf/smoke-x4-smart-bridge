/// A15.3 — the chart pinned at every shape, in both themes.
///
/// The same six shapes, where the content is structural rather than
/// textual: how many bar segments, where the gap boundaries fell, which
/// overlays are present, what colour and stroke each probe drew with, and
/// what the viewport window was.
///
/// The mid-gap golden is the one worth reading: _"a 30-minute dropout
/// must look like a 30-minute dropout"_ is a claim with an exact,
/// checkable shape, and it is checked here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/chart/chart.dart';

import '../support/shapes.dart';
import 'golden.dart';

Widget _chart(
  List<Sample> cook, {
  ChartWindow window = ChartWindow.all,
  List<Mark> marks = const [],
  bool fullHistory = true,
}) {
  final vp = ChartViewport.forSession(
    fromT: cook.isEmpty ? 0 : cook.first.t,
    toT: cook.isEmpty ? 60 : cook.last.t,
    window: window,
  );
  return SizedBox(
    height: 320,
    child: CookChart(
      model: buildChartSeries(
        cook,
        fromT: vp.minX,
        toT: vp.maxX,
        // Fixed, so a golden describes the data rather than the width of
        // whatever surface the test happened to run on.
        targetPoints: 120,
      ),
      viewport: vp,
      probes: pitAndFood,
      marks: marks,
      startedUnixMs: 1784755815000,
      fullHistory: fullHistory,
    ),
  );
}

final Map<String, Widget Function()> _shapes = {
  'no-probes': () => _chart(const []),
  'all-detached': () => _chart(allDetached(hours: 2)),
  'mid-gap': () =>
      _chart(withGap(syntheticCook(hours: 4), fromT: 3600, toT: 5400)),
  'alarm-active': () => _chart(
    syntheticCook(hours: 6),
    marks: const [Mark(t: 10800, kind: MarkKind.alarm, text: 'target reached')],
  ),
  '15h': () => _chart(syntheticCook(hours: 15)),
  '54d': () => _chart(syntheticCook(hours: 54 * 24, periodS: 300)),
};

void main() {
  for (final brightness in Brightness.values) {
    // The two profiles that actually ship. `daylight` is a *contrast*
    // profile — lifted ink, glows off — over the same dark surfaces
    // (14 §14.3.3), not a Material light theme; the app has no light
    // brightness anywhere.
    final theme = brightness == Brightness.dark ? 'dark' : 'daylight';
    group('chart · $theme', () {
      for (final entry in _shapes.entries) {
        testWidgets(entry.key, (tester) async {
          await pumpForGolden(
            tester,
            entry.value(),
            brightness: brightness,
            surface: const Size(420, 420),
          );
          expectGolden(tester, 'chart-${entry.key}-$theme');
        });
      }
    });
  }

  testWidgets('the mid-gap golden splits at exactly the right seconds', (
    tester,
  ) async {
    await pumpForGolden(
      tester,
      _chart(withGap(syntheticCook(hours: 4), fromT: 3600, toT: 5400)),
      surface: const Size(420, 420),
    );
    final described = describeTree(tester);
    // Two runs per attached probe, and the boundary is the hole itself.
    expect(described, contains('to 3600'));
    expect(described, contains('from 5400'));
  });

  testWidgets('the dark palette is in the goldens, so a change is reviewed', (
    tester,
  ) async {
    await pumpForGolden(
      tester,
      _chart(syntheticCook(hours: 6)),
      surface: const Size(420, 420),
    );
    final dark = describeTree(tester).toLowerCase();
    expect(dark, contains('#ffd95926')); // probe 1, dark
    expect(dark, contains('#ff9085e9')); // probe 2, dark
  });

  testWidgets('the daylight profile draws the same validated hues', (
    tester,
  ) async {
    // This used to assert the **light** series hues (`#ffeb6834`,
    // `#ff4a3aa7`) rendered in-app. They never do, and by design:
    // `series_palette.dart` states that the light values "are retained as
    // the export / print palette — CSV plots and share images render on
    // paper-white, not on the app's obsidian — and are not used in-app."
    //
    // The old assertion passed only because the golden harness mounted
    // `app/theme.dart`, a genuine Material light theme that nothing shipped.
    // Pointed at the real one, the daylight profile keeps `Brightness.dark`
    // and the same surfaces, so it keeps the hues those surfaces were
    // validated against — which is the contract worth pinning.
    await pumpForGolden(
      tester,
      _chart(syntheticCook(hours: 6)),
      brightness: Brightness.light,
      surface: const Size(420, 420),
    );
    final daylight = describeTree(tester).toLowerCase();
    expect(daylight, contains('#ffd95926')); // probe 1, validated
    expect(daylight, contains('#ff9085e9')); // probe 2, validated
    expect(
      daylight,
      isNot(contains('#ffeb6834')),
      reason: 'the light values are the export palette, never on screen',
    );
  });
}
