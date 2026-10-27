import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/models.dart';
import 'ble_client.dart';
import 'bridge_codecs.dart';
import 'bridge_protocol.dart';

/// One live sample plus the phone's receipt time.
class BridgeLiveUpdate {
  const BridgeLiveUpdate({required this.live, required this.receivedAt});

  final BridgeLive live;
  final DateTime receivedAt;
}

/// What the link procedure needs from the app state layer.
class BridgeLinkHost {
  const BridgeLinkHost({
    required this.onPhase,
    required this.onLive,
    this.onInfo,
    this.onSync,
    this.onReconnect,
    this.onBondPrompt,
  });

  final void Function(ConnectionPhase phase) onPhase;
  final void Function(BridgeLiveUpdate update) onLive;
  final void Function(BridgeInfo info)? onInfo;
  final void Function(BridgeSyncProgress progress)? onSync;

  /// `attempt` is 1-based; `nextDelay` is null once the attempts are exhausted.
  final void Function(int attempt, int total, Duration? nextDelay)? onReconnect;

  /// Shows the "look at the Bridge screen" instruction and starts the OS bond
  /// when the user agrees. Returning false cancels the procedure.
  final Future<bool> Function()? onBondPrompt;
}

/// Sync progress as the UI vocabulary expects it: the recent pass says
/// `Syncing saved readings`, background loading says `Loading saved readings`.
class BridgeSyncProgress {
  const BridgeSyncProgress({
    required this.state,
    required this.percent,
    this.storedRecords = 0,
    this.error,
  });

  final SyncState state;
  final int percent;
  final int storedRecords;
  final String? error;
}

/// A completed sync batch, handed to the archive seam (T39–T41).
class BridgeSyncBatch {
  const BridgeSyncBatch({
    required this.records,
    required this.startSeq,
    required this.endSeq,
    required this.nextSeq,
    required this.direction,
    required this.generation,
  });

  final List<BridgeSampleRecord> records;
  final int startSeq;
  final int endSeq;
  final int nextSeq;
  final BridgeSyncDirection direction;
  final int generation;
}

/// Where completed sync batches go. V0 uses a no-op sink; T39–T41 implement the
/// durable store. Keeping this a seam means the link procedure never touches
/// SQLite.
abstract interface class BridgeSyncSink {
  Future<void> accept(BridgeSyncBatch batch);
}

class NullBridgeSyncSink implements BridgeSyncSink {
  const NullBridgeSyncSink();

  @override
  Future<void> accept(BridgeSyncBatch batch) async {}
}

/// A cancelable one-shot timer, so tests can fire the watchdog and the 3 s
/// control timeout without waiting.
abstract interface class BridgeLinkTimer {
  void cancel();
}

class _SystemTimer implements BridgeLinkTimer {
  _SystemTimer(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

class BridgeLinkSettings {
  const BridgeLinkSettings({
    this.reconnectBackoff = const <Duration>[
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 15),
      Duration(seconds: 30),
    ],
    this.controlTimeout = const Duration(seconds: 3),
    this.watchdog = const Duration(seconds: 110),
    this.firstSyncWindow = const Duration(minutes: 15),
    this.freshAge = const Duration(seconds: 90),
    this.clockTolerance = const Duration(seconds: 2),
    this.forwardPageSize = 32,
    this.syncTimeout = const Duration(seconds: 10),
    this.maxForwardPages = 16,
  });

  final List<Duration> reconnectBackoff;
  final Duration controlTimeout;
  final Duration watchdog;
  final Duration firstSyncWindow;
  final Duration freshAge;
  final Duration clockTolerance;
  final int forwardPageSize;
  final Duration syncTimeout;
  final int maxForwardPages;
}

/// Named procedural failures. The screens map these to approved copy; the raw
/// detail is debug-only.
enum BridgeLinkFailure {
  protocolMismatch,
  notSecured,
  bondRequired,
  bondFailed,
  bondCancelled,
  controlTimeout,
  syncTimeout,
  syncFailed,
  syncGap,
  notConnected,
  operationFailed,
}

class BridgeLinkException implements Exception {
  const BridgeLinkException(this.failure, [this.message = '']);

