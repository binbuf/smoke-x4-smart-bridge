import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Temperature sentinel carried by the wire record. A stored `NULL` means the
/// probe was absent or invalid; it never becomes 0 °F.
const int deviceTempDetached = -32768;
const int deviceTempInvalid = -32767;

/// The nominal cadence used only to place a sample with an unknown device
/// clock on the History axis. It never makes the time exact.
const int estimatedSampleCadenceMs = 30000;

/// One saved Bridge identity: the `bridge` row T43 loads on launch.
class SavedBridge {
  const SavedBridge({
    required this.id,
    required this.name,
    required this.lastSeenMs,
    this.generation = 0,
    this.cursorAfter,
    this.cursorBefore,
    this.deviceMinSeq,
    this.deviceMaxSeq,
  });

  final String id;
  final String name;
  final int lastSeenMs;
  final int generation;

  /// Highest contiguous sequence stored locally; `null` until there is data.
  final int? cursorAfter;

  /// Lowest contiguous sequence stored locally; `null` until there is data.
  final int? cursorBefore;

  /// Device extent; `null` when the bridge log is empty.
  final int? deviceMinSeq;
  final int? deviceMaxSeq;

  static SavedBridge fromRow(Map<String, Object?> row) => SavedBridge(
    id: row['id']! as String,
    name: row['name']! as String,
    lastSeenMs: row['last_seen_ms']! as int,
    generation: row['generation']! as int,
    cursorAfter: row['cursor_after'] as int?,
    cursorBefore: row['cursor_before'] as int?,
    deviceMinSeq: row['device_min_seq'] as int?,
    deviceMaxSeq: row['device_max_seq'] as int?,
  );

  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'name': name,
    'last_seen_ms': lastSeenMs,
    'generation': generation,
    'cursor_after': cursorAfter,
    'cursor_before': cursorBefore,
    'device_min_seq': deviceMinSeq,
    'device_max_seq': deviceMaxSeq,
  };

  SavedBridge copyWith({
    String? name,
    int? lastSeenMs,
    int? generation,
    int? cursorAfter,
    int? cursorBefore,
    int? deviceMinSeq,
    int? deviceMaxSeq,
  }) => SavedBridge(
    id: id,
    name: name ?? this.name,
    lastSeenMs: lastSeenMs ?? this.lastSeenMs,
    generation: generation ?? this.generation,
    cursorAfter: cursorAfter ?? this.cursorAfter,
    cursorBefore: cursorBefore ?? this.cursorBefore,
    deviceMinSeq: deviceMinSeq ?? this.deviceMinSeq,
    deviceMaxSeq: deviceMaxSeq ?? this.deviceMaxSeq,
  );
}

/// A sync record as read from the bridge, before the archive pins its wall
/// time. [unixS] is null (or 0) when the device clock was unknown.
class DeviceSample {
  const DeviceSample({
    required this.seq,
    required this.unixS,
    required this.tempsF10,
    required this.flags,
    required this.clockValid,
  });

  final int seq;
  final int? unixS;

  /// P1–P4 in tenths °F. Null or a wire sentinel means the probe was absent.
  final List<int?> tempsF10;
  final int flags;
  final bool clockValid;
}

/// One row of the `sample` table.
class StoredSample {
  const StoredSample({
    required this.bridgeId,
    required this.generation,
    required this.seq,
    required this.unixS,
    required this.recordedMs,
    required this.timeEstimated,
    required this.tempsF10,
    required this.flags,
  });

  final String bridgeId;
  final int generation;
  final int seq;

  /// Device clock in seconds, or null when it was unknown.
  final int? unixS;

  /// Wall time (or estimated wall time) in milliseconds; the query axis.
  final int recordedMs;
  final int timeEstimated;

  /// Exactly four entries; null means absent, never 0 °F.
  final List<int?> tempsF10;
  final int flags;

  bool get clockValid => timeEstimated == 0;

