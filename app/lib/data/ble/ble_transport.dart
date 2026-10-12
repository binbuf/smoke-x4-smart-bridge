/// `BleTransport`: the BLE-only [BridgeTransport].
///
/// The wire is the **binary** `protocol/records.yaml` contract, decoded through
/// the generated `data/dto/records.g.dart` codec — the same generator the
/// firmware's `record_gen.h` comes from. We speak the contract; we do not
/// invent one.
///
/// Two things ride BLE: live telemetry (`live_state`, one notify per decoded
/// LoRa packet) and full history (`history_ctrl`/`history_data`, gated on
/// `device_info.caps` b6 `history_full`). This app needs nothing else.
///
/// [FlutterBlueGattClient] (the plugin half) lives beside this file; this file
/// only depends on the [BleGattClient] seam, so it is pure Dart and sits in the
/// `dart test` gate.
library;

import 'dart:async';
import 'dart:typed_data';

import '../../domain/domain.dart';
import '../dto/records.g.dart' as wire;
import 'ble_gatt.dart';
import 'bridge_transport.dart';

/// The client half of the firmware's chunker.
///
/// ATT cannot fragment a notification, so a payload longer than `MTU − 3`
/// arrives as consecutive chunks. The contract guarantees every variable
/// payload's fixed prefix (≤ 10 B) arrives whole in the first chunk, so the
/// total length is always knowable from chunk one — even at the 20-byte
/// default (ble-gatt §4).
class NotificationReassembler {
  NotificationReassembler(this.expectedLength);

  final int? Function(Uint8List prefix) expectedLength;

  final _buf = BytesBuilder();
  int? _want;

  /// Feeds one chunk. Returns a complete payload, or null if more is needed.
  /// Throws [FormatException] rather than silently corrupting when the stream
  /// is nonsense.
  Uint8List? add(Uint8List chunk) {
    _buf.add(chunk);
    final bytes = _buf.toBytes();
    _want ??= expectedLength(bytes);
    if (_want == null) {
      return null;
    }
    if (bytes.length < _want!) {
      return null;
    }
    if (bytes.length > _want!) {
      reset();
      throw FormatException(
        'notification overrun: got ${bytes.length}, expected $_want',
      );
    }
    reset();
    return bytes;
  }

  void reset() {
    _buf.clear();
    _want = null;
  }
}

/// The fixed-prefix length rules, one per variable payload (ble-gatt §5).
int? _resultLength(Uint8List b) => b.length < 4 ? null : 4 + b[3];
int? _historyDataLength(Uint8List b) => b.length < 7 ? null : 7 + b[6];

class BleTransport implements BridgeTransport {
  BleTransport(
    this.client, {
    this.historyTimeout = const Duration(seconds: 30),
  });

  final BleGattClient client;
  final Duration historyTimeout;

  final _live = StreamController<LiveSnapshot>.broadcast();
  final _results = StreamController<wire.ResultFrame>.broadcast();
  final _historyData = StreamController<wire.HistoryData>.broadcast();
  final _disconnects = StreamController<void>.broadcast();
  final _subs = <StreamSubscription<dynamic>>[];
  bool _started = false;
  bool _closed = false;

  /// `device_info.caps` b6 — whether this bridge serves full history over BLE.
  /// **Null means "not asked yet", never "no"**: a bridge that never answers a
  /// `history_ctrl` write would hang rather than fail.
  bool? _historyFull;

  @override
  String get label => 'BLE';

  @override
  Stream<LiveSnapshot> get liveUpdates => _live.stream;

  @override
  Stream<void> get disconnects => _disconnects.stream;

  // ── notification wiring ────────────────────────────────────────────

