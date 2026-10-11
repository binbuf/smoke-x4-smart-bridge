/// The drift schema for the on-device cache.
///
/// The app owns a full copy of every cook it has seen: charts, history and the
/// cook-start view read from here, never from the network, so they work with
/// the bridge unplugged and across a link loss. The schema is multi-bridge
/// capable (`bridgeId` everywhere) even though v1 is single-device.
///
/// This file imports only `drift`, so the schema and the cache are in the host
/// test gate. Opening the real on-device file is split into `open_database.dart`,
/// which imports `path_provider`.
///
/// **The sample key is the whole point.** `samples` is keyed
/// `(bridgeId, sessionId, t)` and every insert is `insertOrIgnore`: the first
/// recorded value wins and no row is ever rewritten, so a re-sync is a no-op.
/// `unixMs` is a nullable projection, never a fabricated timestamp.
library;

import 'package:drift/drift.dart';

import '../../domain/domain.dart';

part 'app_database.g.dart';

/// A recording session as the bridge reported it.
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

/// One row per sample; `p1..p4` are tenths-°F, NULL = detached/invalid.
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

  /// NULL when the bridge had no clock.
  IntColumn get unixMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {bridgeId, sessionId, t};
}

/// A hole in the recording, and **why**.
@DataClassName('GapRow')
class Gaps extends Table {
  TextColumn get bridgeId => text()();
  IntColumn get sessionId => integer()();
  IntColumn get fromT => integer()();
  IntColumn get toT => integer()();

  /// [GapReason] index.
  IntColumn get reason => integer()();
  IntColumn get detectedUnixMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {
    bridgeId,
    sessionId,
    fromT,
    toT,
    reason,
  };
}

/// Per-(bridge, session) sync high-water marks.
@DataClassName('SyncStateRow')
class SyncStates extends Table {
  TextColumn get bridgeId => text()();
  IntColumn get sessionId => integer()();

  /// Highest `t` this phone has stored, or -1.
  IntColumn get highWaterT => integer().withDefault(const Constant(-1))();

  /// The device's buffer extent as of the last read.
  IntColumn get deviceMinT => integer().nullable()();
  IntColumn get deviceMaxT => integer().nullable()();
  IntColumn get lastSyncUnixMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {bridgeId, sessionId};
}

@DriftDatabase(tables: [Sessions, Samples, Gaps, SyncStates])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

// ── row ↔ domain mapping ──────────────────────────────────────────────────

Sample sampleFromRow(SampleRow r) => Sample(
  t: r.t,
  tempsF10: [r.p1, r.p2, r.p3, r.p4],
  unixMs: r.unixMs,
  billows: r.flags & 0x10 != 0,
  newAlarm: r.flags & 0x20 != 0,
  sourceCelsius: r.flags & 0x40 != 0,
  rssi: r.rssi,
);

SessionInfo sessionFromRow(SessionRow r) => SessionInfo(
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