  /// Maps a device record to storage, including the unknown-clock estimate from
  /// 04 §4.7:
  ///
  /// `recorded_ms = sync_wall_ms - (device_max_seq - seq) * 30000`
  ///
  /// A known device clock is stored as-is with `time_estimated = 0`.
  factory StoredSample.fromDevice({
    required String bridgeId,
    required int generation,
    required DeviceSample sample,
    required int syncWallMs,
    required int deviceMaxSeq,
    int cadenceMs = estimatedSampleCadenceMs,
  }) {
    final known =
        sample.clockValid && sample.unixS != null && sample.unixS! > 0;
    final unixS = known ? sample.unixS : null;
    final recordedMs = known
        ? unixS! * 1000
        : syncWallMs - (deviceMaxSeq - sample.seq) * cadenceMs;
    final temps = <int?>[
      for (var index = 0; index < 4; index++)
        _validTemp(
          index < sample.tempsF10.length ? sample.tempsF10[index] : null,
        ),
    ];
    return StoredSample(
      bridgeId: bridgeId,
      generation: generation,
      seq: sample.seq,
      unixS: unixS,
      recordedMs: recordedMs,
      timeEstimated: known ? 0 : 1,
      tempsF10: temps,
      flags: sample.flags,
    );
  }

  static int? _validTemp(int? value) {
    if (value == null ||
        value == deviceTempDetached ||
        value == deviceTempInvalid) {
      return null;
    }
    return value;
  }

  static StoredSample fromRow(Map<String, Object?> row) => StoredSample(
    bridgeId: row['bridge_id']! as String,
    generation: row['generation']! as int,
    seq: row['seq']! as int,
    unixS: row['unix_s'] as int?,
    recordedMs: row['recorded_ms']! as int,
    timeEstimated: row['time_estimated']! as int,
    tempsF10: <int?>[
      row['p1'] as int?,
      row['p2'] as int?,
      row['p3'] as int?,
      row['p4'] as int?,
    ],
    flags: row['flags']! as int,
  );
}

/// One row of the `gap` table.
class StoredGap {
  const StoredGap({
    required this.bridgeId,
    required this.generation,
    required this.fromSeq,
    required this.toSeq,
    required this.reason,
    required this.detectedMs,
  });

  final String bridgeId;
  final int generation;
  final int fromSeq;
  final int toSeq;
  final String reason;
  final int detectedMs;

  static StoredGap fromRow(Map<String, Object?> row) => StoredGap(
    bridgeId: row['bridge_id']! as String,
    generation: row['generation']! as int,
    fromSeq: row['from_seq']! as int,
    toSeq: row['to_seq']! as int,
    reason: row['reason']! as String,
    detectedMs: row['detected_ms']! as int,
  );

  Map<String, Object?> toRow() => <String, Object?>{
    'bridge_id': bridgeId,
    'generation': generation,
    'from_seq': fromSeq,
    'to_seq': toSeq,
    'reason': reason,
    'detected_ms': detectedMs,
  };
}

/// Local sequence and time extent. Non-null only when at least one row matches.
class SampleExtent {
  const SampleExtent({
    required this.count,
    required this.minSeq,
    required this.maxSeq,
    required this.minRecordedMs,
    required this.maxRecordedMs,
  });

  final int count;
  final int minSeq;
  final int maxSeq;
  final int minRecordedMs;
  final int maxRecordedMs;
}

/// One SQL time bucket for a long history range.
///
/// `recordedMs` is the last real reading in the bucket; `tempsF` are the bucket
/// averages in °F (null when that probe had no valid value). The chart uses
/// these as honest downsampled points, never as new readings.
class HistoryBucketRow {
  const HistoryBucketRow({
    required this.startMs,
    required this.recordedMs,
    required this.tempsF,
    required this.estimated,
  });

  /// First real reading in the bucket.
  final int startMs;

  /// Last real reading in the bucket; the chart's x position.
  final int recordedMs;
  final List<double?> tempsF;
  final bool estimated;

  static HistoryBucketRow fromRow(Map<String, Object?> row) {
    double? temp(String column) {
      final value = row[column] as num?;
      return value == null ? null : value.toDouble() / 10.0;
    }

    return HistoryBucketRow(
      startMs: row['start_ms']! as int,
      recordedMs: row['end_ms']! as int,
      tempsF: <double?>[temp('p1'), temp('p2'), temp('p3'), temp('p4')],
      estimated: ((row['estimated'] as int?) ?? 0) != 0,
    );
  }
}

/// Exact per-probe summary for one range, computed by SQLite over raw rows.
///
/// The chart may be decimated, but Summary must report the true latest, lowest
/// and highest valid reading.
class HistoryProbeStatsRow {
  const HistoryProbeStatsRow({
    required this.probe,
    required this.readingCount,
    required this.latestF,
    required this.latestMs,
    required this.minF,
    required this.maxF,
  });

