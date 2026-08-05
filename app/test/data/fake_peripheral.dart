/// A6.1 — a fake bridge peripheral, in Dart, on the generated codecs.
///
/// This is to A6 what `tools/sim` is to A5: the thing that makes every
/// following task board-free. It advertises the §2 blob, walks the bond
/// state machine, enforces the three §3 security levels, serves all nine
/// characteristics, and is configurable for the failure modes that
/// actually happen — MTU negotiation refused, notifications split at
/// `MTU − 3`, a bond rejected, a connection dropped mid-write, and a
/// bridge that was factory-reset since we last paired.
///
/// It must not invent a wire format. Every byte it emits comes from
/// `records.g.dart`, the same generator the firmware's `record_gen.h`
/// comes from, so a divergence is a red test rather than a bridge that
/// will not provision.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:smoke_bridge/data/dto/records.g.dart';
import 'package:smoke_bridge/data/transport/ble_gatt.dart';

/// How the fake should misbehave. Every field here is a real thing a real
/// phone has done to a real peripheral.
class FakePeripheralConfig {
  const FakePeripheralConfig({
    this.negotiatedMtu = 247,
    this.rejectBond = false,
    this.dropOnWrite = false,
    this.staleBond = false,
    this.refuseRemoveBond = false,
    this.scanResults = const [],
    this.emptyScan = false,
    this.wifiConfigOutcome = ResultStatus.ok,
    this.netStatusScript = const [],
    this.silentAfterConfig = false,
    this.advertiseMalformed = false,
    this.advertiseNothing = false,
    this.continuousScan = false,
    this.rssi = -58,
    this.historyStatus = ResultStatus.ok,
    this.historyDropFrame,
    this.historyBusy = false,
  });

  /// The status the end frame reports (§5.11). Anything but `ok` must
  /// surface as a typed failure rather than a short cook.
  final ResultStatus historyStatus;

  /// Drop the frame at this index, keeping the seq chain's gap visible.
  /// A dropped frame is the one history failure a client cannot detect by
  /// looking at the data — only by the counter.
  final int? historyDropFrame;

  /// A stream is already running: answer `busy` on seq 0xFFFF without
  /// disturbing it (§5.10).
  final bool historyBusy;

  /// 23 is the value to fear: it is what a failed negotiation leaves, and
  /// the one `live_state` was designed at 16 B to survive (R7).
  final int negotiatedMtu;

  /// The connected link's RSSI in dBm, for the Bridge tab's signal rows.
  final int rssi;
  final bool rejectBond;

  /// The link drops in the middle of a write — the wizard must not hang.
  final bool dropOnWrite;

  /// The bridge was factory-reset since we bonded: our LTK is meaningless
  /// to it. Surfaces as a re-bond-needed condition, never as a silent
  /// "won't connect" (A6.4).
  final bool staleBond;

  /// The platform refuses [BleGattClient.removeBond] (A24.11) — the case
  /// where the auto-heal cannot run and the user is sent to Bluetooth
  /// settings instead.
  final bool refuseRemoveBond;

  final List<WifiScanResult> scanResults;
  final bool emptyScan;
  final ResultStatus wifiConfigOutcome;

  /// The `net_status` frames to emit after a `wifi_config` write, in
  /// order — e.g. `[connecting, failed]` for the wrong-password path the
  /// M3 exit gate is built around.
  final List<NetStatus> netStatusScript;

  /// Accepts the config and then never reports a transition at all — the
  /// case the wizard's 20 s budget exists for (05 §5.7).
  final bool silentAfterConfig;

  /// A truncated manufacturer blob: the scan list must degrade to a
  /// nameless entry rather than failing the whole scan.
  final bool advertiseMalformed;

  /// Nothing in range at all — powered off, or out of range.
  final bool advertiseNothing;

  /// Reproduce the REAL plugin: `FlutterBluePlus.onScanResults` is a
  /// long-lived stream that keeps re-reporting advertisements and never
  /// ends on its own. The default (a finite stream) is a convenience the
  /// board proved is also a blind spot — with it, a caller that treats
  /// "scan ended" as a step boundary looks correct in tests and flickers
  /// on a phone.
  final bool continuousScan;

