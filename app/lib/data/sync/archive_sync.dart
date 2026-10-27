import 'dart:async';
import 'dart:math' as math;

import '../ble/bridge_protocol.dart';
import '../db/sample_dao.dart';

/// Durable sync state, separate from the UI's [SyncState] vocabulary.
///
/// - [idle]: no pass has run yet (or the link is disconnected);
/// - [syncing]: a recent-first or forward pass is in flight;
/// - [partial]: the recent 24 h slice is stored, older backfill continues;
/// - [complete]: the device extent has been covered (or it is empty);
/// - [error]: the pass gave up after its bounded retries.
enum SyncStatus { idle, syncing, partial, complete, error }

/// Which leg of the two-phase sync is running.
///
/// `backfill` is internal only: the product copy is `Syncing saved readings`
/// for [recent] and `Loading saved readings` for [backfill].
enum SyncPhase { idle, recent, backfill, forward }

/// The approved gap reasons from 04 §4.6. Do not invent a fourth.
const String syncGapNoSignal = 'No signal';
const String syncGapBridgeOff = 'Bridge off';
const String syncGapNotSynced = 'Not synced';

// Wire `sync.status` values (05 §5.8). Named locally so the archive does not
// depend on the generated test codecs.
const int _syncStatusGap = 1;
const int _syncStatusError = 2;

/// One immutable sync-status report for the status model and the UI seam.
class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.status,
    required this.phase,
    required this.generation,
    required this.storedRecords,
    required this.cursorAfter,
    required this.cursorBefore,
    required this.deviceMinSeq,
    required this.deviceMaxSeq,
    required this.deviceEmpty,
    this.error,
  });

  static const SyncStatusSnapshot idle = SyncStatusSnapshot(
    status: SyncStatus.idle,
    phase: SyncPhase.idle,
    generation: 0,
    storedRecords: 0,
    cursorAfter: null,
    cursorBefore: null,
    deviceMinSeq: null,
    deviceMaxSeq: null,
    deviceEmpty: false,
  );

  final SyncStatus status;
  final SyncPhase phase;
  final int generation;

  /// Rows stored by this coordinator's current pass.
  final int storedRecords;
  final int? cursorAfter;
  final int? cursorBefore;
  final int? deviceMinSeq;
  final int? deviceMaxSeq;

  /// The bridge log is empty (`min_seq = max_seq = 0xFFFFFFFF`).
  final bool deviceEmpty;
  final String? error;

  bool get isRunning =>
      status == SyncStatus.syncing || status == SyncStatus.partial;

  SyncStatusSnapshot copyWith({
    SyncStatus? status,
    SyncPhase? phase,
    int? generation,
    int? storedRecords,
    int? cursorAfter,
    int? cursorBefore,
    int? deviceMinSeq,
    int? deviceMaxSeq,
    bool? deviceEmpty,
    String? error,
    bool clearError = false,
  }) => SyncStatusSnapshot(
    status: status ?? this.status,
    phase: phase ?? this.phase,
    generation: generation ?? this.generation,
    storedRecords: storedRecords ?? this.storedRecords,
    cursorAfter: cursorAfter ?? this.cursorAfter,
    cursorBefore: cursorBefore ?? this.cursorBefore,
    deviceMinSeq: deviceMinSeq ?? this.deviceMinSeq,
    deviceMaxSeq: deviceMaxSeq ?? this.deviceMaxSeq,
    deviceEmpty: deviceEmpty ?? this.deviceEmpty,
    error: clearError ? null : (error ?? this.error),
  );
}

/// One accepted batch, delivered so the current-session History store can
/// repaint without a second request path.
class StoredSyncBatch {
  const StoredSyncBatch({
    required this.records,
    required this.generation,
    required this.direction,
  });

  final List<BridgeSampleRecord> records;
  final int generation;
  final BridgeSyncDirection direction;
}

/// The request seam the coordinator needs. [BridgeLink] implements it over the
/// live GATT subscription; host tests implement it with a deterministic ring.
abstract interface class SyncTransport {
  Future<BridgeSyncStream> request(BridgeSyncRequest request);
}

class SyncException implements Exception {
  const SyncException(this.message);

  final String message;

  @override
  String toString() => 'SyncException: $message';
}

