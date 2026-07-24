/// A6.2–A6.4 — `BleTransport`: the third implementation sliding under
/// [BridgeTransport], which is exactly why that interface exists (design
/// 08 §8.1, [ble-gatt](../../../../protocol/ble-gatt.md) §4–§5).
///
/// **It must not invent a wire format.** Every byte in and out goes
/// through `records.g.dart`, generated from the same `records.yaml` as the
/// firmware's `record_gen.h`. A6's job is to speak the contract, not to
/// negotiate it.
///
/// Capabilities are honest rather than optimistic: live telemetry and the
/// 2-hour preview, yes; full history and OTA, no — those stay Wi-Fi-only
/// in v1 and the chart says so ([ble-gatt §5.8](../../../../protocol/ble-gatt.md)).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../domain/entities/entities.dart';
import '../dto/records.g.dart' as dto;
import 'ble_gatt.dart';
import 'bridge_transport.dart';

/// A `result` frame that did not say `ok`. Meaning, never magic numbers —
/// the rule A5.1 set for the HTTP envelope, applied to GATT.
class BridgeControlException implements Exception {
  const BridgeControlException(
    this.status, {
    this.opEcho = 0,
    this.detail = '',
  });

  final dto.ResultStatus status;
  final int opEcho;
  final String detail;

  bool get isBusy => status == dto.ResultStatus.busy;
  bool get isInvalid => status == dto.ResultStatus.invalid;
  bool get isUnauthorized => status == dto.ResultStatus.unauthorized;

  @override
  String toString() =>
      'BridgeControlException(${status.name}'
      '${detail.isEmpty ? '' : ': $detail'})';
}

/// The transport was asked for something its capability flags already
/// said it cannot do. Typed, so the chart can render "full history needs
/// Wi-Fi" instead of an error dialog (08 §8.7).
class BridgeUnsupportedException implements Exception {
  const BridgeUnsupportedException(this.what);
  final String what;
  @override
  String toString() => 'BridgeUnsupportedException: $what needs Wi-Fi';
}

/// What the scan list renders before any connection exists — the whole
/// point of the §2.3 blob (A6.4).
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

  /// `SmokeBridge-A4F2`, or a bare device id when the advertisement was
  /// malformed — a nameless entry beats failing the whole scan.
  final String name;

  /// Null when the pit probe is detached or the blob was unreadable.
  /// NEVER 0: a detached probe rendering as "0 °F" is the confusion this
  /// sentinel has existed to prevent since M0.
  final int? pitTempF10;
  final int sessionMinutes;
  final bool paired;
  final bool sessionActive;

  /// Null until F12 (M5) — `SOC_UNKNOWN` on the wire (ble-gatt §5.1.1).
  final int? socPct;
  final int rssi;

  /// Parses the 7-byte §2.3 blob. Returns a nameless-but-usable entry for
  /// anything it cannot read, because a scan that drops entries is worse
  /// than a scan that shows a plain one.
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
      pitTempF10: (pit == dto.tempDetached || pit == dto.tempInvalid)
          ? null
          : pit,
      sessionMinutes: bd.getUint16(5, Endian.little),
      paired: (flags & (1 << 0)) != 0,
      sessionActive: (flags & (1 << 1)) != 0,
      socPct: soc == dto.socUnknown ? null : soc,
      rssi: adv.rssi,
    );
  }
}

/// A6.3 — the client half of the firmware's chunker.
///
/// ATT cannot fragment a notification, so a payload longer than `MTU − 3`
/// arrives as consecutive chunks. The contract guarantees every variable
/// payload's fixed prefix (≤ 10 B) arrives whole in the first chunk, so
/// the total length is always knowable from chunk one — even at the
/// 20-byte default (ble-gatt §4).
class NotificationReassembler {
  NotificationReassembler(this.expectedLength);

  /// Given the bytes so far (≥ the fixed prefix), the full wire length.
  /// Returns null when the prefix has not fully arrived yet.
  final int? Function(Uint8List prefix) expectedLength;

  final _buf = BytesBuilder();
  int? _want;