  FakePeripheralConfig copyWith({
    int? negotiatedMtu,
    bool? rejectBond,
    bool? dropOnWrite,
    bool? staleBond,
    List<WifiScanResult>? scanResults,
    bool? emptyScan,
    ResultStatus? wifiConfigOutcome,
    List<NetStatus>? netStatusScript,
    bool? silentAfterConfig,
    bool? advertiseMalformed,
    bool? advertiseNothing,
    bool? continuousScan,
    ResultStatus? historyStatus,
    int? historyDropFrame,
    bool? historyBusy,
  }) => FakePeripheralConfig(
    historyStatus: historyStatus ?? this.historyStatus,
    historyDropFrame: historyDropFrame ?? this.historyDropFrame,
    historyBusy: historyBusy ?? this.historyBusy,
    negotiatedMtu: negotiatedMtu ?? this.negotiatedMtu,
    rejectBond: rejectBond ?? this.rejectBond,
    dropOnWrite: dropOnWrite ?? this.dropOnWrite,
    staleBond: staleBond ?? this.staleBond,
    scanResults: scanResults ?? this.scanResults,
    emptyScan: emptyScan ?? this.emptyScan,
    wifiConfigOutcome: wifiConfigOutcome ?? this.wifiConfigOutcome,
    netStatusScript: netStatusScript ?? this.netStatusScript,
    silentAfterConfig: silentAfterConfig ?? this.silentAfterConfig,
    advertiseMalformed: advertiseMalformed ?? this.advertiseMalformed,
    advertiseNothing: advertiseNothing ?? this.advertiseNothing,
    continuousScan: continuousScan ?? this.continuousScan,
  );
}

/// The device's own state, so the fake answers questions consistently
/// rather than replaying canned bytes.
class FakeBridgeState {
  FakeBridgeState({
    this.deviceId = 'A4F2',
    this.model = 'heltec-v3',
    this.fw = '1.0.0',
    this.probes = 4,
    // wifi_ap | wifi_sta | history_preview | history_full. `battery` stays
    // clear until F12 (M5), which is why socPct is socUnknown
    // (ble-gatt §5.1.1). Drop b6 (→ 0x0B) to model a v1.0 bridge that never
    // answers a history_ctrl write at all.
    this.caps = 0x4B,
    this.paired = true,
    this.sessionActive = true,
    this.pitTempF10 = 2431,
    this.sessionSeconds = 15120,
    this.apPsk = 'Gk7mR2xQpT',
  });

  String deviceId;
  String model;
  String fw;
  int probes;
  int caps;
  bool paired;
  bool sessionActive;
  int pitTempF10;
  int sessionSeconds;
  String apPsk;

  NetStatus net = NetStatus(
    mode: NetMode.ap.wire,
    state: NetState.up.wire,
    ip: [192, 168, 4, 1],
    ssidRaw: Uint8List.fromList(utf8.encode('SmokeBridge-A4F2')),
    hostRaw: Uint8List.fromList(utf8.encode('smokebridge')),
  );

  LiveState live() => LiveState(
    flags:
        (paired ? 1 << 0 : 0) |
        (sessionActive ? 1 << 1 : 0) |
        (1 << 4), // clock_valid
    temp: [pitTempF10, 1632, tempDetached, tempInvalid],
    socPct: socUnknown,
    rssiLora: -71,
    sessionT: sessionActive ? sessionSeconds : 0,
  );

  DeviceInfo info() => DeviceInfo(
    api: 1,
    probes: probes,
    caps: caps,
    idRaw: utf8ToPadded(deviceId, 4),
    modelRaw: utf8ToPadded(model, 16),
    fwRaw: utf8ToPadded(fw, 16),
  );

  HistoryPreview preview({int count = 120}) => HistoryPreview(
    bucketMin: 1,
    values: [
      for (var i = 0; i < count; i++)
        i == 3 ? tempDetached : pitTempF10 - count + i,
    ],
  );

  // ── v1.1: what the bridge actually has on flash (§5.10–§5.11) ────────
  //
  // Populated by [recordCook], because the scenario this feature exists for
  // is a bridge that recorded for hours with no phone anywhere near it.

  /// Session id → the records the bridge holds, in `t` order.
  final Map<int, List<SampleRec>> cooks = {};
  final Map<int, List<MarkRec>> cookMarks = {};
  final Map<int, HistorySession> cookHeaders = {};