  final BridgeLinkFailure failure;
  final String message;

  @override
  String toString() {
    final suffix = message.isEmpty ? '' : ': $message';
    return 'BridgeLinkException(${failure.name})$suffix';
  }
}

/// The app-side GATT procedure sequence (05 §5.12, 06 §6.3).
///
/// connect → read `info` → MTU 247 → bond when needed → subscribe → read
/// `live` → `control(set_time)` → sync. It also owns the `op_id` control queue,
/// the reconnect backoff and the 110 s health watchdog.
///
/// The class is free of Flutter imports and talks only to [BleClient], so the
/// scripted fake drives every path in `flutter test`.
class BridgeLink {
  BridgeLink({
    required this.client,
    required this.host,
    this.settings = const BridgeLinkSettings(),
    this.sink = const NullBridgeSyncSink(),
    this.localMaxSeq,
    this.onLocalMaxSeq,
    this.readLocalMaxSeq,
    DateTime Function()? nowUtc,
    Duration Function()? elapsed,
    Future<void> Function(Duration duration)? wait,
    BridgeLinkTimer Function(Duration duration, void Function() action)?
    schedule,
  }) : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _elapsed = elapsed ?? _stopwatchElapsed,
       _wait = wait ?? _defaultWait,
       _schedule = schedule ?? _defaultSchedule;

  final BleClient client;
  final BridgeLinkHost host;
  final BridgeLinkSettings settings;
  final BridgeSyncSink sink;

  /// The newest locally stored sequence, or `null` when the phone has no data.
  final int? Function()? localMaxSeq;
  final void Function(int seq)? onLocalMaxSeq;

  /// Optional durable cursor probe used ahead of [localMaxSeq].
  final int? Function()? readLocalMaxSeq;

  final DateTime Function() _nowUtc;
  final Duration Function() _elapsed;
  final Future<void> Function(Duration) _wait;
  final BridgeLinkTimer Function(Duration, void Function()) _schedule;

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static Duration _stopwatchElapsed() => _stopwatch.elapsed;
  static Future<void> _defaultWait(Duration duration) =>
      Future<void>.delayed(duration);
  static BridgeLinkTimer _defaultSchedule(
    Duration duration,
    void Function() action,
  ) => _SystemTimer(Timer(duration, action));

  ConnectionPhase? _phase;
  BridgeInfo? _info;
  BridgeLive? _lastLive;
  BleDevice? _device;
  DateTime? _lastLiveReceipt;
  int? _negotiatedMtu;
  bool _disposed = false;
  bool _sessionActive = false;
  bool _secure = false;
  int _bondAttempts = 0;
  int _reconnectAttempt = 0;
  bool _reconnecting = false;
  Duration? _nextReconnectIn;
  Completer<void>? _wake;
  BridgeLinkTimer? _watchdog;
  BridgeLinkTimer? _syncTimeoutTimer;

  StreamSubscription<BleConnectionState>? _connectionSubscription;
  StreamSubscription<Uint8List>? _liveSubscription;
  StreamSubscription<Uint8List>? _resultSubscription;
  StreamSubscription<Uint8List>? _syncSubscription;

  final BridgeResultAssembler _resultAssembler = BridgeResultAssembler();
  final BridgeSyncAssembler _syncAssembler = BridgeSyncAssembler();
  final Map<int, _PendingControl> _pendingControls = <int, _PendingControl>{};
  Completer<BridgeSyncStream>? _syncCompleter;

  int _nextOpId = 0;
  int? _lastSetTimeMs;
  Duration? _elapsedAtSetTime;
  bool _lastClockValid = false;
  int? _lastSyncCursor;
  int _storedRecords = 0;

  ConnectionPhase? get phase => _phase;
  BridgeInfo? get info => _info;
  BridgeLive? get lastLive => _lastLive;
  DateTime? get lastLiveReceipt => _lastLiveReceipt;
  int? get negotiatedMtu => _negotiatedMtu;
  bool get isSecured => _secure;
  bool get isReconnecting => _reconnecting;
  int get reconnectAttempt => _reconnectAttempt;
  Duration? get nextReconnectIn => _nextReconnectIn;
  int? get lastSetTimeMs => _lastSetTimeMs;
  int? get lastSyncCursor => _lastSyncCursor;
  int get storedRecords => _storedRecords;