/// Durable, resumable two-phase sync over [SampleDao].
///
/// The coordinator owns no timer and no BLE transport. One caller (the link)
/// drives it: `connectSync` on connect/reconnect, `catchUp` for the existing
/// 30 s quiet pass, and `recordLive` for every live notification. That keeps a
/// single cadence and a single live-append path.
class ArchiveSyncCoordinator {
  ArchiveSyncCoordinator({
    required this.dao,
    DateTime Function()? now,
    this.recentTargetRecords = 2880,
    this.recentPageSize = 32,
    this.backfillPageSize = 64,
    this.forwardPageSize = 32,
    this.maxForwardPages = 64,
    this.maxAttempts = 3,
    this.onStatus,
    this.onBatch,
  }) : _now = now ?? DateTime.now;

  final SampleDao dao;
  final DateTime Function() _now;
  final int recentTargetRecords;
  final int recentPageSize;
  final int backfillPageSize;
  final int forwardPageSize;
  final int maxForwardPages;

  /// Per-request attempts. A frame hole, timeout or transport drop discards the
  /// partial batch and re-requests the same cursor.
  final int maxAttempts;

  final void Function(SyncStatusSnapshot snapshot)? onStatus;
  final void Function(StoredSyncBatch batch)? onBatch;

  String? _bridgeId;
  String? _bridgeName;
  int _generation = 0;
  int? _cursorAfter;
  int? _cursorBefore;
  int? _deviceMin;
  int? _deviceMax;
  bool _deviceEmpty = false;
  int _storedThisPass = 0;
  int _generationRestarts = 0;
  SyncStatusSnapshot _snapshot = SyncStatusSnapshot.idle;
  bool _disposed = false;
  Future<SyncStatusSnapshot>? _backfillFuture;
  Future<void> _queue = Future<void>.value();

  SyncStatusSnapshot get snapshot => _snapshot;

  /// Completes when the background backfill started by the last connect/catch-up
  /// finishes. Tests and the reconnect path await this; the UI never does.
  Future<SyncStatusSnapshot> get backfillDone =>
      _backfillFuture ?? Future<SyncStatusSnapshot>.value(_snapshot);

  /// Stops the background backfill. In-flight requests are allowed to fail; the
  /// next connect resumes from the last committed cursor.
  void dispose() {
    _disposed = true;
  }

  /// Serialises transport use so the 30 s pass and the background backfill never
  /// interleave requests on the single sync stream.
  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  String? get bridgeId => _bridgeId;
  int get generation => _generation;
  int? get cursorAfter => _cursorAfter;
  bool get hasData => _cursorAfter != null;

  /// First sync and every reconnect: read the device extent, then either start
  /// the recent-first/backfill sequence or catch up forward from local data.
  Future<SyncStatusSnapshot> connectSync({
    required SyncTransport transport,
    required String bridgeId,
    required String bridgeName,
  }) async {
    final result = await _serialize(
      () => _connectSyncLocked(
        transport: transport,
        bridgeId: bridgeId,
        bridgeName: bridgeName,
      ),
    );
    if (result.status == SyncStatus.partial) {
      _startBackfill(transport);
    }
    return result;
  }

