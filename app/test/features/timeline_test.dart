/// N8 — the Timeline destination.
///
/// Covers the exit gate: the `running` scenario renders the brisket/ribs/
/// sausage schedule with stall and wrap where the data has them; adding an item
/// is reflected immediately; every derived time reads as an estimate. Also the
/// empty state, the `autoWrapReminder` gate, the per-cook toggles, the rail and
/// the two actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/shell/shell.dart';
import 'package:smoke_bridge/features/shell/shell_screen.dart';
import 'package:smoke_bridge/features/timeline/timeline.dart';

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
        timelineNowProvider.overrideWithValue(_t0),
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
            child: child,
          ),
        ),
      ),
    );
  }

  Future<void> pumpTimeline(
    WidgetTester tester, {
    String scenario = 'running',
    _Capture? capture,
    Future<void> Function()? before,
    Size size = const Size(390, 2000),
  }) async {
    await repo.selectScenario(scenario);
    if (before != null) {
      await before();
    }
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(const TimelinePage(), capture: capture));
    await tester.pumpAndSettle();
  }

  String textAt(WidgetTester tester, String key) {
    final text = tester.widget<Text>(find.byKey(ValueKey<String>(key)));
    return text.data ?? '';
  }

  group('running schedule (exit gate)', () {
    testWidgets('renders header, Gantt, milestones and the rail', (
      tester,
    ) async {
      await pumpTimeline(tester);

      expect(
        find.byKey(const ValueKey<String>('timeline-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-header')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-axis')),
        findsOneWidget,
      );
      expect(textAt(tester, 'timeline-item-count'), '3');

      // Three items: brisket (1), ribs (2), sausage (3).
      for (var jack = 1; jack <= 3; jack++) {
        expect(
          find.byKey(ValueKey<String>('timeline-row-$jack')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey<String>('timeline-now-$jack')),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const ValueKey<String>('timeline-row-4')),
        findsNothing,
      );

      // Stall is where the data has it: brisket only.
      expect(
        find.byKey(const ValueKey<String>('timeline-stall-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-stall-2')),
        findsNothing,
      );
      // Wrap is on brisket and ribs, not sausage.
      expect(
        find.byKey(const ValueKey<String>('timeline-wrap-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-wrap-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-wrap-3')),
        findsNothing,
      );

      expect(
        find.byKey(const ValueKey<String>('timeline-rail')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-rail-now')),
        findsOneWidget,
      );
      // The item names come from the catalog.
      expect(find.text('Texas Brisket'), findsOneWidget);
      expect(find.text('Spare Ribs'), findsOneWidget);
      expect(find.text('Sausages & Brats'), findsOneWidget);
    });

    testWidgets('has no ember primary action once scheduled (I14)', (
      tester,
    ) async {
      await pumpTimeline(tester);
      expect(find.byType(PrimaryAction), findsNothing);
    });

    testWidgets('every derived time reads as an estimate (N8.8)', (
      tester,
    ) async {
      await pumpTimeline(tester);
      expect(find.text('Expected times are estimates.'), findsOneWidget);
      expect(textAt(tester, 'timeline-upcoming-note'), contains('Estimates'));
      // The rail's predictions say so; actual marks do not.
      expect(find.textContaining('· expected'), findsWidgets);
    });

    testWidgets('upcoming shows the future nudges, not the past turn', (
      tester,
    ) async {
      await pumpTimeline(tester);
      expect(find.text('SPRITZ'), findsOneWidget);
      expect(find.text('WRAP IN BUTCHER PAPER'), findsOneWidget);
      // The sausage turn (20 min after it went on, ~35 min ago) is not upcoming.
      expect(find.text('TURN / ROTATE'), findsNothing);
    });
  });

  group('empty + degenerate states (N8.1/N8.12)', () {
    testWidgets('no cook and no session shows the one-action empty state', (
      tester,
    ) async {
      final capture = _Capture();
      await pumpTimeline(tester, scenario: 'idle', capture: capture);

      expect(
        find.byKey(const ValueKey<String>('timeline-empty')),
        findsOneWidget,
      );
      expect(find.text('Start a cook'), findsOneWidget);
      expect(find.byType(PrimaryAction), findsOneWidget);

      await tester.tap(find.text('Start a cook'));
      await tester.pumpAndSettle();
      expect(capture.overlays.single.overlay, DevOverlay.setup);
    });

    testWidgets('a pending session with no items is tolerated', (tester) async {
      await pumpTimeline(tester, scenario: 'existing');

      expect(
        find.byKey(const ValueKey<String>('timeline-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-gantt-empty')),
        findsOneWidget,
      );
      expect(textAt(tester, 'timeline-item-count'), '0');
      expect(textAt(tester, 'timeline-off-by'), '—');
      expect(
        find.byKey(const ValueKey<String>('timeline-upcoming-empty')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-rail-empty')),
        findsOneWidget,
      );
    });
  });

  group('adding an item (exit gate)', () {
    testWidgets('a new item appears immediately', (tester) async {
      await pumpTimeline(tester);
      expect(textAt(tester, 'timeline-item-count'), '3');

      await repo.addItem(presetId: 'pork_ribs', jack: ProbeJack.four);
      await tester.pumpAndSettle();

      expect(textAt(tester, 'timeline-item-count'), '4');
      expect(
        find.byKey(const ValueKey<String>('timeline-row-4')),
        findsOneWidget,
      );
    });
  });

  group('reminders (N8.9/N8.10)', () {
    testWidgets('autoWrapReminder off hides the nudges and disables toggles', (
      tester,
    ) async {
      await pumpTimeline(tester);
      expect(
        find.byKey(const ValueKey<String>('timeline-upcoming')),
        findsOneWidget,
      );

      await prefs.update((s) => s.copyWith(autoWrapReminder: false));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('timeline-reminders-off')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-upcoming-empty')),
        findsOneWidget,
      );
      final toggle = tester.widget<SmokeToggle>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('timeline-wrap-toggle-1')),
          matching: find.byType(SmokeToggle),
        ),
      );
      expect(toggle.onChanged, isNull);
    });

    testWidgets('the per-cook toggle removes the wrap nudge', (tester) async {
      await pumpTimeline(tester);
      expect(find.text('WRAP IN BUTCHER PAPER'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('timeline-wrap-toggle-1')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('WRAP IN BUTCHER PAPER'), findsNothing);
      expect(repo.current.cook.items.first.wrapEnabled, isFalse);
      // The schedule milestone is a fact of the cut, so it stays.
      expect(
        find.byKey(const ValueKey<String>('timeline-wrap-1')),
        findsOneWidget,
      );
    });

    testWidgets('a cut with no wrap shows no wrap toggle', (tester) async {
      await pumpTimeline(tester);
      expect(
        find.byKey(const ValueKey<String>('timeline-reminder-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-reminder-3')),
        findsNothing,
      );
    });
  });

  group('actions (N8.11)', () {
    testWidgets('Add something opens setup; Log event opens mark', (
      tester,
    ) async {
      final capture = _Capture();
      await pumpTimeline(tester, capture: capture);

      await tester.tap(find.byKey(const ValueKey<String>('timeline-add')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-log-event')),
      );
      await tester.pumpAndSettle();

      expect(capture.overlays.map((o) => o.overlay), <DevOverlay>[
        DevOverlay.setup,
        DevOverlay.mark,
      ]);
    });
  });
}
