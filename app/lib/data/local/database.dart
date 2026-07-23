/// The drift database: schema, migrations, and DAOs (A4.1, A4.2 — design
/// 08 §8.5).
///
/// The app owns a full copy of every cook it has seen. Charts read from
/// here, never from the network, so scrolling history works on the couch
/// with the bridge unplugged. Per D12 the schema stays multi-bridge capable
/// (`bridgeId` everywhere) even though the v1 UI is single-device — the
/// plumbing costs nothing to keep general.
///
/// A detached probe stores as NULL, never 0 — the same invariant the wire
/// format and the firmware hold (04 §4.2).
library;

import 'package:drift/drift.dart';

import '../../domain/entities/entities.dart';

part 'database.g.dart';

/// Bridges this app has talked to. `id` is the base station device id.
@DataClassName('BridgeRow')
class Bridges extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withDefault(const Constant(''))();
  IntColumn get lastSeenUnixMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SessionRow')
class Sessions extends Table {
  TextColumn get bridgeId => text()();
  IntColumn get sessionId => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  IntColumn get startedUnixMs => integer().nullable()();
  IntColumn get endedUnixMs => integer().nullable()();
  IntColumn get samplePeriodS => integer().withDefault(const Constant(30))();
  IntColumn get sampleCount => integer().withDefault(const Constant(0))();
  IntColumn get numProbes => integer().withDefault(const Constant(4))();
  BoolColumn get closed => boolean().withDefault(const Constant(false))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {bridgeId, sessionId};
}

/// One row per sample; `p1..p4` are tenths °F, NULL = detached/invalid.
@DataClassName('SampleRow')
class Samples extends Table {
  TextColumn get bridgeId => text()();
  IntColumn get sessionId => integer()();

  /// Seconds since session start — monotonic, gap-preserving.
  IntColumn get t => integer()();
  IntColumn get p1 => integer().nullable()();
  IntColumn get p2 => integer().nullable()();
  IntColumn get p3 => integer().nullable()();
  IntColumn get p4 => integer().nullable()();
  IntColumn get flags => integer().withDefault(const Constant(0))();
  IntColumn get rssi => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {bridgeId, sessionId, t};
}

@DataClassName('MarkRow')
class Marks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get bridgeId => text()();
  IntColumn get sessionId => integer()();
  IntColumn get t => integer()();
  IntColumn get kind => integer()();
  IntColumn get probe => integer().withDefault(const Constant(0))();
  TextColumn get text_ =>
      text().named('text').withDefault(const Constant(''))();
}

@DataClassName('AlarmLogRow')
class AlarmLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get bridgeId => text()();
  IntColumn get unixMs => integer().nullable()();
  TextColumn get rule => text()();
  IntColumn get probe => integer().withDefault(const Constant(0))();
  IntColumn get valueF10 => integer().nullable()();
  TextColumn get action => text()();
}

@DriftDatabase(
  tables: [Bridges, Sessions, Samples, Marks, AlarmLog],
  daos: [SessionDao, SampleDao, MarkDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (m) => m.createAll());
}

/// Sessions: reconcile upserts from sync, watchers for the UI.
@DriftAccessor(tables: [Sessions, Bridges])
class SessionDao extends DatabaseAccessor<AppDatabase> with _$SessionDaoMixin {
  SessionDao(super.db);

  Future<void> upsertBridge(String bridgeId, {int? lastSeenUnixMs}) =>
      into(bridges).insertOnConflictUpdate(
        BridgesCompanion.insert(
          id: bridgeId,
          lastSeenUnixMs: Value(lastSeenUnixMs),
        ),
      );

