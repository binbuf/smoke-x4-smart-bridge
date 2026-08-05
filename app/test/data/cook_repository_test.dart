/// The cook-annotation repository against a real (in-memory) drift database
/// (newapp §D.1–§D.3, §D.6, §E.5), plus the v1→v2 migration.
///
/// The claim under test is the one the whole reframe rests on: **every cook
/// edit is metadata, and the recording is never touched.** Each verb here
/// asserts the sample count before and after.
library;

// `drift/drift.dart` also exports an `isNull`, which collides with matcher's.
// The tests only need the connection type, so the import is narrowed.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/local/database.dart';
import 'package:smoke_bridge/data/repos/cook_repository.dart';
import 'package:smoke_bridge/domain/analysis/gaps.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/domain/plan/plan.dart';

const int _hour = 3600 * 1000;
const int _epoch = 1700000000000;

void main() {
  late AppDatabase db;
  late CookRepository repo;
  var fakeNow = _epoch + 20 * _hour;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = CookRepository(
      db,
      bridgeId: 'bridge-a',
      now: () => DateTime.fromMillisecondsSinceEpoch(fakeNow),
    );
    await db.sessionDao.upsertBridge('bridge-a');
    await db.sessionDao.upsertSessions('bridge-a', const [
      CookSession(
        id: 1,
        name: 'Session 1',
        startedUnixMs: _epoch,
        samplePeriodS: 30,
        sampleCount: 100,
      ),
    ]);
    // 20 hours of samples at 30 s, clocked from _epoch.
    await db.sampleDao.insertSamples(
      'bridge-a',
      1,
      [
        for (var t = 0; t <= 20 * 3600; t += 30)
          Sample(t: t, tempsF10: [2400, 1000 + t ~/ 60, null, null]),
      ],
      sessionStartUnixMs: _epoch,
    );
  });

  tearDown(() => db.close());

  Future<int> sampleCount() async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM samples').getSingle())
          .read<int>('n');

  CookPlan brisketPlan() => CookPlan(
    presetId: 'beef_brisket',
    title: 'Brisket',
    hazard: HazardClass.wholeMuscleRedMeat,
    doneness: 'Tender',
    probes: [
      PlanProbe(jack: 1, isPit: true, name: 'Pit'),
      PlanProbe(
        jack: 2,
        isPit: false,
        name: 'Brisket',
        targetF10: 2030,
        pullF10: 1950,
      ),
    ],
  );

  group('membership is a wall-clock range, not a foreign key', () {
    test('a cook covers exactly the samples inside its bounds', () async {
      final cook = await repo.startFromPlan(
        brisketPlan()..startedUnixMs = _epoch + 2 * _hour,
      );
      final bounded = await repo.end(cook, atUnixMs: _epoch + 5 * _hour);
      final samples = await repo.samplesFor(bounded);

      expect(samples.first.t, 2 * 3600);
      // End is exclusive, so the sample exactly at +5 h belongs to nothing.
      expect(samples.last.t, 5 * 3600 - 30);
    });

    test('a running cook runs to the end of the recording', () async {
      final cook = await repo.startFromPlan(
        brisketPlan()..startedUnixMs = _epoch + 19 * _hour,
      );
      final samples = await repo.samplesFor(cook);
      expect(samples, isNotEmpty);
      expect(samples.last.t, 20 * 3600);
    });

    test('a cook can span a range that predates the app being opened', () async {
      final cook = await repo.startFromPlan(
        brisketPlan()..startedUnixMs = _epoch,
      );
      expect((await repo.samplesFor(cook)).length, greaterThan(2000));
    });
  });

  group('§D.3 — backdating moves metadata and nothing else', () {
    test('the sample table is untouched, and the span grows', () async {
      final before = await sampleCount();
      var cook = await repo.startFromPlan(
        brisketPlan()..startedUnixMs = _epoch + 10 * _hour,
      );
      final narrow = (await repo.samplesFor(cook)).length;

      cook = await repo.backdate(cook, _epoch + 2 * _hour);

      expect(await sampleCount(), before, reason: 'metadata only');
      expect((await repo.samplesFor(cook)).length, greaterThan(narrow));
      expect(cook.startUnixMs, _epoch + 2 * _hour);
    });

    test('the anchors offered come off the recording', () async {
      // Plug probe 3 in partway through, which should be offered as an anchor.
      await db.sampleDao.insertSamples(
        'bridge-a',
        1,
        [
          Sample(t: 4 * 3600, tempsF10: const [2400, 1500, 950, null]),
        ],
        sessionStartUnixMs: _epoch,
      );
      final cook = await repo.startFromPlan(
        brisketPlan()..startedUnixMs = _epoch + 6 * _hour,
      );
      final anchors = await repo.anchorsFor(cook);
      expect(anchors, isNotEmpty);
      expect(
        anchors.any((a) => a.kind == AnchorKind.probeInserted),
        isTrue,
      );
    });
  });

  group('§C.4 — split and merge are metadata', () {
    test('split leaves two cooks and the same samples', () async {
      final before = await sampleCount();
      final cook = await repo.startFromPlan(
        brisketPlan()..startedUnixMs = _epoch,
      );
      final bounded = await repo.end(cook, atUnixMs: _epoch + 10 * _hour);

      final (first, second) = await repo.split(bounded, _epoch + 4 * _hour);

      expect(await sampleCount(), before);
      expect((await repo.cooks()).length, 2);
      expect(first.id, isNot(second.id));
      expect(second.id, greaterThan(0));

      final firstSamples = await repo.samplesFor(first);
      final secondSamples = await repo.samplesFor(second);
      expect(firstSamples.last.t, lessThan(4 * 3600));
      expect(secondSamples.first.t, 4 * 3600);
      // Nothing lost, nothing double-counted.
      expect(
        firstSamples.length + secondSamples.length,
        (await repo.samplesFor(bounded)).length,
      );
    });

    test('merge folds two back into one and drops the extra row', () async {
      final before = await sampleCount();
      final cook = await repo.startFromPlan(
        brisketPlan()..startedUnixMs = _epoch,
      );
      final bounded = await repo.end(cook, atUnixMs: _epoch + 10 * _hour);
      final (first, second) = await repo.split(bounded, _epoch + 4 * _hour);

      final merged = await repo.merge(first, second);

      expect(await sampleCount(), before);
      expect((await repo.cooks()).length, 1);
      expect(merged.startUnixMs, _epoch);
      expect(merged.endUnixMs, _epoch + 10 * _hour);
    });
  });

  group('deleting a cook does not stop the recording', () {
    test('the samples survive the annotation', () async {
      final before = await sampleCount();
      final cook = await repo.startFromPlan(brisketPlan());
      await repo.deleteCook(cook.id);

      expect(await repo.cooks(), isEmpty);
      expect(
        await sampleCount(),
        before,
        reason:
            'the cost sheet promises the readings keep going — a cascade here '
            'would make that copy a lie',
      );
    });

    test('its probe roles go with it', () async {
      final cook = await repo.startFromPlan(brisketPlan());
      await repo.deleteCook(cook.id);
      final rows = await db
          .customSelect('SELECT COUNT(*) AS n FROM cook_probe_roles')
          .getSingle();
      expect(rows.read<int>('n'), 0);
    });
  });

  group('§D.3.2 — targets can arrive later, and the gate still runs', () {
    test('a targetless cook accepts a safe target', () async {
      final plan = CookPlan(
        presetId: 'custom',
        title: 'Cook',
        hazard: HazardClass.poultry,
        doneness: '',
        probes: [
          PlanProbe(jack: 1, isPit: true, name: 'Pit'),
          PlanProbe(jack: 2, isPit: false, name: 'Chicken'),
        ],
      );
      final cook = await repo.startFromPlan(plan);
      expect(cook.hasNoTarget, isTrue);

      final targeted = await repo.retarget(cook, [
        const CookProbeRole(jack: 1, role: ProbeRole.pit),
        const CookProbeRole(
          jack: 2,
          role: ProbeRole.food,
          targetF10: 1650,
          hazard: HazardClass.poultry,
        ),
      ]);
      expect(targeted.hasNoTarget, isFalse);
      expect((await repo.cook(cook.id))!.roleFor(2)?.targetF10, 1650);
    });

    test('an unsafe retarget is refused and nothing is written', () async {
      final cook = await repo.startFromPlan(brisketPlan());
      await expectLater(
        repo.retarget(cook, [
          const CookProbeRole(
            jack: 2,
            role: ProbeRole.food,
            targetF10: 1400,
            hazard: HazardClass.poultry,
          ),
        ]),
        throwsArgumentError,
      );
      expect((await repo.cook(cook.id))!.roleFor(2)?.targetF10, 2030);
    });
  });

  group('§D.6 — repeat', () {
    test('copies the targets and starts fresh', () async {
      final cook = await repo.startFromPlan(brisketPlan());
      final finished = await repo.end(cook, atUnixMs: _epoch + 8 * _hour);
      fakeNow = _epoch + 100 * _hour;

      final again = await repo.repeat(finished);

      expect(again.id, isNot(finished.id));
      expect(again.startUnixMs, _epoch + 100 * _hour);
      expect(again.endUnixMs, isNull);
      expect(again.roleFor(2)?.targetF10, 2030);
    });
  });

  group('running() is the open annotation, not the scheduled one', () {
    test('a future start is not yet running', () async {
      await repo.startFromPlan(
        brisketPlan()..startedUnixMs = fakeNow + 5 * _hour,
      );
      expect(await repo.running(), isNull);
    });

    test('an open cook that has started is', () async {
      final cook = await repo.startFromPlan(
        brisketPlan()..startedUnixMs = fakeNow - _hour,
      );
      expect((await repo.running())?.id, cook.id);
    });

    test('ending it clears running', () async {
      final cook = await repo.startFromPlan(
        brisketPlan()..startedUnixMs = fakeNow - _hour,
      );
      await repo.end(cook);
      expect(await repo.running(), isNull);
    });
  });

  group('§E.5 — gaps are reported, and the permanent ones are distinguished',
      () {
    test('a recorded rollover survives and reads as permanent', () async {
      await db.syncStateDao.recordGap(
        'bridge-a',
        1,
        fromT: 3600,
        toT: 7200,
        reason: GapReason.bufferRollover,
        atUnixMs: fakeNow,
      );
      final cook = await repo.startFromPlan(
        brisketPlan()..startedUnixMs = _epoch,
      );
      final gaps = await repo.gapsFor(cook);
      expect(gaps.where((g) => g.reason.isPermanent), hasLength(1));
    });

    test('a connectivity gap the sync filled is cleared', () async {
      await db.syncStateDao.recordGap(
        'bridge-a',
        1,
        fromT: 3600,
        toT: 7200,
        reason: GapReason.connectivity,
        atUnixMs: fakeNow,
      );
      // The samples between are already present from setUp.
      await db.syncStateDao.clearFilledConnectivityGaps('bridge-a', 1);
      final left = await db.syncStateDao.forBridgeSession('bridge-a', 1);
      expect(left, isEmpty);
    });

    test('a rollover is never cleared by a later sync', () async {
      await db.syncStateDao.recordGap(
        'bridge-a',
        1,
        fromT: 3600,
        toT: 7200,
        reason: GapReason.bufferRollover,
        atUnixMs: fakeNow,
      );
      await db.syncStateDao.clearFilledConnectivityGaps('bridge-a', 1);
      expect(
        await db.syncStateDao.forBridgeSession('bridge-a', 1),
        hasLength(1),
        reason: 'nobody has that data any more; filling it in is impossible',
      );
    });
  });

  group('the sync high-water mark is persisted', () {
    test('record and read back', () async {
      await db.syncStateDao.record(
        'bridge-a',
        1,
        highWaterT: 500,
        deviceMinT: 100,
        deviceMaxT: 900,
        atUnixMs: fakeNow,
      );
      final row = await db.syncStateDao.forSession('bridge-a', 1);
      expect(row?.highWaterT, 500);
      expect(row?.deviceMinT, 100);
      expect(row?.deviceMaxT, 900);
    });

    test('recording again updates rather than duplicating', () async {
      await db.syncStateDao.record('bridge-a', 1, highWaterT: 500);
      await db.syncStateDao.record('bridge-a', 1, highWaterT: 900);
      expect((await db.syncStateDao.forSession('bridge-a', 1))?.highWaterT, 900);
    });
  });

  group('the clockless bridge falls back to its session anchor', () {
    test('samples with no wall clock are still reachable', () async {
      await db.sessionDao.upsertSessions('bridge-a', const [
        CookSession(id: 2, samplePeriodS: 30, sampleCount: 10),
      ]);
      await db.sampleDao.insertSamples('bridge-a', 2, [
        for (var t = 0; t < 300; t += 30)
          Sample(t: t, tempsF10: const [2400, null, null, null]),
      ]);

      final id = await db.cookDao.save(
        const CookAnnotation(
          id: 0,
          bridgeId: 'bridge-a',
          startUnixMs: 0,
          createdUnixMs: 0,
          anchorSessionId: 2,
        ),
      );
      final cook = (await repo.cook(id))!;
      final samples = await repo.samplesFor(cook);
      expect(samples, hasLength(10));
      expect(
        (await db.customSelect(
          'SELECT COUNT(*) AS n FROM samples '
          'WHERE session_id = 2 AND unix_ms IS NOT NULL',
        ).getSingle()).read<int>('n'),
        0,
        reason: 'a bridge with no clock must not be given an invented one',
      );
    });
  });
}
