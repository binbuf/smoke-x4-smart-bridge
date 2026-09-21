/// N2.31 — the dev panel widget.
///
/// The panel is release-excluded, so it is exercised here under the plain test
/// binding: it renders the prototype's scenario / screen / overlay / event
/// switches and drives the repository and preferences through
/// `DevPanelController`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/dev/dev_panel.dart';

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

  Future<void> pumpPanel(
    WidgetTester tester, {
    void Function(DevScreen)? onScreen,
    void Function(DevOverlay, Map<String, String>)? onOverlay,
  }) async {
    tester.view
      ..physicalSize = const Size(700, 2200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bridgeRepositoryProvider.overrideWithValue(repo),
          prefsProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          theme: SmokeTheme.dark,
          home: Scaffold(
            body: DevPanel(onScreen: onScreen, onOverlay: onOverlay),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders every switch group from the fixtures', (tester) async {
    await pumpPanel(tester);

    expect(find.text('Prototype controls'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('dev-scenario-idle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('dev-scenario-offline')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('dev-screen-timeline')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('dev-overlay-connect')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('dev-event-ble-connected')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('dev-units')), findsOneWidget);
    expect(find.text('Units: ° F'), findsOneWidget);
  });

  testWidgets('tapping a scenario switches the repository', (tester) async {
    await pumpPanel(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('dev-scenario-offline')),
    );
    await tester.pumpAndSettle();

    expect(repo.activeScenarioKey, 'offline');
  });

  testWidgets('tapping a screen and an overlay reports to the shell', (
    tester,
  ) async {
    DevScreen? seenScreen;
    DevOverlay? seenOverlay;
    await pumpPanel(
      tester,
      onScreen: (s) => seenScreen = s,
      onOverlay: (o, p) => seenOverlay = o,
    );

    await tester.tap(find.byKey(const ValueKey<String>('dev-screen-timeline')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('dev-overlay-connect')));
    await tester.pumpAndSettle();

    expect(seenScreen, DevScreen.timeline);
    expect(seenOverlay, DevOverlay.connect);
  });

  testWidgets('tapping a mock event mutates the snapshot', (tester) async {
    await pumpPanel(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('dev-event-alarm-pit-crash')),
    );
    await tester.pumpAndSettle();

    expect(repo.current.alarms.single.ruleId, 'pit_crash');
  });

  testWidgets('settings buttons drive units, theme and profile', (
    tester,
  ) async {
    await pumpPanel(tester);

    await tester.tap(find.byKey(const ValueKey<String>('dev-units')));
    await tester.pumpAndSettle();
    expect(prefs.current.units, TempUnit.celsius);

    await tester.tap(find.byKey(const ValueKey<String>('dev-theme')));
    await tester.pumpAndSettle();
    expect(prefs.current.themeMode, AppThemeMode.light);

    await tester.tap(find.byKey(const ValueKey<String>('dev-profile')));
    await tester.pumpAndSettle();
    expect(prefs.current.displayProfile, DisplayProfile.daylight);
  });
}
