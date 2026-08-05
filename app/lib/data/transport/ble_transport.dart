/// A6.2–A6.4 — `BleTransport`: the third implementation sliding under
/// [BridgeTransport], which is exactly why that interface exists (design
/// 08 §8.1, [ble-gatt](../../../../protocol/ble-gatt.md) §4–§5).
///
/// **It must not invent a wire format.** Every byte in and out goes
/// through `records.g.dart`, generated from the same `records.yaml` as the
/// firmware's `record_gen.h`. A6's job is to speak the contract, not to
/// negotiate it.
///
/// Capabilities are honest rather than optimistic: live telemetry, the
/// 2-hour preview, and — from v1.1 — full history
/// ([ble-gatt §5.10–§5.11](../../../../protocol/ble-gatt.md)). OTA stays
/// Wi-Fi-only, and full history is reported from the bridge's own caps bit
/// rather than declared, because the same app build talks to bridges on
/// both sides of that feature.
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
int? _historyDataLength(Uint8List b) => b.length < 7 ? null : 7 + b[6];

/// A history stream that did not end `ok` (ble-gatt §5.11). Separate from
/// [BridgeControlException] because it arrives on `history_data`, not on
/// `result` — and because "the stream died at frame 40" is a different
/// user-visible fact from "the write was refused".
class BridgeHistoryException implements Exception {
  const BridgeHistoryException(this.status, {this.framesSeen = 0});

  final dto.ResultStatus status;
  final int framesSeen;

  bool get isBusy => status == dto.ResultStatus.busy;

  @override
  String toString() =>
      'BridgeHistoryException(${status.name}, after $framesSeen frames)';
}

class BleTransport implements BridgeTransport {
  BleTransport(this.client);

  final BleGattClient client;

  final _events = StreamController<BridgeEvent>.broadcast();
  final _results = StreamController<dto.ResultFrame>.broadcast();
  final _netStatus = StreamController<dto.NetStatus>.broadcast();
  final _scanResults = StreamController<dto.WifiScanResult>.broadcast();
  final _historyData = StreamController<dto.HistoryData>.broadcast();
  final _subs = <StreamSubscription<dynamic>>[];
  bool _started = false;
  bool _closed = false;

  /// `device_info.caps` b6 — whether this bridge serves §5.10/§5.11.
  ///
  /// **Null means "not asked yet", never "no".** A v1.0 bridge does not
  /// merely refuse a `history_ctrl` write, it never answers one at all, so
  /// guessing optimistically would hang the sync rather than fail it. The
  /// flag is latched on the first [deviceInfo] read, which [status] and the
  /// connection handshake both perform before anything reads capabilities.
  bool? _historyFull;