  Future<SyncStatusSnapshot> _connectSyncLocked({
    required SyncTransport transport,
    required String bridgeId,
    required String bridgeName,
  }) async {
    _disposed = false;
    _bridgeId = bridgeId;
    _bridgeName = bridgeName;
    _storedThisPass = 0;
    _generationRestarts = 0;
    _emit(SyncStatus.syncing, SyncPhase.recent);

    final status = await _readWithRetry(
      transport,
      const BridgeSyncRequest(
        cmd: BridgeSyncCmd.status,
        direction: BridgeSyncDirection.backward,
        cursorSeq: 0,
        maxRecords: 0,
      ),
    );
    _generation = status.start.generation;

    if (_isError(status)) {
      return _fail('status request returned error');
    }
    if (_isEmpty(status)) {
      return _finishEmpty();
    }

    _deviceMin = status.start.minSeq;
    _deviceMax = status.start.maxSeq;
    _deviceEmpty = false;

    final saved = await dao.bridgeById(bridgeId);
    final sameEpoch = saved != null && saved.generation == _generation;
    if (!sameEpoch) {
      // A generation change is an epoch boundary, not a delete. The old rows
      // stay readable; this segment starts with fresh cursors.
      _cursorAfter = null;
      _cursorBefore = null;
    } else {
      _cursorAfter = saved.cursorAfter;
      _cursorBefore = saved.cursorBefore;
    }
    await _ensureBridgeRow(
      generation: _generation,
      minSeq: _deviceMin,
      maxSeq: _deviceMax,
    );
    if (!sameEpoch) {
      await dao.updateSyncCursors(
        bridgeId: bridgeId,
        generation: _generation,
        cursorAfter: null,
        cursorBefore: null,
        deviceMinSeq: _deviceMin,
        deviceMaxSeq: _deviceMax,
        lastSeenMs: _now().millisecondsSinceEpoch,
      );
    }

    final local = await dao.extent(bridgeId: bridgeId, generation: _generation);
    if (local == null) {
      return _backwardRecentFirst(transport, recentOnly: true);
    }
    _cursorAfter = local.maxSeq;
    _cursorBefore = local.minSeq;
    if (_deviceMin != null && local.minSeq > _deviceMin!) {
      // Recent-first finished but the older backfill did not: tell the caller
      // the archive is partial and continue in the background.
      _emit(SyncStatus.partial, SyncPhase.backfill);
      return _snapshot;
    }
    return _forwardCatchUp(transport, from: local.maxSeq);
  }

  /// The 30 s quiet pass and reconnect catch-up. It never re-reads the recent
  /// window; it finishes any interrupted backfill, then starts forward from the
  /// local maximum sequence.
  Future<SyncStatusSnapshot> catchUp({required SyncTransport transport}) async {
    final result = await _serialize(() => _catchUpLocked(transport));
    if (result.status == SyncStatus.partial) {
      _startBackfill(transport);
    }
    return result;
  }

  Future<SyncStatusSnapshot> _catchUpLocked(SyncTransport transport) async {
    final bridgeId = _bridgeId;
    if (bridgeId == null) {
      throw const SyncException('catchUp before connectSync');
    }
    _storedThisPass = 0;
    _generationRestarts = 0;

    final status = await _readWithRetry(
      transport,
      const BridgeSyncRequest(
        cmd: BridgeSyncCmd.status,
        direction: BridgeSyncDirection.backward,
        cursorSeq: 0,
        maxRecords: 0,
      ),
    );
    if (_isError(status)) {
      return _fail('status request returned error');
    }
    if (_isEmpty(status)) {
      return _finishEmpty();
    }
    if (status.start.generation != _generation) {
      _generation = status.start.generation;
      _cursorAfter = null;
      _cursorBefore = null;
      _deviceMin = status.start.minSeq;
      _deviceMax = status.start.maxSeq;
      await _ensureBridgeRow(
        generation: _generation,
        minSeq: _deviceMin,
        maxSeq: _deviceMax,
      );
      await dao.updateSyncCursors(
        bridgeId: bridgeId,
        generation: _generation,
        cursorAfter: null,
        cursorBefore: null,
        deviceMinSeq: _deviceMin,
        deviceMaxSeq: _deviceMax,
        lastSeenMs: _now().millisecondsSinceEpoch,
      );
      return _backwardRecentFirst(transport);
    }
    _deviceMin = status.start.minSeq;
    _deviceMax = status.start.maxSeq;
    _deviceEmpty = false;

    final local = await dao.extent(bridgeId: bridgeId, generation: _generation);
    if (local == null) {
      return _backwardRecentFirst(transport, recentOnly: true);
    }
    _cursorAfter = local.maxSeq;
    _cursorBefore = local.minSeq;
    if (_deviceMin != null && local.minSeq > _deviceMin!) {
      _emit(SyncStatus.partial, SyncPhase.backfill);
      return _snapshot;
    }
    return _forwardCatchUp(transport, from: local.maxSeq);
  }

