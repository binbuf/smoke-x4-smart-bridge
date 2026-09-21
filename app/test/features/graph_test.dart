/// N7 — the Graph destination and the fullscreen host.
///
/// Covers the exit gate: the range chips and zoom change the window, the legend
/// isolates without losing stroke identity, the fullscreen chart is the same
/// widget with the same window as the inline one, and the crosshair reports a
/// real reading. Also the empty state and the two actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/graph/graph.dart';
import 'package:smoke_bridge/features/shell/shell.dart';

import '../support/load_fonts.dart';

const int _t0ms = 1700000000000;
final DateTime _t0 = DateTime.fromMillisecondsSinceEpoch(_t0ms);

void main() {
  setUpAll(loadAppFonts);

  late MockBridgeRepository repo;
  late MockPrefsRepository prefs;

  setUp(() {
    repo = MockBridgeRepository(nowMs: _t0ms);
    prefs = MockPrefsRepository();
  });

  tearDown(() async {
    await repo.dispose();
    await prefs.dispose();
  });

  Widget harness() => ProviderScope(
    overrides: [
      bridgeRepositoryProvider.overrideWithValue(repo),
      prefsProvider.overrideWithValue(prefs),
      shellPulseEnabledProvider.overrideWithValue(false),
      shellClockProvider.overrideWithValue(_t0),
      graphNowProvider.overrideWithValue(_t0),
    ],
    child: MaterialApp(
      theme: SmokeThemeData.dark(),
      home: const Scaffold(
        body: AppShell(location: '/graph', child: GraphPage()),
      ),
    ),
  );

  Future<void> pumpGraph(
    WidgetTester tester, {
    String scenario = 'running',
    Future<void> Function()? before,
    Size size = const Size(390, 1600),
  }) async {
    await repo.selectScenario(scenario);
    if (before != null) {
      await before();
    }
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
  }

  CookChart chart(WidgetTester tester, [String key = 'graph-chart']) =>
      tester.widget<CookChart>(find.byKey(ValueKey<String>(key)));

  testWidgets('renders the chart, legend and window statistics', (
    tester,
  ) async {
    await pumpGraph(tester);

    expect(find.byKey(const ValueKey<String>('graph-page')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('graph-range')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('graph-chart')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('graph-legend')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('graph-stats')), findsOneWidget);
    for (var jack = 1; jack <= 4; jack++) {
      expect(find.byKey(ValueKey<String>('graph-stat-$jack')), findsOneWidget);
    }
    expect(chart(tester).series.length, 4);
  });

  testWidgets('a range chip changes the window span', (tester) async {
    await pumpGraph(tester);
    expect(chart(tester).domain.span, closeTo(252, 0.001));

    await tester.tap(find.text('1h'));
    await tester.pumpAndSettle();
    expect(chart(tester).domain.span, closeTo(60, 0.001));
  });

  testWidgets('zoom in/out and Reset view', (tester) async {
    await pumpGraph(tester);
    expect(find.byKey(const ValueKey<String>('graph-reset')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('graph-zoom-in')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('graph-reset')), findsOneWidget);
    final hint = tester.widget<Text>(
      find.byKey(const ValueKey<String>('graph-zoom-hint')),
    );
    expect(hint.data, '1.5× zoom');

    await tester.tap(find.byKey(const ValueKey<String>('graph-zoom-out')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('graph-reset')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('graph-zoom-in')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('graph-reset')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('graph-reset')), findsNothing);
  });

  testWidgets('dragging the chart pans the window', (tester) async {
    await pumpGraph(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>('graph-chart'))),
    );
    // Several moves: the first crosses the touch slop and starts the drag, the
    // rest are the updates the chart pans on.
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('graph-reset')), findsOneWidget);
  });

  testWidgets('the legend tap isolates a probe, then clears', (tester) async {
    await pumpGraph(tester);
    final first = chart(tester).series.first;
    final entry = find.descendant(
      of: find.byKey(const ValueKey<String>('graph-legend')),
      matching: find.text(first.label),
    );

    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(chart(tester).isolatedJack, first.jack.n);

    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(chart(tester).isolatedJack, isNull);
  });

  testWidgets('the crosshair reports a real reading', (tester) async {
    await pumpGraph(tester);
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey<String>('graph-chart'))),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('graph-crosshair')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('graph-crosshair')),
        matching: find.textContaining('° F'),
      ),
      findsWidgets,
    );
  });

  testWidgets('the fullscreen chart matches the inline chart', (tester) async {
    await pumpGraph(tester);
    final inline = chart(tester);

    await tester.tap(find.byKey(const ValueKey<String>('graph-fullscreen')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('shell-graph-host')),
      findsOneWidget,
    );

    final full = chart(tester, 'graph-fullscreen-chart');
    expect(full.model, same(inline.model));
    expect(full.domain, same(inline.domain));

    // A fullscreen zoom moves the shared window, so the inline chart follows.
    await tester.tap(
      find.byKey(const ValueKey<String>('graph-fullscreen-zoom-in')),
    );
    await tester.pumpAndSettle();
    final fullZoomed = chart(tester, 'graph-fullscreen-chart');
    expect(fullZoomed.domain.span, lessThan(full.domain.span));
    expect(chart(tester).domain, same(fullZoomed.domain));

    // Pan back walks the window earlier; the inline chart follows.
    final beforePan = fullZoomed.domain.xMax;
    await tester.tap(find.byKey(const ValueKey<String>('graph-pan-back')));
    await tester.pumpAndSettle();
    expect(
      chart(tester, 'graph-fullscreen-chart').domain.xMax,
      lessThan(beforePan),
    );

    await tester.tap(find.byKey(const ValueKey<String>('shell-graph-exit')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('graph-fullscreen-chart')),
      findsNothing,
    );
  });

  testWidgets('the unit toggle converts the legend and targets', (
    tester,
  ) async {
    await pumpGraph(tester);
    expect(find.textContaining('° F'), findsWidgets);

    await prefs.update(
      (settings) => settings.copyWith(units: TempUnit.celsius),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('° C'), findsWidgets);
  });

  testWidgets('Add mark opens the mark sheet and Share toasts', (tester) async {
    await pumpGraph(tester);

    await tester.tap(find.byKey(const ValueKey<String>('graph-add-mark')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('shell-overlay-sheet')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(195, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('graph-share')));
    await tester.pump();
    expect(find.text('Opening share sheet — graph'), findsOneWidget);
  });

  testWidgets('no attached probes shows the empty state', (tester) async {
    await pumpGraph(
      tester,
      before: () async {
        for (final jack in ProbeJack.values) {
          await repo.probeRole(jack, ProbeRole.unused);
        }
      },
    );

    expect(find.byKey(const ValueKey<String>('graph-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('graph-chart')), findsNothing);
  });
}
