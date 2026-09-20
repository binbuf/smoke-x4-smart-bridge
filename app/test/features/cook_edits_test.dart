/// `/cooks/:id` — the edit surface (16 §16.6, newapp §C.4).
///
/// §16.6 asks for seven edits **reachable in ≤2 taps**: rename, move start,
/// retarget, split, merge, repeat, delete. They used to be spread across a
/// horizontally-scrolling chip rail (where "merge" was not, because it lived on
/// a second route), which is two problems at once — an edit you cannot see is
/// not reachable, and an edit on another screen is three taps.
///
/// So they are rows now, and this file pins the properties that matter: they
/// are all present, one tap each; a row that cannot run renders **dimmed with
/// its reason on screen** rather than absent or inert; and delete says plainly
/// that the recording does not stop.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/app_env.dart';
import 'package:smoke_bridge/data/local/database.dart';
import 'package:smoke_bridge/data/repos/cook_repository.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/domain/plan/plan.dart';
import 'package:smoke_bridge/features/cooks/cook_detail_view.dart';
import 'package:smoke_bridge/features/cooks/cook_sheet_shell.dart';
import 'package:smoke_bridge/features/cooks/cooks_tab.dart';

import '../support/fake_env.dart';

const int _minute = 60 * 1000;
const int _hour = 60 * _minute;

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

  Future<void> seedSamples() => db.sampleDao.insertSamplesForSession('b', 1, [
    for (var i = 0; i < 240; i++)
      Sample(t: i * 30, tempsF10: [2500, 1500 + i, null, null]),
  ]);

  Future<CookAnnotation> seedCook({
    String name = 'Brisket',
    int? startUnixMs,
    int? endUnixMs,
  }) async {
    final id = await db.cookDao.save(
      CookAnnotation(
        id: 0,
        bridgeId: 'b',
        name: name,
        startUnixMs: startUnixMs ?? sessionStart,
        endUnixMs: endUnixMs,
        createdUnixMs: sessionStart,
      ),
    );
    return (await repo.cook(id))!;
  }

  Widget host(CookAnnotation cook) => MaterialApp(
    theme: SmokeTheme.dark,
    home: Scaffold(body: CookDetailView(repo: repo, cook: cook)),
  );

  Future<void> pumpTall(WidgetTester tester, CookAnnotation cook) async {
    tester.view.physicalSize = const Size(900, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(cook));
    await tester.pumpAndSettle();
  }

  group('the whole edit set is on the screen', () {
    testWidgets('every §16.6 edit is one tap from the cook', (tester) async {
      await seedSamples();
      await pumpTall(tester, await seedCook());
      await tester.dragUntilVisible(
        find.byKey(const Key('cook-delete')),
        find.byKey(const Key('session-detail')),
        const Offset(0, -400),
      );

      for (final key in [
        'cook-rename',
        'cook-move-start',
        'cook-retarget',
        'cook-split',
        'cook-merge',
        'cook-repeat',
        'cook-favourite',
        'cook-end',
        'cook-export',
        'cook-delete',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: 'missing $key');
      }
    });

    testWidgets('a running cook offers to end it; an ended one to reopen', (
      tester,
    ) async {
      await seedSamples();
      await pumpTall(tester, await seedCook(endUnixMs: now - _hour));
      await tester.dragUntilVisible(
        find.byKey(const Key('cook-reopen')),
        find.byKey(const Key('session-detail')),
        const Offset(0, -400),
      );
      expect(find.byKey(const Key('cook-reopen')), findsOneWidget);
      expect(find.byKey(const Key('cook-end')), findsNothing);
    });
  });

  group('a row that cannot run says why', () {
    testWidgets('merge with nothing beside it is dimmed, with its reason', (
      tester,
    ) async {
      await seedSamples();
      await pumpTall(tester, await seedCook());
      await tester.dragUntilVisible(
        find.byKey(const Key('cook-merge')),
        find.byKey(const Key('session-detail')),
        const Offset(0, -400),
      );

      final row = tester.widget<CookSheetRow>(
        find.byKey(const Key('cook-merge')),
      );
      expect(row.enabled, isFalse);
      // Rendered, dimmed, **with its reason directly beneath** (§16.5).
      expect(
        find.text('Nothing is recorded next to this cook.'),
        findsOneWidget,
      );
    });

    testWidgets('split and export with no readings are dimmed too', (
      tester,
    ) async {
      await pumpTall(tester, await seedCook());
      await tester.dragUntilVisible(
        find.byKey(const Key('cook-export')),
        find.byKey(const Key('session-detail')),
        const Offset(0, -400),
      );

      expect(
        tester.widget<CookSheetRow>(find.byKey(const Key('cook-split'))).enabled,
        isFalse,
      );
      expect(
        find.text('Nothing is recorded inside this cook to split.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<CookSheetRow>(find.byKey(const Key('cook-export')))
            .enabled,
        isFalse,
      );
      expect(find.text('This cook has no readings to export.'), findsOneWidget);
    });

    testWidgets('a second cook makes merge live again', (tester) async {
      await seedSamples();
      await seedCook(name: 'Earlier one', startUnixMs: sessionStart - 8 * _hour);
      await pumpTall(tester, await seedCook());
      await tester.dragUntilVisible(
        find.byKey(const Key('cook-merge')),
        find.byKey(const Key('session-detail')),
        const Offset(0, -400),
      );

      expect(
        tester.widget<CookSheetRow>(find.byKey(const Key('cook-merge'))).enabled,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('cook-merge')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('merge-sheet')), findsOneWidget);
      expect(find.text('Earlier one'), findsOneWidget);
    });
  });

  group('the edits run', () {
    testWidgets('renaming persists and the list behind is told', (
      tester,
    ) async {
      await seedSamples();
      final cook = await seedCook(name: '');
      var changed = 0;
      tester.view.physicalSize = const Size(900, 4200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: SmokeTheme.dark,
          home: Scaffold(
            body: CookDetailView(
              repo: repo,
              cook: cook,
              onChanged: () async => changed++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byKey(const Key('cook-rename')),
        find.byKey(const Key('session-detail')),
        const Offset(0, -400),
      );
      await tester.tap(find.byKey(const Key('cook-rename')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('cook-rename-field')),
        'Pork butt',
      );
      await tester.tap(find.byKey(const Key('cook-rename-save')));
      await tester.pumpAndSettle();

      expect((await repo.cook(cook.id))!.name, 'Pork butt');
      expect(changed, greaterThan(0));
    });

    testWidgets('delete states that the recording does not stop', (
      tester,
    ) async {
      await seedSamples();
      final cook = await seedCook();
      final before = (await db.select(db.samples).get()).length;

      await pumpTall(tester, cook);
      await tester.dragUntilVisible(
        find.byKey(const Key('cook-delete')),
        find.byKey(const Key('session-detail')),
        const Offset(0, -400),
      );
      await tester.tap(find.byKey(const Key('cook-delete')));
      await tester.pumpAndSettle();

      // The load-bearing half of the ledger.
      expect(
        find.textContaining(
          'The bridge never stops recording.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Every reading', findRichText: true),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('cost-confirm')));
      await tester.pumpAndSettle();

      expect(await repo.cook(cook.id), isNull);
      // …and it was true.
      expect((await db.select(db.samples).get()).length, before);
    });

    testWidgets('the cost sheet’s escape hatch keeps the cook', (tester) async {
      await seedSamples();
      final cook = await seedCook();
      await pumpTall(tester, cook);
      await tester.dragUntilVisible(
        find.byKey(const Key('cook-delete')),
        find.byKey(const Key('session-detail')),
        const Offset(0, -400),
      );
      await tester.tap(find.byKey(const Key('cook-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cost-cancel')));
      await tester.pumpAndSettle();

      expect(await repo.cook(cook.id), isNotNull);
    });
  });

  group('the screen answers its question above the fold', () {
    testWidgets('three numbers: how long, how hot, how much', (tester) async {
      await seedSamples();
      await pumpTall(
        tester,
        await seedCook(endUnixMs: sessionStart + 2 * _hour),
      );

      expect(find.byKey(const Key('cook-stat-strip')), findsOneWidget);
      expect(find.text('TOTAL TIME'), findsOneWidget);
      expect(find.text('PEAK'), findsOneWidget);
      expect(find.text('READINGS'), findsOneWidget);
      expect(find.text('2h'), findsOneWidget);
    });

    testWidgets('a running cook counts up rather than claiming a total', (
      tester,
    ) async {
      await seedSamples();
      await pumpTall(tester, await seedCook());
      expect(find.text('SO FAR'), findsOneWidget);
      expect(find.text('TOTAL TIME'), findsNothing);
    });

    testWidgets('an empty cook shows an em dash for peak, never a zero', (
      tester,
    ) async {
      await pumpTall(tester, await seedCook(startUnixMs: now - _minute));
      expect(find.text('—'), findsWidgets);
      expect(find.text('0.0°'), findsNothing);
    });

    testWidgets('a cook with no target keeps the offer on screen', (
      tester,
    ) async {
      await seedSamples();
      await pumpTall(tester, await seedCook());
      expect(find.byKey(const Key('cook-set-target')), findsOneWidget);
      expect(find.textContaining('works retroactively'), findsOneWidget);
    });
  });

  testWidgets('the detail lays out at 360 dp and at 200% text', (tester) async {
    await seedSamples();
    await seedCook(name: 'Earlier one', startUnixMs: sessionStart - 8 * _hour);
    final cook = await seedCook(name: 'Overnight brisket, point and flat');

    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: CookDetailView(repo: repo, cook: cook)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // …and all the way down it, where the edit rows are.
    await tester.dragUntilVisible(
      find.byKey(const Key('cook-delete')),
      find.byKey(const Key('session-detail')),
      const Offset(0, -400),
    );
    expect(tester.takeException(), isNull);
  });

  group('creating a cook over readings that already exist', () {
    testWidgets('the sheet teaches the model, then makes one in a tap', (
      tester,
    ) async {
      await seedSamples();
      AppEnv.instance = fakeEnv(db: db);
      addTearDown(() => AppEnv.instance = null);

      // Wide, so opening the new cook is a selection rather than a push — a
      // push would need a router this test has no reason to build.
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: SmokeTheme.dark,
          home: const Scaffold(body: CooksTab()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cooks-create')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('create-cook-sheet')), findsOneWidget);
      expect(
        find.textContaining('Your bridge is already recording'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('create-cook-targets')), findsOneWidget);

      await tester.tap(find.byKey(const Key('create-cook-now')));
      await tester.pumpAndSettle();

      final cooks = await repo.cooks();
      expect(cooks, hasLength(1));
      expect(cooks.single.endUnixMs, isNull);
      expect(cooks.single.hasNoTarget, isTrue);
      // It opened straight onto the cook, where the start can be moved back.
      expect(find.byType(CookDetailView), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
