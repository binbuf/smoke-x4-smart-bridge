/// N15.9 — the drift schema for the on-device cache (fresh schema, **not**
/// the legacy v2 database).
///
/// The app owns a full copy of every cook it has seen: charts, history and CSV
/// export read from here, never from the network, so they work with the bridge
/// unplugged and across a link loss. The schema is multi-bridge capable
/// (`bridgeId` everywhere) even though v1 is single-device.
///
/// This file imports only `drift`, so the schema and the cache are in the
/// `dart test` / `flutter test` host gate. Opening the real on-device file is
/// split into `open_database.dart`, which does import `path_provider`.
///
/// **I10 is the whole point.** `samples` is keyed `(bridgeId, sessionId, t)`
/// and every insert is `insertOrIgnore`: the first recorded value wins and no
/// row is ever rewritten, so a re-sync is a no-op. `unixMs` is a nullable
/// *projection* of that key, never a fabricated timestamp (I11).
library;

import 'package:drift/drift.dart';

import '../../domain/domain.dart';

part 'app_database.g.dart';

/// Bridges this app has talked to. `id` is the base station device id.
@DataClassName('BridgeRow')
class Bridges extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withDefault(const Constant(''))();
  IntColumn get lastSeenUnixMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

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

  /// NULL when the bridge had no clock (I11).
  IntColumn get unixMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {bridgeId, sessionId, t};
}

/// A mark the bridge placed (or the app posted).
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

/// A named, time-bounded cook annotation over the continuous recording.
@DataClassName('CookRow')
@TableIndex(name: 'idx_cooks_span', columns: {#bridgeId, #startUnixMs})
class Cooks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get bridgeId => text()();
  TextColumn get name => text().withDefault(const Constant(''))();
  IntColumn get startUnixMs => integer()();
  IntColumn get endUnixMs => integer().nullable()();
  IntColumn get createdUnixMs => integer()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get presetId => text().nullable()();

  /// [HazardClass.name].
  TextColumn get hazard => text().withDefault(const Constant('unstated'))();
  IntColumn get pitBandMinF10 => integer().nullable()();
  IntColumn get pitBandMaxF10 => integer().nullable()();
  BoolColumn get favourite => boolean().withDefault(const Constant(false))();

  /// Clockless fallback: pin to one device session when `samples.unixMs` is
  /// NULL for the whole cook.
  IntColumn get anchorSessionId => integer().nullable()();

  /// When the user took the food off the heat. Never inferred.
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
  IntColumn get targetF10 => integer().nullable()();
  IntColumn get pullOffsetF10 => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {cookId, jack};
}

/// The editable alarm rules of both tiers.
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
  IntColumn get threshold => integer().nullable()();
  IntColumn get windowS => integer().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  BoolColumn get pushedToDevice =>
      boolean().withDefault(const Constant(false))();
  IntColumn get lastConfirmedUnixMs => integer().nullable()();
  IntColumn get cookId => integer().nullable()();
}

/// A hole in the recording, and **why** (N1.18).
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

/// Per-(bridge, session) sync high-water marks (N15.11).
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

@DriftDatabase(
  tables: [
    Bridges,
    Sessions,
    Samples,
    Marks,
    Cooks,
    CookProbeRoles,
    AlarmRules,
    Gaps,
    SyncStates,
  ],
)
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
