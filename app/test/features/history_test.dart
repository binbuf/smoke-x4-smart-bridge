/// N12 — the History destination and the cook detail.
///
/// Covers the exit gate: the seven mock cooks list and group correctly, a cook
/// detail renders chart, recap, marks and notes, "Cook again" opens setup
/// pre-filled with the same preset+style, and export works from the cache with
/// the app offline. Also the annotation verbs (notes, marks, pull, end/reopen,
/// delete) and the gaps card.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/history/history.dart';
import 'package:smoke_bridge/features/shell/shell.dart';
import 'package:smoke_bridge/features/shell/shell_screen.dart';

import '../support/load_fonts.dart';

const int _t0ms = 1700000000000;
final DateTime _t0 = DateTime.fromMillisecondsSinceEpoch(_t0ms);

class _Capture {
  final overlays = <({DevOverlay overlay, Map<String, String> props})>[];
  final screens = <ShellScreen>[];
  final toasts = <String>[];
  final cookIds = <String>[];
}

/// A repository whose history carries a cook with recorded gaps (N12.15).
class _GapRepo extends MockBridgeRepository {
  _GapRepo(this.gapEntry) : super(nowMs: _t0ms);

  final HistoryEntry gapEntry;

  @override
  List<HistoryEntry> get history => <HistoryEntry>[gapEntry, ...super.history];
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
        historyNowProvider.overrideWithValue(_t0),
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
            openCookDetail: (id) => capture?.cookIds.add(id),
            child: child,
          ),
        ),
      ),
    );
  }

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    _Capture? capture,
    Size size = const Size(390, 3200),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(child, capture: capture));
    await tester.pumpAndSettle();
  }

  String textAt(WidgetTester tester, String key) {
    final text = tester.widget<Text>(find.byKey(ValueKey<String>(key)));
    return text.data ?? '';
  }

  group('History list (N12.1–N12.4)', () {
    testWidgets('lists and groups the seven mock cooks', (tester) async {
      await pump(tester, const HistoryPage());

      expect(
        find.byKey(const ValueKey<String>('history-page')),
        findsOneWidget,
      );
      // The annotation-over-recording promise stays on screen (I10).
      expect(
        find.byKey(const ValueKey<String>('history-notice')),
        findsOneWidget,
      );
      expect(find.textContaining('you never lose the gap'), findsOneWidget);

      expect(
        find.byKey(const ValueKey<String>('history-group-thisWeek')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('history-group-earlier')),
        findsOneWidget,
      );
      expect(textAt(tester, 'history-group-count-thisWeek'), '4');
      expect(textAt(tester, 'history-group-count-earlier'), '3');

      for (final id in <String>['c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7']) {
        expect(
          find.byKey(ValueKey<String>('history-card-$id')),
          findsOneWidget,
        );
      }
      // Three favourites carry a star (c1, c4, c6).
      expect(find.byIcon(Icons.star), findsNWidgets(3));
      // Exactly one ember primary (I14).
      expect(find.byType(PrimaryAction), findsOneWidget);
    });

    testWidgets('tapping a card asks the shell to open its detail', (
      tester,
    ) async {
      final capture = _Capture();
      await pump(tester, const HistoryPage(), capture: capture);

      await tester.tap(find.byKey(const ValueKey<String>('history-card-c4')));
      await tester.pumpAndSettle();
      expect(capture.cookIds, <String>['c4']);
    });
  });

  group('Cook detail (N12.5–N12.10)', () {
    testWidgets('renders header, recap, result, chart, notes and marks', (
      tester,
    ) async {
      await pump(tester, const CookDetailPage(id: 'c1'));

      expect(
        find.byKey(const ValueKey<String>('cook-detail-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('cook-detail-header')),
        findsOneWidget,
      );
      expect(textAt(tester, 'cook-detail-name'), 'Labor Day Pulled Pork');
      // date · time · duration · style
      expect(textAt(tester, 'cook-detail-line'), contains('10h 12m'));
      expect(textAt(tester, 'cook-detail-line'), contains('Texas Pulled'));

      expect(
        find.byKey(const ValueKey<String>('cook-detail-recap')),
        findsOneWidget,
      );
      expect(find.textContaining('Reached target 201° F'), findsOneWidget);
      expect(find.textContaining('Evaporative plateau'), findsOneWidget);

      expect(
        find.byKey(const ValueKey<String>('cook-detail-result')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('cook-detail-chart')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('cook-detail-notes')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('cook-detail-marks')),
        findsOneWidget,
      );
      // c1 was wrapped: the derived rail has four events.
      expect(
        find.byKey(const ValueKey<String>('cook-detail-mark-3')),
        findsOneWidget,
      );
      expect(find.text('Wrapped'), findsOneWidget);
      // A detail screen has no ember primary (I14).
      expect(find.byType(PrimaryAction), findsNothing);
    });

    testWidgets('a deep link to a missing cook is a named state, not a crash', (
      tester,
    ) async {
      await pump(tester, const CookDetailPage(id: 'gone'));
      expect(
        find.byKey(const ValueKey<String>('cook-detail-missing')),
        findsOneWidget,
      );
      expect(find.text('Cook not found'), findsOneWidget);
    });

    testWidgets('the favourite toggle writes through', (tester) async {
      await pump(tester, const CookDetailPage(id: 'c2'));
      expect(repo.history.firstWhere((h) => h.id == 'c2').favourite, isFalse);

      await tester.tap(find.byKey(const ValueKey<String>('cook-detail-fav')));
      await tester.pumpAndSettle();
      expect(repo.history.firstWhere((h) => h.id == 'c2').favourite, isTrue);
    });
  });

  group('Cook again + export (exit gate)', () {
    testWidgets('Cook again opens setup pre-filled with preset and style', (
      tester,
    ) async {
      final capture = _Capture();
      await pump(tester, const CookDetailPage(id: 'c1'), capture: capture);

      await tester.tap(
        find.byKey(const ValueKey<String>('cook-detail-repeat')),
      );
      await tester.pumpAndSettle();

      final request = capture.overlays.single;
      expect(request.overlay, DevOverlay.setup);
      expect(request.props['food'], 'pork_butt');
      expect(request.props['style'], 'texas_pulled');
      expect(request.props['jack'], '1');
    });

    testWidgets('Share exports from the cache with the bridge offline', (
      tester,
    ) async {
      final capture = _Capture();
      await repo.disconnect();
      await pump(tester, const CookDetailPage(id: 'c1'), capture: capture);

      await tester.tap(find.byKey(const ValueKey<String>('cook-detail-share')));
      await tester.pumpAndSettle();

      expect(capture.toasts.single, contains('cook-c1.csv'));
      expect(capture.toasts.single, contains('rows'));
      final csv = await repo.exportCookCsv('c1');
      expect(csv, startsWith(cookCsvHeader));
    });
  });

  group('Annotation verbs (N12.13/N12.14)', () {
    testWidgets('delete sits behind a cost sheet that keeps the recording', (
      tester,
    ) async {
      final capture = _Capture();
      await pump(tester, const CookDetailPage(id: 'c1'), capture: capture);

      await tester.tap(
        find.byKey(const ValueKey<String>('cook-detail-delete')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete this cook?'), findsOneWidget);
      expect(find.textContaining('every sample row stays'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CostSheet),
          matching: find.text('Delete cook'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(CostSheet),
          matching: find.text('Delete cook'),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.history.any((h) => h.id == 'c1'), isFalse);
      expect(capture.screens, contains(ShellScreen.history));
      expect(capture.toasts.single, contains('recording is untouched'));
    });

    testWidgets('notes edit writes through', (tester) async {
      await pump(tester, const CookDetailPage(id: 'c2'));
      await tester.tap(
        find.byKey(const ValueKey<String>('cook-detail-notes-edit')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('cook-detail-notes-field')),
        'Two minutes a side.',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('cook-detail-notes-save')),
      );
      await tester.pumpAndSettle();

      expect(
        repo.history.firstWhere((h) => h.id == 'c2').notes,
        'Two minutes a side.',
      );
    });

    testWidgets('add mark and pull write through', (tester) async {
      await pump(tester, const CookDetailPage(id: 'c2'));

      await tester.tap(
        find.byKey(const ValueKey<String>('cook-detail-add-mark')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('spritz'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('cook-detail-mark-save')),
      );
      await tester.pumpAndSettle();

      final afterMark = repo.history.firstWhere((h) => h.id == 'c2');
      expect(afterMark.markEvents.last.kind, MarkKind.spritz);

      await tester.tap(find.byKey(const ValueKey<String>('cook-detail-pull')));
      await tester.pumpAndSettle();
      final afterPull = repo.history.firstWhere((h) => h.id == 'c2');
      expect(afterPull.markEvents.last.text, 'Pulled');
    });

    testWidgets('end / reopen toggles the annotation status', (tester) async {
      await pump(tester, const CookDetailPage(id: 'c1'));
      expect(repo.history.firstWhere((h) => h.id == 'c1').isOpen, isFalse);

      await tester.tap(find.byKey(const ValueKey<String>('cook-detail-end')));
      await tester.pumpAndSettle();
      expect(repo.history.firstWhere((h) => h.id == 'c1').isOpen, isTrue);
      expect(find.text('End this cook'), findsOneWidget);
    });
  });

  group('Gaps card (N12.15)', () {
    testWidgets('renders connectivity vs buffer-rollover with explanations', (
      tester,
    ) async {
      repo = _GapRepo(
        HistoryEntry(
          id: 'g1',
          name: 'Gappy Brisket',
          presetId: 'beef_brisket',
          styleId: 'central_texas',
          glyph: 'brisket',
          jack: 1,
          startedAtMs: _t0ms - 600 * 60000,
          durationMin: 600,
          plannedMin: 600,
          peakF10: 2020,
          targetF10: 2010,
          gaps: const <RecordedGap>[
            RecordedGap(fromT: 600, toT: 900, reason: GapReason.connectivity),
            RecordedGap(
              fromT: 1800,
              toT: 2400,
              reason: GapReason.bufferRollover,
            ),
          ],
        ),
      );
      await pump(tester, const CookDetailPage(id: 'g1'));

      expect(
        find.byKey(const ValueKey<String>('cook-detail-gaps')),
        findsOneWidget,
      );
      expect(find.text('Not synced yet'), findsOneWidget);
      expect(find.text('Buffer rolled over'), findsOneWidget);
      expect(find.textContaining('gone for good'), findsOneWidget);
    });
  });
}
