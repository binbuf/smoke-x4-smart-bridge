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
    final theme = brightness == Brightness.dark ? 'dark' : 'light';
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

  testWidgets('the light palette is in the goldens too', (tester) async {
    await pumpForGolden(
      tester,
      _chart(syntheticCook(hours: 6)),
      brightness: Brightness.light,
      surface: const Size(420, 420),
    );
    final light = describeTree(tester).toLowerCase();
    expect(light, contains('#ffeb6834')); // probe 1, light
    expect(light, contains('#ff4a3aa7')); // probe 2, light
  });
}
