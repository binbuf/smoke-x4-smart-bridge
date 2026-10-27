// The small V0 slice of the generated protocol contract the link procedures
// need: `live`, `control`/`result`, and the sync framing.
//
// `app/lib` cannot import `protocol/gen`, so the field offsets are repeated
// here. `test/link_codec_test.dart` decodes and re-encodes the same bytes with
// the generated codec, so a contract change fails the app suite instead of
// silently drifting. T40/T47 replace this file with the packaged codec.

import 'dart:convert';
import 'dart:typed_data';

const String bleLiveCharacteristicUuid = '7f9b0002-4c5b-4b0f-9a3d-1c2e3f405162';
const String bleControlCharacteristicUuid =
    '7f9b0003-4c5b-4b0f-9a3d-1c2e3f405162';
const String bleResultCharacteristicUuid =
    '7f9b0004-4c5b-4b0f-9a3d-1c2e3f405162';
const String bleSyncCtrlCharacteristicUuid =
    '7f9b0005-4c5b-4b0f-9a3d-1c2e3f405162';
const String bleSyncDataCharacteristicUuid =
    '7f9b0006-4c5b-4b0f-9a3d-1c2e3f405162';

const int bleProtocolMajor = 1;

/// `battery_pct` sentinel for "unknown".
const int bleBatteryUnknown = 255;

/// `seq` sentinel for "no stored sample" (`SEQ_NONE`).
const int bleSeqNone = 0xFFFFFFFF;

/// Probe temperature sentinels.
const int bleTempDetached = -32768;
const int bleTempInvalid = -32767;

/// `live` flag bits.
const int liveFlagSmokePaired = 1 << 0;
const int liveFlagSmokeLive = 1 << 1;
const int liveFlagBillowsAttached = 1 << 2;
const int liveFlagBillowsOutput = 1 << 3;
const int liveFlagClockValid = 1 << 4;
const int liveFlagStorageOk = 1 << 5;
const int liveFlagDisplayOn = 1 << 6;
const int liveFlagSyncActive = 1 << 7;

/// Sync frame flag bits.
const int syncFrameFlagStart = 1 << 0;
const int syncFrameFlagEnd = 1 << 1;
const int syncFrameFlagError = 1 << 2;

/// `control.op` values.
enum BridgeControlOp {
  setTime(1),
  forgetPhone(2),
  factoryReset(3),
  powerOff(4),
  clearHistory(5),
  setBillowsTarget(6),
  unpairSmokeX(7);

  const BridgeControlOp(this.wire);

  final int wire;

  static BridgeControlOp? fromWire(int value) {
    for (final op in values) {
      if (op.wire == value) return op;
    }
    return null;
  }
}

/// `result.status` values. The app branches on these, never on `detail`.
enum BridgeResultStatus {
  ok(0),
  invalid(1),
  unsupported(2),
  busy(3),
  unauthorized(4),
  failed(5),
  notFound(6),
  storage(7);

  const BridgeResultStatus(this.wire);

  final int wire;

  static BridgeResultStatus? fromWire(int value) {
    for (final status in values) {
      if (status.wire == value) return status;
    }
    return null;
  }
}

/// `control` envelope plus an op body (05 §5.5).
class BridgeControl {
  const BridgeControl({
    required this.op,
    required this.opId,
    this.version = bleProtocolMajor,
  });

  final int version;
  final BridgeControlOp op;
  final int opId;

  static const int size = 3;

  Uint8List encode([List<int> body = const <int>[]]) {
    final out = Uint8List(size + body.length);
    final view = ByteData.sublistView(out);
    view.setUint8(0, version);
    view.setUint8(1, op.wire);
    view.setUint8(2, opId & 0xFF);
    out.setRange(size, out.length, body);
    return out;
  }

  static BridgeControl decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < size) {
      throw RangeError('truncated control');
    }
    final view = ByteData.sublistView(bytes, offset, offset + size);
    return BridgeControl(
      version: view.getUint8(0),
      op: BridgeControlOp.fromWire(view.getUint8(1)) ?? BridgeControlOp.setTime,
      opId: view.getUint8(2),
    );
  }
}

/// `control op 1` body: UTC milliseconds and the phone's timezone offset.
Uint8List encodeSetTimeBody({required int unixMs, required int tzOffsetMin}) {
  final out = Uint8List(10);
  final view = ByteData.sublistView(out);
  view.setUint64(0, unixMs, Endian.little);
  view.setInt16(8, tzOffsetMin, Endian.little);
  return out;
}

int unixMsOfSetTimeBody(Uint8List body) {
  if (body.length < 10) throw RangeError('truncated set_time body');
  return ByteData.sublistView(body).getUint64(0, Endian.little);
}

