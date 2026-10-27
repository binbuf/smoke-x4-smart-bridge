import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:smoke_bridge/data/ble/ble_client.dart';

import 'codecs.dart';
import 'fake_gatt_server.dart';

/// In-memory bridge GATT server used by app tests.
///
/// Every payload is built and parsed with the generated codecs from T02, so a
/// protocol change breaks these tests instead of silently passing against
/// hand-written byte offsets.
class FakeBridge implements FakeGattServer {
  FakeBridge({
    this.deviceId = 'A4F2',
    this.model = 'heltec3',
    this.firmware = '0.1.0',
    this.bondsFree = 3,
    this.protoMajor = protocolMajor,
    this.batteryPct = 87,
    this.rssiLora = -71,
    this.ageS = 12,
    this.seq = 1234,
    List<int>? tempsF10,
    int? billowsTargetF10,
    Config? initialConfig,
    List<SampleRec>? initialRecords,
    this.generation = 0xA1B2C3D4,
    this.uptimeS = 4021,
    this.packetsOk = 420,
    this.packetsBad = 3,
    this.clockValid = true,
    this.billowsAttached = true,
    this.dropControlResults = false,
    this.forcedControlStatus,
    int mtu = bleMtuDefault,
  }) : _tempsF10 = List<int>.from(
         tempsF10 ?? const <int>[2250, 1652, tempDetached, 800],
       ),
       _billowsTargetF10 = billowsTargetF10 ?? 2250,
       _config =
           initialConfig ??
           Config(
             units: 1,
             displayTimeoutS: 60,
             deviceName: 'Backyard Bridge',
             billowsTargetF10: 2250,
             billowsMode: 0,
           ),
       _records = List<SampleRec>.from(initialRecords ?? _defaultRecords()),
       _mtu = mtu < bleMtuDefault ? bleMtuDefault : mtu;

  final String deviceId;
  final String model;
  final String firmware;
  final int bondsFree;
  final int protoMajor;

  int batteryPct;
  int rssiLora;
  int ageS;
  int seq;

  /// `live.clock_valid`. A bridge that lost power reports false, which forces
  /// `set_time` on the next connect.
  bool clockValid;
  bool billowsAttached;

  /// Scripts a `result` that never arrives, to prove the 3 s control timeout.
  bool dropControlResults;

  /// Overrides the status of every control result when set.
  ResultStatus? forcedControlStatus;

  final List<Control> controlWrites = <Control>[];
  final List<Uint8List> controlBodies = <Uint8List>[];
  final List<SyncCtrl> syncRequests = <SyncCtrl>[];

  final List<int> _tempsF10;
  int _billowsTargetF10;
  Config _config;
  final List<SampleRec> _records;
  final int generation;
  final int uptimeS;
  final int packetsOk;
  final int packetsBad;
  int _mtu;

  final Map<String, StreamController<Uint8List>> _notificationControllers =
      <String, StreamController<Uint8List>>{};

  /// The live payload currently readable on `0002 live`.
  Live get live => Live(
    flags:
        liveFlagSmokePaired |
        liveFlagSmokeLive |
        (billowsAttached ? liveFlagBillowsAttached : 0) |
        (clockValid ? liveFlagClockValid : 0) |
        liveFlagStorageOk |
        liveFlagDisplayOn,
    temp: _tempsF10,
    seq: seq,
    billowsTargetF10: _billowsTargetF10,
    batteryPct: batteryPct,
    rssiLora: rssiLora,
    ageS: ageS,
  );

  Config get config => _config;

  List<SampleRec> get records => List<SampleRec>.unmodifiable(_records);

  /// Appends one bridge-side record for reconnect/forward-sync tests.
  void addRecord({
    required int seq,
    required int unixS,
    List<int>? tempsF10,
    int flags =
        recordFlagProbe1Attached |
        recordFlagProbe2Attached |
        recordFlagProbe4Attached |
        recordFlagClockValid,
  }) {
    _records.add(
      SampleRec(
        seq: seq,
        unixS: unixS,
        temp: tempsF10 ?? const <int>[2250, 1652, tempDetached, 800],
        flags: flags,
      ),
    );
    _records.sort((a, b) => a.seq.compareTo(b.seq));
  }