  void _startBackfill(SyncTransport transport) {
    if (_disposed || _backfillFuture != null) return;
    final future = _serialize(() => _runBackfill(transport));
    _backfillFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_backfillFuture, future)) _backfillFuture = null;
      }),
    );
  }

  Future<SyncStatusSnapshot> _runBackfill(SyncTransport transport) async {
    if (_disposed) return _snapshot;
    final before = _cursorBefore;
    final deviceMin = _deviceMin;
    if (before == null || deviceMin == null || before <= deviceMin) {
      return _snapshot;
    }
    try {
      // Lower-priority continuation of the backward pass. One request and one
      // transaction at a time, exactly like the recent pass.
      return await _backwardRecentFirst(
        transport,
        resumeBefore: before,
        recentDone: true,
      );
    } catch (error) {
      return _fail('backfill stopped: $error');
    }
  }

  /// Appends one live notification by sequence. Duplicate sequences are no-ops
  /// (the DAO primary key). The forward cursor only advances when the record is
  /// contiguous; a missed notification is left for the next forward pass.
  Future<void> recordLive({
    required BridgeLive live,
    required DateTime receivedAt,
  }) async {
    final bridgeId = _bridgeId;
    if (bridgeId == null || live.seq == bleSeqNone) return;
    final deviceMaxSeq = math.max(_deviceMax ?? live.seq, live.seq);
    final known = live.clockValid;
    final unixS = known
        ? (math.max(0, receivedAt.millisecondsSinceEpoch ~/ 1000 - live.ageS))
        : null;
    final flags =
        <int>[
          for (var index = 0; index < 4; index++)
            live.tempsF10[index] == bleTempDetached ||
                    live.tempsF10[index] == bleTempInvalid
                ? 0
                : 1 << index,
        ].fold<int>(
          (live.billowsAttached ? 1 << 4 : 0) | (known ? 1 << 5 : 0),
          (value, bit) => value | bit,
        );
    final sample = DeviceSample(
      seq: live.seq,
      unixS: unixS,
      tempsF10: live.tempsF10,
      flags: flags,
      clockValid: known,
    );

    var nextAfter = _cursorAfter;
    if (nextAfter != null && live.seq == nextAfter + 1) {
      nextAfter = live.seq;
    }
    var nextBefore = _cursorBefore;
    if (nextBefore == null && _cursorAfter == null) {
      // Do not claim a contiguous archive from one live packet.
      nextBefore = null;
    }
    await dao.storeSyncBatch(
      bridgeId: bridgeId,
      generation: _generation,
      samples: <StoredSample>[
        StoredSample.fromDevice(
          bridgeId: bridgeId,
          generation: _generation,
          sample: sample,
          syncWallMs: receivedAt.millisecondsSinceEpoch,
          deviceMaxSeq: deviceMaxSeq,
        ),
      ],
      cursorAfter: nextAfter,
      cursorBefore: nextBefore,
      deviceMinSeq: _deviceMin,
      deviceMaxSeq: deviceMaxSeq,
      lastSeenMs: receivedAt.millisecondsSinceEpoch,
    );
    _cursorAfter = nextAfter;
    _deviceMax = deviceMaxSeq;
    onBatch?.call(
      StoredSyncBatch(
        records: <BridgeSampleRecord>[
          BridgeSampleRecord(
            seq: live.seq,
            unixS: unixS ?? 0,
            tempsF10: live.tempsF10,
            flags: flags,
          ),
        ],
        generation: _generation,
        direction: BridgeSyncDirection.forward,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Backward recent-first + background backfill
  // ---------------------------------------------------------------------------

  Future<SyncStatusSnapshot> _backwardRecentFirst(
    SyncTransport transport, {
    int? resumeBefore,
    bool recentDone = false,
    bool recentOnly = false,
  }) async {
    final deviceMin = _deviceMin;
    final deviceMax = _deviceMax;
    if (deviceMin == null || deviceMax == null) {
      return _finishEmpty();
    }

    var cursor = resumeBefore ?? deviceMax + 1;
    _emit(
      SyncStatus.syncing,
      recentDone ? SyncPhase.backfill : SyncPhase.recent,
    );

    while (true) {
      if (_disposed) return _snapshot;
      final request = BridgeSyncRequest(
        cmd: BridgeSyncCmd.read,
        direction: BridgeSyncDirection.backward,
        cursorSeq: cursor,
        maxRecords: recentDone ? backfillPageSize : recentPageSize,
      );
      final stream = await _readWithRetry(transport, request);

      if (await _maybeRestartGeneration(transport, stream)) {
        return _snapshot;
      }
      if (_isEmpty(stream)) {
        return _finishEmpty();
      }
      if (_isError(stream)) {
        return _fail('device returned error for backward cursor $cursor');
      }
      if (stream.start.count == 0 || stream.records.isEmpty) {
        // `count = 0` is the only stop condition, for both directions. A
        // backward cursor of 0 is a real cursor, never a stop sentinel.
        break;
      }
      _checkContiguous(stream, cursor: cursor);
      final records = stream.records;
      if (records.first.seq >= cursor) {
        return _fail('backward cursor $cursor did not advance');
      }

      _deviceMin = stream.start.minSeq;
      _deviceMax = stream.start.maxSeq;
      final nextLow = _cursorBefore == null
          ? records.first.seq
          : math.min(_cursorBefore!, records.first.seq);
      final nextHigh = _cursorAfter == null
          ? records.last.seq
          : math.max(_cursorAfter!, records.last.seq);
      await _storeRecords(
        records,
        direction: BridgeSyncDirection.backward,
        cursorAfter: nextHigh,
        cursorBefore: nextLow,
      );
      _cursorBefore = nextLow;
      _cursorAfter = nextHigh;
      _storedThisPass += records.length;

      final nextCursor = stream.end.nextSeq;
      if (nextCursor == cursor) {
        return _fail('backward cursor $cursor did not move');
      }
      cursor = nextCursor;

      if (!recentDone && _storedThisPass >= recentTargetRecords) {
        recentDone = true;
        _emit(SyncStatus.partial, SyncPhase.backfill);
        if (recentOnly) {
          // History is useful now; the older backfill continues in the
          // background without holding up the live view.
          return _snapshot;
        }
      } else {
        _emit(
          SyncStatus.syncing,
          recentDone ? SyncPhase.backfill : SyncPhase.recent,
        );
      }
      // Lower-priority backfill: yield between requests so the UI and live
      // notifications are not starved. Still one request/transaction at a time.
      await Future<void>.delayed(Duration.zero);
    }

    if (recentDone) {
      _emit(SyncStatus.syncing, SyncPhase.forward);
    }
    return _forwardCatchUp(transport, from: _cursorAfter ?? deviceMax);
  }

  // ---------------------------------------------------------------------------
  // Forward catch-up
  // ---------------------------------------------------------------------------

  Future<SyncStatusSnapshot> _forwardCatchUp(
    SyncTransport transport, {
    required int from,
  }) async {
    _emit(SyncStatus.syncing, SyncPhase.forward);
    var cursor = from;
    var pages = 0;

    while (pages < maxForwardPages) {
      pages++;
      final stream = await _readWithRetry(
        transport,
        BridgeSyncRequest(
          cmd: BridgeSyncCmd.read,
          direction: BridgeSyncDirection.forward,
          cursorSeq: cursor,
          maxRecords: forwardPageSize,
        ),
      );

      if (await _maybeRestartGeneration(transport, stream)) {
        return _snapshot;
      }
      if (_isEmpty(stream)) {
        return _finishEmpty();
      }
      if (_isError(stream)) {
        return _fail('device returned error for forward cursor $cursor');
      }
      if (stream.start.count == 0 || stream.records.isEmpty) {
        break;
      }
      _checkContiguous(stream, cursor: cursor, forward: true);

      _deviceMin = stream.start.minSeq;
      _deviceMax = stream.start.maxSeq;
      final gaps = <StoredGap>[];
      if (stream.start.status == _syncStatusGap ||
          stream.end.status == _syncStatusGap) {
        // The ring rotated past the app's cursor: the range the device no longer
        // holds becomes a permanent gap, then sync continues from its extent.
        final gapFrom = cursor + 1;
        final gapTo = stream.start.startSeq - 1;
        if (gapTo >= gapFrom) {
          gaps.add(
            StoredGap(
              bridgeId: _bridgeId!,
              generation: _generation,
              fromSeq: gapFrom,
              toSeq: gapTo,
              reason: syncGapNotSynced,
              detectedMs: _now().millisecondsSinceEpoch,
            ),
          );
        }
      }

      final records = stream.records;
      final nextLow = _cursorBefore == null
          ? records.first.seq
          : math.min(_cursorBefore!, records.first.seq);
      final nextHigh = _cursorAfter == null
          ? records.last.seq
          : math.max(_cursorAfter!, records.last.seq);
      await _storeRecords(
        records,
        direction: BridgeSyncDirection.forward,
        cursorAfter: nextHigh,
        cursorBefore: nextLow,
        gaps: gaps,
      );
      _cursorBefore = nextLow;
      _cursorAfter = nextHigh;
      _storedThisPass += records.length;

      if (records.last.seq <= cursor) {
        return _fail('forward cursor $cursor did not advance');
      }
      cursor = records.last.seq;
      if (stream.start.count < forwardPageSize) break;
    }

    if (pages >= maxForwardPages) {
      return _emitResult(
        _snapshot.copyWith(
          status: SyncStatus.partial,
          phase: SyncPhase.forward,
        ),
      );
    }
    return _emitResult(
      _snapshot.copyWith(
        status: SyncStatus.complete,
        phase: SyncPhase.idle,
        clearError: true,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<void> _ensureBridgeRow({
    required int generation,
    required int? minSeq,
    required int? maxSeq,
  }) async {
    final id = _bridgeId!;
    final existing = await dao.bridgeById(id);
    if (existing == null) {
      await dao.saveBridge(
        SavedBridge(
          id: id,
          name: _bridgeName ?? id,
          lastSeenMs: _now().millisecondsSinceEpoch,
          generation: generation,
          deviceMinSeq: minSeq,
          deviceMaxSeq: maxSeq,
        ),
      );
      return;
    }
    await dao.updateSyncCursors(
      bridgeId: id,
      generation: generation,
      cursorAfter: existing.generation == generation
          ? existing.cursorAfter
          : null,
      cursorBefore: existing.generation == generation
          ? existing.cursorBefore
          : null,
      deviceMinSeq: minSeq,
      deviceMaxSeq: maxSeq,
      lastSeenMs: _now().millisecondsSinceEpoch,
    );
  }

  Future<void> _storeRecords(
    List<BridgeSampleRecord> records, {
    required BridgeSyncDirection direction,
    required int? cursorAfter,
    required int? cursorBefore,
    List<StoredGap> gaps = const <StoredGap>[],
  }) async {
    final bridgeId = _bridgeId!;
    final deviceMax = _deviceMax ?? records.last.seq;
    final wallMs = _now().millisecondsSinceEpoch;
    await dao.storeSyncBatch(
      bridgeId: bridgeId,
      generation: _generation,
      samples: <StoredSample>[
        for (final record in records)
          StoredSample.fromDevice(
            bridgeId: bridgeId,
            generation: _generation,
            sample: DeviceSample(
              seq: record.seq,
              unixS: record.unixS == 0 ? null : record.unixS,
              tempsF10: record.tempsF10,
              flags: record.flags,
              clockValid: record.clockValid,
            ),
            syncWallMs: wallMs,
            deviceMaxSeq: deviceMax,
          ),
      ],
      cursorAfter: cursorAfter,
      cursorBefore: cursorBefore,
      deviceMinSeq: _deviceMin,
      deviceMaxSeq: _deviceMax,
      lastSeenMs: wallMs,
      gaps: gaps,
    );
    onBatch?.call(
      StoredSyncBatch(
        records: records,
        generation: _generation,
        direction: direction,
      ),
    );
  }

  /// A START carrying a different generation is a new epoch. Keep the old rows,
  /// reset this segment's cursors and start recent-first for the new segment.
  Future<bool> _maybeRestartGeneration(
    SyncTransport transport,
    BridgeSyncStream stream,
  ) async {
    if (stream.start.generation == _generation) return false;
    if (_generationRestarts >= 2) {
      _fail('generation kept changing');
      return true;
    }
    _generationRestarts++;
    _generation = stream.start.generation;
    _cursorAfter = null;
    _cursorBefore = null;
    _deviceMin = stream.start.minSeq;
    _deviceMax = stream.start.maxSeq;
    await _ensureBridgeRow(
      generation: _generation,
      minSeq: _deviceMin,
      maxSeq: _deviceMax,
    );
    await dao.updateSyncCursors(
      bridgeId: _bridgeId!,
      generation: _generation,
      cursorAfter: null,
      cursorBefore: null,
      deviceMinSeq: _deviceMin,
      deviceMaxSeq: _deviceMax,
      lastSeenMs: _now().millisecondsSinceEpoch,
    );
    final result = await _backwardRecentFirst(transport, recentOnly: true);
    _snapshot = result;
    return true;
  }

  void _checkContiguous(
    BridgeSyncStream stream, {
    required int cursor,
    bool forward = false,
  }) {
    final records = stream.records;
    if (records.isEmpty) return;
    for (var index = 1; index < records.length; index++) {
      if (records[index].seq != records[index - 1].seq + 1) {
        throw SyncException(
          'sync batch has a sequence hole at '
          '${records[index - 1].seq} -> ${records[index].seq}',
        );
      }
    }
    if (forward && records.first.seq <= cursor) {
      throw SyncException(
        'forward batch starts at ${records.first.seq}, not above $cursor',
      );
    }
  }

  Future<BridgeSyncStream> _readWithRetry(
    SyncTransport transport,
    BridgeSyncRequest request,
  ) async {
    Object? last;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await transport.request(request);
      } catch (error) {
        last = error;
        await Future<void>.delayed(Duration.zero);
      }
    }
    throw SyncException('sync request failed after $maxAttempts: $last');
  }

  /// An empty *whole log* is the sentinel extent, not merely a drained
  /// direction. A backward cursor of 0 returns `count = 0` with a normal
  /// extent and must not be mistaken for an empty bridge.
  bool _isEmpty(BridgeSyncStream stream) =>
      stream.start.minSeq == bleSeqNone && stream.start.maxSeq == bleSeqNone;

  bool _isError(BridgeSyncStream stream) =>
      stream.start.status == _syncStatusError ||
      stream.end.status == _syncStatusError;

  Future<SyncStatusSnapshot> _finishEmpty() async {
    _deviceEmpty = true;
    _deviceMin = null;
    _deviceMax = null;
    final bridgeId = _bridgeId;
    if (bridgeId != null) {
      final existing = await dao.bridgeById(bridgeId);
      if (existing == null) {
        await dao.saveBridge(
          SavedBridge(
            id: bridgeId,
            name: _bridgeName ?? bridgeId,
            lastSeenMs: _now().millisecondsSinceEpoch,
            generation: _generation,
          ),
        );
        _cursorAfter = null;
        _cursorBefore = null;
      } else if (existing.generation == _generation) {
        _cursorAfter = existing.cursorAfter;
        _cursorBefore = existing.cursorBefore;
        await dao.updateSyncCursors(
          bridgeId: bridgeId,
          generation: _generation,
          cursorAfter: existing.cursorAfter,
          cursorBefore: existing.cursorBefore,
          deviceMinSeq: null,
          deviceMaxSeq: null,
          lastSeenMs: _now().millisecondsSinceEpoch,
        );
      } else {
        _cursorAfter = null;
        _cursorBefore = null;
      }
    }
    return _emitResult(
      _snapshot.copyWith(
        status: SyncStatus.complete,
        phase: SyncPhase.idle,
        deviceEmpty: true,
        clearError: true,
      ),
    );
  }

  SyncStatusSnapshot _fail(String message) {
    return _emitResult(
      _snapshot.copyWith(status: SyncStatus.error, error: message),
    );
  }

  void _emit(SyncStatus status, SyncPhase phase) {
    _emitResult(_snapshot.copyWith(status: status, phase: phase));
  }

  SyncStatusSnapshot _emitResult(SyncStatusSnapshot snapshot) {
    // copyWith cannot clear nullable fields, so the authoritative cursor values
    // are always rebuilt explicitly.
    _snapshot = SyncStatusSnapshot(
      status: snapshot.status,
      phase: snapshot.phase,
      generation: _generation,
      storedRecords: _storedThisPass,
      cursorAfter: _cursorAfter,
      cursorBefore: _cursorBefore,
      deviceMinSeq: _deviceMin,
      deviceMaxSeq: _deviceMax,
      deviceEmpty: _deviceEmpty,
      error: snapshot.error,
    );
    onStatus?.call(_snapshot);
    return _snapshot;
  }
}