  /// The device the link is bound to. Reconnect attempts use it directly.
  BleDevice? get device => _device;

  void _setPhase(ConnectionPhase value) {
    _phase = value;
    host.onPhase(value);
  }

  /// Collects link state for a returning launch. Called before any procedure.
  void attach() {
    _connectionSubscription ??= client.connectionStates.listen(
      _onConnectionState,
    );
  }

  /// The first connect after setup finished bonding. The GATT link is already
  /// connected and `info` has been read; this runs MTU → subscribe → live →
  /// set_time → recent sync.
  Future<BridgeInfo> completeFirstConnect(
    BleDevice device, {
    BridgeInfo? info,
  }) async {
    attach();
    _device = device;
    _sessionActive = true;
    _setPhase(ConnectionPhase.syncing);
    host.onSync?.call(
      const BridgeSyncProgress(state: SyncState.recent, percent: 5),
    );
    try {
      final result = await _prepareLink(info: info, firstSync: true);
      return result;
    } on BridgeLinkException {
      _sessionActive = false;
      rethrow;
    }
  }

  /// Full procedure for a fresh link (returning launch or a re-pair).
  Future<BridgeInfo> connectAndSecure(BleDevice device) async {
    attach();
    _device = device;
    _sessionActive = true;
    _setPhase(ConnectionPhase.syncing);
    try {
      if (client.connectionState != BleConnectionState.connected ||
          client.connectedDevice?.id != device.id) {
        await client.connect(device);
      }
      return await _prepareLink(firstSync: localMax() == null);
    } on BleException catch (error) {
      _sessionActive = false;
      throw BridgeLinkException(
        error.failure == BleFailure.notBonded
            ? BridgeLinkFailure.bondRequired
            : BridgeLinkFailure.operationFailed,
        error.message,
      );
    } on BridgeLinkException {
      _sessionActive = false;
      rethrow;
    }
  }

  int? localMax() => readLocalMaxSeq?.call() ?? localMaxSeq?.call();

  Future<BridgeInfo> _prepareLink({
    BridgeInfo? info,
    required bool firstSync,
  }) async {
    final bridgeInfo =
        info ?? BridgeInfo.decode(await client.read(bleInfoCharacteristicUuid));
    _info = bridgeInfo;
    host.onInfo?.call(bridgeInfo);
    if (!bridgeInfo.isCompatible) {
      throw const BridgeLinkException(
        BridgeLinkFailure.protocolMismatch,
        'info.proto_major is not $bleProtocolMajor',
      );
    }

    _negotiatedMtu = await client.requestMtu(bleRequestedMtu);
    await _ensureSecure();
    _secure = true;
    await _subscribeAll();

    final live = await _readLiveWithBond();
    await _setTimeIfNeeded(force: firstSync, live: live);

    if (firstSync) {
      await _syncRecent(live: live);
    } else {
      await syncForward();
    }

    _setPhase(ConnectionPhase.live);
    _armWatchdog();
    return bridgeInfo;
  }

  Future<void> _ensureSecure() async {
    if (client.bondState.isBonded) {
      _bondAttempts = 0;
      return;
    }
    await _bond();
  }

  Future<void> _bond() async {
    if (_bondAttempts >= 1) {
      // One prompt, one OS attempt. A failed bond is a named outcome, never a
      // retry loop.
      throw const BridgeLinkException(BridgeLinkFailure.bondFailed);
    }
    _bondAttempts++;
    final proceed =
        await (host.onBondPrompt?.call() ?? Future<bool>.value(true));
    if (!proceed) {
      throw const BridgeLinkException(BridgeLinkFailure.bondCancelled);
    }
    final result = await client.bond();
    if (!result.isBonded) {
      throw BridgeLinkException(
        BridgeLinkFailure.bondFailed,
        'bond ended in ${result.name}',
      );
    }
    _secure = true;
  }