  /// Subscribes to the notify characteristics we use. Idempotent: calling it
  /// twice does not double the streams.
  Future<void> start() async {
    if (_started || _closed) {
      return;
    }
    _started = true;

    // Settle `device_info` first: it is the one unencrypted characteristic, so
    // this succeeds on any connected link, and it latches `_historyFull`.
    try {
      await deviceInfo();
    } on Object {
      // A bridge we cannot even identify is one nothing else will work against
      // either; leaving `_historyFull` null keeps full history reported absent.
    }

    // `start()` runs on an already-connected link, so the first `disconnected`
    // the client reports is a genuine drop, not link setup.
    _subs.add(
      client.connectionStates.listen((s) {
        if (s == BleConnectionState.disconnected && !_disconnects.isClosed) {
          _disconnects.add(null);
        }
      }),
    );

    _subs.add(client.subscribe(BridgeChar.liveState).listen(_onLiveState));
    _subs.add(_reassembled(BridgeChar.result, _resultLength).listen(_onResult));
    _subs.add(
      _reassembled(
        BridgeChar.historyData,
        _historyDataLength,
      ).listen((bytes) => _historyData.add(wire.HistoryData.unpack(bytes))),
    );
  }

  void _onLiveState(Uint8List chunk) {
    // Fixed 16 B: one PDU at any MTU (§4).
    if (chunk.length < wire.LiveState.size) {
      return;
    }
    final s = wire.LiveState.decode(chunk);
    if (!_live.isClosed) {
      _live.add(
        LiveSnapshot(
          paired: s.paired,
          clockValid: s.clockValid,
          tempsF10: [for (var i = 0; i < 4; i++) s.tempOrNull(i)],
          socPct: s.socPct == wire.socUnknown ? null : s.socPct,
          rssiLora: s.rssiLora,
        ),
      );
    }
  }

  void _onResult(Uint8List bytes) {
    if (!_results.isClosed) {
      _results.add(wire.ResultFrame.unpack(bytes));
    }
  }

  Stream<Uint8List> _reassembled(int slot, int? Function(Uint8List) len) {
    final asm = NotificationReassembler(len);
    final out = StreamController<Uint8List>.broadcast();
    client
        .subscribe(slot)
        .listen(
          (chunk) {
            try {
              final whole = asm.add(chunk);
              if (whole != null) {
                out.add(whole);
              }
            } on FormatException catch (e) {
              // Loudly, never silently: a corrupted frame that looked valid
              // would be far worse than a dropped one.
              out.addError(e);
            }
          },
          onDone: out.close,
          onError: out.addError,
        );
    return out.stream;
  }

  // ── identity / live ────────────────────────────────────────────────

  /// Reads `device_info` and latches the full-history capability.
  Future<wire.DeviceInfo> _readDeviceInfo() async {
    final info = wire.DeviceInfo.decode(
      await client.read(BridgeChar.deviceInfo),
    );
    _historyFull = info.historyFull;
    return info;
  }

  @override
  Future<DeviceIdentity> deviceInfo() async {
    final info = await _readDeviceInfo();
    return DeviceIdentity(
      id: info.id,
      model: info.model,
      fw: info.fw,
      probes: info.probes,
      historyFull: info.historyFull,
      admin: info.admin,
    );
  }

  @override
  Future<LiveSnapshot> readLive() async {
    final s = wire.LiveState.decode(await client.read(BridgeChar.liveState));
    return LiveSnapshot(
      paired: s.paired,
      clockValid: s.clockValid,
      tempsF10: [for (var i = 0; i < 4; i++) s.tempOrNull(i)],
      socPct: s.socPct == wire.socUnknown ? null : s.socPct,
      rssiLora: s.rssiLora,
    );
  }

  // ── full history over BLE (ble-gatt §5.10–§5.11) ────────────────────

  /// One request at a time, enforced here rather than discovered as a `busy`
  /// end frame — the device serialises streams (§5.10) and two concurrent
  /// callers would otherwise interleave frames from one stream into the
  /// other's reassembly.
  Future<void>? _historyLock;

