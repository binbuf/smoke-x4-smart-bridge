/// N9 — the catalog/setup flow's widget surface.
///
/// Covers the exit gate end to end: the three start modes, catalog search, the
/// style/doneness/summary/jack flow, the long-item guard, the custom-food form
/// and the overlay wiring.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dev_panel.dart';
import 'package:smoke_bridge/data/model/app_settings.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/data/repository/mock_bridge_repository.dart';
import 'package:smoke_bridge/data/repository/prefs_repository.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/setup/setup.dart';
import 'package:smoke_bridge/features/shell/overlay.dart';
import 'package:smoke_bridge/features/shell/shell.dart';
import 'package:smoke_bridge/features/shell/shell_screen.dart';

import '../support/load_fonts.dart';

const int _t0ms = 1700000000000;
final DateTime _t0 = DateTime.fromMillisecondsSinceEpoch(_t0ms);

class _Capture {
  final overlays = <({DevOverlay overlay, Map<String, String> props})>[];
  final screens = <ShellScreen>[];
  final toasts = <String>[];
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

  Widget harness(Widget child, {_Capture? capture}) {
    return ProviderScope(
      overrides: [
        bridgeRepositoryProvider.overrideWithValue(repo),
        prefsProvider.overrideWithValue(prefs),
        shellClockProvider.overrideWithValue(_t0),
      ],
      child: MaterialApp(
        theme: SmokeThemeData.dark(),
        home: Scaffold(
          body: ShellScope(
            openOverlay: (overlay, [props = const {}]) =>
                capture?.overlays.add((overlay: overlay, props: props)),
            closeOverlay: () {},
            showToast: (message) => capture?.toasts.add(message),
            toggleFullGraph: () {},
            openScreen: (screen) => capture?.screens.add(screen),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
  }

  Future<void> pumpSetup(
    WidgetTester tester, {
    String scenario = 'idle',
    _Capture? capture,
    bool addContext = false,
    ProbeJack? initialJack,
    String? initialFoodId,
  }) async {
    await repo.selectScenario(scenario);
    tester.view
      ..physicalSize = const Size(390, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(
        SetupSheetBody(
          onDone: () {},
          addContext: addContext,
          initialJack: initialJack,
          initialFoodId: initialFoodId,
        ),
        capture: capture,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  String textAt(WidgetTester tester, String key) {
    final text = tester.widget<Text>(find.byKey(ValueKey<String>(key)));
    return text.data ?? '';
  }

  String factValue(WidgetTester tester, String key) {
    final texts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(ValueKey<String>(key)),
            matching: find.byType(Text),
          ),
        )
        .toList();
    return texts.isEmpty ? '' : texts.last.data ?? '';
  }

  group('new mode (N9.1/N9.4–N9.12)', () {
    testWidgets('renders the segmented switch and the Beef catalog', (
      tester,
    ) async {
      await pumpSetup(tester);
      expect(find.byKey(const ValueKey<String>('setup-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('setup-modes')), findsOneWidget);
      expect(textAt(tester, 'setup-catalog-count'), contains('foods in Beef'));
      expect(
        find.byKey(const ValueKey<String>('setup-food-beef_brisket')),
        findsOneWidget,
      );
    });

    testWidgets('search finds by name, count updates and clear restores', (
      tester,
    ) async {
      await pumpSetup(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('setup-catalog-search')),
        'collagen',
      );
      await tester.pumpAndSettle();
      // Blurb match: brisket.
      expect(
        find.byKey(const ValueKey<String>('setup-food-beef_brisket')),
        findsOneWidget,
      );
      expect(textAt(tester, 'setup-catalog-count'), contains('result'));

      await tapKey(tester, 'setup-catalog-clear');
      expect(textAt(tester, 'setup-catalog-count'), contains('foods in Beef'));
    });

    testWidgets('picking a cut reveals styles, doneness and the summary', (
      tester,
    ) async {
      await pumpSetup(tester);
      await tapKey(tester, 'setup-food-beef_brisket');
      expect(
        find.byKey(const ValueKey<String>('setup-styles')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('setup-style-central_texas')),
        findsOneWidget,
      );
      expect(factValue(tester, 'setup-summary-target'), '201° F');
      expect(factValue(tester, 'setup-summary-rest'), '60 min');
    });

    testWidgets('red meat opens on medium rare (N9.8)', (tester) async {
      await pumpSetup(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('setup-catalog-search')),
        'ribeye',
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'setup-food-beef_ribeye');
      // Medium rare final: 135 °F, pull 133 °F on a thin cut.
      expect(factValue(tester, 'setup-summary-target'), '135° F');
    });

    testWidgets('busy jacks are disabled and say (in use) (N9.10)', (
      tester,
    ) async {
      await pumpSetup(tester, scenario: 'running');
      await tester.enterText(
        find.byKey(const ValueKey<String>('setup-catalog-search')),
        'brisket',
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'setup-food-beef_brisket');
      // Running has ribs on jack 2 and sausage on jack 3.
      expect(find.text('Jack 2 (in use)'), findsOneWidget);
      expect(find.text('Jack 4 · grate'), findsOneWidget);
    });

    testWidgets('start creates the cook, toasts and goes Live (N9.13)', (
      tester,
    ) async {
      final capture = _Capture();
      await pumpSetup(tester, capture: capture);
      await tester.enterText(
        find.byKey(const ValueKey<String>('setup-catalog-search')),
        'brisket',
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'setup-food-beef_brisket');
      await tapKey(tester, 'setup-start');

      final snapshot = await repo.snapshot().first;
      expect(snapshot.cook.active, isTrue);
      expect(snapshot.cook.items.single.presetId, 'beef_brisket');
      final probe = snapshot.probes.firstWhere((p) => p.jack == ProbeJack.one);
      expect(probe.targetF10, 2010);
      expect(capture.toasts.last, 'Texas Brisket added to the cook');
      expect(capture.screens.last, ShellScreen.live);
    });

    testWidgets('a below-floor custom target is refused (I12)', (tester) async {
      const custom = CustomFood(
        id: 'custom_ground',
        name: 'Mystery Patty',
        category: 'Beef',
        hazard: HazardClass.ground,
        targetF10: 1350,
      );
      await prefs.update(
        (s) => s.copyWith(customCatalog: const <CustomFood>[custom]),
      );
      await pumpSetup(tester, initialFoodId: 'custom_ground');
      expect(
        find.byKey(const ValueKey<String>('setup-safety-refusal')),
        findsOneWidget,
      );
    });
  });

  group('watch mode (N9.2)', () {
    testWidgets('watch creates no cook and goes Live', (tester) async {
      final capture = _Capture();
      await pumpSetup(tester, capture: capture);
      await tester.tap(find.text('Just watch'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('setup-watch-notice')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('setup-start')));
      await tester.pumpAndSettle();
      final snapshot = await repo.snapshot().first;
      expect(snapshot.cook.active, isFalse);
      expect(capture.toasts.last, 'Watching live — no cook set');
      expect(capture.screens.last, ShellScreen.live);
      expect(capture.overlays, isEmpty);
    });
  });

  group('existing mode (N9.3/N9.15)', () {
    testWidgets('shows the session card and pulls its samples', (tester) async {
      final capture = _Capture();
      await pumpSetup(tester, scenario: 'existing', capture: capture);
      await tester.tap(find.text('Already started'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('setup-existing-session')),
        findsOneWidget,
      );
      expect(find.text('SMK-4471'), findsOneWidget);
      expect(find.text('253'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('setup-catalog-search')),
        'brisket',
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'setup-food-beef_brisket');
      await tapKey(tester, 'setup-start');

      final snapshot = await repo.snapshot().first;
      expect(snapshot.pendingSession, isNull);
      expect(snapshot.cook.startedAtMs, _t0ms - (2 * 3600 + 5 * 60) * 1000);
      expect(snapshot.notice, contains('253'));
      expect(capture.toasts.last, contains('253'));
    });
  });

  group('long-item guard (N9.14)', () {
    testWidgets('a long add asks first and adds on confirm', (tester) async {
      await pumpSetup(tester, scenario: 'running');
      await tester.enterText(
        find.byKey(const ValueKey<String>('setup-catalog-search')),
        'brisket',
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'setup-food-beef_brisket');
      // Assign to the free grate jack so the add is not a re-assign.
      await tapKey(tester, 'setup-jack-4');
      await tapKey(tester, 'setup-start');

      expect(find.text('This will run long'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('shell-overlay-confirm')),
      );
      await tester.pumpAndSettle();

      final snapshot = await repo.snapshot().first;
      expect(
        snapshot.cook.items.where((i) => i.jack == ProbeJack.four),
        hasLength(1),
      );
    });
  });

  group('edit context (N9.19) and initial jack', () {
    testWidgets('edit context labels the primary Add to cook', (tester) async {
      await pumpSetup(tester, addContext: true);
      expect(find.text('Add to cook'), findsOneWidget);
    });

    testWidgets('an initial jack is preselected', (tester) async {
      await pumpSetup(tester, initialJack: ProbeJack.three);
      // The jack chip exists; picking a food then starting uses jack 3.
      await tester.enterText(
        find.byKey(const ValueKey<String>('setup-catalog-search')),
        'brisket',
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'setup-food-beef_brisket');
      await tapKey(tester, 'setup-start');
      final snapshot = await repo.snapshot().first;
      expect(snapshot.cook.items.single.jack, ProbeJack.three);
    });

    testWidgets('Custom food opens the custom-food overlay', (tester) async {
      final capture = _Capture();
      await pumpSetup(tester, capture: capture);
      await tapKey(tester, 'setup-custom-food');
      expect(capture.overlays.single.overlay, DevOverlay.customFood);
    });
  });

  group('custom-food form (N9.17/N9.18)', () {
    Future<void> pumpForm(WidgetTester tester, _Capture capture) async {
      tester.view
        ..physicalSize = const Size(390, 1800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        harness(CustomFoodSheetBody(onDone: () {}), capture: capture),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('saves a safe custom food with its own timeline', (
      tester,
    ) async {
      final capture = _Capture();
      await pumpForm(tester, capture);
      await tester.enterText(
        find.byKey(const ValueKey<String>('custom-food-name')),
        'Smoked Lamb Ribs',
      );
      await tapKey(tester, 'custom-food-save');
      await tester.pumpAndSettle();

      expect(prefs.current.customCatalog, hasLength(1));
      final saved = prefs.current.customCatalog.single;
      expect(saved.name, 'Smoked Lamb Ribs');
      expect(saved.timeline, isNotNull);
      expect(capture.toasts.last, 'Added Smoked Lamb Ribs to the catalog');
      expect(capture.overlays.single.overlay, DevOverlay.setup);
      expect(capture.overlays.single.props['food'], saved.id);
    });

    testWidgets('an unsafe target is refused and not stored', (tester) async {
      final capture = _Capture();
      await pumpForm(tester, capture);
      await tester.enterText(
        find.byKey(const ValueKey<String>('custom-food-name')),
        'Mystery Patty',
      );
      await tester.tap(find.text('Ground meat'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('custom-food-target')),
        '130',
      );
      await tapKey(tester, 'custom-food-save');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('custom-food-error')),
        findsOneWidget,
      );
      expect(prefs.current.customCatalog, isEmpty);
    });

    testWidgets('a blank name is refused', (tester) async {
      final capture = _Capture();
      await pumpForm(tester, capture);
      await tapKey(tester, 'custom-food-save');
      expect(textAt(tester, 'custom-food-error'), 'Give it a name');
      expect(prefs.current.customCatalog, isEmpty);
    });
  });

  testWidgets('the overlay resolver wires the real setup body', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bridgeRepositoryProvider.overrideWithValue(repo),
          prefsProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          theme: SmokeThemeData.dark(),
          home: Scaffold(
            body: ShellOverlayHost(
              request: const OverlayRequest(DevOverlay.setup),
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('setup-sheet')), findsOneWidget);
  });
}