  /// Reads `live`, and treats an encryption/authentication ATT error as
  /// "bond/authenticate first" exactly once.
  Future<BridgeLive> _readLiveWithBond() async {
    try {
      return _applyLive(
        BridgeLive.decode(await client.read(bleLiveCharacteristicUuid)),
      );
    } on BleException catch (error) {
      if (!_isBondRequired(error)) rethrow;
      await _bond();
      // Retry once, after a successful bond, and never loop.
      return _applyLive(
        BridgeLive.decode(await client.read(bleLiveCharacteristicUuid)),
      );
    }
  }

  bool _isBondRequired(BleException error) {
    switch (error.failure) {
      case BleFailure.notBonded:
        return true;
      case BleFailure.gattError:
      case BleFailure.failed:
        // T32 maps ATT 0x0F / 0x05 to notBonded; the detail keeps the raw code
        // as a fallback for a client that leaves it as a GATT error.
        final message = error.message.toLowerCase();
        return message.contains('0x0f') || message.contains('0x05');
      case BleFailure.notConnected:
      case BleFailure.timeout:
      case BleFailure.unknownCharacteristic:
      case BleFailure.unsupported:
      case BleFailure.invalidValue:
      case BleFailure.notSubscribed:
      case BleFailure.permissionDenied:
      case BleFailure.permissionBlocked:
      case BleFailure.bluetoothOff:
      case BleFailure.unsupportedPhone:
      case BleFailure.scanFailed:
      case BleFailure.noResults:
      case BleFailure.wrongPasskey:
      case BleFailure.promptTimeout:
      case BleFailure.staleBond:
      case BleFailure.bondStoreFull:
      case BleFailure.connectionFailed:
        return false;
    }
  }

  Future<void> _subscribeAll() async {
    await client.setNotify(bleLiveCharacteristicUuid, enabled: true);
    _liveSubscription ??= client
        .notifications(bleLiveCharacteristicUuid)
        .listen(_onLiveChunk, onError: _onNotificationError);

    _resultAssembler.reset();
    await client.setNotify(bleResultCharacteristicUuid, enabled: true);
    _resultSubscription ??= client
        .notifications(bleResultCharacteristicUuid)
        .listen(_onResultChunk, onError: _onNotificationError);

    _syncAssembler.reset();
    await client.setNotify(bleSyncDataCharacteristicUuid, enabled: true);
    _syncSubscription ??= client
        .notifications(bleSyncDataCharacteristicUuid)
        .listen(_onSyncChunk, onError: _onNotificationError);
  }

  void _onNotificationError(Object error) {
    if (_reconnecting || _disposed) return;
    if (error is BleException && error.failure == BleFailure.notConnected) {
      _beginReconnect();
    }
  }

  void _onLiveChunk(Uint8List chunk) {
    if (_disposed) return;
    try {
      final live = BridgeLive.decode(chunk);
      _applyLive(live);
      // A notification during the syncing phase updates the data but must not
      // declare the procedure finished.
      if (!_reconnecting && _phase != ConnectionPhase.syncing) {
        _setPhase(ConnectionPhase.live);
      }
      _armWatchdog();
    } on RangeError {
      // A truncated notification is noise; the next sample replaces it.
    }
  }

  BridgeLive _applyLive(BridgeLive live) {
    _lastLive = live;
    _lastClockValid = live.clockValid;
    _lastLiveReceipt = _nowUtc();
    host.onLive(BridgeLiveUpdate(live: live, receivedAt: _lastLiveReceipt!));
    return live;
  }

  // ---------------------------------------------------------------------------
  // Control / result queue
  // ---------------------------------------------------------------------------