int tzOffsetOfSetTimeBody(Uint8List body) {
  if (body.length < 10) throw RangeError('truncated set_time body');
  return ByteData.sublistView(body).getInt16(8, Endian.little);
}

/// A decoded `result` notification (05 §5.6).
class BridgeResult {
  const BridgeResult({
    required this.version,
    required this.op,
    required this.opId,
    required this.status,
    this.detail = '',
  });

  final int version;
  final int op;
  final int opId;
  final BridgeResultStatus status;

  /// Human-readable detail. Never used for branching.
  final String detail;

  /// The complete result is 5 header bytes plus `len` detail bytes.
  static const int headerSize = 5;
  static const int maxDetail = 59;

  /// Number of bytes the first notification chunk must declare.
  static int expectedLength(Uint8List header) {
    if (header.length < headerSize) {
      throw RangeError('truncated result header');
    }
    final len = header[4];
    if (len > maxDetail) throw RangeError('bad result length');
    return headerSize + len;
  }

  static BridgeResult decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < headerSize) {
      throw RangeError('truncated result header');
    }
    final len = bytes[offset + 4];
    if (len > maxDetail || bytes.length - offset < headerSize + len) {
      throw RangeError('truncated result body');
    }
    final view = ByteData.sublistView(bytes, offset, offset + headerSize + len);
    final detail = _readString(bytes, offset + headerSize, len);
    return BridgeResult(
      version: view.getUint8(0),
      op: view.getUint8(1),
      opId: view.getUint8(2),
      status:
          BridgeResultStatus.fromWire(view.getUint8(3)) ??
          BridgeResultStatus.failed,
      detail: detail,
    );
  }
}

/// `live` (05 §5.4). Decoded on reads and on every notification.
class BridgeLive {
  const BridgeLive({
    required this.flags,
    required this.tempsF10,
    required this.seq,
    required this.billowsTargetF10,
    required this.batteryPct,
    required this.rssiLora,
    required this.ageS,
  });

  final int flags;
  final List<int> tempsF10;
  final int seq;
  final int billowsTargetF10;
  final int batteryPct;
  final int rssiLora;
  final int ageS;

  static const int size = 20;

  bool get smokePaired => (flags & liveFlagSmokePaired) != 0;
  bool get smokeLive => (flags & liveFlagSmokeLive) != 0;
  bool get billowsAttached => (flags & liveFlagBillowsAttached) != 0;
  bool get clockValid => (flags & liveFlagClockValid) != 0;
  bool get storageOk => (flags & liveFlagStorageOk) != 0;
  bool get syncActive => (flags & liveFlagSyncActive) != 0;

  /// `null` means "detached or invalid", never 0 °F.
  double? tempF(int index) {
    final value = tempsF10[index];
    if (value == bleTempDetached || value == bleTempInvalid) return null;
    return value / 10.0;
  }

  static BridgeLive decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < size) {
      throw RangeError('truncated live');
    }
    final view = ByteData.sublistView(bytes, offset, offset + size);
    return BridgeLive(
      flags: view.getUint8(1),
      tempsF10: <int>[
        for (var index = 0; index < 4; index++)
          view.getInt16(2 + index * 2, Endian.little),
      ],
      seq: view.getUint32(10, Endian.little),
      billowsTargetF10: view.getInt16(14, Endian.little),
      batteryPct: view.getUint8(16),
      rssiLora: view.getInt8(17),
      ageS: view.getUint16(18, Endian.little),
    );
  }
}

enum BridgeSyncCmd {
  status(0),
  read(1),
  cancel(2);

  const BridgeSyncCmd(this.wire);

  final int wire;

  static BridgeSyncCmd? fromWire(int value) {
    for (final cmd in values) {
      if (cmd.wire == value) return cmd;
    }
    return null;
  }
}

enum BridgeSyncDirection {
  forward(0),
  backward(1);

  const BridgeSyncDirection(this.wire);

  final int wire;
}

/// `sync_ctrl` request (05 §5.7).
class BridgeSyncRequest {
  const BridgeSyncRequest({
    required this.cmd,
    required this.direction,
    required this.cursorSeq,
    required this.maxRecords,
    this.version = bleProtocolMajor,
  });

  final int version;
  final BridgeSyncCmd cmd;
  final BridgeSyncDirection direction;
  final int cursorSeq;
  final int maxRecords;

  static const int size = 10;

  Uint8List encode() {
    final out = Uint8List(size);
    final view = ByteData.sublistView(out);
    view.setUint8(0, version);
    view.setUint8(1, cmd.wire);
    view.setUint8(2, direction.wire);
    view.setUint32(3, cursorSeq, Endian.little);
    view.setUint8(7, 0);
    view.setUint16(8, maxRecords, Endian.little);
    return out;
  }