  Info get info => Info(
    protoMajor: protoMajor,
    protoMinor: protocolMinor,
    caps:
        capsFlagBillowsObserve |
        capsFlagHistory |
        capsFlagBattery |
        capsFlagDisplayConfig |
        capsFlagPowerOff |
        capsFlagFactoryReset |
        capsFlagConfig,
    probes: 4,
    deviceId: deviceId,
    fw: firmware,
    model: model,
    bondsFree: bondsFree,
  );

  Stats get stats {
    final hasRecords = _records.isNotEmpty;
    final minSeq = hasRecords
        ? _records.map((record) => record.seq).reduce(math.min)
        : seqNone;
    final maxSeq = hasRecords
        ? _records.map((record) => record.seq).reduce(math.max)
        : seqNone;
    return Stats(
      flags:
          statsFlagSmokePaired |
          statsFlagSmokeLive |
          statsFlagConnected |
          statsFlagClockValid |
          statsFlagStorageOk |
          statsFlagBillowsAttached,
      uptimeS: uptimeS,
      recordsStored: _records.length,
      recordsCapacity: recordCapacity,
      minSeq: minSeq,
      maxSeq: maxSeq,
      generation: generation,
      packetsOk: packetsOk,
      packetsBad: packetsBad,
      batteryMv: 4020,
      batteryPct: batteryPct,
      loraRssi: rssiLora,
      loraSnr: 8,
      heapFree: 148000,
      heapMin: 96000,
      droppedSamples: 0,
      oldestUnixS: hasRecords ? _records.first.unixS : 0,
      newestUnixS: hasRecords ? _records.last.unixS : 0,
    );
  }

  /// The scan-response advertisement for this bridge, built with [AdvStatus].
  BleDevice advertisement({
    String? name,
    int rssi = -60,
    String? id,
    int? flags,
    int? pitTempF10,
    int? battery,
    int? targetF10,
    int? age,
  }) {
    final status = AdvStatus(
      flags:
          flags ??
          liveFlagSmokePaired |
              liveFlagSmokeLive |
              liveFlagBillowsAttached |
              liveFlagClockValid |
              liveFlagStorageOk |
              liveFlagDisplayOn,
      pitTempF10: pitTempF10 ?? _tempsF10[3],
      batteryPct: battery ?? batteryPct,
      billowsTargetF10: targetF10 ?? _billowsTargetF10,
      ageS: age ?? ageS,
    ).encode();
    final manufacturerData = Uint8List(2 + status.length);
    ByteData.sublistView(manufacturerData)
        .setUint16(0, bleCompanyId, Endian.little);
    manufacturerData.setRange(2, manufacturerData.length, status);
    return BleDevice(
      id: id ?? 'fake-$deviceId',
      name: name ?? '$bleLocalNamePrefix$deviceId',
      rssi: rssi,
      manufacturerData: manufacturerData,
      serviceUuids: const <String>[bleServiceUuid],
    );
  }

  /// Publishes one live sample and stores it for a subsequent read. Tests call
  /// this after enabling notifications on `0002 live`.
  Live publishLive({
    int? seq,
    List<int>? tempsF10,
    int? flags,
    int? billowsTargetF10,
    int? batteryPct,
    int? rssiLora,
    int? ageS,
  }) {
    if (seq != null) this.seq = seq;
    if (tempsF10 != null) {
      _tempsF10
        ..clear()
        ..addAll(tempsF10);
    }
    if (billowsTargetF10 != null) _billowsTargetF10 = billowsTargetF10;
    if (batteryPct != null) this.batteryPct = batteryPct;
    if (rssiLora != null) this.rssiLora = rssiLora;
    if (ageS != null) this.ageS = ageS;
    final value = live;
    _notify(_uuid('live'), value.encode());
    return value;
  }

  @override
  void setMtu(int mtu) {
    _mtu = mtu < bleMtuDefault ? bleMtuDefault : mtu;
  }