  final int probe;
  final int readingCount;
  final double? latestF;
  final int? latestMs;
  final double? minF;
  final double? maxF;

  bool get hasData => readingCount > 0 && latestF != null;
}

/// What a date-range deletion removed.
class HistoryDeletion {
  const HistoryDeletion({
    required this.samplesDeleted,
    required this.gapsDeleted,
    required this.gapsTrimmed,
  });

  final int samplesDeleted;

  /// Gap rows removed entirely because they fell inside the deleted range.
  final int gapsDeleted;

  /// Gap rows shortened because only part of their sequence range was deleted.
  final int gapsTrimmed;

  int get gapsAffected => gapsDeleted + gapsTrimmed;
}

/// Durable archive operations. The in-memory test database implements the same
/// contract through [SqfliteSampleDao] over `AppDatabase.openInMemory`.
abstract interface class SampleDao {
  /// Inserts one sync batch in a single transaction.
  ///
  /// The primary key `(bridge_id, generation, seq)` is the idempotency key. An
  /// existing row is kept unless it was time-estimated and this batch carries a
  /// real device clock. Returns the number of newly inserted rows.
  Future<int> insertBatch({
    required String bridgeId,
    required int generation,
    required Iterable<DeviceSample> samples,
    required int syncWallMs,
    required int deviceMaxSeq,
  });

  /// Inserts already-mapped rows in one transaction.
  Future<int> insertSamples(Iterable<StoredSample> samples);

  /// Stores one sync batch, its gaps and the resulting cursors atomically.
  ///
  /// T41's sync loop commits exactly one request/batch per transaction: either
  /// the rows and the cursor advance land together, or the request is re-read
  /// from the previous cursor. Passing `null` for a cursor clears it (a
  /// generation change starts a fresh local segment).
  Future<int> storeSyncBatch({
    required String bridgeId,
    required int generation,
    required Iterable<StoredSample> samples,
    required int? cursorAfter,
    required int? cursorBefore,
    required int? deviceMinSeq,
    required int? deviceMaxSeq,
    required int lastSeenMs,
    Iterable<StoredGap> gaps = const <StoredGap>[],
  });

  /// Updates the sync cursors and the observed device extent in one write.
  ///
  /// Unlike [SavedBridge.copyWith], `null` really clears the stored value.
  Future<void> updateSyncCursors({
    required String bridgeId,
    required int generation,
    required int? cursorAfter,
    required int? cursorBefore,
    required int? deviceMinSeq,
    required int? deviceMaxSeq,
    required int lastSeenMs,
  });

  Future<void> insertGaps(Iterable<StoredGap> gaps);

  /// Readings ordered by `recorded_ms`. The range is `[fromMs, toMs)`.
  Future<List<StoredSample>> samplesInRange({
    required int fromMs,
    required int toMs,
    String? bridgeId,
    int? generation,
    int? limit,
    bool ascending = true,
  });

  /// SQL time buckets for a long range, one row per bucket.
  ///
  /// Each probe value is the average of the valid readings in the bucket and
  /// stays null when the probe had none. This keeps a 30-day chart to a few
  /// thousand points without ever inventing a zero.
  Future<List<HistoryBucketRow>> bucketedSamplesInRange({
    required int fromMs,
    required int toMs,
    required int bucketMs,
    String? bridgeId,
    int? generation,
  });

  /// Exact latest/min/max/count for P1–P4 over `[fromMs, toMs)`.
  Future<List<HistoryProbeStatsRow>> probeStatsInRange({
    required int fromMs,
    required int toMs,
    String? bridgeId,
    int? generation,
  });

  /// The stored readings immediately around a missing sequence range.
  ///
  /// `before` is the newest row with `seq <= fromSeq`; `after` is the oldest
  /// row with `seq >= toSeq`. Both are scoped to the same bridge/generation, so
  /// a gap is placed on the time axis using the readings that actually surround
  /// it instead of the time the app detected it.
  Future<(StoredSample?, StoredSample?)> samplesAroundSeq({
    required int fromSeq,
    required int toSeq,
    String? bridgeId,
    int? generation,
  });

  /// Gap rows detected in the range, ordered by detection time.
  Future<List<StoredGap>> gapsInRange({
    required int fromMs,
    required int toMs,
    String? bridgeId,
    int? generation,
  });