  /// Records `hours` of a cook at the nominal 30 s cadence, exactly as an
  /// always-recording bridge would have while nobody was watching.
  int recordCook({
    int id = 0x1A,
    int hours = 12,
    bool closed = false,
    String name = 'Cook — Sat 14 Mar, 06:12',
    int startedUnixMs = 1774051200000,
  }) {
    final n = hours * 120;
    cooks[id] = [
      for (var i = 0; i < n; i++)
        SampleRec(
          t: i * 30,
          // Probe 3 detached throughout: the sentinel has to survive the
          // whole transfer and arrive as null, never as 0 °F.
          temp: [2000 + (i % 400), 1600, tempDetached, 900],
          rssi: -70,
        ),
    ];
    cookMarks.putIfAbsent(id, () => []);
    cookHeaders[id] = HistorySession(
      sessionId: id,
      startedUnixMs: startedUnixMs,
      endedUnixMs: closed ? startedUnixMs + hours * 3600 * 1000 : 0,
      // Authoritative for an OPEN session too: the firmware derives it from
      // the file size rather than the header field, which is the difference
      // between a phone syncing a live 12 h cook and one being told there
      // is nothing there (04 §4.3).
      sampleCount: n,
      samplePeriodS: 30,
      numProbes: 4,
      flags: 0x01 | (closed ? 0x02 : 0),
      nameRaw: utf8ToPadded(name, 28),
    );
    return id;
  }
}

/// The §2.3 manufacturer status blob, built the same way the firmware
/// builds it (app_ble_adv.c) so the two cannot disagree.
Uint8List buildStatusBlob(FakeBridgeState s) {
  final out = Uint8List(7);
  final bd = ByteData.sublistView(out);
  final live = s.live();
  bd.setUint8(0, 1);
  bd.setUint8(1, live.flags);
  bd.setInt16(2, live.temp[0], Endian.little);
  bd.setUint8(4, live.socPct);
  bd.setUint16(5, (live.sessionT ~/ 60).clamp(0, 0xFFFF), Endian.little);
  return out;
}

class FakePeripheral implements BleGattClient {
  FakePeripheral({FakePeripheralConfig? config, FakeBridgeState? state})
    : config = config ?? const FakePeripheralConfig(),
      state = state ?? FakeBridgeState();

  FakePeripheralConfig config;
  final FakeBridgeState state;

  /// Every write the client made, for assertion.
  final List<(int slot, Uint8List value)> writes = [];

  BleConnectionState _conn = BleConnectionState.disconnected;
  BleBondState _bond = BleBondState.none;
  int _mtu = 23;
  bool _disposed = false;

  final _connCtl = StreamController<BleConnectionState>.broadcast();
  final _bondCtl = StreamController<BleBondState>.broadcast();
  final _notifCtls = <int, StreamController<Uint8List>>{};

  // ── scanning ───────────────────────────────────────────────────────

  @override
  Stream<BleAdvertisement> scan({
    Duration timeout = const Duration(seconds: 8),
  }) {
    final adv = BleAdvertisement(
      deviceId:
          'AA:BB:CC:DD:${state.deviceId.substring(0, 2)}:'
          '${state.deviceId.substring(2)}',
      name: 'SmokeBridge-${state.deviceId}',
      manufacturerData: config.advertiseMalformed
          ? Uint8List.fromList([1, 0]) // truncated: 2 of the 7 bytes
          : buildStatusBlob(state),
      rssi: -52,
    );
    if (!config.continuousScan) {
      return config.advertiseNothing
          ? const Stream<BleAdvertisement>.empty()
          : Stream<BleAdvertisement>.fromIterable([adv]);
    }
    // Like the real plugin: keep re-reporting, and never end on our own.
    final ctl = StreamController<BleAdvertisement>();
    _scanCtl = ctl;
    ctl.onListen = () {
      scanTick = () {
        if (!ctl.isClosed) {
          ctl.add(adv);
        }
      };
      if (!config.advertiseNothing) {
        scanTick!();
      }
    };
    ctl.onCancel = () async {
      scanTick = null;
      if (!ctl.isClosed) {
        await ctl.close();
      }
    };
    return ctl.stream;
  }

  StreamController<BleAdvertisement>? _scanCtl;

  /// Test hook (continuousScan only): push another advertisement, as a
  /// real scanner keeps doing while the user is somewhere else entirely.
  void Function()? scanTick;

  @override
  Future<void> stopScan() async {
    scanTick = null;
    final ctl = _scanCtl;
    _scanCtl = null;
    if (ctl != null && !ctl.isClosed) {
      await ctl.close();
    }
  }

  // ── connection and bonding ─────────────────────────────────────────