  Stream<wire.HistoryData> _request(
    wire.HistoryReq req, {
    int sessionId = 0,
    int fromT = 0,
    int? toT,
    int stride = 1,
  }) async* {
    if (_historyFull == null) {
      await deviceInfo();
    }
    if (_historyFull != true) {
      throw const TransportUnsupported('stream full history');
    }
    await start();

    while (_historyLock != null) {
      await _historyLock;
    }
    final gate = Completer<void>();
    _historyLock = gate.future;
    try {
      // Attach BEFORE the write: the device answers on its own task and the
      // first frames can land while the write is still completing.
      final frames = StreamController<wire.HistoryData>();
      final sub = _historyData.stream.listen(
        frames.add,
        onError: frames.addError,
      );
      try {
        await client.write(
          BridgeChar.historyCtrl,
          wire.HistoryCtrl(
            req: req.wire,
            stride: stride,
            sessionId: sessionId,
            fromT: fromT,
            // UINT32_MAX is "to the end" (§5.10).
            toT: toT ?? 0xFFFFFFFF,
          ).encode(),
        );

        var seen = 0;
        var nextSeq = 0;
        await for (final f in frames.stream.timeout(historyTimeout)) {
          seen++;
          // §5.11: a `busy` refusal rides seq 0xFFFF precisely so it cannot be
          // confused with a frame of a stream already in flight.
          if (f.seq != 0xFFFF) {
            if (f.seq != nextSeq) {
              throw FormatException(
                'history_data: frame gap — expected seq $nextSeq, got ${f.seq}',
              );
            }
            nextSeq = f.seq + 1;
          }
          if (f.kindEnum == wire.HistoryKind.end) {
            final status =
                wire.ResultStatus.fromWire(
                  f.payloadRaw.isEmpty ? 3 : f.payloadRaw[0],
                ) ??
                wire.ResultStatus.failed;
            if (status != wire.ResultStatus.ok) {
              throw TransportException(
                _statusCode(status),
                'history stream ended ${status.name}',
                detail: status,
              );
            }
            return;
          }
          yield f;
          if (f.last) {
            throw TransportException(
              'history_failed',
              'history stream ended without a terminator after $seen frames',
            );
          }
        }
        throw const TransportException(
          'history_failed',
          'history stream closed early',
        );
      } finally {
        await sub.cancel();
        await frames.close();
      }
    } finally {
      _historyLock = null;
      gate.complete();
    }
  }

  @override
  Future<List<SessionInfo>> sessions() async {
    if (_historyFull == null) {
      try {
        await deviceInfo();
      } on Object {
        // an unreadable device is not a history failure
      }
    }
    if (_historyFull != true) {
      return const [];
    }
    final out = <SessionInfo>[];
    await for (final f in _request(wire.HistoryReq.sessions)) {
      if (f.kindEnum != wire.HistoryKind.session) {
        continue;
      }
      for (var i = 0; i < f.count; i++) {
        final h = wire.HistorySession.decode(
          f.payloadRaw,
          i * wire.HistorySession.size,
        );
        out.add(
          SessionInfo(
            id: h.sessionId,
            name: h.name,
            // 0 is "the bridge had no clock", not midnight 1970.
            startedUnixMs: h.startedUnixMs == 0 ? null : h.startedUnixMs,
            endedUnixMs: h.endedUnixMs == 0 ? null : h.endedUnixMs,
            samplePeriodS: h.samplePeriodS,
            sampleCount: h.sampleCount,
            numProbes: h.numProbes,
            closed: h.closed,
            pinned: h.pinned,
          ),
        );
      }
    }
    return out;
  }

  @override
  Stream<List<Sample>> samples(
    int sessionId, {
    int fromT = 0,
    int? toT,
    int stride = 1,
  }) async* {
    // The device streams whole records; the app buckets locally. Full fidelity
    // in the cache beats a few saved KB the user can never zoom into.
    var batch = <Sample>[];
    await for (final f in _request(
      wire.HistoryReq.samples,
      sessionId: sessionId,
      fromT: fromT,
      toT: toT,
      stride: stride,
    )) {
      if (f.kindEnum != wire.HistoryKind.samples) {
        continue;
      }
      for (var i = 0; i < f.count; i++) {
        final r = wire.SampleRec.decode(f.payloadRaw, i * wire.SampleRec.size);
        batch.add(Sample(t: r.t, tempsF10: r.tempNullable, rssi: r.rssi));
      }
      // Coalescing keeps the drift transaction count sane without holding the
      // whole session in memory.
      if (batch.length >= 480) {
        yield batch;
        batch = <Sample>[];
      }
    }
    if (batch.isNotEmpty) {
      yield batch;
    }
  }