  static BridgeSyncRequest decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < size) {
      throw RangeError('truncated sync_ctrl');
    }
    final view = ByteData.sublistView(bytes, offset, offset + size);
    return BridgeSyncRequest(
      version: view.getUint8(0),
      cmd: BridgeSyncCmd.fromWire(view.getUint8(1)) ?? BridgeSyncCmd.read,
      direction: view.getUint8(2) == BridgeSyncDirection.backward.wire
          ? BridgeSyncDirection.backward
          : BridgeSyncDirection.forward,
      cursorSeq: view.getUint32(3, Endian.little),
      maxRecords: view.getUint16(8, Endian.little),
    );
  }
}

/// `sync_frame` header (05 §5.8). [payloadBytes] says how many bytes follow.
class BridgeSyncFrame {
  const BridgeSyncFrame({
    required this.version,
    required this.frameSeq,
    required this.flags,
    required this.payloadBytes,
  });

  final int version;
  final int frameSeq;
  final int flags;
  final int payloadBytes;

  static const int size = 4;

  bool get start => (flags & syncFrameFlagStart) != 0;
  bool get end => (flags & syncFrameFlagEnd) != 0;
  bool get error => (flags & syncFrameFlagError) != 0;

  static BridgeSyncFrame decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < size) {
      throw RangeError('truncated sync frame');
    }
    final view = ByteData.sublistView(bytes, offset, offset + size);
    return BridgeSyncFrame(
      version: view.getUint8(0),
      frameSeq: view.getUint8(1),
      flags: view.getUint8(2),
      payloadBytes: view.getUint8(3),
    );
  }
}

/// `sync_start` (05 §5.8).
class BridgeSyncStart {
  const BridgeSyncStart({
    required this.generation,
    required this.minSeq,
    required this.maxSeq,
    required this.startSeq,
    required this.count,
    required this.recordSize,
    required this.status,
  });

  final int generation;
  final int minSeq;
  final int maxSeq;
  final int startSeq;
  final int count;
  final int recordSize;
  final int status;

  static const int size = 20;

  static BridgeSyncStart decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < size) {
      throw RangeError('truncated sync_start');
    }
    final view = ByteData.sublistView(bytes, offset, offset + size);
    return BridgeSyncStart(
      generation: view.getUint32(0, Endian.little),
      minSeq: view.getUint32(4, Endian.little),
      maxSeq: view.getUint32(8, Endian.little),
      startSeq: view.getUint32(12, Endian.little),
      count: view.getUint16(16, Endian.little),
      recordSize: view.getUint8(18),
      status: view.getUint8(19),
    );
  }
}

/// `sync_end` (05 §5.8).
class BridgeSyncEnd {
  const BridgeSyncEnd({
    required this.status,
    required this.nextSeq,
    required this.minSeq,
    required this.maxSeq,
  });

  final int status;
  final int nextSeq;
  final int minSeq;
  final int maxSeq;

  static const int size = 13;

  static BridgeSyncEnd decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < size) {
      throw RangeError('truncated sync_end');
    }
    final view = ByteData.sublistView(bytes, offset, offset + size);
    return BridgeSyncEnd(
      status: view.getUint8(0),
      nextSeq: view.getUint32(1, Endian.little),
      minSeq: view.getUint32(5, Endian.little),
      maxSeq: view.getUint32(9, Endian.little),
    );
  }
}

/// One 18-byte sample record carried by a sync stream.
class BridgeSampleRecord {
  const BridgeSampleRecord({
    required this.seq,
    required this.unixS,
    required this.tempsF10,
    required this.flags,
  });

  final int seq;
  final int unixS;
  final List<int> tempsF10;
  final int flags;

  static const int size = 18;

  bool get clockValid => (flags & (1 << 5)) != 0;
  bool get billowsAttached => (flags & (1 << 4)) != 0;

  bool probeAttached(int index) => (flags & (1 << index)) != 0;

  double? tempF(int index) {
    final value = tempsF10[index];
    if (value == bleTempDetached || value == bleTempInvalid) return null;
    return value / 10.0;
  }

  static BridgeSampleRecord decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < size) {
      throw RangeError('truncated sample record');
    }
    final view = ByteData.sublistView(bytes, offset, offset + size);
    return BridgeSampleRecord(
      seq:
          bytes[offset] |
          ((bytes[offset + 1] & 0xFF) << 8) |
          ((bytes[offset + 2] & 0xFF) << 16),
      unixS: view.getUint32(3, Endian.little),
      tempsF10: <int>[
        for (var index = 0; index < 4; index++)
          view.getInt16(7 + index * 2, Endian.little),
      ],
      flags: view.getUint8(15),
    );
  }
}

