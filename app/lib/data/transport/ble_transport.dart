/// N15.3 — `BleTransport`: the third implementation of [BridgeTransport].
///
/// The wire is the **binary** `protocol/records.yaml` contract, decoded through
/// the generated `data/dto/records.g.dart` codec — the same generator the
/// firmware's `record_gen.h` comes from. We speak the contract; we do not
/// invent one.
///
/// Capabilities are honest rather than optimistic (research notes §4): live
/// telemetry, the 2-hour preview, and — from v1.1, gated on `device_info.caps`
/// b6 — full history. OTA stays Wi-Fi-only. Probe config / device read-back /
/// alarm-rule read-write have no `device_control` op on v1 firmware, so those
/// methods throw a typed [TransportUnsupported] rather than silently dropping a
/// write.
///
/// `FlutterBlueGattClient` (the plugin half) lives in `lib/platform/`; this file
/// only depends on the [BleGattClient] seam, so it is pure Dart and sits in the
/// `dart test test/data` gate.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../domain/domain.dart';
import '../dto/records.g.dart' as wire;
import 'ble_gatt.dart';
import 'bridge_transport.dart';

/// What the scan list renders before any connection exists — the §2.3 blob.
class BridgeDiscovery {
  const BridgeDiscovery({
    required this.deviceId,
    required this.name,
    this.pitTempF10,
    this.sessionMinutes = 0,
    this.paired = false,
    this.sessionActive = false,
    this.socPct,
    this.rssi = 0,
  });

  final String deviceId;
  final String name;

  /// Null when the pit probe is detached or the blob was unreadable. NEVER 0:
  /// a detached probe rendering as "0 °F" is the confusion this sentinel has
  /// existed to prevent since M0 (I3).
  final int? pitTempF10;
  final int sessionMinutes;
  final bool paired;
  final bool sessionActive;
  final int? socPct;
  final int rssi;

  /// Parses the 7-byte §2.3 blob. Returns a nameless-but-usable entry for
  /// anything it cannot read, because a scan that drops entries is worse than a
  /// scan that shows a plain one.
  factory BridgeDiscovery.fromAdvertisement(BleAdvertisement adv) {
    final name = adv.name ?? adv.deviceId;
    final blob = adv.manufacturerData;
    if (blob == null || blob.length < 7) {
      return BridgeDiscovery(
        deviceId: adv.deviceId,
        name: name,
        rssi: adv.rssi,
      );
    }
    final bd = ByteData.sublistView(blob);
    final flags = bd.getUint8(1);
    final pit = bd.getInt16(2, Endian.little);
    final soc = bd.getUint8(4);
    return BridgeDiscovery(
      deviceId: adv.deviceId,
      name: name,
      pitTempF10: (pit == wire.tempDetached || pit == wire.tempInvalid)
          ? null
          : pit,
      sessionMinutes: bd.getUint16(5, Endian.little),
      paired: (flags & (1 << 0)) != 0,
      sessionActive: (flags & (1 << 1)) != 0,
      socPct: soc == wire.socUnknown ? null : soc,
      rssi: adv.rssi,
    );
  }
}

/// N15.3 — the client half of the firmware's chunker.
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
int? _netStatusLength(Uint8List b) => b.length < 10 ? null : 10 + b[8] + b[9];
int? _resultLength(Uint8List b) => b.length < 4 ? null : 4 + b[3];
int? _historyDataLength(Uint8List b) => b.length < 7 ? null : 7 + b[6];

class BleTransport implements BridgeTransport {
  BleTransport(
    this.client, {
    int Function()? nowMs,
    this.historyTimeout = const Duration(seconds: 30),
  }) : _nowMs = nowMs ?? _wallClock;

  final BleGattClient client;
  final int Function() _nowMs;
  final Duration historyTimeout;

  final _events = StreamController<TransportEvent>.broadcast();
  final _results = StreamController<wire.ResultFrame>.broadcast();
  final _netStatus = StreamController<wire.NetStatus>.broadcast();
  final _historyData = StreamController<wire.HistoryData>.broadcast();
  final _subs = <StreamSubscription<dynamic>>[];
  bool _started = false;
  bool _closed = false;

  /// `device_info.caps` b6 — whether this bridge serves §5.10/§5.11. **Null
  /// means "not asked yet", never "no"**: a v1.0 bridge never answers a
  /// `history_ctrl` write at all, so guessing would hang rather than fail.
  bool? _historyFull;