  @override
  Stream<Uint8List> notificationsFor(String characteristicUuid) {
    return _controller(characteristicUuid).stream;
  }

  @override
  Future<Uint8List> read(String characteristicUuid) async {
    final uuid = characteristicUuid.toLowerCase();
    if (uuid == _uuid('info')) return info.encode();
    if (uuid == _uuid('live')) return live.encode();
    if (uuid == _uuid('config')) return _config.encode();
    if (uuid == _uuid('stats')) return stats.encode();
    throw BleException(
      BleFailure.unknownCharacteristic,
      'fake bridge cannot read $characteristicUuid',
    );
  }

  @override
  Future<void> write(String characteristicUuid, Uint8List value) async {
    final uuid = characteristicUuid.toLowerCase();
    if (uuid == _uuid('config')) {
      _writeConfig(value);
      return;
    }
    if (uuid == _uuid('control')) {
      await _writeControl(value);
      return;
    }
    if (uuid == _uuid('sync_ctrl')) {
      await _writeSyncCtrl(value);
      return;
    }
    throw BleException(
      BleFailure.unsupported,
      'fake bridge cannot write $characteristicUuid',
    );
  }

  void _writeConfig(Uint8List value) {
    final next = Config.decode(value);
    if (next.units != 0 && next.units != 1) {
      throw const BleException(BleFailure.invalidValue, 'bad units');
    }
    if (next.displayTimeoutS != 0 &&
        next.displayTimeoutS != 30 &&
        next.displayTimeoutS != 60 &&
        next.displayTimeoutS != 120) {
      throw const BleException(BleFailure.invalidValue, 'bad display timeout');
    }
    if (next.billowsMode != 0) {
      throw const BleException(
        BleFailure.unsupported,
        'Billows is observation-only in the MVP',
      );
    }
    _config = Config(
      units: next.units,
      displayTimeoutS: next.displayTimeoutS,
      deviceName: next.deviceName,
      billowsTargetF10: _billowsTargetF10,
      billowsMode: 0,
    );
  }

