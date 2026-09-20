/// `/cooks` — "Show me my cooks, past and running" (16 §16.6, newapp §C.3).
///
/// The list's contract, tested at the level it is written at: [groupCooks] is
/// a pure function over plain values, [CooksListView] is stateless over what it
/// returns, and [loadCookSparkline] is an aggregate that must never page the
/// cache through Dart. Only the empty and no-bridge states need a real
/// environment, and they get one in memory.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/app_env.dart';
import 'package:smoke_bridge/data/local/database.dart';
import 'package:smoke_bridge/data/repos/cook_repository.dart';
import 'package:smoke_bridge/design/food_glyph.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/domain/plan/plan.dart';
import 'package:smoke_bridge/features/cooks/cook_list_model.dart';
import 'package:smoke_bridge/features/cooks/cook_list_view.dart';
import 'package:smoke_bridge/features/cooks/cooks_tab.dart';
import 'package:smoke_bridge/ui/probe/food_avatar.dart';
import 'package:smoke_bridge/ui/ui.dart';

import '../support/fake_env.dart';
import '../support/shapes.dart';

const int _hour = 3600 * 1000;
const int _day = 24 * _hour;

/// A Wednesday lunchtime, so "today" and "this week" are not the same bucket
/// and neither straddles a month boundary.
const int _now = 1784755815000;

CookAnnotation _cook({
  required int id,
  required int startUnixMs,
  int? endUnixMs,
  String name = '',
  bool favourite = false,
}) => CookAnnotation(
  id: id,
  bridgeId: 'b',
  name: name,
  startUnixMs: startUnixMs,
  endUnixMs: endUnixMs,
  createdUnixMs: startUnixMs,
  favourite: favourite,
);

CookListRow _row(
  CookAnnotation cook, {
  int count = 400,
  int? peakF10 = 2580,
  int probeCount = 3,
  bool line = true,
}) => CookListRow(
  entry: CookListEntry(
    cook: cook,
    summary: CookSummary(
      count: count,
      minT: count == 0 ? null : 0,
      maxT: count == 0 ? null : 6 * 3600,
      peakF10: peakF10,
    ),
  ),
  spark: CookSparkline(
    points: line
        ? [for (var i = 0; i < 20; i++) (t: i * 300, f: 240.0 + i)]
        : const [],
    probeCount: probeCount,
  ),
);

Widget _host(
  List<CookSection> sections, {
  int? selectedId,
  ValueChanged<CookAnnotation>? onOpen,
}) => MaterialApp(
  theme: SmokeTheme.dark,
  home: Scaffold(
    body: CooksListView(
      sections: sections,
      nowUnixMs: _now,
      selectedId: selectedId,
      onOpen: onOpen,
    ),
  ),
);