  /// The last session list read, so `status()` can name the open session. Set
  /// by [sessions]; `_ensureSessions` reads it at most once per link.
  List<SessionInfo> _sessionCache = const [];
  bool _sessionsLoaded = false;

  @override
  TransportKind get kind => TransportKind.ble;

  @override
  TransportCapabilities get capabilities =>
      TransportCapabilities.ble.withFullHistory(_historyFull ?? false);

  @override
  String get label => 'BLE';

  // ── notification wiring ────────────────────────────────────────────

  /// Subscribes to every notify characteristic and starts reassembly.
  /// Idempotent: calling it twice does not double the streams.
  Future<void> start() async {
    if (_started || _closed) {
      return;
    }
    _started = true;

    // Settle `capabilities` before anything can read it. `device_info` is the
    // one unencrypted characteristic (§3), so this succeeds on any connected
    // link — and it must happen HERE rather than lazily, because callers branch
    // on `capabilities.fullHistory` synchronously.
    try {
      await deviceInfo();
    } on Object {
      // A bridge we cannot even identify is one nothing else will work against
      // either; leaving `_historyFull` null keeps full history reported absent,
      // which is the safe direction.
    }

    _subs.add(client.subscribe(BridgeChar.liveState).listen(_onLiveState));
    _subs.add(
      _reassembled(BridgeChar.netStatus, _netStatusLength).listen(_onNetStatus),
    );
    _subs.add(_reassembled(BridgeChar.result, _resultLength).listen(_onResult));
    _subs.add(
      _reassembled(
        BridgeChar.historyData,
        _historyDataLength,
      ).listen((bytes) => _historyData.add(wire.HistoryData.unpack(bytes))),
    );
  }

  void _onLiveState(Uint8List chunk) {
    // Fixed 16 B: one PDU at any MTU, which is the point (§4).
    if (chunk.length < wire.LiveState.size) {
      return;
    }
    final s = wire.LiveState.decode(chunk);
    if (!_events.isClosed) {
      _events.add(
        TransportEvent('sample', {
          't': s.sessionT,
          'temps_f10': s.tempNullable,
          'billows': s.billows,
          'rssi': s.rssiLora,
        }),
      );
    }
  }