  /// Newest readings first, used for last-known values.
  Future<List<StoredSample>> newestSamples({int limit = 1, String? bridgeId});

  Future<int> countSamples({
    String? bridgeId,
    int? generation,
    int? fromMs,
    int? toMs,
  });

  /// Min/max sequence and time extent, or null when no row matches.
  Future<SampleExtent?> extent({String? bridgeId, int? generation});

  Future<List<StoredGap>> gaps({String? bridgeId, int? generation});

  /// Deletes readings in `[fromMs, toMs)` and any gap rows they described.
  ///
  /// Gap rows detected inside the range are removed; gap rows overlapping the
  /// deleted sequence extent are removed or trimmed. `sample` and `gap` rows for
  /// other bridges/generations are untouched.
  Future<HistoryDeletion> deleteRange({
    required int fromMs,
    required int toMs,
    String? bridgeId,
    int? generation,
  });

  /// The most recently used saved Bridge, or null before first pairing.
  Future<SavedBridge?> savedBridge();

  Future<SavedBridge?> bridgeById(String id);

  /// Inserts or replaces the full saved-connection row.
  Future<void> saveBridge(SavedBridge bridge);

  /// Updates only the observed identity, keeping cursors and extent intact.
  Future<void> touchBridge({
    required String id,
    required String name,
    required int lastSeenMs,
    int? generation,
  });

  /// Forgets the saved connection. `sample`/`gap` rows stay readable as
  /// orphaned history.
  Future<bool> removeBridge(String id);

  /// Forgets every saved connection; archive rows are still kept.
  Future<int> removeAllBridges();

  Future<void> close();
}

/// SQLite implementation over [AppDatabase].
class SqfliteSampleDao implements SampleDao {
  SqfliteSampleDao(this._appDatabase);

  final AppDatabase _appDatabase;

  Database get _db => _appDatabase.database;

  @override
  Future<int> insertBatch({
    required String bridgeId,
    required int generation,
    required Iterable<DeviceSample> samples,
    required int syncWallMs,
    required int deviceMaxSeq,
  }) {
    return insertSamples(<StoredSample>[
      for (final sample in samples)
        StoredSample.fromDevice(
          bridgeId: bridgeId,
          generation: generation,
          sample: sample,
          syncWallMs: syncWallMs,
          deviceMaxSeq: deviceMaxSeq,
        ),
    ]);
  }

  @override
  Future<int> insertSamples(Iterable<StoredSample> samples) async {
    final rows = samples.toList(growable: false);
    if (rows.isEmpty) return 0;
    return _db.transaction<int>((txn) => _insertRows(txn, rows));
  }