  /// Sends one control op and waits for the matching `result` (3 s contract).
  ///
  /// The GATT write returning is never treated as success; the returned
  /// [BridgeResult] is the only outcome. A write rejected for security raises
  /// [BridgeLinkFailure.bondRequired].
  Future<BridgeResult> sendControl(
    BridgeControlOp op, [
    List<int> body = const <int>[],
  ]) async {
    if (!_secure && !client.bondState.isBonded) {
      throw const BridgeLinkException(BridgeLinkFailure.notSecured);
    }
    final opId = _allocateOpId();
    final pending = _PendingControl(op: op, opId: opId);
    _pendingControls[opId] = pending;
    pending.timer = _schedule(settings.controlTimeout, () {
      _completeControl(
        opId,
        error: BridgeLinkException(
          BridgeLinkFailure.controlTimeout,
          'no result for op ${op.wire} in ${settings.controlTimeout.inSeconds}s',
        ),
      );
    });
    try {
      await client.write(
        bleControlCharacteristicUuid,
        BridgeControl(op: op, opId: opId).encode(body),
      );
    } on BleException catch (error) {
      _completeControl(opId, error: error);
      if (_isBondRequired(error)) {
        throw const BridgeLinkException(BridgeLinkFailure.bondRequired);
      }
      throw BridgeLinkException(
        BridgeLinkFailure.operationFailed,
        error.message,
      );
    }
    return pending.completer.future;
  }

  int _allocateOpId() {
    for (var count = 0; count < 256; count++) {
      final candidate = _nextOpId;
      _nextOpId = (_nextOpId + 1) & 0xFF;
      if (!_pendingControls.containsKey(candidate)) return candidate;
    }
    throw const BridgeLinkException(
      BridgeLinkFailure.operationFailed,
      'no free op_id',
    );
  }

  void _onResultChunk(Uint8List chunk) {
    BridgeResult result;
    try {
      final decoded = _resultAssembler.add(chunk);
      if (decoded == null) return;
      result = decoded;
    } on RangeError {
      _resultAssembler.reset();
      return;
    }
    final pending = _pendingControls[result.opId];
    if (pending == null) return;
    if (pending.op.wire != result.op) return;
    _completeControl(result.opId, result: result);
  }

  void _completeControl(int opId, {BridgeResult? result, Object? error}) {
    final pending = _pendingControls.remove(opId);
    if (pending == null) return;
    pending.timer?.cancel();
    if (pending.completer.isCompleted) return;
    if (result != null) {
      pending.completer.complete(result);
    } else {
      pending.completer.completeError(
        error ?? const BridgeLinkException(BridgeLinkFailure.operationFailed),
      );
    }
  }

  /// Sets the bridge clock from the phone's UTC milliseconds and timezone.
  ///
  /// Returns the result, or null when the clock is already within tolerance.
  Future<BridgeResult?> setTime({required bool force}) async {
    if (!force && _lastSetTimeMs != null && _lastClockValid) {
      final expected = DateTime.fromMillisecondsSinceEpoch(
        _lastSetTimeMs! + _sinceSetTime().inMilliseconds,
        isUtc: true,
      );
      final drift = _nowUtc().difference(expected).abs();
      if (drift <= settings.clockTolerance) return null;
    }
    final now = _nowUtc();
    final body = encodeSetTimeBody(
      unixMs: now.millisecondsSinceEpoch,
      tzOffsetMin: DateTime.now().timeZoneOffset.inMinutes,
    );
    final result = await sendControl(BridgeControlOp.setTime, body);
    if (result.status == BridgeResultStatus.ok) {
      _lastSetTimeMs = now.millisecondsSinceEpoch;
      _elapsedAtSetTime = _elapsed();
    }
    return result;
  }

