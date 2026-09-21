/// N4.3/N4.7/N4.10 — the assembled shell through the real go_router.
///
/// Boot deep links, bottom-nav navigation, overlay opening/dismissal, the
/// fullscreen graph host, the toast and the dev panel are all exercised here
/// against `SmokeApp` + a fresh router.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/router.dart';
import 'package:smoke_bridge/app/smoke_app.dart';
import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/features/shell/shell.dart';

import '../support/load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  late MockBridgeRepository repo;
  late MockPrefsRepository prefs;

  setUp(() {
    repo = MockBridgeRepository(nowMs: 1700000000000, initialScenario: 'idle');
    prefs = MockPrefsRepository();
  });

  tearDown(() async {
    await repo.dispose();
    await prefs.dispose();
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    DevDeepLink? link,
    Size size = const Size(390, 844),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bridgeRepositoryProvider.overrideWithValue(repo),
          prefsProvider.overrideWithValue(prefs),
          shellPulseEnabledProvider.overrideWithValue(false),
          shellClockProvider.overrideWithValue(DateTime(2026, 9, 21, 9, 41)),
          if (link != null) initialDevDeepLinkProvider.overrideWithValue(link),
        ],
        child: SmokeApp(router: createAppRouter()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('boots to Live inside the chrome', (tester) async {
    await pumpApp(tester);

    expect(find.byKey(const ValueKey<String>('live-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('shell-transport-chip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('shell-nav-settings')),
      findsOneWidget,
    );
  });

  testWidgets('a deep link opens both destination and named overlay', (
    tester,
  ) async {
    await pumpApp(
      tester,
      link: DevDeepLink.parse('?screen=graph&overlay=probe&jack=3'),
    );

    expect(find.byKey(const ValueKey<String>('graph-page')), findsOneWidget);
    // The sheet title and the probe sheet's own header both name the jack.
    expect(find.text('Probe 3'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('probe-sheet-body')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('shell-overlay-sheet')),
      findsOneWidget,
    );
  });

  testWidgets('bottom nav changes destination', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey<String>('shell-nav-temps')));
    await tester.pumpAndSettle();

    // N6 replaced the Temps placeholder with the real per-probe screen.
    expect(find.byKey(const ValueKey<String>('temps-page')), findsOneWidget);
    expect(find.text('Temperatures'), findsWidgets);
    final title = tester.widget<Text>(
      find.byKey(const ValueKey<String>('shell-appbar-title')),
    );
    expect(title.data, 'Temperatures');
  });

  testWidgets('alerts bell opens the alarms overlay; scrim dismisses', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey<String>('shell-alerts-bell')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('shell-overlay-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('shell-overlay-title')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('shell-overlay-sheet')),
      findsNothing,
    );
  });

  testWidgets('preserves per-overlay body scroll across close and reopen', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('shell-transport-chip')),
    );
    await tester.pumpAndSettle();

    Finder sheetScrollable() => find.descendant(
      of: find.byKey(const ValueKey<String>('shell-overlay-sheet')),
      matching: find.byType(Scrollable),
    );

    await tester.drag(
      find.byKey(const ValueKey<String>('shell-overlay-copy')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    final offset = tester
        .state<ScrollableState>(sheetScrollable())
        .position
        .pixels;
    expect(offset, greaterThan(0));

    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('shell-transport-chip')),
    );
    await tester.pumpAndSettle();
    final reopened = tester
        .state<ScrollableState>(sheetScrollable())
        .position
        .pixels;
    expect(reopened, offset);
  });

  testWidgets('the fullscreen graph mounts above and dismisses', (
    tester,
  ) async {
    await pumpApp(tester);

    // Fullscreen is raised from the Graph destination's own control (N7.11).
    await tester.tap(find.byKey(const ValueKey<String>('shell-nav-graph')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('graph-fullscreen')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('shell-graph-host')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('shell-graph-host')),
      findsNothing,
    );
  });

  testWidgets('a destination can raise a toast', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey<String>('shell-nav-timeline')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('destination-toast')));
    await tester.pump();
    expect(find.text('Hello from Timeline'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Hello from Timeline'), findsNothing);
  });

  testWidgets('the dev panel drives screen and overlay', (tester) async {
    await pumpApp(tester, size: const Size(1000, 1400));

    expect(find.text('Prototype controls'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('dev-screen-timeline')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('destination-timeline')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('dev-overlay-connect')));
    await tester.pumpAndSettle();
    final overlayTitle = tester.widget<Text>(
      find.byKey(const ValueKey<String>('shell-overlay-title')),
    );
    expect(overlayTitle.data, 'Connection');
  });
}