/// Reassembles `result` notifications that the platform split at `MTU - 3`.
///
/// The first chunk always carries the five-byte header, so the total length is
/// known before the rest arrives (05 §5.6).
class BridgeResultAssembler {
  final BytesBuilder _buffer = BytesBuilder(copy: true);
  int? _expected;

  /// Adds one chunk and returns a decoded result when it is complete.
  BridgeResult? add(Uint8List chunk) {
    if (_expected == null) {
      if (chunk.length >= BridgeResult.headerSize) {
        _expected = BridgeResult.expectedLength(chunk);
      }
    }
    _buffer.add(chunk);
    final expected = _expected;
    if (expected == null) return null;
    final bytes = _buffer.toBytes();
    if (bytes.length < expected) return null;
    _reset();
    return BridgeResult.decode(bytes);
  }

  /// A disconnect or a new subscribe invalidates a half-read notification.
  void reset() => _reset();

  void _reset() {
    _buffer.clear();
    _expected = null;
  }
}

/// Reassembles `sync_data` notifications split at `MTU - 3`, then turns the
/// contiguous START / RECORDS / END byte stream into one [BridgeSyncStream].
class BridgeSyncAssembler {
  final BytesBuilder _chunk = BytesBuilder(copy: true);
  final BytesBuilder _stream = BytesBuilder(copy: true);
  int? _framePayload;
  int? _frameFlags;
  int _expectedFrameSeq = 0;

  /// Adds one notification chunk and returns the completed stream, if this
  /// chunk carried the END frame.
  BridgeSyncStream? add(Uint8List chunk) {
    _chunk.add(chunk);
    while (true) {
      final buffered = _chunk.toBytes();
      if (_framePayload == null) {
        if (buffered.length < BridgeSyncFrame.size) return null;
        final frame = BridgeSyncFrame.decode(buffered);
        _framePayload = frame.payloadBytes;
        _frameFlags = frame.flags;
        _expectedFrameSeq = frame.frameSeq;
        _discardPrefix(BridgeSyncFrame.size, buffered);
      }
      final payloadEnd = _chunk.toBytes();
      if (payloadEnd.length < _framePayload!) return null;
      final frameBytes = Uint8List.sublistView(payloadEnd, 0, _framePayload!);
      final flags = _frameFlags!;
      _discardPrefix(_framePayload!, payloadEnd);
      _framePayload = null;
      _frameFlags = null;
      if ((flags & syncFrameFlagError) != 0) {
        throw const FormatException('sync frame error');
      }
      if ((flags & syncFrameFlagStart) != 0) _stream.clear();
      _stream.add(frameBytes);
      if ((flags & syncFrameFlagEnd) != 0) {
        final bytes = _stream.toBytes();
        _stream.clear();
        return BridgeSyncStream.decode(bytes);
      }
    }
  }

  void reset() {
    _chunk.clear();
    _stream.clear();
    _framePayload = null;
    _frameFlags = null;
  }

  int get expectedFrameSeq => _expectedFrameSeq;

  void _discardPrefix(int count, Uint8List buffered) {
    _chunk.clear();
    _chunk.add(Uint8List.sublistView(buffered, count));
  }
}

/// One complete sync response: START, its records, then END.
class BridgeSyncStream {
  const BridgeSyncStream({
    required this.start,
    required this.records,
    required this.end,
  });

  final BridgeSyncStart start;
  final List<BridgeSampleRecord> records;
  final BridgeSyncEnd end;

  static BridgeSyncStream decode(Uint8List bytes) {
    final start = BridgeSyncStart.decode(bytes);
    if (start.recordSize != BridgeSampleRecord.size) {
      throw FormatException('unexpected record size ${start.recordSize}');
    }
    final records = <BridgeSampleRecord>[
      for (var index = 0; index < start.count; index++)
        BridgeSampleRecord.decode(
          bytes,
          BridgeSyncStart.size + index * BridgeSampleRecord.size,
        ),
    ];
    final end = BridgeSyncEnd.decode(
      bytes,
      BridgeSyncStart.size + start.count * BridgeSampleRecord.size,
    );
    return BridgeSyncStream(start: start, records: records, end: end);
  }
}

String _readString(Uint8List bytes, int offset, int length) {
  final end = offset + length;
  var stop = offset;
  while (stop < end && bytes[stop] != 0) {
    stop++;
  }
  return utf8.decode(bytes.sublist(offset, stop), allowMalformed: true);
}