  Duration _sinceSetTime() {
    final setAt = _elapsedAtSetTime;
    if (setAt == null) return Duration.zero;
    final elapsed = _elapsed() - setAt;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Future<void> _setTimeIfNeeded({
    required bool force,
    required BridgeLive live,
  }) async {
    final result = await setTime(force: force || !live.clockValid);
    if (result != null && result.status != BridgeResultStatus.ok) {
      throw BridgeLinkException(
        BridgeLinkFailure.operationFailed,
        'set_time returned ${result.status.name}',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------------

  Future<void> _syncRecent({required BridgeLive live}) async {
    final cursor = live.seq == bleSeqNone || live.seq == 0
        ? bleSeqNone
        : (live.seq + 1) & 0xFFFFFFFF;
    host.onSync?.call(
      const BridgeSyncProgress(state: SyncState.recent, percent: 20),
    );
    final stream = await _requestSync(
      BridgeSyncRequest(
        cmd: BridgeSyncCmd.read,
        direction: BridgeSyncDirection.backward,
        cursorSeq: cursor,
        maxRecords: 64,
      ),
    );
    host.onSync?.call(
      const BridgeSyncProgress(state: SyncState.recent, percent: 70),
    );
    final cutoff = _nowUtc().subtract(settings.firstSyncWindow);
    final recent = stream.records
        .where(
          (record) =>
              record.unixS == 0 ||
              !DateTime.fromMillisecondsSinceEpoch(
                record.unixS * 1000,
                isUtc: true,
              ).isBefore(cutoff),
        )
        .toList();
    await _accept(
      stream,
      records: recent,
      direction: BridgeSyncDirection.backward,
      advanceCursorTo: stream.end.maxSeq,
    );
    host.onSync?.call(
      BridgeSyncProgress(
        state: SyncState.complete,
        percent: 100,
        storedRecords: _storedRecords,
      ),
    );
  }

  /// Catches up from the local max immediately. Never re-reads the last 24 h.
  Future<void> syncForward() async {
    if (!_secure) {
      throw const BridgeLinkException(BridgeLinkFailure.notSecured);
    }
    final startCursor = localMax();
    if (startCursor == null) {
      // No forward cursor yet: behave like a first sync rather than duplicating
      // the archive.
      final live = _lastLive ?? await _readLiveWithBond();
      await _syncRecent(live: live);
      return;
    }
    var cursor = startCursor;
    host.onSync?.call(
      BridgeSyncProgress(state: SyncState.backfill, percent: 10),
    );
    var page = 0;
    while (page < settings.maxForwardPages) {
      page++;
      final stream = await _requestSync(
        BridgeSyncRequest(
          cmd: BridgeSyncCmd.read,
          direction: BridgeSyncDirection.forward,
          cursorSeq: cursor,
          maxRecords: settings.forwardPageSize,
        ),
      );
      final fresh = stream.records
          .where((record) => record.seq >= cursor)
          .toList();
      if (fresh.isNotEmpty) {
        await _accept(
          stream,
          records: fresh,
          direction: BridgeSyncDirection.forward,
          advanceCursorTo: fresh.last.seq,
        );
        cursor = fresh.last.seq + 1;
      }
      final more =
          stream.end.nextSeq > cursor &&
          stream.start.count >= settings.forwardPageSize;
      host.onSync?.call(
        BridgeSyncProgress(
          state: SyncState.backfill,
          percent: math.min(90, 10 + page * 20),
          storedRecords: _storedRecords,
        ),
      );
      if (!more) break;
    }
    host.onSync?.call(
      BridgeSyncProgress(
        state: SyncState.complete,
        percent: 100,
        storedRecords: _storedRecords,
      ),
    );
  }

  Future<void> _accept(
    BridgeSyncStream stream, {
    required List<BridgeSampleRecord> records,
    required BridgeSyncDirection direction,
    required int advanceCursorTo,
  }) async {
    final end = stream.end;
    if (end.status == 1 || end.status == 2) {
      host.onSync?.call(
        const BridgeSyncProgress(
          state: SyncState.error,
          percent: 0,
          error: 'sync status',
        ),
      );
      throw const BridgeLinkException(BridgeLinkFailure.syncGap);
    }
    _storedRecords += records.length;
    await sink.accept(
      BridgeSyncBatch(
        records: records,
        startSeq: stream.start.startSeq,
        endSeq: end.maxSeq,
        nextSeq: end.nextSeq,
        direction: direction,
        generation: stream.start.generation,
      ),
    );
    final advanced = advanceCursorTo == bleSeqNone ? null : advanceCursorTo;
    final current = localMax();
    final next = advanced == null
        ? current
        : (current == null ? advanced : math.max(current, advanced));
    if (next != null) {
      _lastSyncCursor = next;
      onLocalMaxSeq?.call(next);
    }
  }

  Future<BridgeSyncStream> _requestSync(BridgeSyncRequest request) async {
    final completer = Completer<BridgeSyncStream>();
    _syncCompleter = completer;
    _syncAssembler.reset();
    _syncTimeoutTimer?.cancel();
    _syncTimeoutTimer = _schedule(settings.syncTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          const BridgeLinkException(BridgeLinkFailure.syncTimeout),
        );
      }
    });
    try {
      await client.write(bleSyncCtrlCharacteristicUuid, request.encode());
    } on BleException catch (error) {
      _syncTimeoutTimer?.cancel();
      _syncCompleter = null;
      throw BridgeLinkException(
        _isBondRequired(error)
            ? BridgeLinkFailure.bondRequired
            : BridgeLinkFailure.syncFailed,
        error.message,
      );
    }
    try {
      return await completer.future;
    } finally {
      _syncTimeoutTimer?.cancel();
      _syncTimeoutTimer = null;
      if (identical(_syncCompleter, completer)) _syncCompleter = null;
    }
  }

  void _onSyncChunk(Uint8List chunk) {
    try {
      final stream = _syncAssembler.add(chunk);
      if (stream == null) return;
      final completer = _syncCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(stream);
      }
    } on FormatException {
      final completer = _syncCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.completeError(
          const BridgeLinkException(BridgeLinkFailure.syncFailed),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Reconnect and health
  // ---------------------------------------------------------------------------

  void _onConnectionState(BleConnectionState state) {
    if (_disposed) return;
    if (state != BleConnectionState.disconnected) return;
    if (!_sessionActive) return;
    if (_reconnecting || _phase == ConnectionPhase.failed) return;
    _beginReconnect();
  }

  void _beginReconnect() {
    if (_disposed || _reconnecting) return;
    _reconnecting = true;
    _secure = false;
    _cleanupSubscriptions();
    _watchdog?.cancel();
    _watchdog = null;
    _failPendingControls(
      const BridgeLinkException(BridgeLinkFailure.notConnected),
    );
    _reconnectAttempt = 0;
    _nextReconnectIn = null;
    _setPhase(ConnectionPhase.reconnecting);
    host.onReconnect?.call(
      1,
      settings.reconnectBackoff.length,
      settings.reconnectBackoff.first,
    );
    unawaited(_runReconnectLoop());
  }

  Future<void> _runReconnectLoop() async {
    final device = _device;
    if (device == null) {
      _finishFailed();
      return;
    }
    for (
      var attempt = 1;
      attempt <= settings.reconnectBackoff.length;
      attempt++
    ) {
      _reconnectAttempt = attempt;
      final waitFor = settings.reconnectBackoff[attempt - 1];
      _nextReconnectIn = waitFor;
      host.onReconnect?.call(
        attempt,
        settings.reconnectBackoff.length,
        waitFor,
      );
      await _waitCancellable(waitFor);
      if (_disposed || !_reconnecting) return;
      try {
        if (client.connectionState != BleConnectionState.connected ||
            client.connectedDevice?.id != device.id) {
          await client.connect(device);
        }
        _sessionActive = true;
        _bondAttempts = 0;
        _setPhase(ConnectionPhase.syncing);
        await _prepareLink(firstSync: localMax() == null);
        _reconnecting = false;
        _nextReconnectIn = null;
        _reconnectAttempt = 0;
        host.onReconnect?.call(0, settings.reconnectBackoff.length, null);
        return;
      } catch (error) {
        _secure = false;
        _cleanupSubscriptions();
        if (_disposed || !_reconnecting) return;
        if (_isBondFailure(error)) {
          // Never spin through six attempts on a bond that needs the approved
          // setup passkey screen.
          _finishFailed();
          return;
        }
      }
    }
    _finishFailed();
  }

  bool _isBondFailure(Object error) {
    if (error is! BridgeLinkException) return false;
    switch (error.failure) {
      case BridgeLinkFailure.bondRequired:
      case BridgeLinkFailure.bondFailed:
      case BridgeLinkFailure.bondCancelled:
        return true;
      case BridgeLinkFailure.protocolMismatch:
      case BridgeLinkFailure.notSecured:
      case BridgeLinkFailure.controlTimeout:
      case BridgeLinkFailure.syncTimeout:
      case BridgeLinkFailure.syncFailed:
      case BridgeLinkFailure.syncGap:
      case BridgeLinkFailure.notConnected:
      case BridgeLinkFailure.operationFailed:
        return false;
    }
  }

  void _finishFailed() {
    _reconnecting = false;
    _nextReconnectIn = null;
    host.onReconnect?.call(
      settings.reconnectBackoff.length,
      settings.reconnectBackoff.length,
      null,
    );
    _setPhase(ConnectionPhase.failed);
  }

  Future<void> _waitCancellable(Duration duration) async {
    final wake = Completer<void>();
    _wake = wake;
    try {
      await Future.any(<Future<void>>[_wait(duration), wake.future]);
    } finally {
      if (identical(_wake, wake)) _wake = null;
    }
  }

  /// Pull-to-refresh or app resume cuts a reconnect wait short and retries.
  Future<void> retryNow() async {
    if (_disposed) return;
    if (_reconnecting) {
      final wake = _wake;
      if (wake != null && !wake.isCompleted) wake.complete();
      return;
    }
    if (_phase == ConnectionPhase.failed) {
      _beginReconnect();
    }
  }

  /// App resume: health check + forward sync, or resume the reconnect loop.
  Future<void> onAppResume() async {
    if (_disposed) return;
    if (_reconnecting || _phase == ConnectionPhase.failed) {
      await retryNow();
      return;
    }
    if (_secure) {
      await healthCheck();
      try {
        await syncForward();
      } catch (_) {
        // Live data stays usable if a forward catch-up fails.
      }
    }
  }

  /// User pull-to-refresh while connected.
  Future<void> pullToRefresh() async {
    if (_phase == ConnectionPhase.reconnecting ||
        _phase == ConnectionPhase.failed) {
      await retryNow();
      return;
    }
    if (!_secure) return;
    await healthCheck();
    try {
      await syncForward();
    } catch (_) {
      // The sync card owns the failure state.
    }
  }

  /// No notification for 110 s: read `live`.
  Future<void> healthCheck() async {
    if (_disposed || !_secure) return;
    final hadQuietX4 = _lastLive != null && !_isFresh(_lastLive!);
    try {
      final live = await client.read(bleLiveCharacteristicUuid);
      _applyLive(BridgeLive.decode(live));
      if (_isFresh(_lastLive!)) {
        _setPhase(ConnectionPhase.live);
      } else {
        _setPhase(ConnectionPhase.stale);
      }
      _armWatchdog();
    } on BleException catch (error) {
      if (_isBondRequired(error)) {
        try {
          await _bond();
          await healthCheck();
          return;
        } catch (_) {
          _beginReconnect();
          return;
        }
      }
      _beginReconnect();
    } catch (_) {
      if (hadQuietX4) {
        _setPhase(ConnectionPhase.stale);
      } else {
        _beginReconnect();
      }
    }
  }

  bool _isFresh(BridgeLive live) =>
      Duration(seconds: live.ageS) <= settings.freshAge;

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = _schedule(settings.watchdog, () {
      unawaited(healthCheck());
    });
  }

  void _cleanupSubscriptions() {
    unawaited(_liveSubscription?.cancel());
    unawaited(_resultSubscription?.cancel());
    unawaited(_syncSubscription?.cancel());
    _liveSubscription = null;
    _resultSubscription = null;
    _syncSubscription = null;
    _resultAssembler.reset();
    _syncAssembler.reset();
  }

  void _failPendingControls(Object error) {
    for (final opId in _pendingControls.keys.toList()) {
      _completeControl(opId, error: error);
    }
  }

  /// Stops procedures and reconnect attempts without disconnecting the client.
  void abandon() {
    _sessionActive = false;
    _reconnecting = false;
    _secure = false;
    _watchdog?.cancel();
    _watchdog = null;
    _syncTimeoutTimer?.cancel();
    _syncTimeoutTimer = null;
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
    _failPendingControls(
      const BridgeLinkException(BridgeLinkFailure.notConnected),
    );
    _cleanupSubscriptions();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    abandon();
    unawaited(_connectionSubscription?.cancel());
    _connectionSubscription = null;
  }
}

class _PendingControl {
  _PendingControl({required this.op, required this.opId});

  final BridgeControlOp op;
  final int opId;
  final Completer<BridgeResult> completer = Completer<BridgeResult>();
  BridgeLinkTimer? timer;
}
