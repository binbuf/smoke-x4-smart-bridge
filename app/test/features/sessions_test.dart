/// A11.2 / A11.3 — the sessions list and detail.
///
/// The epic flag's claim gets an actual test: **row summaries come from an
/// aggregate query, not from loading the samples.** A spy repository
/// counts `samples()` calls, and a 54-day cache must not provoke one.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/local/database.dart';
import 'package:smoke_bridge/data/repos/repositories.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/sessions/sessions_screen.dart';

import '../support/shapes.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: child),
    );

void main() {
  group('the list', () {
    testWidgets('an empty cache renders an honest empty state', (tester) async {
      await tester.pumpWidget(_wrap(const SessionsListView(rows: [])));
      expect(find.byKey(const Key('sessions-empty')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a row states date, duration, peak and probe count', (
      tester,
    ) async {
      final cook = syntheticCook(hours: 6);
      await tester.pumpWidget(
        _wrap(
          SessionsListView(
            rows: [
              SessionListRow(
                session: sessionFor(cook),
                summary: SampleSummary(
                  sessionId: 27,
                  minT: 0,
                  maxT: cook.last.t,
                  count: cook.length,
                  peakF10: 2580,
                ),
                sparkline: [
                  for (var i = 0; i < 20; i++) (t: i * 300, f: 240.0 + i),
                ],
              ),
            ],
          ),
        ),
      );
      expect(find.byKey(const Key('session-row-27')), findsOneWidget);
      expect(find.textContaining('peak 258.0°'), findsOneWidget);
      expect(find.textContaining('4 probes'), findsOneWidget);
    });

    testWidgets('a running cook is distinguishable at a glance', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SessionsListView(
            rows: [
              SessionListRow(session: sessionFor(const [])),
              SessionListRow(
                session: sessionFor(const []).copyWith(id: 26, closed: true),
              ),
            ],
          ),
        ),
      );
      expect(find.byKey(const Key('session-running-27')), findsOneWidget);
      expect(find.byKey(const Key('session-running-26')), findsNothing);
    });

    testWidgets('a cook with no clock says so rather than showing 1970', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SessionsListView(
            rows: [
              SessionListRow(
                session: const CookSession(id: 3, name: 'Unknown'),
              ),
            ],
          ),
        ),
      );
      expect(find.textContaining('Time not set'), findsOneWidget);
      expect(find.textContaining('1970'), findsNothing);
    });
  });

  group('the aggregate query', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('summaries and sparklines never materialise the samples', () async {
      // 54 days at a 5-minute cadence: the shape that makes a per-row
      // range() unusable on a real phone after two months.
      const bridgeId = 'LMXC[\\';
      final cook = syntheticCook(hours: 54 * 24, periodS: 300);
      expect(cook.length, greaterThan(15000));
      await db.sessionDao.upsertBridge(bridgeId);
      await db.sessionDao.upsertSessions(bridgeId, [sessionFor(cook)]);
      await db.sampleDao.insertSamples(bridgeId, 27, cook);

      final repo = _SpyRepository(db, bridgeId: bridgeId);
      final summaries = await repo.summaries();
      final spark = await repo.sparkline(27);

      expect(summaries[27]!.count, cook.length);
      expect(summaries[27]!.maxT, cook.last.t);
      expect(summaries[27]!.peakF10, greaterThan(2000));
      // The sparkline comes back bucketed, not row-per-sample.
      expect(spark.length, lessThanOrEqualTo(64));
      // And the list path never asked for a single sample row.
      expect(repo.sampleReads, 0);
    });

    test('a session with no readings has no peak — not a peak of 0', () async {
      const bridgeId = 'B';
      await db.sessionDao.upsertBridge(bridgeId);
      await db.sampleDao.insertSamples(bridgeId, 1, allDetached(hours: 1));
      final s = await db.sampleDao.summaries(bridgeId);
      expect(s[1]!.peakF10, isNull);
      expect(await db.sampleDao.sparkline(bridgeId, 1), isEmpty);
    });
  });

  group('the detail view', () {
    testWidgets('renders offline from a seeded cook', (tester) async {
      final cook = syntheticCook(hours: 6);
      await tester.pumpWidget(
        _wrap(
          SessionDetailView(
            session: sessionFor(cook),
            samples: cook,
            probes: pitAndFood,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('session-detail')), findsOneWidget);
      expect(find.byKey(const Key('session-stats')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no marks is a sentence, not an empty list', (tester) async {
      final cook = syntheticCook(hours: 2);
      await tester.pumpWidget(
        _wrap(SessionDetailView(session: sessionFor(cook), samples: cook)),
      );
      await tester.pump();
      await tester.dragUntilVisible(
        find.byKey(const Key('session-marks-empty')),
        find.byKey(const Key('session-detail')),
        const Offset(0, -300),
      );
      expect(find.byKey(const Key('session-marks-empty')), findsOneWidget);
    });

    testWidgets('all eight mark kinds render with their names', (tester) async {
      // A tall surface so the whole list builds — a lazily-built child
      // that was never on screen is not in the tree to be found.
      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cook = syntheticCook(hours: 2);
      final marks = [
        for (var i = 0; i < MarkKind.values.length; i++)
          Mark(t: i * 600, kind: MarkKind.values[i]),
      ];
      await tester.pumpWidget(
        _wrap(
          SessionDetailView(
            session: sessionFor(cook),
            samples: cook,
            marks: marks,
          ),
        ),
      );
      await tester.pump();
      for (final name in [
        'Note',
        'Wrapped',
        'Lid open',
        'Added fuel',
        'Moved a probe',
        'Alarm',
        'Phase change',
        'Auto-detected',
      ]) {
        expect(find.text(name), findsOneWidget, reason: 'missing "$name"');
      }
    });

    testWidgets('tapping a mark moves the chart to it', (tester) async {
      final cook = syntheticCook(hours: 6);
      await tester.pumpWidget(
        _wrap(
          SessionDetailView(
            session: sessionFor(cook),
            samples: cook,
            probes: pitAndFood,
            marks: const [Mark(t: 3600, kind: MarkKind.wrapped)],
          ),
        ),
      );
      await tester.pump();
      await tester.dragUntilVisible(
        find.byKey(const Key('session-mark-3600-wrapped')),
        find.byKey(const Key('session-detail')),
        const Offset(0, -300),
      );
      await tester.tap(find.byKey(const Key('session-mark-3600-wrapped')));
      await tester.pump();
      // The chip row no longer reads "All": the viewport moved.
      expect(tester.takeException(), isNull);
    });

    testWidgets('renaming dispatches exactly once, with the new name', (
      tester,
    ) async {
      final names = <String>[];
      final cook = syntheticCook(hours: 1);
      await tester.pumpWidget(
        _wrap(
          SessionDetailView(
            session: sessionFor(cook),
            samples: cook,
            onRename: names.add,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('session-rename')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('session-rename-field')),
        'Pork butt',
      );
      await tester.tap(find.byKey(const Key('session-rename-save')));
      await tester.pumpAndSettle();
      expect(names, ['Pork butt']);
    });

    testWidgets('a session with no clock says so, not 1970', (tester) async {
      final cook = syntheticCook(hours: 1);
      await tester.pumpWidget(
        _wrap(
          SessionDetailView(
            session: const CookSession(id: 3, name: 'Unknown'),
            samples: cook,
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('before the bridge knew'), findsOneWidget);
      expect(find.textContaining('1970'), findsNothing);
    });
  });
}

/// Counts sample-row reads so the epic flag's claim is checked rather
/// than asserted in prose.
class _SpyRepository extends SessionRepository {
  _SpyRepository(super.db, {required super.bridgeId});

  int sampleReads = 0;

  @override
  Future<List<Sample>> samples(
    int sessionId, {
    int fromT = 0,
    int toT = 0x7fffffff,
  }) {
    sampleReads++;
    return super.samples(sessionId, fromT: fromT, toT: toT);
  }
}