  // ── time / cook clock ───────────────────────────────────────────────

  @override
  Future<void> setTime(int unixMs, {int? tzOffsetMin}) async {
    await _writeAndAwaitResult(
      wire.ControlOp.setTime,
      wire.CtrlSetTime(unixMs: unixMs, tzOffsetMin: tzOffsetMin ?? 0).encode(),
    );
  }

  @override
  Future<void> pair() =>
      _writeAndAwaitResult(wire.ControlOp.pair, Uint8List(0));

  @override
  Future<void> unpair() =>
      _writeAndAwaitResult(wire.ControlOp.unpair, Uint8List(0));

  @override
  Future<void> identify() =>
      _writeAndAwaitResult(wire.ControlOp.identify, Uint8List(0));

  @override
  Future<void> reboot() =>
      _writeAndAwaitResult(wire.ControlOp.reboot, Uint8List(0));

  @override
  Future<void> factoryReset() =>
      _writeAndAwaitResult(wire.ControlOp.factoryReset, Uint8List(0));

  @override
  Future<void> powerOff() =>
      _writeAndAwaitResult(wire.ControlOp.powerOff, Uint8List(0));

  @override
  Future<void> setUnits(TempUnit unit) => _writeAndAwaitResult(
    wire.ControlOp.setUnits,
    wire.CtrlSetUnits(
      units: unit == TempUnit.celsius
          ? wire.TempUnits.celsius.wire
          : wire.TempUnits.fahrenheit.wire,
    ).encode(),
  );

  @override
  Future<void> setBatterySaver(BatterySaverMode mode) => _writeAndAwaitResult(
    wire.ControlOp.setBatterySaver,
    wire.CtrlSetBatterySaver(saver: mode.wire).encode(),
  );

  // ── device administration (v1.2) ────────────────────────────────────

  @override
  Future<DeviceStats> stats() async {
    final d = wire.DeviceStats.decode(
      await client.read(BridgeChar.deviceStats),
    );
    return DeviceStats(
      paired: d.paired,
      clockValid: d.clockValid,
      advertising: d.advertising,
      connected: d.connected,
      uptimeS: d.uptimeS,
      heapFreeB: d.heapFree,
      heapMinB: d.heapMin,
      storageUsedB: d.storageUsedB,
      storageTotalB: d.storageTotalB,
      storedSessions: d.storedSessions,
      loraFreqHz: d.loraFreqHz,
      loraRssi: d.loraRssi,
      loraSnr: d.loraSnr,
      packetsOk: d.packetsOk,
      packetsBad: d.packetsBad,
      bonds: d.bonds,
    );
  }

  @override
  Future<DeviceConfig> deviceConfig() async {
    final d = wire.DeviceConfig.decode(
      await client.read(BridgeChar.deviceConfig),
    );
    final names = d.probeName;
    final roles = d.probeRole;
    final targets = d.probeTarget;
    return DeviceConfig(
      prefs: DevicePrefs(
        displayTimeoutS: d.displayTimeoutS,
        ledEnabled: d.ledEnabled != 0,
        buzzerEnabled: d.buzzerEnabled != 0,
        retentionMaxSessions: d.retentionMaxSessions,
        retentionMinFreePct: d.retentionMinFreePct,
      ),
      probes: [
        for (var i = 0; i < 4; i++)
          ProbeConfig(
            index: i,
            name: names[i],
            role: _roleFromWire(roles[i]),
            targetF10: targets[i],
          ),
      ],
    );
  }

  @override
  Future<void> setProbe(ProbeConfig probe) => _writeAndAwaitResult(
    wire.ControlOp.setProbe,
    wire.CtrlSetProbe(
      index: probe.index,
      role: _roleToWire(probe.role),
      nameRaw: wire.utf8ToPadded(probe.name, 17),
      targetF10: probe.targetF10,
    ).encode(),
  );

