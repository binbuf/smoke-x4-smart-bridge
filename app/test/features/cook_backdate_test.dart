/// Moving a cook's start (newapp §D.3.1, 16 §16.6) — the differentiator.
///
/// Two levels, because the feature is two things:
///
///  * the **sheet**, which has to read as evidence rather than as a date
///    picker: what the recording saw, when, and how far it would move the
///    start;
///  * the **flow**, end to end against a real cache: the detail screen leads
///    with the offer, tapping an anchor commits it, the app reports what it did
///    in the past tense with a way back — and **not one sample row moves**,
///    which is the property the whole reframe rests on.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/local/database.dart';
import 'package:smoke_bridge/data/repos/cook_repository.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/domain/plan/plan.dart';
import 'package:smoke_bridge/features/cooks/cook_backdate_sheet.dart';
import 'package:smoke_bridge/features/cooks/cook_detail_view.dart';

const int _minute = 60 * 1000;
const int _hour = 60 * _minute;
const int _start = 1784755815000;

CookAnnotation _cook({int startUnixMs = _start, int? endUnixMs}) =>
    CookAnnotation(
      id: 1,
      bridgeId: 'b',
      name: 'Brisket',
      startUnixMs: startUnixMs,
      endUnixMs: endUnixMs,
      createdUnixMs: startUnixMs,
    );

