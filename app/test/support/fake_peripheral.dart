/// A fake bridge peripheral, in Dart, on the generated codecs.
///
/// This is to the BLE transport what `tools/sim` is to the HTTP API: the thing
/// that makes the layer board-free. It advertises the §2 blob, walks the bond
/// state machine, enforces the §3 security levels, serves the characteristics
/// this app uses, and is configurable for the failure modes that actually
/// happen — MTU negotiation refused, notifications split at `MTU − 3`, a bond
/// rejected, a connection dropped mid-write, a stale bond, and a dropped
/// history frame.
///
/// It must not invent a wire format. Every byte it emits comes from
/// `records.g.dart`, the same generator the firmware's `record_gen.h` comes
/// from, so a divergence is a red test rather than a bridge that will not talk.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:smoke_bridge/data/ble/ble_gatt.dart';
import 'package:smoke_bridge/data/ble/bridge_transport.dart';
import 'package:smoke_bridge/data/dto/records.g.dart';

/// How the fake should misbehave. Every field here is a real thing a real phone
/// has done to a real peripheral.
class FakePeripheralConfig {
  const FakePeripheralConfig({
    this.negotiatedMtu = 247,
    this.rejectBond = false,
    this.dropOnWrite = false,
    this.staleBond = false,
    this.refuseRemoveBond = false,
    this.emptyScan = false,
    this.advertiseMalformed = false,
    this.advertiseNothing = false,
    this.continuousScan = false,
    this.rssi = -58,
    this.historyStatus = ResultStatus.ok,
    this.historyDropFrame,
    this.historyBusy = false,
  });

  /// The status the end frame reports (§5.11). Anything but `ok` must surface
  /// as a typed failure rather than a short cook.
  final ResultStatus historyStatus;

  /// Drop the frame at this index, keeping the seq chain's gap visible.
  final int? historyDropFrame;

  /// A stream is already running: answer `busy` on seq 0xFFFF without
  /// disturbing it (§5.10).
  final bool historyBusy;

  /// 23 is the value to fear: it is what a failed negotiation leaves, and the
  /// one `live_state` was designed at 16 B to survive.
  final int negotiatedMtu;
  final int rssi;
  final bool rejectBond;
  final bool dropOnWrite;
  final bool staleBond;
  final bool refuseRemoveBond;
  final bool emptyScan;
  final bool advertiseMalformed;
  final bool advertiseNothing;
  final bool continuousScan;

  FakePeripheralConfig copyWith({
    int? negotiatedMtu,
    bool? rejectBond,
    bool? dropOnWrite,
    bool? staleBond,
    bool? emptyScan,
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
    emptyScan: emptyScan ?? this.emptyScan,
    advertiseMalformed: advertiseMalformed ?? this.advertiseMalformed,
    advertiseNothing: advertiseNothing ?? this.advertiseNothing,
    continuousScan: continuousScan ?? this.continuousScan,
  );
}

/// The device's own state, so the fake answers questions consistently rather
/// than replaying canned bytes.
class FakeBridgeState {
  FakeBridgeState({
    this.deviceId = 'A4F2',
    this.model = 'heltec-v3',
    this.fw = '1.0.0',
    this.probes = 4,
    // wifi_ap | wifi_sta | history_preview | history_full. `battery` stays
    // clear until the firmware reports SoC, which is why socPct is socUnknown.
    this.caps = 0x4B,
    this.paired = true,
    this.sessionActive = true,
    this.pitTempF10 = 2431,
    this.sessionSeconds = 15120,
    this.admin = false,
    this.displayTimeoutS = 60,
    this.ledEnabled = 1,
    this.buzzerEnabled = 1,
    this.retentionMaxSessions = 64,
    this.retentionMinFreePct = 10,
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

  /// v1.2 admin surface: caps b7 + the device_stats / device_config reads.
  bool admin;
  int displayTimeoutS;
  int ledEnabled;
  int buzzerEnabled;
  int retentionMaxSessions;
  int retentionMinFreePct;

  /// Probe labels/roles(wire)/targets, index 0..3.
  final List<String> probeNames = ['', '', '', ''];
  final List<int> probeRoles = [0, 0, 0, 0];
  final List<int> probeTargets = [0, 0, 0, 0];

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
    caps: admin ? (caps | 0x80) : (caps & ~0x80),
    idRaw: utf8ToPadded(deviceId, 4),
    modelRaw: utf8ToPadded(model, 16),
    fwRaw: utf8ToPadded(fw, 16),
  );

  DeviceStats stats() => DeviceStats(
    flags: (paired ? 1 << 0 : 0) | (1 << 1) | (1 << 2) | (1 << 3),
    uptimeS: 1234,
    heapFree: 100000,
    heapMin: 90000,
    storageUsedB: 12 * 1024,
    storageTotalB: 2944 * 1024,
    storedSessions: 3,
    loraFreqHz: 918500000,
    loraRssi: -71,
    loraSnr: 7,
    packetsOk: 500,
    packetsBad: 4,
    bonds: 1,
  );

  DeviceConfig config() => DeviceConfig(
    displayTimeoutS: displayTimeoutS,
    ledEnabled: ledEnabled,
    buzzerEnabled: buzzerEnabled,
    retentionMaxSessions: retentionMaxSessions,
    retentionMinFreePct: retentionMinFreePct,
    probeNameRaw: Uint8List.fromList([
      for (final n in probeNames) ...utf8ToPadded(n, 17),
    ]),
    probeRole: List<int>.of(probeRoles),
    probeTarget: List<int>.of(probeTargets),
  );

  /// Session id → the records the bridge holds, in `t` order.
  final Map<int, List<SampleRec>> cooks = {};
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
          // Probe 3 detached throughout: the sentinel has to survive the whole
          // transfer and arrive as null, never as 0 °F.
          temp: [2000 + (i % 400), 1600, tempDetached, 900],
          rssi: -70,
        ),
    ];
    cookHeaders[id] = HistorySession(
      sessionId: id,
      startedUnixMs: startedUnixMs,
      endedUnixMs: closed ? startedUnixMs + hours * 3600 * 1000 : 0,
      sampleCount: n,
      samplePeriodS: 30,
      numProbes: 4,
      flags: 0x01 | (closed ? 0x02 : 0),
      nameRaw: utf8ToPadded(name, 28),
    );
    return id;
  }
}