  @override
  BleConnectionState get connectionState => _conn;

  @override
  Stream<BleConnectionState> get connectionStates => _connCtl.stream;

  @override
  Future<void> connect(String deviceId) async {
    if (_disposed) {
      throw const BleStateException('connect() after dispose()');
    }
    if (_conn == BleConnectionState.connected) {
      throw const BleStateException('already connected');
    }
    _setConn(BleConnectionState.connecting);
    _setConn(BleConnectionState.connected);
    _mtu = 23; // every link starts at the default until negotiated
  }

  @override
  Future<void> disconnect() async {
    if (_conn == BleConnectionState.disconnected) {
      return;
    }
    _setConn(BleConnectionState.disconnected);
    _mtu = 23;
  }

  @override
  BleBondState get bondState => _bond;

  @override
  Stream<BleBondState> get bondStates => _bondCtl.stream;

  @override
  Future<void> bond() async {
    if (_conn != BleConnectionState.connected) {
      throw const BleStateException('bond() while disconnected');
    }
    _setBond(BleBondState.bonding);
    if (config.rejectBond) {
      _setBond(BleBondState.failed);
      throw const BleBondRejectedException();
    }
    // The OS owns the passkey dialog; the user reads the six digits off
    // the bridge's OLED and types them there (A6 epic flag).
    _setBond(BleBondState.bonded);
  }

  /// How many times the client healed a stale bond (A24.11), for assertions.
  int removeBondCalls = 0;

  /// After a heal, the fresh pairing gets REAL keys — the stale-bond
  /// condition is gone. Modelled as a cleared flag consulted alongside
  /// [FakePeripheralConfig.staleBond].
  bool _staleBondCleared = false;

  @override
  Future<void> removeBond() async {
    removeBondCalls++;
    if (config.refuseRemoveBond) {
      throw const BleStateException('platform refused removeBond');
    }
    _staleBondCleared = true;
    _setBond(BleBondState.none);
  }

  @override
  Future<int> requestMtu(int mtu) async {
    _requireConnected();
    // A refusal is a legitimate answer, not an error: the peer keeps 23.
    _mtu = config.negotiatedMtu.clamp(23, mtu);
    return _mtu;
  }

  @override
  int get mtu => _mtu;

  /// The link's own RSSI, which needs a link — reading it while
  /// disconnected must fail the same way every other op does.
  @override
  Future<int> readRssi() async {
    _requireConnected();
    return config.rssi;
  }

  // ── attribute access ───────────────────────────────────────────────

  void _requireConnected() {
    if (_conn != BleConnectionState.connected) {
      throw const BleConnectionLostException();
    }
  }

  /// ble-gatt §3, enforced rather than assumed — the fake is the only
  /// place the client's security expectations get tested before a board.
  void _requireSecurity(int slot) {
    _requireConnected();
    if (slot == BridgeChar.deviceInfo) {
      return; // open: identify a bridge before bonding
    }
    if (config.staleBond &&
        !_staleBondCleared &&
        _bond == BleBondState.bonded) {
      // We think we are bonded; the peer disagrees. This is what a
      // factory-reset bridge does, and it must be distinguishable.
      throw const BleRebondRequiredException();
    }
    if (_bond != BleBondState.bonded) {
      throw const BleNotBondedException();
    }
  }

  @override
  Future<Uint8List> read(int slot) async {
    _requireSecurity(slot);
    switch (slot) {
      case BridgeChar.deviceInfo:
        return state.info().encode();
      case BridgeChar.netStatus:
        return state.net.pack();
      case BridgeChar.liveState:
        return state.live().encode();
      case BridgeChar.historyPreview:
        return state.preview().pack();
      default:
        throw const BleStateException('characteristic is not readable');
    }
  }

  @override
  Future<void> write(int slot, Uint8List value) async {
    _requireSecurity(slot);
    if (config.dropOnWrite) {
      _setConn(BleConnectionState.disconnected);
      throw const BleConnectionLostException();
    }
    writes.add((slot, value));
    switch (slot) {
      case BridgeChar.wifiScanCtrl:
        await _onScanCtrl(value);
      case BridgeChar.wifiConfig:
        await _onWifiConfig(value);
      case BridgeChar.deviceControl:
        await _onDeviceControl(value);
      case BridgeChar.historyCtrl:
        await _onHistoryCtrl(value);
      default:
        throw const BleStateException('characteristic is not writable');
    }
  }