  /// Reconciles the remote list. Deliberately upsert-only: a session the
  /// device has purged stays in the cache — the app owns a full copy of
  /// every cook it has SEEN, which is the whole point of the cache.
  Future<void> upsertSessions(String bridgeId, List<CookSession> remote) =>
      batch((b) {
        for (final s in remote) {
          b.insert(
            sessions,
            SessionsCompanion.insert(
              bridgeId: bridgeId,
              sessionId: s.id,
              name: Value(s.name),
              startedUnixMs: Value(s.startedUnixMs),
              endedUnixMs: Value(s.endedUnixMs),
              samplePeriodS: Value(s.samplePeriodS),
              sampleCount: Value(s.sampleCount),
              numProbes: Value(s.numProbes),
              closed: Value(s.closed),
              pinned: Value(s.pinned),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });

  Future<List<CookSession>> allSessions(String bridgeId) async {
    final rows =
        await (select(sessions)
              ..where((s) => s.bridgeId.equals(bridgeId))
              ..orderBy([(s) => OrderingTerm.desc(s.sessionId)]))
            .get();
    return rows.map(sessionFromRow).toList();
  }

  Stream<List<CookSession>> watchSessions(String bridgeId) =>
      (select(sessions)
            ..where((s) => s.bridgeId.equals(bridgeId))
            ..orderBy([(s) => OrderingTerm.desc(s.sessionId)]))
          .watch()
          .map((rows) => rows.map(sessionFromRow).toList());
}

/// Samples: batched inserts (the sync hot path) and range reads (the
/// chart hot path). The interface deals in domain [Sample]s so swapping
/// the storage to per-session BLOB chunks — exactly the wire format —
/// would never reach the repository layer (the A4.2 escape hatch).
@DriftAccessor(tables: [Samples])
class SampleDao extends DatabaseAccessor<AppDatabase> with _$SampleDaoMixin {
  SampleDao(super.db);

  /// One `batch()` inside one transaction: 2,880 rows (a 24 h cook) must
  /// land within the frame budget. insertOrReplace makes retries and
  /// mid-sync restarts idempotent.
  Future<int> insertSamples(
    String bridgeId,
    int sessionId,
    List<Sample> list,
  ) async {
    await batch((b) {
      for (final s in list) {
        b.insert(
          samples,
          SamplesCompanion.insert(
            bridgeId: bridgeId,
            sessionId: sessionId,
            t: s.t,
            p1: Value(s.tempsF10[0]),
            p2: Value(s.tempsF10.length > 1 ? s.tempsF10[1] : null),
            p3: Value(s.tempsF10.length > 2 ? s.tempsF10[2] : null),
            p4: Value(s.tempsF10.length > 3 ? s.tempsF10[3] : null),
            flags: Value(_flagsOf(s)),
            rssi: Value(s.rssi),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
    return list.length;
  }

  /// Highest cached `t` for a session, or null when nothing is cached —
  /// the delta-sync cursor (08 §8.5).
  Future<int?> maxT(String bridgeId, int sessionId) async {
    final maxExpr = samples.t.max();
    final q = selectOnly(samples)
      ..addColumns([maxExpr])
      ..where(
        samples.bridgeId.equals(bridgeId) & samples.sessionId.equals(sessionId),
      );
    final row = await q.getSingle();
    return row.read(maxExpr);
  }

  Future<int> count(String bridgeId, int sessionId) async {
    final countExpr = samples.t.count();
    final q = selectOnly(samples)
      ..addColumns([countExpr])
      ..where(
        samples.bridgeId.equals(bridgeId) & samples.sessionId.equals(sessionId),
      );
    final row = await q.getSingle();
    return row.read(countExpr) ?? 0;
  }

  Future<List<Sample>> range(
    String bridgeId,
    int sessionId, {
    int fromT = 0,
    int toT = 0x7fffffff,
  }) async {
    final rows =
        await (select(samples)
              ..where(
                (s) =>
                    s.bridgeId.equals(bridgeId) &
                    s.sessionId.equals(sessionId) &
                    s.t.isBetweenValues(fromT, toT),
              )
              ..orderBy([(s) => OrderingTerm.asc(s.t)]))
            .get();
    return rows.map(sampleFromRow).toList();
  }
}

@DriftAccessor(tables: [Marks])
class MarkDao extends DatabaseAccessor<AppDatabase> with _$MarkDaoMixin {
  MarkDao(super.db);

  Future<void> replaceMarks(String bridgeId, int sessionId, List<Mark> list) =>
      transaction(() async {
        await (delete(marks)..where(
              (m) =>
                  m.bridgeId.equals(bridgeId) & m.sessionId.equals(sessionId),
            ))
            .go();
        await batch((b) {
          for (final m in list) {
            b.insert(
              marks,
              MarksCompanion.insert(
                bridgeId: bridgeId,
                sessionId: sessionId,
                t: m.t,
                kind: m.kind.index,
                probe: Value(m.probe),
                text_: Value(m.text),
              ),
            );
          }
        });
      });

  Future<List<Mark>> forSession(String bridgeId, int sessionId) async {
    final rows =
        await (select(marks)
              ..where(
                (m) =>
                    m.bridgeId.equals(bridgeId) & m.sessionId.equals(sessionId),
              )
              ..orderBy([(m) => OrderingTerm.asc(m.t)]))
            .get();
    return rows
        .map(
          (r) => Mark(
            t: r.t,
            kind: MarkKind.values[r.kind],
            probe: r.probe,
            text: r.text_,
          ),
        )
        .toList();
  }
}

// ── Row ↔ domain mapping ──────────────────────────────────────────────────

int _flagsOf(Sample s) =>
    (s.billows ? 0x10 : 0) |
    (s.newAlarm ? 0x20 : 0) |
    (s.sourceCelsius ? 0x40 : 0);

Sample sampleFromRow(SampleRow r) => Sample(
  t: r.t,
  tempsF10: [r.p1, r.p2, r.p3, r.p4],
  billows: r.flags & 0x10 != 0,
  newAlarm: r.flags & 0x20 != 0,
  sourceCelsius: r.flags & 0x40 != 0,
  rssi: r.rssi,
);

CookSession sessionFromRow(SessionRow r) => CookSession(
  id: r.sessionId,
  name: r.name,
  startedUnixMs: r.startedUnixMs,
  endedUnixMs: r.endedUnixMs,
  samplePeriodS: r.samplePeriodS,
  sampleCount: r.sampleCount,
  numProbes: r.numProbes,
  closed: r.closed,
  pinned: r.pinned,
);