/// The §2.3 manufacturer status blob, built the same way the firmware builds it
/// so the two cannot disagree.
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

  /// The elapsed time the fake's OLED is currently showing, or null. Kept so a
  /// test can prove the app declared (and re-declared) the cook clock, which
  /// has no BLE read-back.
  int? cookClockElapsedS;

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

  /// Test hook (continuousScan only): push another advertisement.
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
    _setBond(BleBondState.bonded);
  }

  int removeBondCalls = 0;
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
    _mtu = config.negotiatedMtu.clamp(23, mtu);
    return _mtu;
  }

  @override
  int get mtu => _mtu;

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

  void _requireSecurity(int slot) {
    _requireConnected();
    if (slot == BridgeChar.deviceInfo) {
      return; // open: identify a bridge before bonding
    }
    if (config.staleBond &&
        !_staleBondCleared &&
        _bond == BleBondState.bonded) {
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
      case BridgeChar.liveState:
        return state.live().encode();
      case BridgeChar.deviceStats when state.admin:
        return state.stats().encode();
      case BridgeChar.deviceConfig when state.admin:
        return state.config().encode();
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

  /// The thing the fake exists to exercise: ATT cannot fragment a notification,
  /// so anything longer than `MTU − 3` goes out as consecutive chunks and the
  /// client concatenates (ble-gatt §4).
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

  Future<void> _onDeviceControl(Uint8List value) async {
    final ctrl = DeviceControl.unpack(value);
    final op = ctrl.opEnum;
    if (op == null) {
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
      case ControlOp.pair:
        state.paired = true;
      case ControlOp.unpair:
        state.paired = false;
      case ControlOp.setCookClock:
        final body = CtrlSetCookClock.decode(ctrl.bodyRaw);
        if (body.elapsedS > cookClockMaxS) {
          // The device refuses an age wider than its OLED (`ble-gatt.md` §5.6.8).
          status = ResultStatus.invalid;
        } else {
          cookClockElapsedS = body.elapsedS;
        }
      case ControlOp.clearCookClock:
        cookClockElapsedS = null;
      case ControlOp.setProbe:
        final body = CtrlSetProbe.decode(ctrl.bodyRaw);
        if (body.index < 4) {
          state.probeNames[body.index] = body.name;
          state.probeRoles[body.index] = body.role;
          state.probeTargets[body.index] = body.targetF10;
        }
      case ControlOp.setDevicePrefs:
        final body = CtrlSetDevicePrefs.decode(ctrl.bodyRaw);
        state.displayTimeoutS = body.displayTimeoutS;
        state.ledEnabled = body.ledEnabled;
        state.buzzerEnabled = body.buzzerEnabled;
        state.retentionMaxSessions = body.retentionMaxSessions;
        state.retentionMinFreePct = body.retentionMinFreePct;
      default:
        break;
    }
    notify(BridgeChar.result, _result(ctrl.op, status));
  }

  // ── full history over BLE (§5.10–§5.11) ─────────────────────────────
  //
  // Framed exactly as the firmware frames it — whole items only, the largest
  // number that fits 237 B, one seq chain across the whole response including
  // the terminator.

  static const _payloadMax = 237;

  /// Frames emitted for the last request, for assertion.
  int historyFramesSent = 0;

  /// Every `history_ctrl` request the client has made, across all requests.
  /// Lets a test prove a bounded sync issues no BLE round trips.
  int historyRequests = 0;

  Future<void> _onHistoryCtrl(Uint8List value) async {
    final req = HistoryCtrl.decode(value);
    historyRequests++;
    var seq = 0;
    historyFramesSent = 0;

    void send(
      HistoryKind kind,
      int count,
      List<int> payload, {
      bool last = false,
    }) {
      final index = historyFramesSent;
      historyFramesSent++;
      // A dropped frame still burns its seq — that gap is the only trace it
      // leaves, and the whole reason seq is on the wire.
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

    void stream(HistoryKind kind, List<Uint8List> items, int itemSize) {
      final perFrame = _payloadMax ~/ itemSize;
      for (var i = 0; i < items.length; i += perFrame) {
        final slice = items.sublist(i, (i + perFrame).clamp(0, items.length));
        send(kind, slice.length, [for (final it in slice) ...it]);
      }
    }

    switch (req.reqEnum) {
      case HistoryReq.cancel:
        end(ResultStatus.ok);
      case HistoryReq.sessions:
        stream(HistoryKind.session, [
          for (final h in state.cookHeaders.values) h.encode(),
        ], HistorySession.size);
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
        end(ResultStatus.ok);
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