  /// Feeds one chunk. Returns a complete payload, or null if more is
  /// needed. Throws [FormatException] rather than silently corrupting
  /// when the stream is nonsense.
  Uint8List? add(Uint8List chunk) {
    _buf.add(chunk);
    final bytes = _buf.toBytes();
    _want ??= expectedLength(bytes);
    if (_want == null) {
      return null; // prefix incomplete — impossible per the contract, but
      // a peer that violates it must not corrupt us.
    }
    if (bytes.length < _want!) {
      return null;
    }
    if (bytes.length > _want!) {
      // Two payloads ran together, or a chunk arrived out of order. Fail
      // loudly: silently returning the first `_want` bytes would hand the
      // caller a plausible, wrong frame.
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
int? _scanResultLength(Uint8List b) => b.length < 7 ? null : 7 + b[6];
int? _resultLength(Uint8List b) => b.length < 4 ? null : 4 + b[3];

class BleTransport implements BridgeTransport {
  BleTransport(this.client);

  final BleGattClient client;

  final _events = StreamController<BridgeEvent>.broadcast();
  final _results = StreamController<dto.ResultFrame>.broadcast();
  final _netStatus = StreamController<dto.NetStatus>.broadcast();
  final _scanResults = StreamController<dto.WifiScanResult>.broadcast();
  final _subs = <StreamSubscription<dynamic>>[];
  bool _started = false;
  bool _closed = false;

  @override
  BridgeCapabilities get capabilities => const BridgeCapabilities(
    liveState: true,
    historyPreview: true,
    // v1.1 (ble-gatt §5.8). The chart's "full history needs Wi-Fi" notice
    // is driven by exactly this flag — A3.1 built it for this moment.
    fullHistory: false,
    // Network config is the whole reason this transport exists. Probe
    // names/roles have no `device_control` op and stay HTTP-only in v1;
    // configure() says so with a typed condition rather than pretending.
    config: true,
    ota: false,
  );

  // ── notification wiring ────────────────────────────────────────────

  /// Subscribes to every notify characteristic and starts reassembly.
  /// Idempotent: calling it twice does not double the streams.
  Future<void> start() async {
    if (_started || _closed) {
      return;
    }
    _started = true;

    _subs.add(
      client.subscribe(BridgeChar.liveState).listen((chunk) {
        // Fixed 16 B: one PDU at any MTU, which is the point (§4).
        if (chunk.length < dto.LiveState.size) {
          return;
        }
        final s = dto.LiveState.decode(chunk);
        _events.add(
          BridgeEvent.sample(
            Sample(
              t: s.sessionT,
              tempsF10: s.tempNullable,
              billows: s.billows,
              rssi: s.rssiLora,
            ),
          ),
        );
      }),
    );

    _subs.add(
      _reassembled(BridgeChar.netStatus, _netStatusLength).listen((bytes) {
        final n = dto.NetStatus.unpack(bytes);
        _netStatus.add(n);
        _events.add(
          BridgeEvent.net(
            mode: n.modeEnum?.name ?? '',
            state: n.stateEnum?.name ?? '',
            ip: n.ip.every((o) => o == 0) ? null : n.ip.join('.'),
          ),
        );
      }),
    );

    _subs.add(
      _reassembled(BridgeChar.result, _resultLength).listen((bytes) {
        _results.add(dto.ResultFrame.unpack(bytes));
      }),
    );

    _subs.add(
      _reassembled(BridgeChar.wifiScanResult, _scanResultLength).listen((
        bytes,
      ) {
        _scanResults.add(dto.WifiScanResult.unpack(bytes));
      }),
    );
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

  // ── BridgeTransport ────────────────────────────────────────────────

  @override
  Stream<BridgeEvent> get events => _events.stream;

  /// `net_status` transitions, which the onboarding wizard watches across
  /// the §5.7 handoff. A missed transition strands the wizard, so this is
  /// a first-class stream rather than something dug out of [events].
  Stream<dto.NetStatus> get netStatus => _netStatus.stream;

  Stream<dto.WifiScanResult> get scanResults => _scanResults.stream;

  Future<dto.DeviceInfo> deviceInfo() async =>
      dto.DeviceInfo.decode(await client.read(BridgeChar.deviceInfo));

  /// Reads `net_status` on demand (§5.2 is Read as well as Notify).
  /// Notifications report CHANGES; when nothing changed there is nothing
  /// to notify, so asking is the only way to learn the current answer.
  Future<dto.NetStatus> readNetStatus() async =>
      dto.NetStatus.unpack(await client.read(BridgeChar.netStatus));

  @override
  Future<BridgeStatus> status() async {
    final info = await deviceInfo();
    final live = dto.LiveState.decode(await client.read(BridgeChar.liveState));
    return BridgeStatus(
      deviceId: info.id,
      model: info.model,
      fw: info.fw,
      uptimeS: 0, // not on the BLE contract; HTTP has it
      paired: live.paired,
      numProbes: info.probes,
      sessionActive: live.sessionActive,
      storageFreePct: 0,
      socPct: live.socPct == dto.socUnknown ? null : live.socPct,
      alarms: const [],
    );
  }

  @override
  Future<LiveState> live({Duration window = const Duration(hours: 1)}) async {
    final s = dto.LiveState.decode(await client.read(BridgeChar.liveState));
    final preview = dto.HistoryPreview.unpack(
      await client.read(BridgeChar.historyPreview),
    );
    // The 2-hour preview is one probe at 1-minute buckets — enough for a
    // real sparkline over BLE alone (§5.8), so `recent` is honest data
    // rather than an empty list.
    final stepS = preview.bucketMin * 60;
    final t0 = s.sessionT - (preview.values.length - 1) * stepS;
    return LiveState(
      t: s.sessionT,
      tempsF10: s.tempNullable,
      billows: s.billows,
      recent: [
        for (var i = 0; i < preview.values.length; i++)
          Sample(
            t: t0 + i * stepS,
            tempsF10: [preview.valuesNullable[i], null, null, null],
          ),
      ],
    );
  }

  @override
  Future<List<CookSession>> sessions() =>
      throw const BridgeUnsupportedException('the session list');

  @override
  Stream<List<Sample>> samples(
    int sessionId, {
    int fromT = 0,
    int? toT,
    int? bucketS,
  }) => throw const BridgeUnsupportedException('full history');

  @override
  Future<void> control(ControlCommand cmd) async {
    final (op, body) = switch (cmd) {
      StartSessionCommand() => (dto.ControlOp.sessionStart, Uint8List(0)),
      StopSessionCommand() => (dto.ControlOp.sessionStop, Uint8List(0)),
      PairCommand() => (dto.ControlOp.pair, Uint8List(0)),
      UnpairCommand() => (dto.ControlOp.unpair, Uint8List(0)),
      MarkCommand(:final kind, :final text) => (
        dto.ControlOp.mark,
        dto.CtrlMark(
          kind: kind.index,
          textRaw: Uint8List.fromList(utf8.encode(text)),
        ).pack(),
      ),
      SetTimeCommand(:final unixMs) => (
        dto.ControlOp.setTime,
        dto.CtrlSetTime(unixMs: unixMs, tzOffsetMin: 0).encode(),
      ),
      AckAlarmCommand(:final alarmId) => (
        dto.ControlOp.ackAlarm,
        dto.CtrlAckAlarm(alarmId: alarmId).encode(),
      ),
    };
    await _writeAndAwaitResult(op, body);
  }

  @override
  Future<void> uploadFirmware(
    Stream<List<int>> image, {
    required int lengthBytes,
    bool force = false,
  }) =>
      // OTA is HTTP-only, always (F14 device side). capabilities.ota is
      // false on BLE, so the upload button is absent rather than
      // disabled-and-mysterious — but a caller that ignores the flag gets
      // an honest refusal rather than a silent drop.
      throw const BridgeUnsupportedException('firmware update');

  @override
  Future<void> configure(BridgeConfig cfg) async {
    if (cfg.probes != null) {
      // No `device_control` op sets probe names or roles — that surface is
      // HTTP-only in v1, and saying so beats silently dropping the write.
      throw const BridgeUnsupportedException('probe configuration');
    }
    final units = cfg.displayUnits;
    if (units == null) {
      return;
    }
    await _writeAndAwaitResult(
      dto.ControlOp.setUnits,
      dto.CtrlSetUnits(
        units: units.toUpperCase() == 'C'
            ? dto.TempUnits.celsius.wire
            : dto.TempUnits.fahrenheit.wire,
      ).encode(),
    );
  }

  /// A pending correlation whose write then failed will never be answered,
  /// and its `firstWhere` would surface as an unhandled "No element" long
  /// after the caller has already handled the real error. Detach it.
  void _abandon(Future<dto.ResultFrame> pending) {
    unawaited(pending.then((_) {}, onError: (Object _) {}));
  }

  /// Writes `device_control` and correlates the `result` notify by
  /// `op_echo` — never by arrival order, because a scan or a config reply
  /// can land in between.
  Future<dto.ResultFrame> _writeAndAwaitResult(
    dto.ControlOp op,
    Uint8List body, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await start();
    final answer = _results.stream
        .firstWhere((r) => r.opEcho == op.wire)
        .timeout(timeout);
    try {
      await client.write(
        BridgeChar.deviceControl,
        dto.DeviceControl(op: op.wire, bodyRaw: body).pack(),
      );
    } on Object {
      _abandon(answer);
      rethrow;
    }
    final r = await answer;
    if (r.statusEnum != dto.ResultStatus.ok) {
      throw BridgeControlException(
        r.statusEnum ?? dto.ResultStatus.failed,
        opEcho: r.opEcho,
        detail: r.detail,
      );
    }
    return r;
  }

  // ── provisioning (A8's surface) ────────────────────────────────────

  /// Starts an AP scan. Results arrive on [scanResults]; completion is
  /// implicit in the last one's `index == total - 1`, and an empty scan
  /// answers `total 0` rather than never completing (§5.3–§5.4).
  Future<void> startWifiScan() async {
    await start();
    final ack = _results.stream.firstWhere((r) => r.opEcho == 0);
    try {
      await client.write(
        BridgeChar.wifiScanCtrl,
        dto.WifiScanCtrl(cmd: dto.ScanCmd.start.wire).encode(),
      );
    } on Object {
      _abandon(ack);
      rethrow;
    }
    final r = await ack.timeout(const Duration(seconds: 10));
    if (r.statusEnum != dto.ResultStatus.ok) {
      throw BridgeControlException(
        r.statusEnum ?? dto.ResultStatus.failed,
        detail: r.detail,
      );
    }
  }

  Future<void> cancelWifiScan() async {
    await client.write(
      BridgeChar.wifiScanCtrl,
      dto.WifiScanCtrl(cmd: dto.ScanCmd.cancel.wire).encode(),
    );
  }

  /// The provisioning artery. Returns the `result` frame, whose `detail`
  /// carries the generated AP PSK on a mode change to AP — the phone
  /// needs it to join (§5.5, 05 §5.7).
  Future<dto.ResultFrame> applyWifiConfig({
    required dto.NetMode mode,
    String ssid = '',
    String psk = '',
    String user = '',
    int auth = 3,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await start();
    final answer = _results.stream.firstWhere((r) => r.opEcho == 0);
    try {
      await client.write(
        BridgeChar.wifiConfig,
        dto.WifiConfig(
          mode: mode.wire,
          auth: auth,
          ssidRaw: Uint8List.fromList(utf8.encode(ssid)),
          pskRaw: Uint8List.fromList(utf8.encode(psk)),
          userRaw: Uint8List.fromList(utf8.encode(user)),
        ).pack(),
      );
    } on Object {
      _abandon(answer);
      rethrow;
    }
    final r = await answer.timeout(timeout);
    if (r.statusEnum != dto.ResultStatus.ok) {
      throw BridgeControlException(
        r.statusEnum ?? dto.ResultStatus.failed,
        detail: r.detail,
      );
    }
    return r;
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
    await _scanResults.close();
    await client.dispose();
  }
}
