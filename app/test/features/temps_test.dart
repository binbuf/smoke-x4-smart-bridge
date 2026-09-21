/// N6 — the Temps destination and the probe detail sheet.
///
/// Covers the exit gate: toggling a jack's role re-renders Live, Temps and the
/// summary strip consistently; a detached probe never renders a numeric
/// temperature anywhere; and I3/I4/I6/I12 plus the non-destructive role/target
/// edits hold.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/live/live.dart';
import 'package:smoke_bridge/features/shell/shell.dart';
import 'package:smoke_bridge/features/shell/shell_screen.dart';
import 'package:smoke_bridge/features/temps/temps.dart';

import '../support/load_fonts.dart';

const int _t0ms = 1700000000000;

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

  Future<void> pumpTemps(
    WidgetTester tester, {
    required String scenario,
    _Capture? capture,
    Future<void> Function()? before,
    Widget? child,
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
    await tester.pumpWidget(
      harness(child ?? const TempsPage(), capture: capture),
    );
    await tester.pumpAndSettle();
  }

  String textAt(WidgetTester tester, String key) {
    final text = tester.widget<Text>(find.byKey(ValueKey<String>(key)));
    return text.textSpan?.toPlainText() ?? text.data ?? '';
  }

  String metaAt(WidgetTester tester, String label, int jack) => textAt(
    tester,
    'temps-meta-${label.toLowerCase().replaceAll(' ', '-')}-$jack',
  );

  group('header (N6.1)', () {
    testWidgets('counts attached probes and states live/stale', (tester) async {
      await pumpTemps(tester, scenario: 'running');
      expect(
        textAt(tester, 'temps-attached-count'),
        '4 attached · updated live',
      );

      await pumpTemps(tester, scenario: 'idle');
      expect(
        textAt(tester, 'temps-attached-count'),
        '2 attached · updated live',
      );

      await pumpTemps(tester, scenario: 'offline');
      expect(
        textAt(tester, 'temps-attached-count'),
        '3 attached · updated stale',
      );
    });

    testWidgets('the °F/°C toggle re-renders and stores the unit', (
      tester,
    ) async {
      await pumpTemps(tester, scenario: 'running');
      expect(textAt(tester, 'temps-temp-1'), '164.2° F');

      await tester.tap(find.text('°C'));
      await tester.pumpAndSettle();

      expect(prefs.current.units, TempUnit.celsius);
      expect(textAt(tester, 'temps-temp-1'), '73.4° C');
    });
  });

  group('temp cards (N6.2–N6.4)', () {
    testWidgets('render jack, name, temperature, trend and freshness', (
      tester,
    ) async {
      await pumpTemps(tester, scenario: 'running');

      for (final jack in <int>[1, 2, 3, 4]) {
        expect(
          find.byKey(ValueKey<String>('temps-card-$jack')),
          findsOneWidget,
        );
      }
      expect(find.text('Texas Brisket'), findsOneWidget);
      expect(textAt(tester, 'temps-temp-1'), '164.2° F');
      expect(textAt(tester, 'temps-fresh-1'), 'Live');
      expect(find.text('6.2° F/hr'), findsOneWidget);
    });

    testWidgets('flags STALL, DONE and GRATE', (tester) async {
      await pumpTemps(tester, scenario: 'running');
      // Jack 1 is stalled; jack 4 is the grate.
      expect(find.text('STALL'), findsOneWidget);
      expect(find.text('GRATE'), findsOneWidget);
      expect(find.text('DONE'), findsNothing);

      await pumpTemps(tester, scenario: 'offline');
      // Offline jack 4 reads 251 °F against a 250 °F grate target.
      expect(find.text('DONE'), findsOneWidget);
    });

    testWidgets('the progress rule appears only when there is a target', (
      tester,
    ) async {
      await pumpTemps(tester, scenario: 'running');
      expect(
        find.byKey(const ValueKey<String>('temps-progress-1')),
        findsOneWidget,
      );

      await pumpTemps(tester, scenario: 'idle');
      // Idle jack 1 is attached but carries no target.
      expect(
        find.byKey(const ValueKey<String>('temps-progress-1')),
        findsNothing,
      );
    });

    testWidgets('the meta grid shows target/pull/ETA for food and the pit band '
        'for the grate', (tester) async {
      await pumpTemps(tester, scenario: 'running');

      expect(metaAt(tester, 'Target', 1), '201° F');
      expect(metaAt(tester, 'Pull at', 1), '193° F');
      expect(metaAt(tester, 'ETA', 1), 'Stalled');
      expect(metaAt(tester, 'High', 1), '164° F');
      expect(metaAt(tester, 'Avg', 1), '128° F');

      expect(metaAt(tester, 'Pit band', 4), '225–275°');
      expect(metaAt(tester, 'Status', 4), 'In band');
    });

    testWidgets('a frozen reading removes the ETA (I4)', (tester) async {
      await pumpTemps(tester, scenario: 'offline');
      expect(metaAt(tester, 'ETA', 1), '—');
      // The card says "Stale" for a frozen reading and shows the flat chip.
      expect(textAt(tester, 'temps-fresh-1'), 'Stale');
      expect(find.text('stale'), findsWidgets);
    });
  });

  group('detached section (N6.5, I3)', () {
    testWidgets('lists unplugged jacks and never renders a number', (
      tester,
    ) async {
      await pumpTemps(tester, scenario: 'idle');

      expect(find.text('NOT ATTACHED'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('temps-detached-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('temps-detached-3')),
        findsOneWidget,
      );
      expect(find.text('Unplugged — absent, never 0°'), findsNWidgets(2));
      expect(find.text('Set role'), findsNWidgets(2));
      // No card and no numeric temperature for the absent jacks.
      expect(find.byKey(const ValueKey<String>('temps-card-2')), findsNothing);
      expect(find.byKey(const ValueKey<String>('temps-temp-2')), findsNothing);
    });

    testWidgets('Set role opens the probe sheet for that jack', (tester) async {
      final capture = _Capture();
      await pumpTemps(tester, scenario: 'idle', capture: capture);

      await tester.tap(
        find.byKey(const ValueKey<String>('temps-detached-role-2')),
      );
      await tester.pump();
      expect(capture.overlays.last.overlay, DevOverlay.probe);
      expect(capture.overlays.last.props['jack'], '2');
    });
  });

  group('empty state (N6.6, I6)', () {
    testWidgets('nothing attached offers one action: View graph', (
      tester,
    ) async {
      final capture = _Capture();
      await pumpTemps(
        tester,
        scenario: 'running',
        capture: capture,
        before: () async {
          for (final jack in ProbeJack.values) {
            await repo.probeRole(jack, ProbeRole.unused);
          }
        },
      );

      expect(find.text('No probes attached'), findsOneWidget);
      expect(find.byType(PrimaryAction), findsOneWidget);

      await tester.tap(find.text('View graph'));
      await tester.pump();
      expect(capture.screens, contains(ShellScreen.graph));
    });
  });

  group('probe sheet (N6.7–N6.12)', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      required String scenario,
      required ProbeJack jack,
      _Capture? capture,
      VoidCallback? onDone,
    }) async {
      await repo.selectScenario(scenario);
      tester.view
        ..physicalSize = const Size(390, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        harness(
          SingleChildScrollView(
            child: ProbeSheetBody(jack: jack, onDone: onDone ?? () {}),
          ),
          capture: capture,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('header, hero, sparkline, phase and stats', (tester) async {
      await pumpSheet(tester, scenario: 'running', jack: ProbeJack.one);

      expect(textAt(tester, 'probe-sheet-name'), 'Texas Brisket');
      expect(textAt(tester, 'probe-sheet-sub'), 'Live · jack 1');
      expect(textAt(tester, 'probe-sheet-temp'), '164.2° F');
      expect(
        find.byKey(const ValueKey<String>('probe-sheet-spark')),
        findsOneWidget,
      );
      final phase = tester.widget<PhaseTrack>(
        find.byKey(const ValueKey<String>('probe-sheet-phase')),
      );
      expect(phase.currentIndex, 0);
      expect(phase.phases, <String>[
        'Approaching',
        'Pull now',
        'Resting',
        'Ready',
      ]);
      expect(find.text('164° F'), findsOneWidget);
      expect(find.text('128° F'), findsOneWidget);
      expect(find.text('58° F'), findsOneWidget);
    });

    testWidgets('role editor reassigns any jack', (tester) async {
      await pumpSheet(tester, scenario: 'running', jack: ProbeJack.four);
      expect(find.text('Grate (pit)'), findsOneWidget);

      await tester.tap(find.text('Unused'));
      await tester.pumpAndSettle();

      final probe = repo.current.probes.firstWhere(
        (p) => p.jack == ProbeJack.four,
      );
      expect(probe.role, ProbeRole.unused);
      expect(probe.attached, isFalse);
      expect(probe.tempF10, isNull);
    });

    testWidgets('the target editor re-runs the pull through the safety gate', (
      tester,
    ) async {
      await pumpSheet(tester, scenario: 'running', jack: ProbeJack.one);

      expect(find.textContaining('Pull at 193° F'), findsOneWidget);
      await tester.tap(find.text('Sliceable · 195° F'));
      await tester.pumpAndSettle();

      final probe = repo.current.probes.firstWhere(
        (p) => p.jack == ProbeJack.one,
      );
      expect(probe.targetF10, 1950);
      // Whole-muscle brisket has no floor: pull is target − carryover (8 °F).
      expect(probe.pullF10, 1870);
    });

    testWidgets('an unassignable probe offers Set a target', (tester) async {
      final capture = _Capture();
      await pumpSheet(
        tester,
        scenario: 'idle',
        jack: ProbeJack.one,
        capture: capture,
      );

      expect(
        find.byKey(const ValueKey<String>('probe-set-target')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('probe-set-target')));
      await tester.pump();
      expect(capture.overlays.last.overlay, DevOverlay.setup);
      expect(capture.overlays.last.props['jack'], '1');
      expect(capture.overlays.last.props['context'], 'edit');
    });

    testWidgets('Mark pulled logs a mark, toasts and closes', (tester) async {
      final capture = _Capture();
      var done = false;
      await pumpSheet(
        tester,
        scenario: 'running',
        jack: ProbeJack.one,
        capture: capture,
        onDone: () => done = true,
      );

      await tester.tap(find.text('Mark pulled'));
      await tester.pumpAndSettle();

      expect(repo.current.marks.last.text, 'Pulled probe 1');
      expect(capture.toasts, contains('Pulled — rest timer started'));
      expect(done, isTrue);
    });

    testWidgets('Test alarm and Share this probe toast', (tester) async {
      final capture = _Capture();
      await pumpSheet(
        tester,
        scenario: 'running',
        jack: ProbeJack.one,
        capture: capture,
      );

      await tester.tap(find.text('Test alarm'));
      await tester.pump();
      expect(capture.toasts.last, 'Test alarm sent to your phone');

      await tester.tap(find.text('Share this probe'));
      await tester.pump();
      expect(capture.toasts.last, 'Opening share sheet — probe');
    });

    testWidgets('an unplugged probe never shows a numeric hero (I3)', (
      tester,
    ) async {
      await pumpSheet(tester, scenario: 'idle', jack: ProbeJack.two);

      expect(textAt(tester, 'probe-sheet-temp'), '—');
      expect(textAt(tester, 'probe-sheet-sub'), 'Unplugged');
      expect(
        find.byKey(const ValueKey<String>('probe-sheet-phase')),
        findsNothing,
      );
    });
  });

  group('exit gate: role changes agree across surfaces', () {
    testWidgets('re-roling a jack updates Live, Temps and the summary', (
      tester,
    ) async {
      await pumpTemps(
        tester,
        scenario: 'running',
        child: Column(
          children: <Widget>[
            Expanded(child: LivePage()),
            Expanded(child: TempsPage()),
          ],
        ),
      );

      // Before: jack 4 is the grate everywhere.
      expect(
        find.byKey(const ValueKey<String>('temps-card-4')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('live-summary-grate')),
          matching: find.text('Pit band 225–275°'),
        ),
        findsOneWidget,
      );

      // Re-role jack 4 to unused (the probe sheet's role editor calls this).
      await repo.probeRole(ProbeJack.four, ProbeRole.unused);
      await tester.pumpAndSettle();

      // Temps: the card becomes a detached row.
      expect(find.byKey(const ValueKey<String>('temps-card-4')), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('temps-detached-4')),
        findsOneWidget,
      );
      // Live: an unused jack is absent, so the tile says Unplugged and shows
      // no number (I3).
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('live-probe-sub-4')),
            )
            .data,
        'Unplugged',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('live-probe-temp-4')),
            )
            .textSpan
            ?.toPlainText(),
        '—',
      );
      // Summary: there is no grate any more.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('live-summary-grate')),
          matching: find.text('No pit probe'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('re-roling jack 1 to the pit makes it the summary grate', (
      tester,
    ) async {
      await pumpTemps(
        tester,
        scenario: 'idle',
        child: Column(
          children: <Widget>[
            Expanded(child: LivePage()),
            Expanded(child: TempsPage()),
          ],
        ),
      );

      await repo.probeRole(ProbeJack.one, ProbeRole.pit);
      await repo.probeRole(ProbeJack.four, ProbeRole.unused);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('live-summary-grate')),
          matching: find.text('Pit band 225–275°'),
        ),
        findsOneWidget,
      );
    });
  });
}
