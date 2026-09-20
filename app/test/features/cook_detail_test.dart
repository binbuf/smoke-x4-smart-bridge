/// `/cooks/:id` — the things the screen writes, and the clock it reads by
/// (16 §16.6, §16.7; newapp §C.4, §D.3).
///
/// Every case here is a control or a number that *looked* right and was not,
/// which is the failure §16.2 ranks above a bad chart:
///
///  * the notes field took typing and threw it away, because a three-line field
///    has no submit action to hang a save on;
///  * a retarget reported success and kept only the roles;
///  * "Time in band" said "no band set" on a cook whose preset set one;
///  * a mark inside a ten-minute cook read "02:00:00" because it was measured
///    from the *session*;
///  * a backdated cook's clock times slid by the width of the hole it was
///    backdated across;
///  * a read that threw left a spinner turning with no words on it.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/app_env.dart';
import 'package:smoke_bridge/data/local/database.dart';
import 'package:smoke_bridge/data/repos/cook_repository.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/domain/plan/plan.dart';
import 'package:smoke_bridge/features/cooks/cook_detail_route.dart';
import 'package:smoke_bridge/features/cooks/cook_detail_view.dart';
import 'package:smoke_bridge/ui/ui.dart';

import '../support/fake_env.dart';

const int _minute = 60 * 1000;
const int _hour = 60 * _minute;

/// The same clock arithmetic [CookGapsCard] does, so the expectation is a time
/// of day rather than a timezone-dependent literal.
String _hhmm(int unixMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixMs);
  return '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

