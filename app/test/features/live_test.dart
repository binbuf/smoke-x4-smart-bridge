/// N5 — the Live screen.
///
/// Covers the exit gate: `running`, `idle`, `existing` and `offline` render;
/// detached/stale probes remove derived values; no tile shows `0` for an absent
/// probe; pausing the stopwatch does not stop recording (I2/§7.3); and at most
/// one ember primary action is on screen (I14).
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

import '../support/load_fonts.dart';

const int _t0ms = 1700000000000;
final DateTime _t0 = DateTime.fromMillisecondsSinceEpoch(_t0ms);

/// A mutable clock the stopwatch reads, so a test can advance time.
class _ClockNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => _t0;

  void set(DateTime value) => state = value;
}

final _clockProvider = NotifierProvider<_ClockNotifier, DateTime>(
  _ClockNotifier.new,
);

class _Capture {
  final overlays = <({DevOverlay overlay, Map<String, String> props})>[];
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

  Widget harness(Widget child, {_Capture? capture, bool mutableClock = false}) {
    return ProviderScope(
      overrides: [
        bridgeRepositoryProvider.overrideWithValue(repo),
        prefsProvider.overrideWithValue(prefs),
        if (mutableClock)
          liveNowProvider.overrideWith((ref) => ref.watch(_clockProvider))
        else
          liveNowProvider.overrideWithValue(_t0),
      ],
      child: MaterialApp(
        theme: SmokeThemeData.dark(),
        home: Scaffold(
          body: ShellScope(
            openOverlay: (overlay, [props = const {}]) =>
                capture?.overlays.add((overlay: overlay, props: props)),
            closeOverlay: () {},
            showToast: (_) {},
            toggleFullGraph: () {},
            openScreen: (screen) => capture?.screens.add(screen),
            child: child,
          ),
        ),
      ),
    );
  }

  Future<void> pumpLive(
    WidgetTester tester, {
    required String scenario,
    _Capture? capture,
    bool mutableClock = false,
  }) async {
    await repo.selectScenario(scenario);
    tester.view
      ..physicalSize = const Size(390, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(const LivePage(), capture: capture, mutableClock: mutableClock),
    );
    await tester.pumpAndSettle();
  }

  String tileTemp(WidgetTester tester, int jack) {
    final text = tester.widget<Text>(
      find.byKey(ValueKey<String>('live-probe-temp-$jack')),
    );
    return text.textSpan?.toPlainText() ?? text.data ?? '';
  }

