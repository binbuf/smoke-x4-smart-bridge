/// N16.7 — the empty / problem / capability walkthrough.
///
/// I5 (no dead controls), I6 (no state without a next step) and I13 (copy over
/// error) say every "nothing here" surface offers a real way forward, and a
/// missing capability is a notice rather than a broken control. This walks the
/// reachable states on the real destinations and checks the action is present
/// and wired.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/graph/graph.dart';
import 'package:smoke_bridge/features/history/history.dart';
import 'package:smoke_bridge/features/live/live.dart';
import 'package:smoke_bridge/features/onboarding/onboarding.dart';
import 'package:smoke_bridge/features/shell/shell.dart';
import 'package:smoke_bridge/features/shell/shell_screen.dart';
import 'package:smoke_bridge/features/temps/temps.dart';
import 'package:smoke_bridge/features/timeline/timeline.dart';

import '../support/load_fonts.dart';

const int _t0ms = 1700000000000;

class _Capture {
  final overlays = <DevOverlay>[];
  final screens = <ShellScreen>[];
}

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

  Future<_Capture> pump(
    WidgetTester tester,
    Widget child, {
    bool skipped = false,
  }) async {
    final capture = _Capture();
    tester.view
      ..physicalSize = const Size(390, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bridgeRepositoryProvider.overrideWithValue(repo),
          prefsProvider.overrideWithValue(prefs),
          if (skipped) onboardingSkippedProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: SmokeThemeData.dark(),
          home: Scaffold(
            body: ShellScope(
              openOverlay: (overlay, [props = const {}]) =>
                  capture.overlays.add(overlay),
              closeOverlay: () {},
              showToast: (_) {},
              toggleFullGraph: () {},
              openScreen: capture.screens.add,
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return capture;
  }

  testWidgets('Timeline with no cook offers "Start a cook" (I6)', (
    tester,
  ) async {
    await repo.selectScenario('idle');
    final capture = await pump(tester, const TimelinePage());

    expect(
      find.byKey(const ValueKey<String>('timeline-empty')),
      findsOneWidget,
    );
    await tester.tap(find.text('Start a cook'));
    await tester.pumpAndSettle();
    expect(capture.overlays, contains(DevOverlay.setup));
  });

  testWidgets('History with no cooks offers "Start a cook" (I6)', (
    tester,
  ) async {
    for (final entry in repo.history) {
      await repo.deleteCook(entry.id);
    }
    final capture = await pump(tester, const HistoryPage());

    expect(find.byKey(const ValueKey<String>('history-empty')), findsOneWidget);
    await tester.tap(find.text('Start a cook'));
    await tester.pumpAndSettle();
    expect(capture.overlays, contains(DevOverlay.setup));
  });

  testWidgets('a missing cook is a named problem with a way back (I6/I15)', (
    tester,
  ) async {
    final capture = await pump(tester, const CookDetailPage(id: 'nope'));

    expect(
      find.byKey(const ValueKey<String>('cook-detail-missing')),
      findsOneWidget,
    );
    await tester.tap(find.text('Back to history'));
    await tester.pumpAndSettle();
    expect(capture.screens, contains(ShellScreen.history));
  });

  testWidgets('a skipped onboarding offers "Set up your bridge" (I6)', (
    tester,
  ) async {
    final capture = await pump(tester, const LivePage(), skipped: true);

    expect(
      find.byKey(const ValueKey<String>('live-connect-bridge')),
      findsOneWidget,
    );
    await tester.tap(find.text('Set up your bridge'));
    await tester.pumpAndSettle();
    expect(capture.overlays, contains(DevOverlay.onboarding));
  });

  testWidgets('Temps and Graph with every jack unused offer a way forward', (
    tester,
  ) async {
    await repo.selectScenario('running');
    for (final jack in ProbeJack.values) {
      await repo.probeRole(jack, ProbeRole.unused);
    }

    final temps = await pump(tester, const TempsPage());
    expect(find.byKey(const ValueKey<String>('temps-empty')), findsOneWidget);
    await tester.tap(find.text('View graph'));
    await tester.pumpAndSettle();
    expect(temps.screens, contains(ShellScreen.graph));

    final graph = await pump(tester, const GraphPage());
    expect(find.byKey(const ValueKey<String>('graph-empty')), findsOneWidget);
    await tester.tap(find.text('View temps'));
    await tester.pumpAndSettle();
    expect(graph.screens, contains(ShellScreen.temps));
  });

  testWidgets('a capability notice is copy, not a disabled control (I5/I13)', (
    tester,
  ) async {
    await repo.selectScenario('offline');
    await pump(tester, const HistoryPage());

    expect(
      find.byKey(const ValueKey<String>('history-notice')),
      findsOneWidget,
    );
    // The notice is informational: it carries no button at all.
    final notice = find.byKey(const ValueKey<String>('history-notice'));
    expect(
      find.descendant(of: notice, matching: find.byType(ButtonStyleButton)),
      findsNothing,
    );
  });
}