  void _onNetStatus(Uint8List bytes) {
    final n = wire.NetStatus.unpack(bytes);
    if (!_netStatus.isClosed) {
      _netStatus.add(n);
    }
    if (!_events.isClosed) {
      _events.add(
        TransportEvent('net', {
          'mode': n.modeEnum?.name ?? '',
          'state': n.stateEnum?.name ?? '',
          'ip': n.ip.every((o) => o == 0) ? null : n.ip.join('.'),
        }),
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

  // ── BridgeTransport reads ──────────────────────────────────────────

  /// `net_status` transitions, which the provisioning wizard watches across the
  /// §5.7 handoff. A missed transition strands the wizard, so this is a
  /// first-class stream rather than something dug out of [events].
  Stream<wire.NetStatus> get netStatus => _netStatus.stream;

  Future<wire.DeviceInfo> deviceInfo() async {
    final info = wire.DeviceInfo.decode(
      await client.read(BridgeChar.deviceInfo),
    );
    // Latch the one capability the app cannot otherwise discover safely.
    _historyFull = info.historyFull;
    return info;
  }

  /// `net_status` on demand (§5.2 is Read as well as Notify): notifications
  /// report CHANGES, so asking is the only way to learn the current answer.
  Future<wire.NetStatus> readNetStatus() async =>
      wire.NetStatus.unpack(await client.read(BridgeChar.netStatus));

  /// Pull the session list once so `status()` can name the open session. A
  /// v1.0 bridge yields an empty list rather than throwing, so the live link
  /// still works without a history surface.
  Future<void> _ensureSessions() async {
    if (_sessionsLoaded) {
      return;
    }
    try {
      await sessions();
    } on Object {
      _sessionsLoaded = true;
    }
  }

  SessionInfo? _openSession() {
    for (final s in _sessionCache) {
      if (!s.closed) {
        return s;
      }
    }
    return null;
  }

  @override
  Future<BridgeStatus> status() async {
    final info = await deviceInfo();
    final live = wire.LiveState.decode(await client.read(BridgeChar.liveState));
    wire.NetStatus net;
    try {
      net = await readNetStatus();
    } on Object {
      net = wire.NetStatus();
    }
    if (info.historyFull) {
      await _ensureSessions();
    }
    final open = _openSession();
    final ip = net.ip.every((o) => o == 0) ? null : net.ip.join('.');
    final rssi = net.wifiRssi == 0 ? null : net.wifiRssi;
    return BridgeStatus(
      device: DeviceStatus(
        id: info.id,
        model: info.model,
        fw: info.fw,
        // Not on the BLE contract; HTTP has uptime/heap.
        uptimeS: 0,
        freeHeap: 0,
        minFreeHeap: 0,
        resetReason: 'unknown',
        coredumpAvailable: false,
      ),
      // No wall clock rides the GATT contract (I11): the app keeps it, and a
      // session header's `started_unix_ms` is the honest source.
      time: TimeStatus(
        unixMs: null,
        source: 'ble',
        tzOffsetMin: 0,
        valid: live.clockValid,
      ),
      net: NetStatus(
        mode: net.modeEnum?.name ?? 'off',
        state: net.stateEnum?.name ?? 'down',
        ssid: net.ssid.isEmpty ? null : net.ssid,
        rssi: rssi,
        ip: ip,
        host: net.host.isEmpty ? null : net.host,
        apClients: 0,
      ),
      ble: const BleStatus(advertising: false, connections: 1, bonded: 0),
      pairing: PairingStatus(
        paired: live.paired,
        deviceId: info.id,
        model: info.model,
        numProbes: info.probes,
        frequencyHz: null,
        lastPacketSAgo: null,
        baseLost: false,
      ),
      radio: RadioStatus(
        // The LoRa packet RSSI; the phone↔bridge dBm is a link property and
        // arrives through the onboarding/permission seam, not here.
        rssi: live.rssiLora,
        snr: 0,
        packetsOk: 0,
        packetsBad: 0,
        idMismatch: 0,
      ),
      storage: const StorageStatus(
        totalB: 0,
        usedB: 0,
        freePct: 0,
        sessions: 0,
        oldestSessionId: null,
      ),
      power: PowerStatus(
        mv: 0,
        socPct: live.socPct == wire.socUnknown ? null : live.socPct,
        charging: false,
        saver: false,
      ),
      session: SessionStatus(
        active: live.sessionActive,
        id: open?.id ?? 0,
        name: open?.name ?? '',
        startedUnixMs: open?.startedUnixMs,
        elapsedS: live.sessionT,
        samples: open?.sampleCount ?? 0,
      ),
      cookClock: CookClockStatus(
        set: live.sessionActive,
        elapsedS: live.sessionActive ? live.sessionT : null,
      ),
      ota: const OtaStatus(slot: 'ota_0', gate: 'unknown', failed: null),
    );
  }

  @override
  Future<LiveStatus> live({int windowS = 3600}) async {
    final s = wire.LiveState.decode(await client.read(BridgeChar.liveState));
    final probes = <LiveProbe>[];
    for (var i = 0; i < 4; i++) {
      final value = s.tempOrNull(i);
      probes.add(
        LiveProbe(
          n: i + 1,
          name: '',
          // v1 has no BLE op for probe names/roles; the app overlay owns them.
          role: ProbeRole.unused,
          // A sentinel is a detached probe, never 0 °F (I3).
          attached: value != null,
          tempF10: value,
          alarmEnabled: false,
          targetF10: null,
          rateFPerHr: null,
        ),
      );
    }
    return LiveStatus(
      t: s.sessionT,
      unixMs: null,
      unitsSource: 'F',
      billowsAttached: s.billows,
      billowsTargetF10: null,
      probes: probes,
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
      _sessionCache = const [];
      _sessionsLoaded = true;
      return _sessionCache;
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
            // 0 is "the bridge had no clock", not midnight 1970 (I11).
            startedUnixMs: h.startedUnixMs == 0 ? null : h.startedUnixMs,
            endedUnixMs: h.endedUnixMs == 0 ? null : h.endedUnixMs,
            samplePeriodS: h.samplePeriodS,
            sampleCount: h.sampleCount,
            numProbes: h.numProbes,
            // history_session carries no per-probe name/role/target; the
            // session_header does, but it is not part of this stream.
            probes: const [],
            closed: h.closed,
            pinned: h.pinned,
            markCount: 0,
          ),
        );
      }
    }
    _sessionCache = out;
    _sessionsLoaded = true;
    return out;
  }