void main() {
  group('the sheet reads as evidence, not as a date picker', () {
    Widget host(CookAnnotation cook, List<CookAnchor> anchors) => MaterialApp(
      theme: SmokeTheme.dark,
      home: Scaffold(body: BackdateSheet(cook: cook, anchors: anchors)),
    );

    testWidgets('each anchor states what was seen, when, and how far it moves',
        (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(_cook(), [
          CookAnchor(
            unixMs: _start - 2 * _hour - 14 * _minute,
            kind: AnchorKind.probeInserted,
            label: 'Probe 2 plugged in',
            probe: 2,
          ),
          CookAnchor(
            unixMs: _start - 30 * _minute,
            kind: AnchorKind.crossedAmbient,
            label: 'Probe 2 went above 90°F',
            probe: 2,
          ),
          CookAnchor(
            unixMs: _start - 5 * _hour,
            kind: AnchorKind.recordingStart,
            label: 'When recording started',
          ),
        ]),
      );
      await tester.pump();

      expect(find.byKey(const Key('backdate-sheet')), findsOneWidget);
      expect(find.text('Probe 2 plugged in'), findsOneWidget);

      // The line that makes the feature land: how far back this really was.
      expect(find.textContaining('2h 14m earlier'), findsOneWidget);
      expect(find.textContaining('30m earlier'), findsOneWidget);
      expect(find.textContaining('5h earlier'), findsOneWidget);

      // …and why the recording thinks it is a start, in plain words.
      expect(
        find.textContaining('usually the food going on'),
        findsOneWidget,
      );
      expect(find.textContaining('the food met the fire'), findsOneWidget);
      expect(
        find.textContaining('the oldest reading this phone holds'),
        findsOneWidget,
      );

      // Never the mechanism.
      expect(find.textContaining('sample['), findsNothing);
      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('it promises, up front, that no reading moves', (tester) async {
      await tester.pumpWidget(host(_cook(), const []));
      await tester.pump();
      expect(find.textContaining('No reading moves'), findsOneWidget);
    });

    testWidgets('an anchor at or after the end is not offered', (tester) async {
      final cook = _cook(endUnixMs: _start + _hour);
      await tester.pumpWidget(
        host(cook, [
          CookAnchor(
            unixMs: _start + 2 * _hour,
            kind: AnchorKind.mark,
            label: 'Wrapped',
          ),
          CookAnchor(
            unixMs: _start - _hour,
            kind: AnchorKind.mark,
            label: 'Lid open',
          ),
        ]),
      );
      await tester.pump();

      // A cook cannot start after it finished, and a row that throws on tap is
      // a dead control with extra steps.
      expect(find.text('Wrapped'), findsNothing);
      expect(find.text('Lid open'), findsOneWidget);
    });

    testWidgets('no anchors says why, and still offers the manual way', (
      tester,
    ) async {
      await tester.pumpWidget(host(_cook(), const []));
      await tester.pump();

      expect(find.byKey(const Key('backdate-no-anchors')), findsOneWidget);
      expect(find.textContaining('had no clock'), findsOneWidget);
      expect(find.byKey(const Key('anchor-manual')), findsOneWidget);
    });
  });

  group('the shift label', () {
    test('names the direction, and refuses false precision at zero', () {
      expect(shiftLabel(_start - 2 * _hour, _start), '2h earlier');
      expect(shiftLabel(_start + 90 * _minute, _start), '1h 30m later');
      expect(shiftLabel(_start + 3000, _start), 'where it starts now');
    });
  });

  group('the flow, against a real cache', () {
    late AppDatabase db;
    late CookRepository repo;
    late int now;
    late int sessionStart;
    late CookAnnotation cook;

    setUp(() async {
      now = DateTime.now().millisecondsSinceEpoch;
      sessionStart = now - 5 * _hour;
      db = AppDatabase(NativeDatabase.memory());
      repo = CookRepository(
        db,
        bridgeId: 'b',
        now: () => DateTime.fromMillisecondsSinceEpoch(now),
      );
      await db.sessionDao.upsertBridge('b');
      await db.sessionDao.upsertSessions('b', [
        CookSession(
          id: 1,
          name: 'session',
          startedUnixMs: sessionStart,
          samplePeriodS: 30,
        ),
      ]);
      // Probe 1 hot from the start; probe 2 goes in — and straight past
      // ambient — twenty minutes in. That is the moment the meat went on.
      await db.sampleDao.insertSamplesForSession('b', 1, [
        for (var i = 0; i < 120; i++)
          Sample(
            t: i * 30,
            tempsF10: [2500, i < 40 ? null : 950, null, null],
          ),
      ]);
      final id = await db.cookDao.save(
        _cook(startUnixMs: sessionStart + _hour).copyWith(id: 0),
      );
      cook = (await repo.cook(id))!;
    });

    tearDown(() => db.close());

    Widget host() => MaterialApp(
      theme: SmokeTheme.dark,
      home: Scaffold(
        body: CookDetailView(repo: repo, cook: cook),
      ),
    );

    testWidgets('the detail screen leads with the offer and counts it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cook-start-card')), findsOneWidget);
      // The count is the pitch — proof the feature is real before you tap it.
      expect(find.textContaining('The recording holds 3 moments'), findsOneWidget);
      expect(
        find.textContaining('does not move a single reading'),
        findsOneWidget,
      );
      // It gets the screen's one ember button (rail R1).
      expect(find.byKey(const Key('cook-backdate')), findsOneWidget);
    });

    testWidgets('tapping an anchor moves the start and no sample moves', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final before = (await db.select(db.samples).get()).length;
      expect(before, 120);

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cook-backdate')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('backdate-sheet')), findsOneWidget);
      final anchorAt = sessionStart + 40 * 30 * 1000;
      await tester.tap(find.byKey(Key('anchor-probeInserted-$anchorAt')));
      await tester.pumpAndSettle();

      final saved = await repo.cook(cook.id);
      expect(saved!.startUnixMs, anchorAt);
      // The claim the whole reframe rests on.
      expect((await db.select(db.samples).get()).length, before);

      // Reported in the past tense, with the way back (§16.4).
      expect(find.textContaining('Start moved'), findsOneWidget);
      expect(find.textContaining('40m earlier'), findsOneWidget);
      expect(find.textContaining('No readings moved'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('undo puts the start back where it was', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final was = cook.startUnixMs;
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cook-backdate')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('anchor-probeInserted-${sessionStart + 40 * 30 * 1000}')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect((await repo.cook(cook.id))!.startUnixMs, was);
    });

    testWidgets('the edit list also reaches it, one tap from the cook', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byKey(const Key('cook-move-start')),
        find.byKey(const Key('session-detail')),
        const Offset(0, -400),
      );
      await tester.tap(find.byKey(const Key('cook-move-start')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('backdate-sheet')), findsOneWidget);
    });
  });
}