  @override
  BridgeCapabilities get capabilities => BridgeCapabilities(
    liveState: true,
    historyPreview: true,
    // v1.1 (ble-gatt §5.10). Derived from the device rather than declared
    // here: the same app build talks to bridges on both sides of this
    // feature, and the chart's "full history needs Wi-Fi" notice — which
    // A3.1 built for exactly this flag — must still be right in front of
    // an older one.
    fullHistory: _historyFull ?? false,
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

    // Settle `capabilities` before anything can read it. `device_info` is
    // the one unencrypted characteristic (§3), so this succeeds on any
    // connected link — and it must happen HERE rather than lazily, because
    // callers branch on `capabilities.fullHistory` synchronously and a
    // capability that is briefly wrong is a UI that briefly lies.
    try {
      await deviceInfo();
    } on Object {
      // A bridge we cannot even identify is one nothing else will work
      // against either; leaving _historyFull null keeps full history
      // reported as absent, which is the safe direction.
    }

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

    // §5.11. Subscribed unconditionally: an older bridge simply has no such
    // characteristic and the client's subscribe is a no-op there, whereas
    // subscribing lazily at request time would race the first frames.
    _subs.add(
      _reassembled(BridgeChar.historyData, _historyDataLength).listen((bytes) {
        _historyData.add(dto.HistoryData.unpack(bytes));
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

  Future<dto.DeviceInfo> deviceInfo() async {
    final info = dto.DeviceInfo.decode(await client.read(BridgeChar.deviceInfo));
    // Latch the one capability the app cannot otherwise discover safely.
    _historyFull = info.historyFull;
    return info;
  }

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

  /// A26 — the one lane that can measure the hop the user is standing in.
  ///
  /// The GATT connection's RSSI *is* phone↔bridge, read from the phone's own
  /// radio, so this is the only place in the app where "how far away am I"
  /// has a real answer. `net_status` rides along for free (§5.2 is Read as
  /// well as Notify) so the screen can also say how the bridge is doing on
  /// Wi-Fi while we are talking to it over Bluetooth.
  @override
  Future<LinkSignal> signal() async {
    final linkDbm = await client.readRssi();
    try {
      final n = await readNetStatus();
      return LinkSignal(
        linkDbm: linkDbm,
        // 0 is "not applicable" (hosting, or never joined), not a reading.
        wifiDbm: (n.modeEnum == dto.NetMode.ap || n.wifiRssi == 0)
            ? null
            : n.wifiRssi,
        ssid: n.ssid,
      );
    } on Object {
      // The link answered for itself; the bridge's Wi-Fi picture is a bonus
      // this lane can do without rather than a reason to report nothing.
      return LinkSignal(linkDbm: linkDbm);
    }
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

  // ── full history over BLE (A27 — ble-gatt §5.10–§5.11) ─────────────
  //
  // The transfer that makes an always-recording bridge useful without a
  // network: turn the bridge on with the base station, walk away, come back
  // twelve hours later, and the phone pulls the whole cook over Bluetooth.

  /// One request at a time, enforced here rather than discovered as a
  /// `busy` end frame — the device serialises streams (§5.10) and two
  /// concurrent callers would otherwise interleave frames from one stream
  /// into the other's reassembly.
  Future<void>? _historyLock;

  /// Runs one `history_ctrl` request and yields its frames until `last`.
  ///
  /// Throws [BridgeHistoryException] when the end frame reports anything
  /// but `ok`, and [BridgeUnsupportedException] on a bridge whose caps say
  /// it does not serve this at all.
  Stream<dto.HistoryData> _request(
    dto.HistoryReq req, {
    int sessionId = 0,
    int fromT = 0,
    int? toT,
    int stride = 1,
    Duration timeout = const Duration(seconds: 30),
  }) async* {
    if (_historyFull == null) {
      await deviceInfo(); // cheap, unencrypted, and settles the question
    }
    if (_historyFull != true) {
      throw const BridgeUnsupportedException('full history');
    }
    await start();

    // Serialise against any stream already running on this transport.
    while (_historyLock != null) {
      await _historyLock;
    }
    final gate = Completer<void>();
    _historyLock = gate.future;
    try {
      // Attach BEFORE the write: the device answers on its own task and the
      // first frames can land while the write is still completing.
      final frames = StreamController<dto.HistoryData>();
      final sub = _historyData.stream.listen(frames.add, onError: frames.addError);
      try {
        await client.write(
          BridgeChar.historyCtrl,
          dto.HistoryCtrl(
            req: req.wire,
            stride: stride,
            sessionId: sessionId,
            fromT: fromT,
            // UINT32_MAX is "to the end" (§5.10), which is what an absent
            // bound means everywhere else in this app too.
            toT: toT ?? 0xFFFFFFFF,
          ).encode(),
        );

        var seen = 0;
        var nextSeq = 0;
        await for (final f in frames.stream.timeout(timeout)) {
          seen++;
          // §5.11: a `busy` refusal rides seq 0xFFFF precisely so it cannot
          // be confused with a frame of a stream already in flight.
          if (f.seq != 0xFFFF) {
            if (f.seq != nextSeq) {
              // A gap means a dropped frame. Stitching across it would hand
              // the cache a cook with an invisible hole, so fail instead and
              // let the caller re-request the range.
              throw FormatException(
                'history_data: frame gap — expected seq $nextSeq, got ${f.seq}',
              );
            }
            nextSeq = f.seq + 1;
          }
          if (f.kindEnum == dto.HistoryKind.end) {
            final status =
                dto.ResultStatus.fromWire(
                  f.payloadRaw.isEmpty ? 3 : f.payloadRaw[0],
                ) ??
                dto.ResultStatus.failed;
            if (status != dto.ResultStatus.ok) {
              throw BridgeHistoryException(status, framesSeen: seen);
            }
            return; // the one clean exit: an end frame that said ok
          }
          yield f;
          if (f.last) {
            // `last` without `end` means the terminator was dropped. The
            // data so far is real, but the stream is not provably complete.
            throw const BridgeHistoryException(dto.ResultStatus.failed);
          }
        }
        throw const BridgeHistoryException(dto.ResultStatus.failed);
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
  Future<List<CookSession>> sessions() async {
    final out = <CookSession>[];
    await for (final f in _request(dto.HistoryReq.sessions)) {
      if (f.kindEnum != dto.HistoryKind.session) {
        continue;
      }
      for (var i = 0; i < f.count; i++) {
        final s = dto.HistorySession.decode(
          f.payloadRaw,
          i * dto.HistorySession.size,
        );
        out.add(
          CookSession(
            id: s.sessionId,
            name: s.name,
            // 0 is "the bridge had no clock", not midnight 1970 — the same
            // absent-is-null rule every other reading here follows.
            startedUnixMs: s.startedUnixMs == 0 ? null : s.startedUnixMs,
            endedUnixMs: s.endedUnixMs == 0 ? null : s.endedUnixMs,
            samplePeriodS: s.samplePeriodS,
            sampleCount: s.sampleCount,
            numProbes: s.numProbes,
            closed: s.closed,
            pinned: s.pinned,
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
    int? bucketS,
  }) async* {
    // The device aggregates for the HTTP chart; over BLE it streams whole
    // records and the app buckets locally. Sending 23 KB unaggregated and
    // keeping full fidelity in the cache beats saving a few KB and caching
    // something the user can never zoom into.
    var batch = <Sample>[];
    await for (final f in _request(
      dto.HistoryReq.samples,
      sessionId: sessionId,
      fromT: fromT,
      toT: toT,
    )) {
      if (f.kindEnum != dto.HistoryKind.samples) {
        continue;
      }
      for (var i = 0; i < f.count; i++) {
        final r = dto.SampleRec.decode(f.payloadRaw, i * dto.SampleRec.size);
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
      // 14 records per frame would mean ~103 drift transactions for a 12 h
      // cook. Coalescing keeps the insert count sane without holding the
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

  /// A28 — the marks the bridge recorded, over the same stream (§5.11).
  /// Not on [BridgeTransport] because HTTP fetches them through the session
  /// detail endpoint; this is the BLE lane's equivalent.
  Future<List<Mark>> marks(int sessionId, {int fromT = 0, int? toT}) async {
    final out = <Mark>[];
    await for (final f in _request(
      dto.HistoryReq.marks,
      sessionId: sessionId,
      fromT: fromT,
      toT: toT,
    )) {
      if (f.kindEnum != dto.HistoryKind.marks) {
        continue;
      }
      for (var i = 0; i < f.count; i++) {
        final m = dto.MarkRec.decode(f.payloadRaw, i * dto.MarkRec.size);
        out.add(
          Mark(
            t: m.t,
            kind: m.kind < MarkKind.values.length
                ? MarkKind.values[m.kind]
                : MarkKind.values.first,
            probe: m.probe,
            text: m.text,
          ),
        );
      }
    }
    return out;
  }

  /// Stops a stream in flight (§5.10). Always succeeds, including with
  /// nothing running — that is what a retrying caller's second cancel is.
  Future<void> cancelHistory() async {
    if (_historyFull != true) {
      return;
    }
    await client.write(
      BridgeChar.historyCtrl,
      dto.HistoryCtrl(req: dto.HistoryReq.cancel.wire).encode(),
    );
  }

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
      // The device answers these before it acts, then drops the link — the
      // result notify is flushed first, which is why they are ordinary
      // awaited writes here rather than fire-and-forget.
      RebootCommand() => (dto.ControlOp.reboot, Uint8List(0)),
      FactoryResetCommand() => (dto.ControlOp.factoryReset, Uint8List(0)),
      PowerOffCommand() => (dto.ControlOp.powerOff, Uint8List(0)),
    };
    await _writeAndAwaitResult(op, body);
  }

  @override
  Future<String> applyNetwork({
    required NetworkMode mode,
    String ssid = '',
    String psk = '',
    int revertAfterS = 0,
  }) async {
    final r = await applyWifiConfig(
      mode: mode == NetworkMode.ap ? dto.NetMode.ap : dto.NetMode.sta,
      ssid: ssid,
      psk: psk,
    );
    // On a switch to AP the generated PSK rides back in `detail` (§5.5) —
    // the phone has to leave its own network to rejoin, so it needs the key.
    return mode == NetworkMode.ap ? r.detail : '';
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

  /// newapp §G.3 — the device's alarm rules over the `device_control`
  /// surface.
  ///
  /// v1 firmware has no BLE op for reading or writing a rule, and the honest
  /// answer to "can this link change the bridge's alarms" is therefore no.
  /// Throwing the typed condition is what makes the editor render its rows
  /// disabled-with-a-reason instead of offering switches that write nothing —
  /// which is the exact bug the settings tree shipped with.
  /// newapp §E.3 — BLE has no `netmode/commit` op, and that is the honest
  /// answer rather than a problem: BLE is the **escape hatch** the switch
  /// keeps open, not the lane the switch is confirmed on. A confirmation over
  /// Bluetooth would prove the phone can reach the bridge over Bluetooth,
  /// which was never in doubt and is not what the rollback is protecting.
  @override
  Future<void> commitNetworkMode() =>
      throw const BridgeUnsupportedException('Confirming a network switch');

  @override
  Future<Map<String, Object?>> alarmConfig() =>
      throw const BridgeUnsupportedException('Changing the bridge’s alarms');

  @override
  Future<void> setAlarmConfig(Map<String, Object?> patch) =>
      throw const BridgeUnsupportedException('Changing the bridge’s alarms');

  @override
  Future<MqttConfig> mqttConfig() =>
      // The broker lives on the Wi-Fi LAN the bridge joins; there is no BLE
      // op for it, and capabilities.mqtt is false so the page explains rather
      // than offers a dead form.
      throw const BridgeUnsupportedException('Home Assistant');

  @override
  Future<void> setMqttConfig({
    bool? enabled,
    String? host,
    int? port,
    String? user,
    String? password,
    String? prefix,
    bool? haDiscovery,
  }) => throw const BridgeUnsupportedException('Home Assistant');

  @override
  Future<void> configure(BridgeConfig cfg) async {
    if (cfg.probes != null) {
      // No `device_control` op sets probe names or roles — that surface is
      // HTTP-only in v1, and saying so beats silently dropping the write.
      throw const BridgeUnsupportedException('probe configuration');
    }
    final units = cfg.displayUnits;
    if (units != null) {
      await _writeAndAwaitResult(
        dto.ControlOp.setUnits,
        dto.CtrlSetUnits(
          units: units.toUpperCase() == 'C'
              ? dto.TempUnits.celsius.wire
              : dto.TempUnits.fahrenheit.wire,
        ).encode(),
      );
    }
    final saver = cfg.batterySaver;
    if (saver != null) {
      // Spelled out rather than indexed off the enum's position: these are
      // two independently-declared orderings and a silent drift would set
      // the wrong profile.
      final wire = switch (saver) {
        BatterySaverMode.off => dto.BatterySaver.off,
        BatterySaverMode.on => dto.BatterySaver.on,
        BatterySaverMode.auto => dto.BatterySaver.auto,
      }.wire;
      await _writeAndAwaitResult(
        dto.ControlOp.setBatterySaver,
        dto.CtrlSetBatterySaver(saver: wire).encode(),
      );
    }
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
    // The correlation is pre-abandoned the moment it exists: if it errors
    // while the WRITE below is still in flight (a stalled link — the write
    // itself can outlive this timeout), there must already be a listener,
    // or the error surfaces as an uncaught zone fault on the crash page.
    // Board-found (A24.11): a stale-bond stall did exactly that.
    final answer = _results.stream
        .firstWhere((r) => r.opEcho == op.wire)
        .timeout(timeout);
    _abandon(answer);
    await client.write(
      BridgeChar.deviceControl,
      dto.DeviceControl(op: op.wire, bodyRaw: body).pack(),
    );
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
    _abandon(ack); // pre-attached: see _writeAndAwaitResult (A24.11)
    await client.write(
      BridgeChar.wifiScanCtrl,
      dto.WifiScanCtrl(cmd: dto.ScanCmd.start.wire).encode(),
    );
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
    _abandon(answer); // pre-attached: see _writeAndAwaitResult (A24.11)
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
    await _historyData.close();
    await client.dispose();
  }
}
