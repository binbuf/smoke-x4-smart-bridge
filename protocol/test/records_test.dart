// Host test for the generated Dart codecs. Runs with:
//   dart protocol/test/records_test.dart
//
// The `live` vector is the normative example in
// docs/design/05-ble-contract.md §5.4.

import 'dart:typed_data';

import '../gen/records.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

final Uint8List liveVector = Uint8List.fromList(<int>[
  0x01, 0x17, 0xCA, 0x08, 0x74, 0x06, 0x00, 0x80, 0x20, 0x03,
  0xD2, 0x04, 0x00, 0x00, 0xCA, 0x08, 0x57, 0xB9, 0x0C, 0x00,
]);

void testCrc16() {
  final data = Uint8List.fromList('123456789'.codeUnits);
  check(crc16CcittFalse(data) == 0x29B1, 'CRC-16/CCITT-FALSE check vector');
}

void testSeq24() {
  final b = Uint8List(3);
  seq24Write(b, 0, 0x123456);
  check(b[0] == 0x56 && b[1] == 0x34 && b[2] == 0x12, 'seq24 little-endian');
  check(seq24Read(b) == 0x123456, 'seq24 read');
  seq24Write(b, 0, 0xFFFFFF);
  check(seq24Read(b) == 0xFFFFFF, 'seq24 max');
  var threw = false;
  try {
    seq24Write(b, 0, 0x1000000);
  } on RangeError {
    threw = true;
  }
  check(threw, 'seq24 rejects 2^24');
}

void testLiveVector() {
  final live = Live.decode(liveVector);
  check(live.ver == 1, 'live.ver');
  check(live.flags == 0x17, 'live.flags');
  check(live.smokePaired, 'smoke_paired');
  check(live.smokeLive, 'smoke_live');
  check(live.billowsAttached, 'billows_attached');
  check(live.clockValid, 'clock_valid');
  check(!live.storageOk, 'storage_ok');
  check(live.temp[0] == 2250, 'p1 temperature');
  check(live.temp[1] == 1652, 'p2 temperature');
  check(live.temp[2] == tempDetached, 'p3 detached sentinel');
  check(live.tempOrNull(2) == null, 'detached must surface as null');
  check(live.temp[3] == 800, 'p4 temperature');
  check(live.seq == 1234, 'live.seq');
  check(live.billowsTargetF10 == 2250, 'billows target');
  check(live.batteryPct == 87, 'battery');
  check(live.rssiLora == -71, 'RSSI');
  check(live.ageS == 12, 'age');

  final encoded = live.encode();
  check(encoded.length == liveVector.length, 'live encode length');
  for (var i = 0; i < liveVector.length; i++) {
    check(encoded[i] == liveVector[i], 'live byte $i');
  }

  var threw = false;
  try {
    Live.decode(Uint8List.sublistView(liveVector, 1));
  } on RangeError {
    threw = true;
  }
  check(threw, 'short live payload rejected');
}

void testSampleRec() {
  final rec = SampleRec(
    seq: 0xABCDEF,
    unixS: 1720000000,
    temp: <int>[2250, 1652, tempDetached, tempInvalid],
    flags: recordFlagProbe1Attached |
        recordFlagProbe2Attached |
        recordFlagClockValid,
  );
  final wire = rec.encode();
  check(wire.length == SampleRec.size, 'record size');
  check(wire[0] == 0xEF && wire[1] == 0xCD && wire[2] == 0xAB, 'seq24 wire');
  check(wire.length == 18, 'record is 18 bytes');

  final decoded = SampleRec.decode(wire);
  check(decoded.seq == 0xABCDEF, 'record seq');
  check(decoded.unixS == 1720000000, 'record unix_s');
  check(decoded.temp[2] == tempDetached && decoded.temp[3] == tempInvalid,
      'record sentinels');
  check(decoded.flags == rec.flags, 'record flags');
  check(decoded.crcOk, 'record CRC');

  final corrupt = Uint8List.fromList(wire);
  corrupt[3] ^= 0x01;
  final corrupted = SampleRec.decode(corrupt);
  check(!corrupted.crcOk, 'corrupt record must fail CRC');
}

void testResultAndSync() {
  final result = Result(
    op: ControlOp.setTime.wire,
    opId: 9,
    status: ResultStatus.invalid.wire,
    detail: 'clock out of range',
  );
  final wire = result.encode();
  check(wire.length == 23, 'result length');
  check(wire[4] == 18, 'result detail length');
  final decoded = Result.decode(wire);
  check(decoded.op == ControlOp.setTime.wire, 'result op');
  check(decoded.opId == 9, 'result op_id');
  check(decoded.status == ResultStatus.invalid.wire, 'result status');
  check(decoded.detail == 'clock out of range', 'result detail');

  final ctrl = SyncCtrl(
    cmd: SyncCmd.read.wire,
    direction: SyncDirection.backward.wire,
    cursorSeq: 4000,
    maxRecords: 32,
  );
  final ctrlWire = ctrl.encode();
  check(ctrlWire.length == SyncCtrl.size, 'sync_ctrl size');
  final ctrl2 = SyncCtrl.decode(ctrlWire);
  check(ctrl2.cursorSeq == 4000, 'sync cursor');
  check(ctrl2.maxRecords == 32, 'sync max_records');

  final start = SyncStart(
    generation: 0xDEADBEEF,
    minSeq: 10,
    maxSeq: 20,
    startSeq: 15,
    count: 6,
    status: SyncStatus.ok.wire,
  );
  final startWire = start.encode();
  check(startWire.length == SyncStart.size, 'sync_start size');
  final start2 = SyncStart.decode(startWire);
  check(start2.generation == 0xDEADBEEF, 'sync generation');
  check(start2.recordSize == recordSize, 'sync record_size');
}

void testInfoStrings() {
  final info = Info(
    protoMajor: 1,
    caps: capsFlagBillowsObserve | capsFlagHistory | capsFlagBattery |
        capsFlagConfig,
    probes: 4,
    deviceId: 'A4F2',
    fw: '0.1.0',
    model: 'heltec3',
    bondsFree: 3,
  );
  final wire = info.encode();
  check(wire.length == Info.size, 'info size');
  final info2 = Info.decode(wire);
  check(info2.deviceId == 'A4F2', 'info device_id');
  check(info2.fw == '0.1.0', 'info fw');
  check(!info2.billowsControl, 'billows_control is 0');
  check(info2.billowsObserve, 'billows_observe');
}

void main() {
  testCrc16();
  testSeq24();
  testLiveVector();
  testSampleRec();
  testResultAndSync();
  testInfoStrings();
  print('Dart protocol codec tests passed');
}