  group('running scenario', () {
    testWidgets('renders the cook header, stopwatch, rail and summary', (
      tester,
    ) async {
      await pumpLive(tester, scenario: 'running');

      expect(
        find.byKey(const ValueKey<String>('live-cook-header')),
        findsOneWidget,
      );
      expect(find.text('Sunday Brisket & Ribs'), findsOneWidget);
      expect(
        find.text('Recording on the bridge — safe even if this phone drops'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('live-stopwatch-time')),
            )
            .data,
        '04:12:00',
      );
      final startedAt = DateTime.fromMillisecondsSinceEpoch(
        _t0ms - (4 * 3600000 + 12 * 60000),
      );
      expect(find.text('Started ${fmtClock(startedAt)}'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('live-probe-rail')),
        findsOneWidget,
      );
      for (final jack in <int>[1, 2, 3, 4]) {
        expect(
          find.byKey(ValueKey<String>('live-probe-$jack')),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const ValueKey<String>('live-summary')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('live-mini-graph')),
        findsOneWidget,
      );
      expect(find.text('Mark'), findsOneWidget);
      expect(find.text('Add food'), findsOneWidget);
      // A running cook owns no ember primary (I14).
      expect(find.byType(PrimaryAction), findsNothing);
    });

    testWidgets('alarm strips sort by severity and acknowledge inline', (
      tester,
    ) async {
      await pumpLive(tester, scenario: 'running');

      expect(find.text('2 active alerts'), findsOneWidget);
      expect(find.text('Acknowledge all'), findsOneWidget);
      final pit = tester.getTopLeft(
        find.byKey(const ValueKey<String>('live-alarm-pit_crash')),
      );
      final eta = tester.getTopLeft(
        find.byKey(const ValueKey<String>('live-alarm-eta_soon')),
      );
      expect(pit.dy, lessThan(eta.dy));
      expect(find.text('Device'), findsOneWidget);
      expect(find.text('Insight'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('live-alarm-pit_crash')),
          matching: find.byIcon(Icons.check),
        ),
      );
      await tester.pump();
      expect(
        repo.current.alarms.firstWhere((a) => a.id == 'pit_crash').acked,
        isTrue,
      );
      expect(
        repo.current.alarms.firstWhere((a) => a.id == 'eta_soon').acked,
        isFalse,
      );

      // A fresh set of two alarms shows the bulk action.
      await repo.selectScenario('running');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('live-alarm-ack-all')),
      );
      await tester.pump();
      expect(repo.current.alarms.every((a) => a.acked), isTrue);
    });

    testWidgets('quick actions request the mark and setup overlays', (
      tester,
    ) async {
      final capture = _Capture();
      await pumpLive(tester, scenario: 'running', capture: capture);

      await tester.tap(find.text('Mark'));
      await tester.pump();
      expect(capture.overlays.last.overlay, DevOverlay.mark);

      await tester.tap(find.text('Add food'));
      await tester.pump();
      expect(capture.overlays.last.overlay, DevOverlay.setup);
    });

    testWidgets('cook settings opens setup in edit context', (tester) async {
      final capture = _Capture();
      await pumpLive(tester, scenario: 'running', capture: capture);

      await tester.tap(
        find.byKey(const ValueKey<String>('live-cook-settings')),
      );
      await tester.pump();
      expect(capture.overlays.last.overlay, DevOverlay.setup);
      expect(capture.overlays.last.props['context'], 'edit');
    });

    testWidgets('a probe tile opens the probe sheet with its jack', (
      tester,
    ) async {
      final capture = _Capture();
      await pumpLive(tester, scenario: 'running', capture: capture);

      await tester.tap(find.byKey(const ValueKey<String>('live-probe-2')));
      await tester.pump();
      expect(capture.overlays.last.overlay, DevOverlay.probe);
      expect(capture.overlays.last.props['jack'], '2');
    });

    testWidgets('the mini graph opens the Graph destination', (tester) async {
      final capture = _Capture();
      await pumpLive(tester, scenario: 'running', capture: capture);

      await tester.tap(find.byKey(const ValueKey<String>('live-mini-graph')));
      await tester.pump();
      expect(capture.screens, contains(ShellScreen.graph));
    });
  });

  group('idle scenario (instrument mode)', () {
    testWidgets('shows instrument mode with one ember primary', (tester) async {
      final capture = _Capture();
      await pumpLive(tester, scenario: 'idle', capture: capture);

      expect(
        find.byKey(const ValueKey<String>('live-instrument')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('live-cook-header')),
        findsNothing,
      );
      expect(find.byType(PrimaryAction), findsOneWidget);
      expect(find.text('Start a cook'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('live-instrument-start')),
      );
      await tester.pump();
      expect(capture.overlays.last.overlay, DevOverlay.setup);

      await tester.tap(
        find.byKey(const ValueKey<String>('live-instrument-graph')),
      );
      await tester.pump();
      expect(capture.screens, contains(ShellScreen.graph));
    });

    testWidgets('detached probes show — / Unplugged, never 0 (I3)', (
      tester,
    ) async {
      await pumpLive(tester, scenario: 'idle');

      for (final jack in <int>[2, 3]) {
        expect(tileTemp(tester, jack), '—');
        expect(
          tester
              .widget<Text>(
                find.byKey(ValueKey<String>('live-probe-sub-$jack')),
              )
              .data,
          'Unplugged',
        );
      }
      // The exit gate: no tile shows 0 for an absent probe.
      for (final jack in <int>[1, 2, 3, 4]) {
        expect(tileTemp(tester, jack), isNot('0'));
      }
    });
  });

  group('existing scenario (adopt banner)', () {
    testWidgets('shows the adopt banner with one ember primary', (
      tester,
    ) async {
      await pumpLive(tester, scenario: 'existing');

      expect(find.byKey(const ValueKey<String>('live-adopt-banner')), findsOne);
      expect(find.textContaining('253 samples', findRichText: true), findsOne);
      expect(
        find.textContaining('2 probes', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Adopt session'), findsOneWidget);
      expect(find.text('Start fresh'), findsOneWidget);
      // The banner owns the single ember action; the instrument card defers.
      expect(find.byType(PrimaryAction), findsOneWidget);
    });

    testWidgets('Start fresh drops the pending session', (tester) async {
      await pumpLive(tester, scenario: 'existing');

      await tester.tap(
        find.byKey(const ValueKey<String>('live-discard-session')),
      );
      await tester.pumpAndSettle();

      expect(repo.current.pendingSession, isNull);
      expect(
        find.byKey(const ValueKey<String>('live-adopt-banner')),
        findsNothing,
      );
    });
  });

  group('offline scenario (I4)', () {
    testWidgets('frozen probes remove derived values but keep recording', (
      tester,
    ) async {
      await pumpLive(tester, scenario: 'offline');

      // No ETA anywhere: derived values are removed, not greyed.
      expect(find.textContaining('to pull'), findsNothing);
      // The stopwatch still runs: the bridge records without the phone (I2).
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('live-stopwatch-time')),
            )
            .data,
        '04:30:00',
      );
      expect(find.text('Target 201°'), findsOneWidget);
    });
  });

  group('stopwatch (§7.3)', () {
    testWidgets('pause freezes the display and never stops recording', (
      tester,
    ) async {
      await pumpLive(tester, scenario: 'running', mutableClock: true);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LivePage)),
      );
      final startedAt = repo.current.cook.startedAtMs;

      await tester.tap(
        find.byKey(const ValueKey<String>('live-stopwatch-toggle')),
      );
      await tester.pump();
      expect(repo.current.cook.paused, isTrue);
      expect(repo.current.cook.startedAtMs, startedAt);

      // Advancing the wall clock must not move the frozen display.
      container
          .read(_clockProvider.notifier)
          .set(_t0.add(const Duration(hours: 1)));
      await tester.pump();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('live-stopwatch-time')),
            )
            .data,
        '04:12:00',
      );
      expect(repo.current.cook.startedAtMs, startedAt);

      // Resume: the clock catches up and recording was never interrupted.
      await tester.tap(
        find.byKey(const ValueKey<String>('live-stopwatch-toggle')),
      );
      await tester.pump();
      expect(repo.current.cook.paused, isFalse);
      expect(repo.current.cook.startedAtMs, startedAt);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('live-stopwatch-time')),
            )
            .data,
        '05:12:00',
      );
    });
  });

  group('notice banner (N5.2)', () {
    testWidgets('renders the scenario notice', (tester) async {
      await pumpLive(tester, scenario: 'switch_rollback');

      expect(find.byKey(const ValueKey<String>('live-notice')), findsOneWidget);
      expect(
        find.textContaining('kept Bluetooth', findRichText: true),
        findsOne,
      );
    });
  });

  group('mark sheet (N5.13)', () {
    testWidgets('logs all eight kinds with an optional note', (tester) async {
      var done = false;
      tester.view
        ..physicalSize = const Size(390, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        harness(MarkSheetBody(onDone: () => done = true)),
      );
      await tester.pumpAndSettle();

      for (final kind in <String>[
        'note',
        'wrapped',
        'spritz',
        'turn',
        'lidOpen',
        'fuel',
        'probeMoved',
        'phaseChange',
      ]) {
        expect(find.byKey(ValueKey<String>('mark-kind-$kind')), findsOneWidget);
      }

      await tester.tap(find.byKey(const ValueKey<String>('mark-kind-spritz')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey<String>('mark-note')),
        'Spritzed the ribs',
      );
      await tester.tap(find.byKey(const ValueKey<String>('mark-save')));
      await tester.pumpAndSettle();

      expect(repo.current.marks.last.kind, MarkKind.spritz);
      expect(repo.current.marks.last.text, 'Spritzed the ribs');
      expect(done, isTrue);
    });
  });

  group('edit start (N5.12, I10)', () {
    testWidgets('moves the window without touching samples or marks', (
      tester,
    ) async {
      var done = false;
      await repo.selectScenario('running');
      final before = repo.current;
      tester.view
        ..physicalSize = const Size(390, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        harness(EditStartBody(onDone: () => done = true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Just now'), findsOneWidget);
      expect(find.text('30 min ago'), findsOneWidget);
      expect(find.text('1 hour ago'), findsOneWidget);
      expect(find.text('2 hours ago'), findsOneWidget);
      expect(find.text('4 hours ago'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('edit-start-60')));
      await tester.pumpAndSettle();

      expect(repo.current.cook.startedAtMs, _t0ms - 60 * 60000);
      // The samples (probe readings) and marks are untouched.
      expect(repo.current.probes, before.probes);
      expect(repo.current.marks, before.marks);
      expect(done, isTrue);
    });
  });

  group('adopt confirmation (N5.3)', () {
    testWidgets('adopt keeps the recorded samples and starts the cook', (
      tester,
    ) async {
      var done = false;
      await repo.selectScenario('existing');
      tester.view
        ..physicalSize = const Size(390, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        harness(
          Column(
            children: <Widget>[
              AdoptSessionBody(onDone: () {}),
              AdoptSessionActions(onDone: () => done = true),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('253 samples', findRichText: true), findsOne);
      await tester.tap(
        find.byKey(const ValueKey<String>('live-adopt-confirm')),
      );
      await tester.pumpAndSettle();

      expect(repo.current.cook.active, isTrue);
      expect(repo.current.pendingSession, isNull);
      expect(done, isTrue);
    });
  });

  group('details link (N5.8)', () {
    testWidgets('opens the Temps destination', (tester) async {
      final capture = _Capture();
      await pumpLive(tester, scenario: 'running', capture: capture);

      await tester.tap(
        find.byKey(const ValueKey<String>('live-probes-details')),
      );
      await tester.pump();
      expect(capture.screens, contains(ShellScreen.temps));
    });
  });
}