  @override
  Future<int> storeSyncBatch({
    required String bridgeId,
    required int generation,
    required Iterable<StoredSample> samples,
    required int? cursorAfter,
    required int? cursorBefore,
    required int? deviceMinSeq,
    required int? deviceMaxSeq,
    required int lastSeenMs,
    Iterable<StoredGap> gaps = const <StoredGap>[],
  }) async {
    final rows = samples.toList(growable: false);
    final gapRows = gaps.toList(growable: false);
    return _db.transaction<int>((txn) async {
      final inserted = rows.isEmpty ? 0 : await _insertRows(txn, rows);
      final batch = txn.batch();
      for (final gap in gapRows) {
        batch.insert(
          'gap',
          gap.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (gapRows.isNotEmpty) await batch.commit(noResult: true);
      await _updateCursors(
        txn,
        bridgeId: bridgeId,
        generation: generation,
        cursorAfter: cursorAfter,
        cursorBefore: cursorBefore,
        deviceMinSeq: deviceMinSeq,
        deviceMaxSeq: deviceMaxSeq,
        lastSeenMs: lastSeenMs,
      );
      return inserted;
    });
  }

  @override
  Future<void> updateSyncCursors({
    required String bridgeId,
    required int generation,
    required int? cursorAfter,
    required int? cursorBefore,
    required int? deviceMinSeq,
    required int? deviceMaxSeq,
    required int lastSeenMs,
  }) {
    return _db.transaction<void>(
      (txn) => _updateCursors(
        txn,
        bridgeId: bridgeId,
        generation: generation,
        cursorAfter: cursorAfter,
        cursorBefore: cursorBefore,
        deviceMinSeq: deviceMinSeq,
        deviceMaxSeq: deviceMaxSeq,
        lastSeenMs: lastSeenMs,
      ),
    );
  }

  Future<void> _updateCursors(
    DatabaseExecutor txn, {
    required String bridgeId,
    required int generation,
    required int? cursorAfter,
    required int? cursorBefore,
    required int? deviceMinSeq,
    required int? deviceMaxSeq,
    required int lastSeenMs,
  }) async {
    await txn.update(
      'bridge',
      <String, Object?>{
        'generation': generation,
        'last_seen_ms': lastSeenMs,
        'cursor_after': cursorAfter,
        'cursor_before': cursorBefore,
        'device_min_seq': deviceMinSeq,
        'device_max_seq': deviceMaxSeq,
      },
      where: 'id = ?',
      whereArgs: <Object?>[bridgeId],
    );
  }

  /// Inserts rows inside an existing transaction. Shared by [insertSamples] and
  /// [storeSyncBatch] so a batch and its cursors never use two write paths.
  Future<int> _insertRows(DatabaseExecutor txn, List<StoredSample> rows) async {
    final before = Sqflite.firstIntValue(
      await txn.rawQuery('SELECT COUNT(*) FROM sample'),
    )!;
    final batch = txn.batch();
    for (final sample in rows) {
      final values = <Object?>[
        sample.bridgeId,
        sample.generation,
        sample.seq,
        sample.unixS,
        sample.recordedMs,
        sample.timeEstimated,
        sample.tempsF10[0],
        sample.tempsF10[1],
        sample.tempsF10[2],
        sample.tempsF10[3],
        sample.flags,
      ];
      // Portable across the Android system SQLite versions: never replace an
      // existing row, then upgrade it only if it was time-estimated and this
      // batch has the device's real clock.
      batch.rawInsert('''
        INSERT OR IGNORE INTO sample (
          bridge_id, generation, seq, unix_s, recorded_ms, time_estimated,
          p1, p2, p3, p4, flags
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', values);
      batch.rawUpdate(
        '''
        UPDATE sample SET
          unix_s = ?,
          recorded_ms = ?,
          time_estimated = ?,
          p1 = ?,
          p2 = ?,
          p3 = ?,
          p4 = ?,
          flags = ?
        WHERE bridge_id = ? AND generation = ? AND seq = ?
          AND time_estimated = 1 AND ? = 0
        ''',
        <Object?>[
          sample.unixS,
          sample.recordedMs,
          sample.timeEstimated,
          sample.tempsF10[0],
          sample.tempsF10[1],
          sample.tempsF10[2],
          sample.tempsF10[3],
          sample.flags,
          sample.bridgeId,
          sample.generation,
          sample.seq,
          sample.timeEstimated,
        ],
      );
    }
    await batch.commit(noResult: true);
    final after = Sqflite.firstIntValue(
      await txn.rawQuery('SELECT COUNT(*) FROM sample'),
    )!;
    return after - before;
  }

  @override
  Future<void> insertGaps(Iterable<StoredGap> gaps) async {
    final rows = gaps.toList(growable: false);
    if (rows.isEmpty) return;
    await _db.transaction<void>((txn) async {
      final batch = txn.batch();
      for (final gap in rows) {
        batch.insert(
          'gap',
          gap.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<List<StoredSample>> samplesInRange({
    required int fromMs,
    required int toMs,
    String? bridgeId,
    int? generation,
    int? limit,
    bool ascending = true,
  }) async {
    final where = <String>['recorded_ms >= ?', 'recorded_ms < ?'];
    final args = <Object?>[fromMs, toMs];
    if (bridgeId != null) {
      where.add('bridge_id = ?');
      args.add(bridgeId);
    }
    if (generation != null) {
      where.add('generation = ?');
      args.add(generation);
    }
    final rows = await _db.query(
      'sample',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'recorded_ms ${ascending ? 'ASC' : 'DESC'}, seq ASC',
      limit: limit,
    );
    return rows.map(StoredSample.fromRow).toList(growable: false);
  }

  @override
  Future<List<HistoryBucketRow>> bucketedSamplesInRange({
    required int fromMs,
    required int toMs,
    required int bucketMs,
    String? bridgeId,
    int? generation,
  }) async {
    final where = <String>['recorded_ms >= ?', 'recorded_ms < ?'];
    final args = <Object?>[fromMs, toMs];
    if (bridgeId != null) {
      where.add('bridge_id = ?');
      args.add(bridgeId);
    }
    if (generation != null) {
      where.add('generation = ?');
      args.add(generation);
    }
    final bucket = bucketMs <= 0 ? 1 : bucketMs;
    args.add(bucket);
    final rows = await _db.rawQuery('''
      SELECT MIN(recorded_ms) AS start_ms,
             MAX(recorded_ms) AS end_ms,
             AVG(p1) AS p1,
             AVG(p2) AS p2,
             AVG(p3) AS p3,
             AVG(p4) AS p4,
             MAX(time_estimated) AS estimated
      FROM sample
      WHERE ${where.join(' AND ')}
      GROUP BY CAST(recorded_ms / ? AS INTEGER)
      ORDER BY start_ms ASC
      ''', args);
    return rows.map(HistoryBucketRow.fromRow).toList(growable: false);
  }

  @override
  Future<List<HistoryProbeStatsRow>> probeStatsInRange({
    required int fromMs,
    required int toMs,
    String? bridgeId,
    int? generation,
  }) async {
    final where = <String>['recorded_ms >= ?', 'recorded_ms < ?'];
    final baseArgs = <Object?>[fromMs, toMs];
    if (bridgeId != null) {
      where.add('bridge_id = ?');
      baseArgs.add(bridgeId);
    }
    if (generation != null) {
      where.add('generation = ?');
      baseArgs.add(generation);
    }
    final clause = where.join(' AND ');
    final stats = <HistoryProbeStatsRow>[];
    for (var probe = 1; probe <= 4; probe++) {
      final column = 'p$probe';
      final aggregate = await _db.rawQuery('''
        SELECT MIN($column) AS min_value,
               MAX($column) AS max_value,
               COUNT($column) AS count
        FROM sample
        WHERE $clause
        ''', baseArgs);
      final aggregateRow = aggregate.first;
      final latest = await _db.rawQuery('''
        SELECT $column AS value, recorded_ms
        FROM sample
        WHERE $clause AND $column IS NOT NULL
        ORDER BY recorded_ms DESC, seq DESC
        LIMIT 1
        ''', baseArgs);
      final latestRow = latest.isEmpty ? null : latest.first;
      double? fahrenheit(Object? tenths) =>
          tenths == null ? null : (tenths as num).toDouble() / 10.0;
      stats.add(
        HistoryProbeStatsRow(
          probe: probe,
          readingCount: (aggregateRow['count'] as int?) ?? 0,
          latestF: fahrenheit(latestRow?['value']),
          latestMs: latestRow?['recorded_ms'] as int?,
          minF: fahrenheit(aggregateRow['min_value']),
          maxF: fahrenheit(aggregateRow['max_value']),
        ),
      );
    }
    return stats;
  }

  @override
  Future<(StoredSample?, StoredSample?)> samplesAroundSeq({
    required int fromSeq,
    required int toSeq,
    String? bridgeId,
    int? generation,
  }) async {
    Future<StoredSample?> adjacent({required bool below}) async {
      final where = <String>[below ? 'seq <= ?' : 'seq >= ?'];
      final args = <Object?>[below ? fromSeq : toSeq];
      if (bridgeId != null) {
        where.add('bridge_id = ?');
        args.add(bridgeId);
      }
      if (generation != null) {
        where.add('generation = ?');
        args.add(generation);
      }
      final rows = await _db.query(
        'sample',
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: below
            ? 'seq DESC, recorded_ms DESC'
            : 'seq ASC, recorded_ms ASC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return StoredSample.fromRow(rows.first);
    }

    final before = await adjacent(below: true);
    final after = await adjacent(below: false);
    return (before, after);
  }

  @override
  Future<List<StoredGap>> gapsInRange({
    required int fromMs,
    required int toMs,
    String? bridgeId,
    int? generation,
  }) async {
    final where = <String>['detected_ms >= ?', 'detected_ms < ?'];
    final args = <Object?>[fromMs, toMs];
    if (bridgeId != null) {
      where.add('bridge_id = ?');
      args.add(bridgeId);
    }
    if (generation != null) {
      where.add('generation = ?');
      args.add(generation);
    }
    final rows = await _db.query(
      'gap',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'generation ASC, from_seq ASC',
    );
    return rows.map(StoredGap.fromRow).toList(growable: false);
  }

  @override
  Future<List<StoredSample>> newestSamples({
    int limit = 1,
    String? bridgeId,
  }) async {
    final rows = await _db.query(
      'sample',
      where: bridgeId == null ? null : 'bridge_id = ?',
      whereArgs: bridgeId == null ? null : <Object?>[bridgeId],
      orderBy: 'recorded_ms DESC, seq DESC',
      limit: limit,
    );
    return rows.map(StoredSample.fromRow).toList(growable: false);
  }

  @override
  Future<int> countSamples({
    String? bridgeId,
    int? generation,
    int? fromMs,
    int? toMs,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (bridgeId != null) {
      where.add('bridge_id = ?');
      args.add(bridgeId);
    }
    if (generation != null) {
      where.add('generation = ?');
      args.add(generation);
    }
    if (fromMs != null) {
      where.add('recorded_ms >= ?');
      args.add(fromMs);
    }
    if (toMs != null) {
      where.add('recorded_ms < ?');
      args.add(toMs);
    }
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM sample'
      '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}',
      args,
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  @override
  Future<SampleExtent?> extent({String? bridgeId, int? generation}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (bridgeId != null) {
      where.add('bridge_id = ?');
      args.add(bridgeId);
    }
    if (generation != null) {
      where.add('generation = ?');
      args.add(generation);
    }
    final rows = await _db.rawQuery('''
      SELECT COUNT(*) AS count,
             MIN(seq) AS min_seq,
             MAX(seq) AS max_seq,
             MIN(recorded_ms) AS min_ms,
             MAX(recorded_ms) AS max_ms
      FROM sample
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ''', args);
    final row = rows.first;
    final count = (row['count'] as int?) ?? 0;
    if (count == 0) return null;
    return SampleExtent(
      count: count,
      minSeq: row['min_seq']! as int,
      maxSeq: row['max_seq']! as int,
      minRecordedMs: row['min_ms']! as int,
      maxRecordedMs: row['max_ms']! as int,
    );
  }

  @override
  Future<List<StoredGap>> gaps({String? bridgeId, int? generation}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (bridgeId != null) {
      where.add('bridge_id = ?');
      args.add(bridgeId);
    }
    if (generation != null) {
      where.add('generation = ?');
      args.add(generation);
    }
    final rows = await _db.query(
      'gap',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'generation ASC, from_seq ASC',
    );
    return rows.map(StoredGap.fromRow).toList(growable: false);
  }

  @override
  Future<HistoryDeletion> deleteRange({
    required int fromMs,
    required int toMs,
    String? bridgeId,
    int? generation,
  }) async {
    return _db.transaction<HistoryDeletion>((txn) async {
      final groupWhere = <String>['recorded_ms >= ?', 'recorded_ms < ?'];
      final groupArgs = <Object?>[fromMs, toMs];
      if (bridgeId != null) {
        groupWhere.add('bridge_id = ?');
        groupArgs.add(bridgeId);
      }
      if (generation != null) {
        groupWhere.add('generation = ?');
        groupArgs.add(generation);
      }
      final groups = await txn.rawQuery('''
        SELECT bridge_id, generation, MIN(seq) AS min_seq, MAX(seq) AS max_seq
        FROM sample
        WHERE ${groupWhere.join(' AND ')}
        GROUP BY bridge_id, generation
        ''', groupArgs);

      var gapsDeleted = 0;
      var gapsTrimmed = 0;
      final touchedRows = <int>{};

      for (final group in groups) {
        final groupBridge = group['bridge_id']! as String;
        final groupGeneration = group['generation']! as int;
        final minSeq = group['min_seq']! as int;
        final maxSeq = group['max_seq']! as int;
        final overlapping = await txn.rawQuery(
          '''
          SELECT rowid AS row_id, from_seq, to_seq, reason, detected_ms
          FROM gap
          WHERE bridge_id = ? AND generation = ?
            AND from_seq <= ? AND to_seq >= ?
          ''',
          <Object?>[groupBridge, groupGeneration, maxSeq, minSeq],
        );
        for (final gap in overlapping) {
          final rowId = gap['row_id']! as int;
          final fromSeq = gap['from_seq']! as int;
          final toSeq = gap['to_seq']! as int;
          final leftRemains = fromSeq < minSeq;
          final rightRemains = toSeq > maxSeq;
          if (leftRemains && rightRemains) {
            await txn.update(
              'gap',
              <String, Object?>{'to_seq': minSeq - 1},
              where: 'rowid = ?',
              whereArgs: <Object?>[rowId],
            );
            final newRowId = await txn.insert('gap', <String, Object?>{
              'bridge_id': groupBridge,
              'generation': groupGeneration,
              'from_seq': maxSeq + 1,
              'to_seq': toSeq,
              'reason': gap['reason'],
              'detected_ms': gap['detected_ms'],
            }, conflictAlgorithm: ConflictAlgorithm.replace);
            gapsTrimmed++;
            touchedRows
              ..add(rowId)
              ..add(newRowId);
          } else if (leftRemains) {
            await txn.update(
              'gap',
              <String, Object?>{'to_seq': minSeq - 1},
              where: 'rowid = ?',
              whereArgs: <Object?>[rowId],
            );
            gapsTrimmed++;
            touchedRows.add(rowId);
          } else if (rightRemains) {
            // Trim in place: replacing the row would make the new row visible to
            // the detected-in-range sweep below and silently drop the kept tail.
            await txn.update(
              'gap',
              <String, Object?>{'from_seq': maxSeq + 1},
              where: 'rowid = ?',
              whereArgs: <Object?>[rowId],
            );
            gapsTrimmed++;
            touchedRows.add(rowId);
          } else {
            await txn.delete(
              'gap',
              where: 'rowid = ?',
              whereArgs: <Object?>[rowId],
            );
            gapsDeleted++;
            touchedRows.add(rowId);
          }
        }
      }

      final deleteWhere = <String>['recorded_ms >= ?', 'recorded_ms < ?'];
      final deleteArgs = <Object?>[fromMs, toMs];
      if (bridgeId != null) {
        deleteWhere.add('bridge_id = ?');
        deleteArgs.add(bridgeId);
      }
      if (generation != null) {
        deleteWhere.add('generation = ?');
        deleteArgs.add(generation);
      }
      final samplesDeleted = await txn.delete(
        'sample',
        where: deleteWhere.join(' AND '),
        whereArgs: deleteArgs,
      );

      final gapWhere = <String>['detected_ms >= ?', 'detected_ms < ?'];
      final gapArgs = <Object?>[fromMs, toMs];
      if (bridgeId != null) {
        gapWhere.add('bridge_id = ?');
        gapArgs.add(bridgeId);
      }
      if (generation != null) {
        gapWhere.add('generation = ?');
        gapArgs.add(generation);
      }
      if (touchedRows.isNotEmpty) {
        gapWhere.add(
          'rowid NOT IN (${List.filled(touchedRows.length, '?').join(',')})',
        );
        gapArgs.addAll(touchedRows);
      }
      gapsDeleted += await txn.delete(
        'gap',
        where: gapWhere.join(' AND '),
        whereArgs: gapArgs,
      );

      return HistoryDeletion(
        samplesDeleted: samplesDeleted,
        gapsDeleted: gapsDeleted,
        gapsTrimmed: gapsTrimmed,
      );
    });
  }

  @override
  Future<SavedBridge?> savedBridge() async {
    final rows = await _db.query(
      'bridge',
      orderBy: 'last_seen_ms DESC, id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SavedBridge.fromRow(rows.first);
  }

  @override
  Future<SavedBridge?> bridgeById(String id) async {
    final rows = await _db.query(
      'bridge',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SavedBridge.fromRow(rows.first);
  }

  @override
  Future<void> saveBridge(SavedBridge bridge) async {
    await _db.insert(
      'bridge',
      bridge.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> touchBridge({
    required String id,
    required String name,
    required int lastSeenMs,
    int? generation,
  }) async {
    await _db.transaction<void>((txn) async {
      await txn.rawInsert(
        '''
        INSERT OR IGNORE INTO bridge (id, name, last_seen_ms, generation)
        VALUES (?, ?, ?, ?)
        ''',
        <Object?>[id, name, lastSeenMs, generation ?? 0],
      );
      await txn.rawUpdate(
        '''
        UPDATE bridge SET
          name = ?,
          last_seen_ms = ?,
          generation = COALESCE(?, generation)
        WHERE id = ?
        ''',
        <Object?>[name, lastSeenMs, generation, id],
      );
    });
  }

  @override
  Future<bool> removeBridge(String id) async {
    final deleted = await _db.delete(
      'bridge',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return deleted > 0;
  }

  @override
  Future<int> removeAllBridges() => _db.delete('bridge');

  @override
  Future<void> close() => _appDatabase.close();
}