  @override
  Future<void> setDevicePrefs(DevicePrefs prefs) => _writeAndAwaitResult(
    wire.ControlOp.setDevicePrefs,
    wire.CtrlSetDevicePrefs(
      displayTimeoutS: prefs.displayTimeoutS,
      ledEnabled: prefs.ledEnabled ? 1 : 0,
      buzzerEnabled: prefs.buzzerEnabled ? 1 : 0,
      retentionMaxSessions: prefs.retentionMaxSessions,
      retentionMinFreePct: prefs.retentionMinFreePct,
    ).encode(),
  );

  @override
  Future<void> setCookClock(int elapsedS) async {
    // The device refuses `invalid` past 99:59; clamping here keeps a long cook
    // from turning a state write into a failed write.
    final clamped = elapsedS.clamp(0, cookClockMaxS);
    await _writeAndAwaitResult(
      wire.ControlOp.setCookClock,
      wire.CtrlSetCookClock(elapsedS: clamped).encode(),
    );
  }

  @override
  Future<void> clearCookClock() async {
    await _writeAndAwaitResult(wire.ControlOp.clearCookClock, Uint8List(0));
  }

  @override
  Future<int> readRssi() => client.readRssi();

  @override
  Future<void> forget() => client.removeBond();

  // ── internals ───────────────────────────────────────────────────────

  /// Writes `device_control` and correlates the `result` notify by `op_echo` —
  /// never by arrival order, because a history reply can land between.
  Future<wire.ResultFrame> _writeAndAwaitResult(
    wire.ControlOp op,
    Uint8List body, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await start();
    // Pre-abandoned the moment it exists: if it errors while the WRITE below is
    // still in flight there must already be a listener, or the error surfaces
    // as an uncaught zone fault.
    final answer = _results.stream
        .firstWhere((r) => r.opEcho == op.wire)
        .timeout(timeout);
    _abandon(answer);
    await client.write(
      BridgeChar.deviceControl,
      wire.DeviceControl(op: op.wire, bodyRaw: body).pack(),
    );
    final r = await answer;
    if (r.statusEnum != wire.ResultStatus.ok) {
      throw TransportException(
        _statusCode(r.statusEnum),
        r.detail.isEmpty ? 'the bridge refused the request' : r.detail,
        detail: r.statusEnum,
      );
    }
    return r;
  }

  /// A pending correlation whose write then failed will never be answered, and
  /// its `firstWhere` would surface as an unhandled "No element". Detach it.
  void _abandon(Future<wire.ResultFrame> pending) {
    unawaited(pending.then((_) {}, onError: (Object _) {}));
  }

  @override
  Future<void> close() async {
    _closed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _live.close();
    await _results.close();
    await _historyData.close();
    await _disconnects.close();
    await client.dispose();
  }
}

String _statusCode(wire.ResultStatus? s) => switch (s) {
  wire.ResultStatus.busy => 'busy',
  wire.ResultStatus.invalid => 'invalid',
  wire.ResultStatus.unauthorized => 'unauthorized',
  wire.ResultStatus.failed => 'failed',
  _ => 'failed',
};

/// The wire `probe_role` order (unused 0, pit 1, food 2, ambient 3) differs
/// from the app's [ProbeRole]; these two functions are the only place that
/// knows, so the mapping cannot drift.
ProbeRole _roleFromWire(int wireRole) => switch (wireRole) {
  1 => ProbeRole.pit,
  2 => ProbeRole.food,
  3 => ProbeRole.ambient,
  _ => ProbeRole.unused,
};

int _roleToWire(ProbeRole role) => switch (role) {
  ProbeRole.pit => wire.ProbeRole.pit.wire,
  ProbeRole.food => wire.ProbeRole.food.wire,
  ProbeRole.ambient => wire.ProbeRole.ambient.wire,
  ProbeRole.unused => wire.ProbeRole.unused.wire,
};