  @override
  Future<SessionInfo> session(int sessionId) async {
    final list = await sessions();
    for (final s in list) {
      if (s.id == sessionId) {
        return s;
      }
    }
    throw TransportException('not_found', 'no session $sessionId');
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
        batch.add(
          Sample(
            t: r.t,
            tempsF10: r.tempNullable,
            billows: r.billows,
            newAlarm: r.newAlarm,
            sourceCelsius: r.sourceCelsius,
            rssi: r.rssi,
          ),
        );
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

  @override
  Future<List<Mark>> marks(int sessionId) async {
    if (_historyFull == null) {
      try {
        await deviceInfo();
      } on Object {
        // fall through: an unreadable device reports no marks
      }
    }
    // A bridge without full history has no mark stream; an empty list lets the
    // live link keep working rather than tearing the session down.
    if (_historyFull != true) {
      return const [];
    }
    final out = <Mark>[];
    await for (final f in _request(
      wire.HistoryReq.marks,
      sessionId: sessionId,
    )) {
      if (f.kindEnum != wire.HistoryKind.marks) {
        continue;
      }
      for (var i = 0; i < f.count; i++) {
        final m = wire.MarkRec.decode(f.payloadRaw, i * wire.MarkRec.size);
        out.add(
          Mark(
            t: m.t,
            kind: _markKindFromWire(m.kind),
            probe: m.probe,
            text: m.text,
          ),
        );
      }
    }
    return out;
  }

  @override
  Future<Mark> postMark(
    int sessionId, {
    int? t,
    required MarkKind kind,
    int probe = 0,
    String text = '',
  }) async {
    final raw = utf8.encode(text);
    await _writeAndAwaitResult(
      wire.ControlOp.mark,
      wire.CtrlMark(
        kind: _markKindToWire(kind),
        textRaw: Uint8List.fromList(raw.length > 24 ? raw.sublist(0, 24) : raw),
      ).pack(),
    );
    return Mark(t: t ?? 0, kind: kind, probe: probe, text: text);
  }

  // ── config / provisioning ───────────────────────────────────────────

  @override
  Future<Map<String, Object?>> wifiConfig() async {
    final n = await readNetStatus();
    final ip = n.ip.every((o) => o == 0) ? null : n.ip.join('.');
    return {
      'mode': n.modeEnum?.name ?? 'off',
      'state': n.stateEnum?.name ?? 'down',
      'ssid': n.ssid,
      'rssi': n.wifiRssi,
      'ip': ip,
      'host': n.host,
    };
  }

  @override
  Future<Map<String, Object?>> applyNetwork({
    required String mode,
    String? ssid,
    String? psk,
    String? user,
  }) async {
    await start();
    final netMode = switch (mode) {
      'ap' => wire.NetMode.ap,
      'sta' => wire.NetMode.sta,
      _ => wire.NetMode.off,
    };
    // The device answers `wifi_config` on op_echo 0, not a device_control op.
    final answer = _results.stream
        .firstWhere((r) => r.opEcho == 0)
        .timeout(const Duration(seconds: 10));
    _abandon(answer);
    await client.write(
      BridgeChar.wifiConfig,
      wire.WifiConfig(
        mode: netMode.wire,
        auth: 3,
        ssidRaw: _bytes(ssid),
        pskRaw: _bytes(psk),
        userRaw: _bytes(user),
      ).pack(),
    );
    final r = await answer;
    if (r.statusEnum != wire.ResultStatus.ok) {
      throw TransportException(
        _statusCode(r.statusEnum),
        'the bridge refused the network change',
        detail: r.detail,
      );
    }
    return {
      'ok': true,
      'detail': r.detail,
      // On a switch to AP the generated PSK rides back in `detail` (§5.5) —
      // the phone has to leave its own network to rejoin, so it needs the key.
      if (netMode == wire.NetMode.ap) 'psk': r.detail,
    };
  }

  @override
  Future<Map<String, Object?>> commitNetwork() =>
      // BLE has no netmode/commit op; BLE is the escape hatch the switch keeps
      // open, not the lane the switch is confirmed on.
      throw const TransportUnsupported('confirm a network switch');

  @override
  Future<Map<String, Object?>> deviceConfig() =>
      throw const TransportUnsupported('read the device settings');

  @override
  Future<void> setDeviceConfig(Map<String, Object?> patch) =>
      throw const TransportUnsupported('change the device settings over BLE');

  @override
  Future<Map<String, Object?>> alarmConfig() =>
      throw const TransportUnsupported('read the bridge’s alarm rules');

  @override
  Future<void> setAlarmConfig(Map<String, Object?> patch) =>
      throw const TransportUnsupported('change the bridge’s alarm rules');

  // ── time / cook clock ───────────────────────────────────────────────

  @override
  Future<void> setTime(int unixMs, {int? tzOffsetMin}) async {
    await _writeAndAwaitResult(
      wire.ControlOp.setTime,
      wire.CtrlSetTime(unixMs: unixMs, tzOffsetMin: tzOffsetMin ?? 0).encode(),
    );
  }

  @override
  Future<CookClockStatus> cookClock() async {
    final s = wire.LiveState.decode(await client.read(BridgeChar.liveState));
    return CookClockStatus(
      set: s.sessionActive,
      elapsedS: s.sessionActive ? s.sessionT : null,
    );
  }

  @override
  Future<CookClockStatus> setCookClock({
    int? elapsedS,
    int? startedUnixMs,
  }) async {
    final elapsed =
        elapsedS ?? ((_nowMs() - startedUnixMs!) ~/ 1000).clamp(0, 0xFFFFFFFF);
    await _writeAndAwaitResult(
      wire.ControlOp.setCookClock,
      wire.CtrlSetCookClock(elapsedS: elapsed).encode(),
    );
    return CookClockStatus(set: true, elapsedS: elapsed);
  }

  @override
  Future<CookClockStatus> clearCookClock() async {
    await _writeAndAwaitResult(wire.ControlOp.clearCookClock, Uint8List(0));
    return const CookClockStatus(set: false, elapsedS: null);
  }

  // ── verbs ───────────────────────────────────────────────────────────

  @override
  Future<void> pairSync() async =>
      _writeAndAwaitResult(wire.ControlOp.pair, Uint8List(0));

  @override
  Future<void> unpair() async =>
      _writeAndAwaitResult(wire.ControlOp.unpair, Uint8List(0));

  @override
  Future<void> restart() async =>
      _writeAndAwaitResult(wire.ControlOp.reboot, Uint8List(0));

  @override
  Future<void> factoryReset() async =>
      _writeAndAwaitResult(wire.ControlOp.factoryReset, Uint8List(0));

  @override
  Future<void> powerOff() async =>
      _writeAndAwaitResult(wire.ControlOp.powerOff, Uint8List(0));

  @override
  Future<void> stopSession(int sessionId) async =>
      _writeAndAwaitResult(wire.ControlOp.sessionStop, Uint8List(0));

  @override
  Future<void> deleteSession(int sessionId) =>
      // The GATT op table has no delete; deleting a recording is a Wi-Fi-only
      // action, and the UI offers it on the lane that can do it.
      throw const TransportUnsupported('delete a recording over BLE');

  @override
  Future<Map<String, Object?>> uploadOta(
    Stream<List<int>> image, {
    bool force = false,
  }) =>
      // OTA is HTTP-only, always (capabilities.ota is false on BLE).
      throw const TransportUnsupported('update firmware over BLE');

  @override
  Stream<TransportEvent> events() => _events.stream;

  // ── internals ───────────────────────────────────────────────────────

  /// Writes `device_control` and correlates the `result` notify by `op_echo` —
  /// never by arrival order, because a scan or a config reply can land between.
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
    await _events.close();
    await _results.close();
    await _netStatus.close();
    await _historyData.close();
    await client.dispose();
  }
}