  @override
  Stream<Uint8List> subscribe(int slot) {
    _requireSecurity(slot);
    return _ctl(slot).stream;
  }

  StreamController<Uint8List> _ctl(int slot) =>
      _notifCtls.putIfAbsent(slot, () => StreamController.broadcast());

  /// THE thing the fake exists to exercise: ATT cannot fragment a
  /// notification, so anything longer than `MTU − 3` goes out as
  /// consecutive chunks and the client concatenates (ble-gatt §4).
  void notify(int slot, Uint8List payload) {
    final ctl = _notifCtls[slot];
    if (ctl == null || !ctl.hasListener) {
      return;
    }
    final chunk = _mtu - 3;
    for (var off = 0; off < payload.length; off += chunk) {
      final end = (off + chunk).clamp(0, payload.length);
      ctl.add(Uint8List.fromList(payload.sublist(off, end)));
    }
  }

  // ── write handlers, on the generated codecs ────────────────────────

  Future<void> _onScanCtrl(Uint8List value) async {
    final ctrl = WifiScanCtrl.decode(value);
    if (ctrl.cmdEnum == ScanCmd.cancel) {
      notify(BridgeChar.result, _result(0, ResultStatus.ok));
      return;
    }
    notify(BridgeChar.result, _result(0, ResultStatus.ok));
    final aps = config.emptyScan ? <WifiScanResult>[] : config.scanResults;
    for (var i = 0; i < aps.length; i++) {
      final ap = aps[i];
      notify(
        BridgeChar.wifiScanResult,
        WifiScanResult(
          index: i,
          total: aps.length,
          rssi: ap.rssi,
          auth: ap.auth,
          channel: ap.channel,
          ssidRaw: ap.ssidRaw,
        ).pack(),
      );
    }
  }

  Future<void> _onWifiConfig(Uint8List value) async {
    final cfg = WifiConfig.unpack(value);
    final toAp = cfg.mode == NetMode.ap.wire;
    // detail carries the AP PSK on a mode change to AP — the phone needs
    // it to join. No stored STA credential is ever emitted (§5.9).
    notify(
      BridgeChar.result,
      _result(
        0,
        config.wifiConfigOutcome,
        detail: toAp && config.wifiConfigOutcome == ResultStatus.ok
            ? state.apPsk
            : '',
      ),
    );
    if (config.wifiConfigOutcome != ResultStatus.ok ||
        config.silentAfterConfig) {
      return;
    }
    // Then the transition frames the wizard watches across the handoff.
    final script = config.netStatusScript.isNotEmpty
        ? config.netStatusScript
        : [
            NetStatus(
              mode: cfg.mode,
              state: NetState.connecting.wire,
              ssidRaw: cfg.ssidRaw,
              hostRaw: Uint8List.fromList(utf8.encode('smokebridge')),
            ),
            NetStatus(
              mode: cfg.mode,
              state: NetState.up.wire,
              ip: toAp ? [192, 168, 4, 1] : [192, 168, 1, 42],
              ssidRaw: cfg.ssidRaw,
              hostRaw: Uint8List.fromList(utf8.encode('smokebridge')),
            ),
          ];
    for (final s in script) {
      state.net = s;
      notify(BridgeChar.netStatus, s.pack());
    }
  }

  Future<void> _onDeviceControl(Uint8List value) async {
    final ctrl = DeviceControl.unpack(value);
    final op = ctrl.opEnum;
    if (op == null) {
      // Unknown ops answer invalid with no side effects (§5.9).
      notify(BridgeChar.result, _result(ctrl.op, ResultStatus.invalid));
      return;
    }
    var status = ResultStatus.ok;
    switch (op) {
      case ControlOp.sessionStart:
        if (state.sessionActive) {
          status = ResultStatus.busy;
        } else {
          state.sessionActive = true;
        }
      case ControlOp.sessionStop:
        if (!state.sessionActive) {
          status = ResultStatus.invalid;
        } else {
          state.sessionActive = false;
        }
      case ControlOp.mark:
        if (!state.sessionActive) {
          status = ResultStatus.invalid;
        }
      default:
        break;
    }
    notify(BridgeChar.result, _result(ctrl.op, status));
  }

  // ── v1.1: full history over BLE (§5.10–§5.11) ──────────────────────
  //
  // Framed exactly as the firmware frames it — whole items only, the
  // largest number that fits 237 B, one seq chain across the whole
  // response including the terminator. A client that passes against this
  // and fails against the board means the two disagree about the CONTRACT,
  // which is the divergence this fake exists to catch early.