void main() {
  late AppDatabase db;
  late CookRepository repo;
  late int now;
  late int sessionStart;

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
  });

  tearDown(() => db.close());

  /// Five hours of pit-and-food at 30 s, clocked from the session start.
  Future<void> seedSamples() => db.sampleDao.insertSamplesForSession('b', 1, [
    for (var i = 0; i < 600; i++)
      Sample(t: i * 30, tempsF10: [2500, 1500 + i, null, null]),
  ]);

  Future<CookAnnotation> seedCook({
    String name = 'Brisket',
    String notes = '',
    int? startUnixMs,
    int? endUnixMs,
    int? pitBandMinF10,
    int? pitBandMaxF10,
    List<CookProbeRole> roles = const [],
  }) async {
    final id = await db.cookDao.save(
      CookAnnotation(
        id: 0,
        bridgeId: 'b',
        name: name,
        notes: notes,
        startUnixMs: startUnixMs ?? sessionStart,
        endUnixMs: endUnixMs,
        createdUnixMs: sessionStart,
        pitBandMinF10: pitBandMinF10,
        pitBandMaxF10: pitBandMaxF10,
        roles: roles,
      ),
    );
    return (await repo.cook(id))!;
  }

  Future<void> pumpTall(
    WidgetTester tester,
    CookAnnotation cook, {
    CookRepository? over,
  }) async {
    tester.view.physicalSize = const Size(900, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeTheme.dark,
        home: Scaffold(body: CookDetailView(repo: over ?? repo, cook: cook)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('§C.4 — the notes field is a control that writes', () {
    testWidgets('a note typed and tapped away from is on the row', (
      tester,
    ) async {
      await seedSamples();
      final cook = await seedCook();
      await pumpTall(tester, cook);

      await tester.enterText(
        find.byKey(const Key('cook-notes')),
        'wrapped at 165, apple wood',
      );
      await tester.pump();
      // No Enter: a three-line field's Enter is a newline. Tapping away is the
      // gesture people actually use, and it is the one that has to write.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect((await repo.cook(cook.id))!.notes, 'wrapped at 165, apple wood');
    });

    testWidgets('a note survives leaving the screen mid-sentence', (
      tester,
    ) async {
      await seedSamples();
      final cook = await seedCook();
      await pumpTall(tester, cook);

      await tester.enterText(find.byKey(const Key('cook-notes')), 'foiled');
      await tester.pump();
      // Backing out of the cook is the commonest way a note ends.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect((await repo.cook(cook.id))!.notes, 'foiled');
    });

    testWidgets('what is already on the row is what the field shows', (
      tester,
    ) async {
      await seedSamples();
      await pumpTall(tester, await seedCook(notes: 'pecan, 12 h'));

      expect(
        tester.widget<TextField>(find.byKey(const Key('cook-notes'))).controller
            ?.text,
        'pecan, 12 h',
      );
    });
  });

  group('§C.4 — the pit band reaches the statistics', () {
    testWidgets('a cook that carries a band gets a time in it', (tester) async {
      await seedSamples();
      await pumpTall(
        tester,
        await seedCook(
          // What every pit preset sets, and what nothing was reading.
          pitBandMinF10: 2250,
          pitBandMaxF10: 2750,
          endUnixMs: sessionStart + 3 * _hour,
          roles: const [
            CookProbeRole(jack: 1, role: ProbeRole.pit, label: 'Pit'),
            CookProbeRole(
              jack: 2,
              role: ProbeRole.food,
              label: 'Brisket',
              targetF10: 2030,
            ),
          ],
        ),
      );

      expect(find.text('Time in band'), findsOneWidget);
      expect(find.text('no band set'), findsNothing);
      expect(find.text('3h'), findsWidgets);
    });

    testWidgets('a cook with no band still says so plainly', (tester) async {
      await seedSamples();
      await pumpTall(
        tester,
        await seedCook(
          roles: const [
            CookProbeRole(jack: 1, role: ProbeRole.pit, label: 'Pit'),
          ],
        ),
      );

      expect(find.text('no band set'), findsOneWidget);
    });
  });

  group('§16.6 — marks are measured from the cook, not the session', () {
    testWidgets('a mark an hour into a cook reads 01:00:00', (tester) async {
      await seedSamples();
      await db.markDao.replaceMarks('b', 1, const [
        Mark(t: 3600, kind: MarkKind.note, text: 'Before this cook'),
        Mark(t: 3 * 3600, kind: MarkKind.note, text: 'Wrapped'),
      ]);
      await pumpTall(
        tester,
        await seedCook(startUnixMs: sessionStart + 2 * _hour),
      );

      expect(find.text('Wrapped'), findsOneWidget);
      expect(find.text('01:00:00'), findsOneWidget);
      // The session-relative reading, which is a true fact about the session
      // and a false one about the cook on screen.
      expect(find.text('03:00:00'), findsNothing);
      // …and a mark an hour *before* this cook began is not part of it.
      expect(find.text('Before this cook'), findsNothing);
    });

    testWidgets('a cook that starts with its session is unchanged', (
      tester,
    ) async {
      await seedSamples();
      await db.markDao.replaceMarks('b', 1, const [
        Mark(t: 3600, kind: MarkKind.note, text: 'Wrapped'),
      ]);
      await pumpTall(tester, await seedCook());

      expect(find.text('01:00:00'), findsOneWidget);
    });
  });

  group('§D.3 — a backdated cook keeps the recording’s clock', () {
    testWidgets('the gap card names the hour the hole really happened in', (
      tester,
    ) async {
      await seedSamples();
      await db.syncStateDao.recordGap(
        'b',
        1,
        fromT: 3600,
        toT: 7200,
        reason: GapReason.bufferRollover,
        atUnixMs: now,
      );
      // Backdated to an hour before the recording exists — §D.3.1's own case,
      // and the one where inferring `t = 0` from the first sample inside the
      // cook slides every clock time on the screen by an hour.
      await pumpTall(tester, await seedCook(startUnixMs: sessionStart - _hour));

      expect(
        find.textContaining(
          '${_hhmm(sessionStart + _hour)} → ${_hhmm(sessionStart + 2 * _hour)}',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          '${_hhmm(sessionStart)} → ${_hhmm(sessionStart + _hour)}',
        ),
        findsNothing,
      );
    });
  });

  group('§C.4 — merging with the earlier neighbour does not strand the route',
      () {
    testWidgets('the route follows the surviving cook instead of losing it', (
      tester,
    ) async {
      await seedSamples();
      final earlier = await seedCook(
        name: 'Earlier one',
        endUnixMs: sessionStart + 2 * _hour,
      );
      final later = await seedCook(
        name: 'Later one',
        startUnixMs: sessionStart + 2 * _hour,
        endUnixMs: sessionStart + 4 * _hour,
      );
      AppEnv.instance = fakeEnv(db: db);
      addTearDown(() => AppEnv.instance = null);

      tester.view.physicalSize = const Size(900, 4200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: SmokeTheme.dark,
          home: CookDetailRoute(cookId: later.id),
        ),
      );
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('cook-merge')),
        find.byKey(const Key('session-detail')),
        const Offset(0, -400),
      );
      await tester.tap(find.byKey(const Key('cook-merge')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('cook-merge-${earlier.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cost-confirm')));
      await tester.pumpAndSettle();

      // The merge keeps the earlier row and deletes this one. A route that kept
      // re-reading its URL's id reported the cook missing here.
      expect(find.byKey(const Key('cook-detail-missing')), findsNothing);
      expect(find.text('That cook isn’t here'), findsNothing);
      expect(find.byType(CookDetailView), findsOneWidget);

      final survivor = (await repo.cook(earlier.id))!;
      expect(survivor.startUnixMs, sessionStart);
      expect(survivor.endUnixMs, sessionStart + 4 * _hour);
      expect(await repo.cook(later.id), isNull);
    });
  });

  group('§16.7 — the failed rung of the ladder renders', () {
    testWidgets('a read that throws says so, and offers the read again', (
      tester,
    ) async {
      final broken = AppDatabase(NativeDatabase.memory());
      await broken.sessionDao.upsertBridge('b');
      await broken.close();

      await pumpTall(
        tester,
        const CookAnnotation(
          id: 1,
          bridgeId: 'b',
          startUnixMs: 0,
          createdUnixMs: 0,
        ),
        over: CookRepository(broken, bridgeId: 'b'),
      );

      expect(find.byKey(const Key('cook-detail-failed')), findsOneWidget);
      expect(find.byType(ProblemState), findsOneWidget);
      expect(find.text('Couldn’t read this cook'), findsOneWidget);
      expect(
        find.textContaining('Nothing has been lost on the bridge.'),
        findsOneWidget,
      );
      // §16.4: exactly one action, and it is a verb naming the outcome.
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