void main() {
  group('grouping', () {
    test('the open cook leads, and finished cooks read backwards', () {
      final rows = [
        _row(_cook(id: 1, startUnixMs: _now - 40 * _day, endUnixMs: _now)),
        _row(_cook(id: 2, startUnixMs: _now - 2 * _hour)),
        _row(
          _cook(
            id: 3,
            startUnixMs: _now - 3 * _day,
            endUnixMs: _now - 3 * _day + _hour,
          ),
        ),
        _row(_cook(id: 4, startUnixMs: _now + 6 * _hour)),
        _row(
          _cook(
            id: 5,
            startUnixMs: _now - 4 * _hour,
            endUnixMs: _now - 3 * _hour,
          ),
        ),
      ];

      final sections = groupCooks(rows, nowUnixMs: _now);
      expect(sections.map((s) => s.group), [
        CookGroup.scheduled,
        CookGroup.running,
        CookGroup.today,
        CookGroup.thisWeek,
        CookGroup.earlier,
      ]);
      expect(sections[1].rows.single.cook.id, 2);
      expect(sections[2].rows.single.cook.id, 5);
      expect(sections[3].rows.single.cook.id, 3);
      expect(sections[4].rows.single.cook.id, 1);
    });

    test('an empty bucket renders no label at all', () {
      final sections = groupCooks([
        _row(_cook(id: 1, startUnixMs: _now - 90 * _day, endUnixMs: _now)),
      ], nowUnixMs: _now);
      expect(sections.map((s) => s.group), [CookGroup.earlier]);
    });

    test('scheduled cooks read forwards — the soonest is next', () {
      final sections = groupCooks([
        _row(_cook(id: 1, startUnixMs: _now + 8 * _hour)),
        _row(_cook(id: 2, startUnixMs: _now + 2 * _hour)),
      ], nowUnixMs: _now);
      expect(sections.single.rows.map((r) => r.cook.id), [2, 1]);
    });
  });

  group('a row', () {
    testWidgets('states date, duration, peak and probe count', (tester) async {
      await tester.pumpWidget(
        _host(
          groupCooks([
            _row(
              _cook(
                id: 27,
                name: 'Brisket',
                startUnixMs: _now - 30 * _hour,
                endUnixMs: _now - 24 * _hour,
              ),
            ),
          ], nowUnixMs: _now),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('cook-row-27')), findsOneWidget);
      expect(find.text('Brisket'), findsOneWidget);
      expect(find.textContaining('6h'), findsOneWidget);
      expect(find.textContaining('peak 258.0°'), findsOneWidget);
      expect(find.textContaining('3 probes'), findsOneWidget);
      // The mark, in the pit hue, reaching the row.
      expect(find.byKey(const Key('cook-spark-27')), findsOneWidget);
    });

    testWidgets('an open cook reads "Recording", never "Cooking"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          groupCooks([
            _row(_cook(id: 27, name: 'Brisket', startUnixMs: _now - _hour)),
            _row(
              _cook(
                id: 26,
                name: 'Pork butt',
                startUnixMs: _now - 30 * _hour,
                endUnixMs: _now - 20 * _hour,
              ),
            ),
          ], nowUnixMs: _now),
        ),
      );
      await tester.pump();

      // The bridge records whether or not a cook was ever set up; an open cook
      // only means the app is calling this stretch by that name.
      expect(find.text('Recording'), findsOneWidget);
      expect(find.textContaining('Cooking'), findsNothing);
      expect(find.byKey(const Key('cooks-section-running')), findsOneWidget);
      expect(find.textContaining('so far'), findsOneWidget);
    });

    testWidgets('a scheduled cook says when it arms, not that it is running', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          groupCooks([
            _row(_cook(id: 9, name: 'Overnight', startUnixMs: _now + 3 * _hour)),
          ], nowUnixMs: _now),
        ),
      );
      await tester.pump();

      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.textContaining('starts in 3h'), findsOneWidget);
    });

    testWidgets('a cook with no readings says so — it never shows a zero', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          groupCooks([
            _row(
              _cook(id: 5, name: 'Just started', startUnixMs: _now - 60000),
              count: 0,
              peakF10: null,
              probeCount: 0,
              line: false,
            ),
          ], nowUnixMs: _now),
        ),
      );
      await tester.pump();

      expect(find.textContaining('no readings yet'), findsOneWidget);
      expect(find.textContaining('0 probes'), findsNothing);
      expect(find.textContaining('peak'), findsNothing);
      // A flat line is a claim that the temperature held steady, so an empty
      // cook draws no line at all.
      expect(find.byKey(const Key('cook-spark-5')), findsNothing);
    });

    testWidgets('readings with every probe unplugged is not "0 probes"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          groupCooks([
            _row(
              _cook(id: 6, name: 'Idle', startUnixMs: _now - 2 * _hour),
              peakF10: null,
              probeCount: 0,
              line: false,
            ),
          ], nowUnixMs: _now),
        ),
      );
      await tester.pump();

      expect(find.textContaining('no probe plugged in'), findsOneWidget);
    });
  });

  group('adaptive: tapping is a selection, not a navigation', () {
    testWidgets('the selected row is the only one marked', (tester) async {
      final sections = groupCooks([
        _row(
          _cook(
            id: 27,
            name: 'Brisket',
            startUnixMs: _now - 30 * _hour,
            endUnixMs: _now - 24 * _hour,
          ),
        ),
        _row(
          _cook(
            id: 28,
            name: 'Pork butt',
            startUnixMs: _now - 50 * _hour,
            endUnixMs: _now - 44 * _hour,
          ),
        ),
      ], nowUnixMs: _now);

      await tester.pumpWidget(_host(sections, selectedId: 27));
      await tester.pump();

      Color? fillOf(String name) => tester
          .widget<Container>(
            find.ancestor(
              of: find.text(name),
              matching: find.byType(Container),
            ).first,
          )
          .color;

      expect(fillOf('Brisket'), isNotNull);
      expect(fillOf('Pork butt'), isNull);
    });

    testWidgets('with no selection nothing is marked — the compact case', (
      tester,
    ) async {
      final sections = groupCooks([
        _row(
          _cook(
            id: 27,
            name: 'Brisket',
            startUnixMs: _now - 30 * _hour,
            endUnixMs: _now - 24 * _hour,
          ),
        ),
      ], nowUnixMs: _now);

      await tester.pumpWidget(_host(sections));
      await tester.pump();

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.text('Brisket'),
          matching: find.byType(Container),
        ).first,
      );
      expect(container.color, isNull);
    });

    testWidgets('tapping reports the cook, whatever the layout does next', (
      tester,
    ) async {
      final opened = <int>[];
      final sections = groupCooks([
        _row(_cook(id: 27, name: 'Brisket', startUnixMs: _now - _hour)),
      ], nowUnixMs: _now);

      await tester.pumpWidget(_host(sections, onOpen: (c) => opened.add(c.id)));
      await tester.pump();
      await tester.tap(find.text('Brisket'));
      await tester.pump();

      expect(opened, [27]);
    });
  });

  // ── §17.3 A / §17.5 — the identity channel on the history list ───────

  group('every row leads with what was cooked', () {
    testWidgets('the preset picks the glyph, the name is the fallback', (
      tester,
    ) async {
      final sections = groupCooks([
        _row(
          _cook(
            id: 1,
            name: 'Sunday ribs',
            startUnixMs: _now - 30 * _hour,
            endUnixMs: _now - 24 * _hour,
          ),
        ),
        _row(
          _cook(
            id: 2,
            name: 'Whatever',
            startUnixMs: _now - 50 * _hour,
            endUnixMs: _now - 44 * _hour,
          ).copyWith(presetId: 'poultry_whole'),
        ),
      ], nowUnixMs: _now);
      await tester.pumpWidget(_host(sections));
      await tester.pump(const Duration(milliseconds: 400));

      FoodAvatar avatarOf(int id) =>
          tester.widget<FoodAvatar>(find.byKey(Key('cook-avatar-$id')));
      expect(avatarOf(1).glyph, FoodGlyph.ribs);
      expect(avatarOf(2).glyph, FoodGlyph.wholeBird);
      // A cook nobody said anything about gets cutlery, not a guess.
      expect(avatarOf(1).announce, isTrue);
    });

    testWidgets('a finished cook is rich, the recording one has cooled', (
      tester,
    ) async {
      // §17.5, made visible. History claims no temperature, so it wears the
      // rich register; the cook being watched is the quiet one — and the
      // difference is never carried by saturation alone, because that section
      // also has an accent border and a "Recording" pill.
      final sections = groupCooks([
        _row(_cook(id: 1, name: 'Brisket', startUnixMs: _now - 2 * _hour)),
        _row(
          _cook(
            id: 2,
            name: 'Pork butt',
            startUnixMs: _now - 50 * _hour,
            endUnixMs: _now - 44 * _hour,
          ),
        ),
      ], nowUnixMs: _now);
      await tester.pumpWidget(_host(sections));
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester
            .widget<FoodAvatar>(find.byKey(const Key('cook-avatar-1')))
            .vivid,
        isFalse,
      );
      expect(
        tester
            .widget<FoodAvatar>(find.byKey(const Key('cook-avatar-2')))
            .vivid,
        isTrue,
      );
      expect(find.text('Recording'), findsOneWidget);
    });
  });

  testWidgets('it lays out at 360 dp and at 200% text', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: CooksListView(
              nowUnixMs: _now,
              sections: groupCooks([
                _row(
                  _cook(
                    id: 1,
                    name: 'Overnight brisket, point and flat',
                    startUnixMs: _now - 2 * _hour,
                    favourite: true,
                  ),
                ),
                _row(
                  _cook(
                    id: 2,
                    name: 'Pork butt',
                    startUnixMs: _now - 40 * _day,
                    endUnixMs: _now - 40 * _day + 9 * _hour,
                  ),
                ),
              ], nowUnixMs: _now),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  group('the sparkline aggregate', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('a 54-day cook comes back bucketed, with its probe count', () async {
      const bridgeId = 'b';
      const start = 1700000000000;
      final samples = syntheticCook(hours: 54 * 24, periodS: 300, probes: 3);
      expect(samples.length, greaterThan(15000));
      await db.sessionDao.upsertBridge(bridgeId);
      await db.sessionDao.upsertSessions(bridgeId, const [
        CookSession(id: 1, name: 's', startedUnixMs: start, samplePeriodS: 300),
      ]);
      await db.sampleDao.insertSamplesForSession(bridgeId, 1, samples);

      final cook = _cook(id: 1, startUnixMs: start);
      final repo = CookRepository(db, bridgeId: bridgeId);
      final summary = await repo.summaryFor(cook);
      final spark = await loadCookSparkline(db, cook, summary: summary);

      expect(spark.points.length, lessThanOrEqualTo(64));
      expect(spark.points.length, greaterThan(2));
      expect(spark.probeCount, 3);
      // Monotonic in x, so the mark reads left to right.
      for (var i = 1; i < spark.points.length; i++) {
        expect(spark.points[i].t, greaterThan(spark.points[i - 1].t));
      }
    });

    test('a cook with nothing recorded has no line and no probes', () async {
      const bridgeId = 'b';
      await db.sessionDao.upsertBridge(bridgeId);
      final cook = _cook(id: 1, startUnixMs: 1700000000000);
      final repo = CookRepository(db, bridgeId: bridgeId);
      final spark = await loadCookSparkline(
        db,
        cook,
        summary: await repo.summaryFor(cook),
      );
      expect(spark.points, isEmpty);
      expect(spark.hasLine, isFalse);
      expect(spark.probeCount, 0);
    });

    test('every probe detached still counts as no probes, not one', () async {
      const bridgeId = 'b';
      const start = 1700000000000;
      await db.sessionDao.upsertBridge(bridgeId);
      await db.sessionDao.upsertSessions(bridgeId, const [
        CookSession(id: 1, name: 's', startedUnixMs: start),
      ]);
      await db.sampleDao.insertSamplesForSession(
        bridgeId,
        1,
        allDetached(hours: 2),
      );

      final cook = _cook(id: 1, startUnixMs: start);
      final repo = CookRepository(db, bridgeId: bridgeId);
      final spark = await loadCookSparkline(
        db,
        cook,
        summary: await repo.summaryFor(cook),
      );
      expect(spark.probeCount, 0);
      expect(spark.points, isEmpty);
    });
  });

  group('the screen states', () {
    testWidgets('no bridge is not "no cooks" — it names the real situation', (
      tester,
    ) async {
      AppEnv.instance = fakeEnv();
      addTearDown(() => AppEnv.instance = null);

      await tester.pumpWidget(
        const MaterialApp(
          theme: null,
          home: Scaffold(body: CooksTab()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cooks-no-bridge')), findsOneWidget);
      expect(find.byKey(const Key('cooks-empty')), findsNothing);
      // The "+" cannot create a cook against a bridge that does not exist, so
      // it is disabled rather than dead.
      final add = tester.widget<IconButton>(
        find.byKey(const Key('cooks-create')),
      );
      expect(add.onPressed, isNull);
    });

    testWidgets('a known bridge with no cooks reinforces the model', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.sessionDao.upsertBridge('b');
      AppEnv.instance = fakeEnv(db: db);
      addTearDown(() => AppEnv.instance = null);

      await tester.pumpWidget(
        MaterialApp(theme: SmokeTheme.dark, home: const Scaffold(body: CooksTab())),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cooks-empty')), findsOneWidget);
      expect(
        find.textContaining('Your bridge is still recording'),
        findsOneWidget,
      );
      expect(
        find.textContaining('name a stretch that already happened'),
        findsOneWidget,
      );
      // Exactly one action on an empty state (§16.4).
      expect(
        find.descendant(
          of: find.byType(EmptyState),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('a cook written elsewhere appears without a relaunch', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.sessionDao.upsertBridge('b');
      AppEnv.instance = fakeEnv(db: db);
      addTearDown(() => AppEnv.instance = null);

      await tester.pumpWidget(
        MaterialApp(theme: SmokeTheme.dark, home: const Scaffold(body: CooksTab())),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cooks-empty')), findsOneWidget);

      // What the background monitor, or a split on another screen, does.
      await db.cookDao.save(
        _cook(id: 0, name: 'Written elsewhere', startUnixMs: _now - _hour),
      );
      await tester.pumpAndSettle();

      expect(find.text('Written elsewhere'), findsOneWidget);
      expect(find.byKey(const Key('cooks-empty')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