Uint8List _bytes(String? s) =>
    s == null ? Uint8List(0) : Uint8List.fromList(utf8.encode(s));

String _statusCode(wire.ResultStatus? s) => switch (s) {
  wire.ResultStatus.busy => 'busy',
  wire.ResultStatus.invalid => 'invalid',
  wire.ResultStatus.unauthorized => 'unauthorized',
  wire.ResultStatus.failed => 'failed',
  _ => 'failed',
};

/// App-only kinds ([MarkKind.spritz]/[MarkKind.turn]) are written as `note` —
/// the device has no slot for them, and the app's own mark store keeps the
/// richer kind.
int _markKindToWire(MarkKind kind) => switch (kind) {
  MarkKind.note => 0,
  MarkKind.wrapped => 1,
  MarkKind.lidOpen => 2,
  MarkKind.fuel => 3,
  MarkKind.probeMoved => 4,
  MarkKind.alarm => 5,
  MarkKind.phaseChange => 6,
  MarkKind.autoDetected => 7,
  MarkKind.spritz => 0,
  MarkKind.turn => 0,
};

MarkKind _markKindFromWire(int value) =>
    value >= 0 && value < MarkKind.values.length
    ? MarkKind.values[value]
    : MarkKind.note;

int _wallClock() => DateTime.now().millisecondsSinceEpoch;