  static const _payloadMax = 237;

  /// Frames emitted for the last request, for assertion.
  int historyFramesSent = 0;

  Future<void> _onHistoryCtrl(Uint8List value) async {
    final req = HistoryCtrl.decode(value);
    var seq = 0;
    historyFramesSent = 0;

    void send(HistoryKind kind, int count, List<int> payload, {bool last = false}) {
      final index = historyFramesSent;
      historyFramesSent++;
      // A dropped frame still burns its seq — that gap is the only trace
      // it leaves, and the whole reason seq is on the wire.
      final skip = config.historyDropFrame == index;
      final frame = HistoryData(
        kind: kind.wire,
        seq: seq++,
        flags: last ? 0x01 : 0,
        count: count,
        payloadRaw: Uint8List.fromList(payload),
      );
      if (!skip) {
        notify(BridgeChar.historyData, frame.pack());
      }
    }

    void end(ResultStatus status) =>
        send(HistoryKind.end, 0, [status.wire], last: true);

    if (config.historyBusy) {
      // Rides seq 0xFFFF so it cannot be mistaken for a frame of the
      // stream already in flight.
      notify(
        BridgeChar.historyData,
        HistoryData(
          kind: HistoryKind.end.wire,
          seq: 0xFFFF,
          flags: 0x01,
          payloadRaw: Uint8List.fromList([ResultStatus.busy.wire]),
        ).pack(),
      );
      return;
    }

    /// Packs `items` into frames of at most `perFrame` whole items.
    void stream(HistoryKind kind, List<Uint8List> items, int itemSize) {
      final perFrame = _payloadMax ~/ itemSize;
      for (var i = 0; i < items.length; i += perFrame) {
        final slice = items.sublist(
          i,
          (i + perFrame).clamp(0, items.length),
        );
        send(kind, slice.length, [for (final it in slice) ...it]);
      }
    }

    switch (req.reqEnum) {
      case HistoryReq.cancel:
        end(ResultStatus.ok);
      case HistoryReq.sessions:
        stream(
          HistoryKind.session,
          [for (final h in state.cookHeaders.values) h.encode()],
          HistorySession.size,
        );
        end(config.historyStatus);
      case HistoryReq.samples:
        final recs = state.cooks[req.sessionId];
        if (recs == null) {
          end(ResultStatus.invalid);
          return;
        }
        final stride = req.stride == 0 ? 1 : req.stride;
        final wanted = <Uint8List>[];
        for (var i = 0; i < recs.length; i += stride) {
          final r = recs[i];
          if (r.t < req.fromT || r.t > req.toT) {
            continue;
          }
          wanted.add(r.encode());
        }
        stream(HistoryKind.samples, wanted, SampleRec.size);
        end(config.historyStatus);
      case HistoryReq.marks:
        final marks = state.cookMarks[req.sessionId];
        if (marks == null) {
          end(ResultStatus.invalid);
          return;
        }
        stream(
          HistoryKind.marks,
          [
            for (final m in marks)
              if (m.t >= req.fromT && m.t <= req.toT) m.encode(),
          ],
          MarkRec.size,
        );
        end(config.historyStatus);
      case null:
        end(ResultStatus.invalid);
    }
  }

  Uint8List _result(int opEcho, ResultStatus status, {String detail = ''}) =>
      ResultFrame(
        opEcho: opEcho,
        status: status.wire,
        detailRaw: Uint8List.fromList(utf8.encode(detail)),
      ).pack();

  // ── plumbing ───────────────────────────────────────────────────────

  void _setConn(BleConnectionState s) {
    _conn = s;
    _connCtl.add(s);
  }

  void _setBond(BleBondState s) {
    _bond = s;
    _bondCtl.add(s);
  }

  /// Test hook: the link drops from the peer's side.
  void dropLink() => _setConn(BleConnectionState.disconnected);

  /// Test hook: push a live_state notification at the sample cadence.
  void pushSample({int? pitTempF10}) {
    if (pitTempF10 != null) {
      state.pitTempF10 = pitTempF10;
    }
    notify(BridgeChar.liveState, state.live().encode());
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _connCtl.close();
    await _bondCtl.close();
    for (final c in _notifCtls.values) {
      await c.close();
    }
  }
}