  Future<void> _writeControl(Uint8List value) async {
    final control = Control.decode(value);
    final body = Uint8List.sublistView(value, Control.size);
    controlWrites.add(control);
    controlBodies.add(body);
    var status = forcedControlStatus ?? ResultStatus.ok;
    final op = ControlOp.fromWire(control.op);
    if (op == ControlOp.setTime && body.length < ControlSetTimeBody.size) {
      status = ResultStatus.invalid;
    } else if (op == ControlOp.setBillowsTarget || op == null) {
      status = ResultStatus.unsupported;
    } else if (op == ControlOp.setTime) {
      ControlSetTimeBody.decode(body);
    }
    if (dropControlResults) return;
    final result = Result(
      op: control.op,
      opId: control.opId,
      status: status.wire,
    );
    _notify(_uuid('result'), result.encode());
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> _writeSyncCtrl(Uint8List value) async {
    final ctrl = SyncCtrl.decode(value);
    syncRequests.add(ctrl);
    final cmd = SyncCmd.fromWire(ctrl.cmd);
    if (cmd == null) {
      throw const BleException(BleFailure.invalidValue, 'bad sync command');
    }
    if (cmd == SyncCmd.cancel) return;
    if (cmd == SyncCmd.status) {
      await _emitSync(ctrl, statusOnly: true);
      return;
    }
    await _emitSync(ctrl);
  }

  Future<void> _emitSync(SyncCtrl ctrl, {bool statusOnly = false}) async {
    final direction = SyncDirection.fromWire(ctrl.direction);
    final backwards = direction == SyncDirection.backward;
    final limit = ctrl.maxRecords == 0
        ? bleSyncDefaultRecords
        : ctrl.maxRecords.clamp(1, bleSyncMaxRecords);

    var selected = statusOnly
        ? <SampleRec>[]
        : _records
              .where(
                (record) => backwards
                    ? record.seq < ctrl.cursorSeq
                    : record.seq >= ctrl.cursorSeq,
              )
              .toList();
    if (backwards) {
      selected = selected.reversed.take(limit).toList().reversed.toList();
    } else {
      selected = selected.take(limit).toList();
    }

    final hasRecords = _records.isNotEmpty;
    final minSeq = hasRecords
        ? _records.map((record) => record.seq).reduce(math.min)
        : seqNone;
    final maxSeq = hasRecords
        ? _records.map((record) => record.seq).reduce(math.max)
        : seqNone;
    final nextSeq = selected.isEmpty ? ctrl.cursorSeq : selected.last.seq + 1;

    final bytes = BytesBuilder(copy: false)
      ..add(
        SyncStart(
          generation: generation,
          minSeq: minSeq,
          maxSeq: maxSeq,
          startSeq: selected.isEmpty ? nextSeq : selected.first.seq,
          count: selected.length,
          status: selected.isEmpty ? SyncStatus.empty.wire : SyncStatus.ok.wire,
        ).encode(),
      );
    for (final record in selected) {
      bytes.add(record.encode());
    }
    bytes.add(
      SyncEnd(
        status: selected.isEmpty ? SyncStatus.empty.wire : SyncStatus.ok.wire,
        nextSeq: nextSeq,
        minSeq: minSeq,
        maxSeq: maxSeq,
      ).encode(),
    );

    for (final frame in _frameStream(bytes.toBytes())) {
      _notify(_uuid('sync_data'), frame);
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Splits the logical sync stream into framed notifications. The first frame
  /// carries START and the last carries END, as the app reassembles them.
  List<Uint8List> _frameStream(Uint8List stream) {
    final maxPayload = math.min(
      bleSyncFrameMaxPayload,
      _mtu - 3 - SyncFrame.size,
    );
    final frames = <Uint8List>[];
    var frameSeq = 0;
    for (var offset = 0; offset < stream.length; offset += maxPayload) {
      final end = math.min(offset + maxPayload, stream.length);
      final payload = Uint8List.sublistView(stream, offset, end);
      var flags = 0;
      if (offset == 0) flags |= syncFrameFlagStart;
      if (end == stream.length) flags |= syncFrameFlagEnd;
      final header = SyncFrame(
        frameSeq: frameSeq,
        flags: flags,
        len: payload.length,
      ).encode();
      final frame = Uint8List(header.length + payload.length)
        ..setRange(0, header.length, header)
        ..setRange(header.length, header.length + payload.length, payload);
      frames.add(frame);
      frameSeq = (frameSeq + 1) & 0xFF;
    }
    return frames;
  }

  void _notify(String uuid, Uint8List payload) {
    _notificationControllers[uuid.toLowerCase()]?.add(payload);
  }

  StreamController<Uint8List> _controller(String uuid) {
    return _notificationControllers.putIfAbsent(
      uuid.toLowerCase(),
      () => StreamController<Uint8List>.broadcast(),
    );
  }

  String _uuid(String name) => bleCharacteristicByName(name).uuid.toLowerCase();

  @override
  Future<void> onDisconnected() async {}

  /// Releases the notification controllers created for a test.
  Future<void> dispose() async {
    for (final controller in _notificationControllers.values) {
      await controller.close();
    }
    _notificationControllers.clear();
  }

  static List<SampleRec> _defaultRecords() {
    const flags =
        recordFlagProbe1Attached |
        recordFlagProbe2Attached |
        recordFlagProbe4Attached |
        recordFlagBillowsAttached |
        recordFlagClockValid;
    return <SampleRec>[
      SampleRec(
        seq: 100,
        unixS: 1700000000,
        temp: const <int>[1652, 1640, tempDetached, 2250],
        flags: flags,
      ),
      SampleRec(
        seq: 101,
        unixS: 1700000030,
        temp: const <int>[1660, 1644, tempDetached, 2252],
        flags: flags,
      ),
      SampleRec(
        seq: 102,
        unixS: 1700000060,
        temp: const <int>[1658, 1648, tempDetached, 2250],
        flags: flags,
      ),
    ];
  }
}
