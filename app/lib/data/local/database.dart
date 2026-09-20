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

import '../../domain/alarms/alarm_rule.dart';
import '../../domain/analysis/gaps.dart';
import '../../domain/entities/entities.dart';
import '../../domain/plan/cook_annotation.dart';
import '../../domain/plan/hazard.dart';

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
///
/// **The key stays device-authoritative** (`bridge, session, t`), which is what
/// makes the delta-sync upsert idempotent and is the rule §E.7 states: never
/// mint phone-side sample ids. [unixMs] is a *projection* of that key onto the
/// wall clock, not a second identity — it exists so a cook annotation can
/// resolve its membership with a range query instead of owning a foreign key on
/// every sample (see `cook_annotation.dart` for why that matters).
@DataClassName('SampleRow')
@TableIndex(name: 'idx_samples_unix', columns: {#bridgeId, #unixMs})
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

  /// v2 — `session.startedUnixMs + t * 1000`, or **NULL when the bridge had no
  /// clock**. Null is a first-class answer here: §E.7 forbids inventing wall
  /// times for a device whose RTC was never set, and a cook over such a session
  /// pins itself with `Cooks.anchorSessionId` instead.
  IntColumn get unixMs => integer().nullable()();

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

  /// v2 — this mark is offerable as a cook start anchor (§D.2). Set on marks
  /// the firmware placed for a detected event, so "re-anchor the start" can
  /// list them without re-deriving the detection on the phone.
  BoolColumn get autoAnchor => boolean().withDefault(const Constant(false))();
}

// ── v2: cooks as annotations over the recording (§D.1–§D.3) ─────────────

/// A named, time-bounded, targeted window over the bridge's continuous
/// recording. See `domain/plan/cook_annotation.dart` for the model and why the
/// membership is a wall-clock range rather than a foreign key on `samples`.
@DataClassName('CookRow')
@TableIndex(name: 'idx_cooks_span', columns: {#bridgeId, #startUnixMs})
class Cooks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get bridgeId => text()();

  /// '' → the UI renders "Cook #id". Stored empty so a rename can tell
  /// "never named" from "deliberately named that".
  TextColumn get name => text().withDefault(const Constant(''))();

  /// Wall clock. May precede the app's first launch, and may be in the future
  /// (a scheduled cook).
  IntColumn get startUnixMs => integer()();

  /// NULL = running. Nothing auto-closes it.
  IntColumn get endUnixMs => integer().nullable()();
  IntColumn get createdUnixMs => integer()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get presetId => text().nullable()();
  TextColumn get doneness => text().withDefault(const Constant(''))();

  /// [HazardClass.name].
  TextColumn get hazard =>
      text().withDefault(const Constant('wholeMuscleRedMeat'))();

  /// [SafetyMode.name].
  TextColumn get safetyMode =>
      text().withDefault(const Constant('enthusiast'))();
  IntColumn get pitBandMinF10 => integer().nullable()();
  IntColumn get pitBandMaxF10 => integer().nullable()();
  BoolColumn get favourite => boolean().withDefault(const Constant(false))();

  /// The clockless fallback: pin this cook to one device session when the
  /// bridge's RTC was never set and `samples.unix_ms` is therefore NULL.
  IntColumn get anchorSessionId => integer().nullable()();

  /// When the user said they took the food off the heat (§D.5). Never inferred.
  IntColumn get pulledAtUnixMs => integer().nullable()();
}

/// One jack's job within a cook.
@DataClassName('CookProbeRoleRow')
class CookProbeRoles extends Table {
  IntColumn get cookId =>
      integer().references(Cooks, #id, onDelete: KeyAction.cascade)();
  IntColumn get jack => integer()();

  /// [ProbeRole] index.
  IntColumn get role => integer().withDefault(const Constant(0))();
  TextColumn get label => text().withDefault(const Constant(''))();

  /// Final (post-rest) target, tenths °F. NULL is the ordinary state of a cook
  /// started before its target was chosen.
  IntColumn get targetF10 => integer().nullable()();

  /// Carryover, tenths °F. Pull temperature is `target − this`.
  IntColumn get pullOffsetF10 => integer().withDefault(const Constant(0))();
  TextColumn get doneness => text().withDefault(const Constant(''))();

  /// [HazardClass.name], or NULL to take the cook's.
  TextColumn get hazard => text().nullable()();

  /// False forces the ground-meat floor on red meat (§D.4).
  BoolColumn get isIntact => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {cookId, jack};
}

/// The editable alarm rules of **both tiers** (§G.2).
///
/// One table, a `scope` discriminator, and no merging in the UI: the device
/// tier keeps working with the phone off and the app tier does not, so they are
/// rendered as two sections with two stated promises. [pushedToDevice] and
/// [lastConfirmedUnixMs] are what let a row say "Saved to bridge" only after a
/// read-back matched — the house rule the settings tree used to violate.
@DataClassName('AlarmRuleRow')
class AlarmRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get bridgeId => text()();

  /// 0 = device tier, 1 = app tier.
  IntColumn get scope => integer()();

  /// NULL = whole cook; 1..4 = one jack.
  IntColumn get jack => integer().nullable()();

  /// [AlarmRuleType.name].
  TextColumn get type => text()();

  /// Tenths °F for temperature rules, seconds for time rules. NULL for the
  /// rules that carry no threshold at all (probe unplugged, base lost).
  IntColumn get threshold => integer().nullable()();

  /// The dwell a rule must hold before it fires, seconds. NULL = instant.
  IntColumn get windowS => integer().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  BoolColumn get pushedToDevice =>
      boolean().withDefault(const Constant(false))();
  IntColumn get lastConfirmedUnixMs => integer().nullable()();

  /// Scoped to one cook, or NULL for a standing rule.
  IntColumn get cookId => integer().nullable()();
}

/// A hole in the recording, and **why** (§E.5).
///
/// The distinction is the whole point: a `connectivity` gap is data the phone
/// has not fetched *yet* and a later sync may fill it, while a `bufferRollover`
/// gap is data the device has overwritten and **nobody will ever have again**.
/// Rendering both as one dashed line would tell a user to wait for something
/// that is not coming.
@DataClassName('GapRow')
class Gaps extends Table {
  TextColumn get bridgeId => text()();
  IntColumn get sessionId => integer()();

  /// Session-relative seconds, exclusive of the samples either side.
  IntColumn get fromT => integer()();
  IntColumn get toT => integer()();

  /// [GapReason] index.
  IntColumn get reason => integer()();
  IntColumn get detectedUnixMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {bridgeId, sessionId, fromT};
}

/// Per-(bridge, session) sync high-water marks (§E.4).
///
/// The cursor used to be recomputed as `MAX(t)` on every connect, which is
/// correct but says nothing about what the *device* holds — so the app could
/// not tell "I have everything" from "the device rolled its buffer past me".
/// Storing the device's reported extent beside our own is what makes rollover
/// detectable at all.
@DataClassName('SyncStateRow')
class SyncStates extends Table {
  TextColumn get bridgeId => text()();
  IntColumn get sessionId => integer()();

  /// Highest `t` this phone has stored.
  IntColumn get highWaterT => integer().withDefault(const Constant(-1))();

  /// The device's buffer extent as of the last `status`/`sessions` read.
  IntColumn get deviceMinT => integer().nullable()();
  IntColumn get deviceMaxT => integer().nullable()();
  IntColumn get lastSyncUnixMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {bridgeId, sessionId};
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
  tables: [
    Bridges,
    Sessions,
    Samples,
    Marks,
    AlarmLog,
    Cooks,
    CookProbeRoles,
    AlarmRules,
    Gaps,
    SyncStates,
  ],
  daos: [SessionDao, SampleDao, MarkDao, CookDao, AlarmRuleDao, SyncStateDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  /// v1 → v2 (§D.2, §E.4, §E.5).
  ///
  /// Five new tables, two new columns, and one **backfill that has to be right
  /// the first time**: every session already in the cache becomes a Cook
  /// annotation spanning its own samples, so a user who upgrades mid-brisket
  /// opens the new History and finds their cooks there rather than an empty
  /// list under a reassuring "your bridge is still recording".
  ///
  /// Foreign keys go off around the transaction per drift's migration guidance
  /// — `cook_probe_roles` references `cooks`, and SQLite checks FK constraints
  /// as rows land rather than at commit.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      await customStatement('PRAGMA foreign_keys = OFF');
      await transaction(() async {
        if (from < 2) {
          await m.addColumn(samples, samples.unixMs);
          await m.addColumn(marks, marks.autoAnchor);
          await m.createTable(cooks);
          await m.createTable(cookProbeRoles);
          await m.createTable(alarmRules);
          await m.createTable(gaps);
          await m.createTable(syncStates);
          await m.createIndex(idxSamplesUnix);
          await m.createIndex(idxCooksSpan);
          await _backfillV2();
        }
      });
      await customStatement('PRAGMA foreign_keys = ON');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Project wall-clock onto existing samples, then turn every cached session
  /// into an annotation over them.
  ///
  /// Done in SQL rather than by reading rows into Dart: a two-month cache is
  /// ~155,000 sample rows, and a migration that pages them through the VM is a
  /// migration that ANRs on the phone it matters on.
  Future<void> _backfillV2() async {
    // A session with no clock leaves unix_ms NULL — §E.7 forbids inventing one.
    await customStatement(
      'UPDATE samples SET unix_ms = ('
      '  SELECT s.started_unix_ms + samples.t * 1000 FROM sessions s '
      '  WHERE s.bridge_id = samples.bridge_id '
      '    AND s.session_id = samples.session_id '
      '    AND s.started_unix_ms IS NOT NULL)',
    );
    // One Cook per session, spanning that session's own samples. A session with
    // no samples yet still earns an annotation — it is a cook that has started,
    // and dropping it would lose its name.
    await customStatement(
      'INSERT INTO cooks (bridge_id, name, start_unix_ms, end_unix_ms, '
      '                   created_unix_ms, anchor_session_id) '
      'SELECT s.bridge_id, s.name, '
      '  COALESCE(s.started_unix_ms, 0), '
      // A closed session ends where it ended; an open one stays running.
      '  CASE WHEN s.closed THEN s.ended_unix_ms ELSE NULL END, '
      '  COALESCE(s.started_unix_ms, 0), '
      // Clockless sessions pin to their session id; clocked ones range by time.
      '  CASE WHEN s.started_unix_ms IS NULL THEN s.session_id ELSE NULL END '
      'FROM sessions s',
    );
    // Seed the high-water marks from what is already cached, so the first sync
    // after the upgrade is a delta rather than a full refetch of everything.
    await customStatement(
      'INSERT INTO sync_states (bridge_id, session_id, high_water_t) '
      'SELECT bridge_id, session_id, MAX(t) FROM samples '
      'GROUP BY bridge_id, session_id',
    );
  }

  /// A29 — what the cache holds right now.
  Future<CacheStats> cacheStats() async {
    final row = await customSelect(
      'SELECT (SELECT COUNT(*) FROM sessions) AS s, '
      '(SELECT COUNT(*) FROM samples) AS n, '
      '(SELECT COUNT(*) FROM marks) AS m',
      readsFrom: {sessions, samples, marks},
    ).getSingle();
    return CacheStats(
      sessions: row.read<int>('s'),
      samples: row.read<int>('n'),
      marks: row.read<int>('m'),
    );
  }

  /// A29 — **the user's erase.** The cache keeps every cook it has ever
  /// seen, forever and deliberately, including ones the bridge has since
  /// purged under its own retention (04 §4.7). That policy is only
  /// defensible if there is a way out of it, and this is it.
  ///
  /// Deletes cooks, not identity: the `bridges` row survives, so the app
  /// still knows which bridge it is paired with and the next sync refills
  /// whatever the device still holds rather than starting a fresh pairing.
  Future<void> clearCachedCooks() => transaction(() async {
    await delete(samples).go();
    await delete(marks).go();
    await delete(sessions).go();
    await delete(alarmLog).go();
  });

  /// A29 — erase one cook. The granular form matters because the usual
  /// reason to clear anything is a single counter-top session recorded by
  /// a base station someone left switched on, not a wish to lose the year.
  Future<void> deleteCachedSession(String bridgeId, int sessionId) =>
      transaction(() async {
        await (delete(samples)..where(
              (s) =>
                  s.bridgeId.equals(bridgeId) & s.sessionId.equals(sessionId),
            ))
            .go();
        await (delete(marks)..where(
              (m) =>
                  m.bridgeId.equals(bridgeId) & m.sessionId.equals(sessionId),
            ))
            .go();
        await (delete(sessions)..where(
              (s) =>
                  s.bridgeId.equals(bridgeId) & s.sessionId.equals(sessionId),
            ))
            .go();
      });
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

  /// The bridge this app last talked to. v1 is single-bridge (D12), so
  /// "the one row" is the answer — but the schema stays multi-capable and
  /// this is the only place that assumption is written down.
  Future<String?> knownBridgeId() async {
    final rows =
        await (select(bridges)
              ..orderBy([(b) => OrderingTerm.desc(b.lastSeenUnixMs)])
              ..limit(1))
            .get();
    return rows.isEmpty ? null : rows.first.id;
  }

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

/// A29 — how big the cache has grown, for the screen that offers to clear
/// it. Asking someone to delete their cooking history without telling them
/// how much of it there is would be a dialog with no information in it.
class CacheStats {
  const CacheStats({
    required this.sessions,
    required this.samples,
    required this.marks,
  });

  static const CacheStats empty = CacheStats(
    sessions: 0,
    samples: 0,
    marks: 0,
  );

  final int sessions;
  final int samples;
  final int marks;

  bool get isEmpty => sessions == 0 && samples == 0;

  /// Rough on-disk cost. Each sample is 6 integer columns plus a 3-part key;
  /// ~48 B a row is what SQLite actually costs here, measured rather than
  /// derived, and it is only ever shown rounded to whole megabytes.
  int get approxBytes => samples * 48 + marks * 64 + sessions * 256;
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
  ///
  /// [sessionStartUnixMs] projects each `t` onto the wall clock so cook
  /// annotations can range over it (v2, §D.2). Null — a bridge whose RTC was
  /// never set — stores NULL rather than a fabricated epoch time, and the cook
  /// that covers those samples pins itself by session id instead. When the
  /// caller does not know, [insertSamplesForSession] looks it up.
  Future<int> insertSamples(
    String bridgeId,
    int sessionId,
    List<Sample> list, {
    int? sessionStartUnixMs,
  }) async {
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
            unixMs: Value(
              sessionStartUnixMs == null
                  ? null
                  : sessionStartUnixMs + s.t * 1000,
            ),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
    return list.length;
  }

  /// [insertSamples] with the session's start read from the cache, for the two
  /// hot paths (the live push and the monitor) that hold a sample and a session
  /// id but no header.
  Future<int> insertSamplesForSession(
    String bridgeId,
    int sessionId,
    List<Sample> list,
  ) async {
    final row =
        await (db.select(db.sessions)..where(
              (s) =>
                  s.bridgeId.equals(bridgeId) & s.sessionId.equals(sessionId),
            ))
            .getSingleOrNull();
    return insertSamples(
      bridgeId,
      sessionId,
      list,
      sessionStartUnixMs: row?.startedUnixMs,
    );
  }

  /// Backfill `unix_ms` for a session whose clock arrived **after** its
  /// samples did — the ordinary case for a bridge that syncs its RTC from the
  /// phone mid-cook (§E.7). Without this those rows stay invisible to every
  /// cook range query for the rest of the session.
  Future<void> projectWallClock(
    String bridgeId,
    int sessionId,
    int startedUnixMs,
  ) => customStatement(
    'UPDATE samples SET unix_ms = ? + t * 1000 '
    'WHERE bridge_id = ? AND session_id = ? AND unix_ms IS NULL',
    [startedUnixMs, bridgeId, sessionId],
  );

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

  /// Wall clock of the newest cached reading for a bridge, or null when
  /// nothing is cached **or** the bridge had no clock when it recorded.
  ///
  /// This is what dates a cold start: it lets the reader open out of range and
  /// show last night's numbers carrying last night's age, rather than showing
  /// them as live (13 §13.6.1). Null is a real answer — §E.7 forbids
  /// inventing a timestamp for a bridge whose RTC was never set — and it
  /// renders as "unknown", never as fresh.
  ///
  /// Rides the `idx_samples_unix` index, so it stays a cheap boot-path read.
  Future<int?> newestUnixMs(String bridgeId) async {
    final newest = samples.unixMs.max();
    final q = selectOnly(samples)
      ..addColumns([newest])
      ..where(samples.bridgeId.equals(bridgeId));
    final row = await q.getSingleOrNull();
    return row?.read(newest);
  }

  /// Lowest cached `t` for a session, or null when nothing is cached.
  ///
  /// A non-zero value means the cache starts partway into the cook, which
  /// the [maxT] cursor alone can never repair — see `SyncEngine`.
  Future<int?> minT(String bridgeId, int sessionId) async {
    final minExpr = samples.t.min();
    final q = selectOnly(samples)
      ..addColumns([minExpr])
      ..where(
        samples.bridgeId.equals(bridgeId) & samples.sessionId.equals(sessionId),
      );
    final row = await q.getSingle();
    return row.read(minExpr);
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

  /// A11.2 — one aggregate query for the whole sessions list.
  ///
  /// The list must never build its rows by loading samples: 54 days of
  /// retention is ~155,000 rows (08 §8.5), and a per-row `range()` is
  /// smooth on the sim's single fixture and unusable on a real device
  /// after two months. SQLite does the arithmetic and hands back one row
  /// per session.
  Future<Map<int, SampleSummary>> summaries(String bridgeId) async {
    final rows = await customSelect(
      'SELECT session_id, MIN(t) AS min_t, MAX(t) AS max_t, COUNT(*) AS n, '
      'MAX(MAX(IFNULL(p1, -32768), IFNULL(p2, -32768), '
      'IFNULL(p3, -32768), IFNULL(p4, -32768))) AS peak '
      'FROM samples WHERE bridge_id = ? GROUP BY session_id',
      variables: [Variable<String>(bridgeId)],
      readsFrom: {samples},
    ).get();
    return {
      for (final r in rows)
        r.read<int>('session_id'): SampleSummary(
          sessionId: r.read<int>('session_id'),
          minT: r.read<int>('min_t'),
          maxT: r.read<int>('max_t'),
          count: r.read<int>('n'),
          // -32768 is the "no reading at all" floor of the aggregate,
          // never a temperature — it stays null, like every other
          // absent reading in this codebase.
          peakF10: switch (r.read<int?>('peak')) {
            null || -32768 => null,
            final v => v,
          },
        ),
    };
  }

  /// The list row's sparkline: bucketed in SQL to ~[points] values, so a
  /// 54-day cook costs the same as an 18-hour one to draw.
  Future<List<({int t, double f})>> sparkline(
    String bridgeId,
    int sessionId, {
    int points = 48,
  }) async {
    final bounds = await customSelect(
      'SELECT MIN(t) AS lo, MAX(t) AS hi FROM samples '
      'WHERE bridge_id = ? AND session_id = ?',
      variables: [Variable<String>(bridgeId), Variable<int>(sessionId)],
      readsFrom: {samples},
    ).getSingleOrNull();
    final lo = bounds?.read<int?>('lo');
    final hi = bounds?.read<int?>('hi');
    if (lo == null || hi == null) {
      return const [];
    }
    final bucket = ((hi - lo) / (points < 2 ? 2 : points)).ceil().clamp(
      1,
      1 << 30,
    );
    final rows = await customSelect(
      'SELECT MIN(t) AS t, AVG(COALESCE(p1, p2, p3, p4)) AS v '
      'FROM samples WHERE bridge_id = ? AND session_id = ? '
      'AND COALESCE(p1, p2, p3, p4) IS NOT NULL '
      'GROUP BY t / ? ORDER BY t / ?',
      variables: [
        Variable<String>(bridgeId),
        Variable<int>(sessionId),
        Variable<int>(bucket),
        Variable<int>(bucket),
      ],
      readsFrom: {samples},
    ).get();
    return [
      for (final r in rows)
        (t: r.read<int>('t'), f: r.read<double>('v') / 10.0),
    ];
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

/// Cooks and their probe roles — the annotation system (§D.1–§D.3, §D.6).
///
/// Every edit here is metadata. Nothing in this class writes a sample row, and
/// that is the design: backdating, splitting and merging are cheap and
/// reversible precisely because they never touch the recording.
@DriftAccessor(tables: [Cooks, CookProbeRoles, Samples, Sessions])
class CookDao extends DatabaseAccessor<AppDatabase> with _$CookDaoMixin {
  CookDao(super.db);

  /// Insert (id 0) or update in place. Returns the row id either way, so a
  /// caller that just split a cook can hold on to both halves.
  Future<int> save(CookAnnotation cook) => transaction(() async {
    final id = cook.id == 0
        ? await into(cooks).insert(_companionFor(cook))
        : await (update(cooks)..where((c) => c.id.equals(cook.id)))
                  .write(_companionFor(cook))
              .then((_) => cook.id);
    await _writeRoles(id, cook.roles);
    return id;
  });

  Future<void> _writeRoles(int cookId, List<CookProbeRole> roles) async {
    await (delete(cookProbeRoles)..where((r) => r.cookId.equals(cookId))).go();
    if (roles.isEmpty) {
      return;
    }
    await batch((b) {
      for (final r in roles) {
        b.insert(
          cookProbeRoles,
          CookProbeRolesCompanion.insert(
            cookId: cookId,
            jack: r.jack,
            role: Value(r.role.index),
            label: Value(r.label),
            targetF10: Value(r.targetF10),
            pullOffsetF10: Value(r.pullOffsetF10),
            doneness: Value(r.doneness),
            hazard: Value(r.hazard?.name),
            isIntact: Value(r.isIntact),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  CooksCompanion _companionFor(CookAnnotation c) => CooksCompanion(
    bridgeId: Value(c.bridgeId),
    name: Value(c.name),
    startUnixMs: Value(c.startUnixMs),
    endUnixMs: Value(c.endUnixMs),
    createdUnixMs: Value(c.createdUnixMs),
    notes: Value(c.notes),
    presetId: Value(c.presetId),
    doneness: Value(c.doneness),
    hazard: Value(c.hazard.name),
    safetyMode: Value(c.safetyMode.name),
    pitBandMinF10: Value(c.pitBandMinF10),
    pitBandMaxF10: Value(c.pitBandMaxF10),
    favourite: Value(c.favourite),
    anchorSessionId: Value(c.anchorSessionId),
    pulledAtUnixMs: Value(c.pulledAtUnixMs),
  );

  /// Deletes the annotation **only**. The recording is untouched, which is
  /// exactly what the cost sheet promises — so this must never cascade to
  /// samples, and the schema is arranged so it cannot.
  Future<void> deleteCook(int id) =>
      (delete(cooks)..where((c) => c.id.equals(id))).go();

  Future<CookAnnotation?> byId(int id) async {
    final row = await (select(cooks)..where((c) => c.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _withRoles([row]).then((l) => l.first);
  }

  Future<List<CookAnnotation>> forBridge(String bridgeId) async {
    final rows =
        await (select(cooks)
              ..where((c) => c.bridgeId.equals(bridgeId))
              ..orderBy([(c) => OrderingTerm.desc(c.startUnixMs)]))
            .get();
    return _withRoles(rows);
  }

  /// The list watches the database, so a cook created on another surface (the
  /// monitor, a split) appears without a relaunch.
  Stream<List<CookAnnotation>> watchForBridge(String bridgeId) =>
      (select(cooks)
            ..where((c) => c.bridgeId.equals(bridgeId))
            ..orderBy([(c) => OrderingTerm.desc(c.startUnixMs)]))
          .watch()
          .asyncMap(_withRoles);

  /// The open annotation — started and not yet ended. A scheduled cook whose
  /// start has not arrived is deliberately **not** running.
  Future<CookAnnotation?> running(String bridgeId, int nowUnixMs) async {
    final rows =
        await (select(cooks)
              ..where(
                (c) =>
                    c.bridgeId.equals(bridgeId) &
                    c.endUnixMs.isNull() &
                    c.startUnixMs.isSmallerOrEqualValue(nowUnixMs),
              )
              ..orderBy([(c) => OrderingTerm.desc(c.startUnixMs)])
              ..limit(1))
            .get();
    if (rows.isEmpty) {
      return null;
    }
    return _withRoles(rows).then((l) => l.first);
  }

  Future<List<CookAnnotation>> _withRoles(List<CookRow> rows) async {
    if (rows.isEmpty) {
      return const [];
    }
    final ids = rows.map((r) => r.id).toList();
    final roleRows = await (select(
      cookProbeRoles,
    )..where((r) => r.cookId.isIn(ids))).get();
    final byCook = <int, List<CookProbeRole>>{};
    for (final r in roleRows) {
      byCook.putIfAbsent(r.cookId, () => []).add(
        CookProbeRole(
          jack: r.jack,
          role: r.role >= 0 && r.role < ProbeRole.values.length
              ? ProbeRole.values[r.role]
              : ProbeRole.unused,
          label: r.label,
          targetF10: r.targetF10,
          pullOffsetF10: r.pullOffsetF10,
          doneness: r.doneness,
          hazard: HazardClass.values
              .where((h) => h.name == r.hazard)
              .firstOrNull,
          isIntact: r.isIntact,
        ),
      );
    }
    return [
      for (final r in rows)
        CookAnnotation(
          id: r.id,
          bridgeId: r.bridgeId,
          name: r.name,
          startUnixMs: r.startUnixMs,
          endUnixMs: r.endUnixMs,
          createdUnixMs: r.createdUnixMs,
          notes: r.notes,
          presetId: r.presetId,
          doneness: r.doneness,
          // A name this build does not know — a row written by a later
          // release — falls back to the *floored* class, not the floor-free
          // one. Downgrading an unknown protein to "no minimum" is the one
          // way a storage read can become a food-safety decision.
          hazard:
              HazardClass.values.where((h) => h.name == r.hazard).firstOrNull ??
              HazardClass.unstated,
          safetyMode:
              SafetyMode.values.where((m) => m.name == r.safetyMode).firstOrNull ??
              SafetyMode.enthusiast,
          pitBandMinF10: r.pitBandMinF10,
          pitBandMaxF10: r.pitBandMaxF10,
          favourite: r.favourite,
          anchorSessionId: r.anchorSessionId,
          pulledAtUnixMs: r.pulledAtUnixMs,
          // `?? const []` then `..sort()` would try to sort an unmodifiable
          // list for every cook with no roles — which is every cook created
          // before its probes were mapped.
          roles: <CookProbeRole>[...?byCook[r.id]]
            ..sort((a, b) => a.jack.compareTo(b.jack)),
        ),
    ];
  }

  /// The samples a cook covers — **a range query, not a join through a foreign
  /// key**, which is the whole reason backdating is free.
  ///
  /// Falls back to the pinned session when the bridge had no clock, because
  /// those rows have no `unix_ms` to range over.
  Future<List<Sample>> samplesFor(CookAnnotation cook) async {
    final anchor = cook.anchorSessionId;
    if (anchor != null) {
      final rows =
          await (select(samples)
                ..where(
                  (s) =>
                      s.bridgeId.equals(cook.bridgeId) &
                      s.sessionId.equals(anchor),
                )
                ..orderBy([(s) => OrderingTerm.asc(s.t)]))
              .get();
      return rows.map(sampleFromRow).toList();
    }
    final end = cook.endUnixMs ?? 0x7fffffffffffff;
    final rows =
        await (select(samples)
              ..where(
                (s) =>
                    s.bridgeId.equals(cook.bridgeId) &
                    s.unixMs.isNotNull() &
                    s.unixMs.isBiggerOrEqualValue(cook.startUnixMs) &
                    s.unixMs.isSmallerThanValue(end),
              )
              ..orderBy([
                (s) => OrderingTerm.asc(s.unixMs),
                (s) => OrderingTerm.asc(s.t),
              ]))
            .get();
    return rows.map(sampleFromRow).toList();
  }

  /// The list row's header numbers, in SQL — same reason as [SampleDao.summaries]:
  /// a two-month cache must not be paged through Dart to draw a list.
  Future<CookSummary> summaryFor(CookAnnotation cook) async {
    final anchor = cook.anchorSessionId;
    final where = anchor != null
        ? 'bridge_id = ? AND session_id = ?'
        : 'bridge_id = ? AND unix_ms IS NOT NULL AND unix_ms >= ? '
              'AND unix_ms < ?';
    final vars = anchor != null
        ? [Variable<String>(cook.bridgeId), Variable<int>(anchor)]
        : [
            Variable<String>(cook.bridgeId),
            Variable<int>(cook.startUnixMs),
            Variable<int>(cook.endUnixMs ?? 0x7fffffffffffff),
          ];
    final row = await customSelect(
      'SELECT MIN(t) AS min_t, MAX(t) AS max_t, COUNT(*) AS n, '
      'MAX(MAX(IFNULL(p1, -32768), IFNULL(p2, -32768), '
      'IFNULL(p3, -32768), IFNULL(p4, -32768))) AS peak '
      'FROM samples WHERE $where',
      variables: vars,
      readsFrom: {samples},
    ).getSingle();
    return CookSummary(
      count: row.read<int>('n'),
      minT: row.read<int?>('min_t'),
      maxT: row.read<int?>('max_t'),
      peakF10: switch (row.read<int?>('peak')) {
        null || -32768 => null,
        final v => v,
      },
    );
  }
}

/// What a cook row needs to draw its header, computed in SQL.
class CookSummary {
  const CookSummary({
    required this.count,
    this.minT,
    this.maxT,
    this.peakF10,
  });

  final int count;
  final int? minT;
  final int? maxT;

  /// Null when no probe ever reported — never 0.
  final int? peakF10;
}

/// The editable alarm rules of both tiers (§G.2, §G.3).
@DriftAccessor(tables: [AlarmRules])
class AlarmRuleDao extends DatabaseAccessor<AppDatabase>
    with _$AlarmRuleDaoMixin {
  AlarmRuleDao(super.db);

  Future<int> save(AlarmRuleSpec rule) async {
    final companion = AlarmRulesCompanion(
      bridgeId: Value(rule.bridgeId),
      scope: Value(rule.tier.index),
      jack: Value(rule.jack),
      type: Value(rule.type.name),
      threshold: Value(rule.threshold),
      windowS: Value(rule.windowS),
      enabled: Value(rule.enabled),
      pushedToDevice: Value(rule.pushedToDevice),
      lastConfirmedUnixMs: Value(rule.lastConfirmedUnixMs),
      cookId: Value(rule.cookId),
    );
    if (rule.id == 0) {
      return into(alarmRules).insert(companion);
    }
    await (update(alarmRules)..where((r) => r.id.equals(rule.id)))
        .write(companion);
    return rule.id;
  }

  Future<void> deleteRule(int id) =>
      (delete(alarmRules)..where((r) => r.id.equals(id))).go();

  Future<List<AlarmRuleSpec>> forBridge(String bridgeId) async {
    final rows = await (select(
      alarmRules,
    )..where((r) => r.bridgeId.equals(bridgeId))).get();
    return rows.map(_fromRow).toList();
  }

  Stream<List<AlarmRuleSpec>> watchForBridge(String bridgeId) =>
      (select(alarmRules)..where((r) => r.bridgeId.equals(bridgeId)))
          .watch()
          .map((rows) => rows.map(_fromRow).toList());

  /// §G.3 — a rule is "Saved to bridge" only once a read-back matched. This is
  /// the write that records that, and nothing else may set [pushedToDevice].
  Future<void> markConfirmed(int id, {required int atUnixMs}) =>
      (update(alarmRules)..where((r) => r.id.equals(id))).write(
        AlarmRulesCompanion(
          pushedToDevice: const Value(true),
          lastConfirmedUnixMs: Value(atUnixMs),
        ),
      );

  Future<void> markUnconfirmed(int id) =>
      (update(alarmRules)..where((r) => r.id.equals(id))).write(
        const AlarmRulesCompanion(pushedToDevice: Value(false)),
      );

  AlarmRuleSpec _fromRow(AlarmRuleRow r) => AlarmRuleSpec(
    id: r.id,
    bridgeId: r.bridgeId,
    tier: r.scope == 0 ? AlarmTier.device : AlarmTier.app,
    jack: r.jack,
    type:
        AlarmRuleType.values.where((t) => t.name == r.type).firstOrNull ??
        AlarmRuleType.internalAbove,
    threshold: r.threshold,
    windowS: r.windowS,
    enabled: r.enabled,
    pushedToDevice: r.pushedToDevice,
    lastConfirmedUnixMs: r.lastConfirmedUnixMs,
    cookId: r.cookId,
  );
}

/// Sync high-water marks and the gaps they reveal (§E.4, §E.5).
@DriftAccessor(tables: [SyncStates, Gaps, Samples])
class SyncStateDao extends DatabaseAccessor<AppDatabase>
    with _$SyncStateDaoMixin {
  SyncStateDao(super.db);

  Future<SyncStateRow?> forSession(String bridgeId, int sessionId) =>
      (select(syncStates)..where(
            (s) => s.bridgeId.equals(bridgeId) & s.sessionId.equals(sessionId),
          ))
          .getSingleOrNull();

  Future<void> record(
    String bridgeId,
    int sessionId, {
    required int highWaterT,
    int? deviceMinT,
    int? deviceMaxT,
    int? atUnixMs,
  }) => into(syncStates).insertOnConflictUpdate(
    SyncStatesCompanion.insert(
      bridgeId: bridgeId,
      sessionId: sessionId,
      highWaterT: Value(highWaterT),
      deviceMinT: Value(deviceMinT),
      deviceMaxT: Value(deviceMaxT),
      lastSyncUnixMs: Value(atUnixMs),
    ),
  );

  /// Record a hole. Idempotent on `(bridge, session, fromT)` so a re-sync that
  /// re-detects the same gap does not multiply it in the statistics table.
  Future<void> recordGap(
    String bridgeId,
    int sessionId, {
    required int fromT,
    required int toT,
    required GapReason reason,
    required int atUnixMs,
  }) => into(gaps).insertOnConflictUpdate(
    GapsCompanion.insert(
      bridgeId: bridgeId,
      sessionId: sessionId,
      fromT: fromT,
      toT: toT,
      reason: reason.index,
      detectedUnixMs: atUnixMs,
    ),
  );

  /// A connectivity gap the phone has since filled in stops being a gap. A
  /// rollover gap never does — nobody has that data any more — so this only
  /// ever clears the recoverable kind.
  Future<void> clearFilledConnectivityGaps(
    String bridgeId,
    int sessionId,
  ) async {
    await customStatement(
      'DELETE FROM gaps WHERE bridge_id = ? AND session_id = ? '
      'AND reason = ? AND EXISTS ('
      '  SELECT 1 FROM samples s WHERE s.bridge_id = gaps.bridge_id '
      '    AND s.session_id = gaps.session_id '
      '    AND s.t > gaps.from_t AND s.t < gaps.to_t)',
      // `customStatement` binds raw values, not `Variable`s — the latter is
      // `customSelect`'s currency and silently fails at bind time here.
      [bridgeId, sessionId, GapReason.connectivity.index],
    );
  }

  Future<List<RecordedGap>> forBridgeSession(
    String bridgeId,
    int sessionId,
  ) async {
    final rows =
        await (select(gaps)
              ..where(
                (g) =>
                    g.bridgeId.equals(bridgeId) & g.sessionId.equals(sessionId),
              )
              ..orderBy([(g) => OrderingTerm.asc(g.fromT)]))
            .get();
    return [
      for (final g in rows)
        RecordedGap(
          fromT: g.fromT,
          toT: g.toT,
          reason: g.reason >= 0 && g.reason < GapReason.values.length
              ? GapReason.values[g.reason]
              : GapReason.connectivity,
        ),
    ];
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

/// What the sessions list needs per cook, computed in SQL.
class SampleSummary {
  const SampleSummary({
    required this.sessionId,
    required this.minT,
    required this.maxT,
    required this.count,
    this.peakF10,
  });

  final int sessionId;
  final int minT;
  final int maxT;
  final int count;

  /// Null when no probe ever reported — never 0.
  final int? peakF10;

  int get durationS => maxT - minT;
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
