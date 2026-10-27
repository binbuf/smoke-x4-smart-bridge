import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/data/ble/ble_client.dart';
import 'package:smoke_bridge/data/ble/bridge_protocol.dart';
import 'package:smoke_bridge/data/db/app_database.dart';
import 'package:smoke_bridge/data/db/sample_dao.dart';
import 'package:smoke_bridge/data/sync/archive_sync.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_ble_client.dart';
import 'support/fake_bridge.dart';

const int _seqNone = 0xFFFFFFFF;
final DateTime _now = DateTime.utc(2026, 10, 27, 12);
const int _baseSec = 1700000000;

/// A deterministic bridge ring with the T39 cursor rules.
class FakeRing implements SyncTransport {
  FakeRing({this.generation = 7, required this.minSeq, required this.maxSeq});

  int generation;
  int minSeq;
  int maxSeq;
  int requests = 0;

  /// Throws before answering this request, modelling a link drop in the middle
  /// of a batch. The device remembers nothing about the partial transfer.
  int? failOnceAtRequest;

  /// Answers status with `status = error` this many times.
  int statusErrorsRemaining = 0;

  final List<BridgeSyncRequest> log = <BridgeSyncRequest>[];

  bool get isEmpty => minSeq == _seqNone && maxSeq == _seqNone;

  BridgeSampleRecord recordAt(int seq) => BridgeSampleRecord(
    seq: seq,
    unixS: _baseSec + seq * 30,
    tempsF10: const <int>[700 + 1, 710, -32768, 730],
    flags: 0x01 | 0x02 | 0x04 | 0x10 | 0x20,
  );

  @override
  Future<BridgeSyncStream> request(BridgeSyncRequest request) async {
    requests++;
    log.add(request);
    if (failOnceAtRequest == requests) {
      failOnceAtRequest = null;
      throw const SyncException('link dropped mid-batch');
    }
    if (request.cmd == BridgeSyncCmd.status) {
      if (statusErrorsRemaining > 0) {
        statusErrorsRemaining--;
        return _stream(
          const <BridgeSampleRecord>[],
          status: _statusError,
          startSeq: request.cursorSeq,
          nextSeq: request.cursorSeq,
          minSeq: isEmpty ? _seqNone : minSeq,
          maxSeq: isEmpty ? _seqNone : maxSeq,
        );
      }
      return _stream(
        const <BridgeSampleRecord>[],
        status: isEmpty ? _statusEmpty : _statusOk,
        startSeq: request.cursorSeq,
        nextSeq: request.cursorSeq,
        minSeq: isEmpty ? _seqNone : minSeq,
        maxSeq: isEmpty ? _seqNone : maxSeq,
      );
    }
    if (isEmpty) {
      return _stream(
        const <BridgeSampleRecord>[],
        status: _statusEmpty,
        startSeq: request.cursorSeq,
        nextSeq: request.cursorSeq,
        minSeq: _seqNone,
        maxSeq: _seqNone,
      );
    }
    final limit = request.maxRecords == 0
        ? 32
        : request.maxRecords.clamp(1, 64);
    if (request.direction == BridgeSyncDirection.backward) {
      return _backward(request, limit);
    }
    return _forward(request, limit);
  }

  BridgeSyncStream _backward(BridgeSyncRequest request, int limit) {
    var cursor = request.cursorSeq;
    var status = _statusOk;
    if (cursor > maxSeq + 1) {
      cursor = maxSeq + 1;
      status = _statusGap;
    }
    var low = cursor - limit;
    if (low < minSeq) low = minSeq;
    final records = <BridgeSampleRecord>[
      for (var seq = low; seq < cursor; seq++) recordAt(seq),
    ];
    return _stream(
      records,
      status: status,
      startSeq: records.isEmpty ? cursor : records.first.seq,
      nextSeq: records.isEmpty ? cursor : records.first.seq,
      minSeq: minSeq,
      maxSeq: maxSeq,
    );
  }

  BridgeSyncStream _forward(BridgeSyncRequest request, int limit) {
    final cursor = request.cursorSeq;
    var status = _statusOk;
    var seq = cursor + 1;
    if (minSeq > 1 && cursor < minSeq - 1) {
      status = _statusGap;
      seq = minSeq;
    }
    if (seq < minSeq) seq = minSeq;
    final records = <BridgeSampleRecord>[
      for (var i = 0; i < limit && seq + i <= maxSeq; i++) recordAt(seq + i),
    ];
    return _stream(
      records,
      status: status,
      startSeq: records.isEmpty ? cursor : records.first.seq,
      nextSeq: records.isEmpty ? cursor : records.last.seq + 1,
      minSeq: minSeq,
      maxSeq: maxSeq,
    );
  }

  BridgeSyncStream _stream(
    List<BridgeSampleRecord> records, {
    required int status,
    required int startSeq,
    required int nextSeq,
    required int minSeq,
    required int maxSeq,
  }) => BridgeSyncStream(
    start: BridgeSyncStart(
      generation: generation,
      minSeq: minSeq,
      maxSeq: maxSeq,
      startSeq: startSeq,
      count: records.length,
      recordSize: BridgeSampleRecord.size,
      status: status,
    ),
    records: records,
    end: BridgeSyncEnd(
      status: status,
      nextSeq: nextSeq,
      minSeq: minSeq,
      maxSeq: maxSeq,
    ),
  );
}

const int _statusOk = 0;
const int _statusGap = 1;
const int _statusError = 2;
const int _statusEmpty = 4;

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late SampleDao dao;

  setUp(() async {
    database = await AppDatabase.openInMemory(factory: databaseFactoryFfi);
    dao = SqfliteSampleDao(database);
  });

  tearDown(() async {
    // The DAO owns the database handle.
    await dao.close();
  });

  ArchiveSyncCoordinator coordinator({
    List<SyncStatusSnapshot>? statuses,
    List<StoredSyncBatch>? batches,
    int maxAttempts = 3,
    int recentTargetRecords = 2880,
  }) => ArchiveSyncCoordinator(
    dao: dao,
    now: () => _now,
    maxAttempts: maxAttempts,
    recentTargetRecords: recentTargetRecords,
    onStatus: statuses?.add,
    onBatch: batches?.add,
  );

  Future<SyncStatusSnapshot> connect(
    ArchiveSyncCoordinator sync,
    FakeRing ring, {
    String id = 'bridge-a',
  }) => sync.connectSync(
    transport: ring,
    bridgeId: id,
    bridgeName: 'Backyard Bridge',
  );

  test(
    'the status read supplies generation, extent and an empty log',
    () async {
      final ring = FakeRing(minSeq: 5, maxSeq: 900);
      final statuses = <SyncStatusSnapshot>[];
      final sync = coordinator(statuses: statuses);

      await connect(sync, ring);

      final statusRequest = ring.log.first;
      expect(statusRequest.cmd, BridgeSyncCmd.status);
      expect(sync.generation, 7);
      expect(statuses.first.status, SyncStatus.syncing);
      expect(statuses.first.phase, SyncPhase.recent);
      expect(sync.snapshot.deviceMinSeq, 5);
      expect(sync.snapshot.deviceMaxSeq, 900);
      expect(sync.snapshot.status, SyncStatus.complete);

      final emptyRing = FakeRing(minSeq: _seqNone, maxSeq: _seqNone);
      final emptySync = coordinator();
      final empty = await connect(emptySync, emptyRing, id: 'bridge-empty');
      expect(empty.status, SyncStatus.complete);
      expect(empty.deviceEmpty, isTrue);
      expect(empty.cursorAfter, isNull);
      expect(await dao.countSamples(bridgeId: 'bridge-empty'), 0);
      expect(await dao.gaps(bridgeId: 'bridge-empty'), isEmpty);
    },
  );

  test('a 30-day ring syncs the recent 24 h first, then backfills', () async {
    final ring = FakeRing(minSeq: 0, maxSeq: 30 * 24 * 120 - 1);
    final statuses = <SyncStatusSnapshot>[];
    final sync = coordinator(statuses: statuses);

    final recentPass = await connect(sync, ring);
    expect(
      recentPass.status,
      SyncStatus.partial,
      reason: 'the recent pass returns before the 30-day backfill',
    );
    final result = await sync.backfillDone;

    expect(result.status, SyncStatus.complete);
    expect(result.generation, 7);
    expect(await dao.countSamples(bridgeId: 'bridge-a'), 86400);

    final reads = ring.log
        .where((request) => request.cmd == BridgeSyncCmd.read)
        .toList();
    final recent = reads
        .where((request) => request.direction == BridgeSyncDirection.backward)
        .toList();
    expect(recent.first.cursorSeq, 86400);
    expect(recent.first.maxRecords, 32);
    expect(
      recent.take(90).every((request) => request.maxRecords == 32),
      isTrue,
    );
    expect(
      reads.any(
        (request) =>
            request.direction == BridgeSyncDirection.backward &&
            request.maxRecords == 64,
      ),
      isTrue,
      reason: 'background backfill uses the larger page',
    );

    final partial = statuses.where((s) => s.status == SyncStatus.partial);
    expect(partial, isNotEmpty);
    expect(partial.first.phase, SyncPhase.backfill);

    final extent = await dao.extent(bridgeId: 'bridge-a');
    expect(extent!.minSeq, 0);
    expect(extent.maxSeq, 86399);
    final saved = await dao.bridgeById('bridge-a');
    expect(saved!.cursorAfter, 86399);
    expect(saved.cursorBefore, 0);
    expect(saved.deviceMinSeq, 0);
    expect(saved.deviceMaxSeq, 86399);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('record 0 is fetched; next_seq 0 is a cursor, not a stop', () async {
    final ring = FakeRing(minSeq: 0, maxSeq: 39);
    final sync = coordinator();

    final result = await connect(sync, ring);

    expect(result.status, SyncStatus.complete);
    final backward = ring.log
        .where(
          (request) =>
              request.cmd == BridgeSyncCmd.read &&
              request.direction == BridgeSyncDirection.backward,
        )
        .map((request) => request.cursorSeq)
        .toList();
    // 40 -> 8 (the 32-record recent page) -> 0 (the exclusive cursor that
    // reaches record 0) -> 0 again returns count = 0 and stops the direction.
    expect(backward, <int>[40, 8, 0]);
    final samples = await dao.samplesInRange(
      fromMs: 0,
      toMs: 0x7FFFFFFFFFFFFFFF,
      bridgeId: 'bridge-a',
    );
    expect(samples.map((sample) => sample.seq), contains(0));
    expect(await dao.countSamples(bridgeId: 'bridge-a'), 40);
  });

  test(
    'a disconnect mid-batch resumes from the last fully stored seq',
    () async {
      final ring = FakeRing(minSeq: 0, maxSeq: 999)..failOnceAtRequest = 5;
      final first = coordinator(maxAttempts: 1);

      await expectLater(connect(first, ring), throwsA(isA<SyncException>()));
      final partial = await dao.extent(bridgeId: 'bridge-a');
      expect(partial, isNotNull);
      expect(partial!.count, 96, reason: 'three complete 32-record batches');
      expect(partial.minSeq, 904);

      final second = coordinator();
      final resumed = await connect(second, ring);
      expect(resumed.status, SyncStatus.partial);
      final result = await second.backfillDone;

      expect(result.status, SyncStatus.complete);
      expect(await dao.countSamples(bridgeId: 'bridge-a'), 1000);
      final extent = await dao.extent(bridgeId: 'bridge-a');
      expect(extent!.minSeq, 0);
      expect(extent.maxSeq, 999);
      final saved = await dao.bridgeById('bridge-a');
      expect(saved!.cursorBefore, 0);
      expect(saved.cursorAfter, 999);
    },
  );

  test('a seeded 338,400-record ring completes and resumes without '
      'duplicates', () async {
    final ring = FakeRing(minSeq: 0, maxSeq: 338399)..failOnceAtRequest = 1001;
    final first = coordinator(maxAttempts: 1);

    final recent = await connect(first, ring);
    expect(recent.status, SyncStatus.partial);
    final stopped = await first.backfillDone;
    expect(stopped.status, SyncStatus.error);
    final interrupted = await dao.countSamples(bridgeId: 'bridge-a');
    expect(interrupted, greaterThan(0));
    expect(interrupted, lessThan(338400));

    final second = coordinator();
    await connect(second, ring);
    final result = await second.backfillDone;

    expect(result.status, SyncStatus.complete);
    expect(await dao.countSamples(bridgeId: 'bridge-a'), 338400);
    final extent = await dao.extent(bridgeId: 'bridge-a');
    expect(extent!.minSeq, 0);
    expect(extent.maxSeq, 338399);
    expect(extent.count, 338400, reason: 'the PK makes re-sync idempotent');

    // A third pass has nothing to add.
    final third = coordinator();
    final again = await connect(third, ring);
    expect(again.status, SyncStatus.complete);
    expect(await dao.countSamples(bridgeId: 'bridge-a'), 338400);
  }, timeout: const Timeout(Duration(minutes: 8)));

  test(
    'a generation change keeps old rows and starts a fresh segment',
    () async {
      final ring = FakeRing(minSeq: 0, maxSeq: 99);
      final sync = coordinator();
      await connect(sync, ring);
      expect(await dao.countSamples(bridgeId: 'bridge-a', generation: 7), 100);

      ring
        ..generation = 8
        ..minSeq = 0
        ..maxSeq = 49;
      final result = await sync.catchUp(transport: ring);

      expect(result.status, SyncStatus.complete);
      expect(result.generation, 8);
      expect(
        await dao.countSamples(bridgeId: 'bridge-a', generation: 7),
        100,
        reason: 'a generation change is an epoch boundary, not a delete',
      );
      expect(await dao.countSamples(bridgeId: 'bridge-a', generation: 8), 50);
      final saved = await dao.bridgeById('bridge-a');
      expect(saved!.generation, 8);
      expect(saved.cursorAfter, 49);
      expect(saved.cursorBefore, 0);
    },
  );

  test('a forward gap is stored with its reason and sync continues at the '
      'device extent', () async {
    final ring = FakeRing(minSeq: 0, maxSeq: 50);
    final sync = coordinator();
    await connect(sync, ring);

    // The 90,000-record ring rotated past the app's cursor.
    ring
      ..minSeq = 100
      ..maxSeq = 200;
    final result = await sync.catchUp(transport: ring);

    expect(result.status, SyncStatus.complete);
    final gaps = await dao.gaps(bridgeId: 'bridge-a', generation: 7);
    expect(gaps, hasLength(1));
    expect(gaps.single.fromSeq, 51);
    expect(gaps.single.toSeq, 99);
    expect(gaps.single.reason, syncGapNotSynced);
    expect(await dao.countSamples(bridgeId: 'bridge-a'), 51 + 101);
  });

  test('every sync status branch is reachable, including error', () async {
    expect(SyncStatusSnapshot.idle.status, SyncStatus.idle);

    final statuses = <SyncStatusSnapshot>[];
    final ring = FakeRing(minSeq: 0, maxSeq: 3000);
    final sync = coordinator(statuses: statuses);
    await connect(sync, ring);
    await sync.backfillDone;
    expect(statuses.any((s) => s.status == SyncStatus.syncing), isTrue);
    expect(statuses.any((s) => s.phase == SyncPhase.recent), isTrue);
    expect(statuses.any((s) => s.status == SyncStatus.partial), isTrue);
    expect(statuses.any((s) => s.status == SyncStatus.complete), isTrue);

    final errorRing = FakeRing(minSeq: 0, maxSeq: 10)
      ..statusErrorsRemaining = 1;
    final error = await connect(coordinator(), errorRing, id: 'bridge-error');
    expect(error.status, SyncStatus.error);
    expect(error.error, isNotNull);
  });

  test(
    'live notifications append by seq and never create a false cursor',
    () async {
      final ring = FakeRing(minSeq: 0, maxSeq: 10);
      final batches = <StoredSyncBatch>[];
      final sync = coordinator(batches: batches);
      await connect(sync, ring);
      batches.clear();

      const live = BridgeLive(
        flags: 0x01 | 0x10 | 0x20,
        tempsF10: <int>[700, 710, -32768, 730],
        seq: 11,
        billowsTargetF10: 0,
        batteryPct: 87,
        rssiLora: -60,
        ageS: 2,
      );
      await sync.recordLive(live: live, receivedAt: _now);
      expect(await dao.countSamples(bridgeId: 'bridge-a'), 12);
      expect((await dao.bridgeById('bridge-a'))!.cursorAfter, 11);
      expect(batches.single.records.single.seq, 11);

      // Duplicate sequence is a no-op.
      await sync.recordLive(live: live, receivedAt: _now);
      expect(await dao.countSamples(bridgeId: 'bridge-a'), 12);

      // A hole is stored but must not advance the contiguous cursor.
      const hole = BridgeLive(
        flags: 0x20,
        tempsF10: <int>[700, 710, 720, 730],
        seq: 13,
        billowsTargetF10: 0,
        batteryPct: 87,
        rssiLora: -60,
        ageS: 2,
      );
      await sync.recordLive(live: hole, receivedAt: _now);
      expect(await dao.countSamples(bridgeId: 'bridge-a'), 13);
      expect((await dao.bridgeById('bridge-a'))!.cursorAfter, 11);
    },
  );

  test(
    'BridgeLink writes its first sync through the durable archive',
    () async {
      final bridge = FakeBridge();
      final client = FakeBleClient(
        server: bridge,
        advertisements: <BleDevice>[bridge.advertisement()],
        connectDelay: Duration.zero,
        bondDelay: Duration.zero,
        scanInterval: Duration.zero,
      );
      final controller = BridgeController(bleClient: client, sampleDao: dao)
        ..hasSavedBridge = true
        ..phase = ConnectionPhase.offline;
      final link = controller.ensureLink(bondPrompt: () async => true);
      addTearDown(() async {
        await link.dispose();
        controller.dispose();
        await client.dispose();
        await bridge.dispose();
      });

      await link.connectAndSecure(bridge.advertisement());

      expect(controller.phase, ConnectionPhase.live);
      // The saved identity is the BLE address, so a later launch can scan for
      // it directly; the advertised name is the fallback.
      final device = bridge.advertisement();
      expect(await dao.countSamples(bridgeId: device.id), 3);
      final saved = await dao.bridgeById(device.id);
      expect(saved, isNotNull);
      expect(saved!.cursorAfter, 102);
      expect(saved.cursorBefore, 100);
      expect(controller.archiveSync, isNotNull);
    },
  );

  test('a sync stream with a missing frame is rejected, not stored', () {
    final records = <BridgeSampleRecord>[
      for (var seq = 10; seq < 30; seq++)
        BridgeSampleRecord(
          seq: seq,
          unixS: _baseSec + seq * 30,
          tempsF10: const <int>[700, 710, 720, 730],
          flags: 0x3F,
        ),
    ];
    final stream = BridgeSyncStream(
      start: const BridgeSyncStart(
        generation: 1,
        minSeq: 10,
        maxSeq: 29,
        startSeq: 10,
        count: 20,
        recordSize: BridgeSampleRecord.size,
        status: _statusOk,
      ),
      records: records,
      end: const BridgeSyncEnd(
        status: _statusOk,
        nextSeq: 30,
        minSeq: 10,
        maxSeq: 29,
      ),
    );
    // Build the logical stream the same way the device does.
    final encoded = _encodeStream(stream);
    final frames = _frame(encoded);
    expect(frames.length, greaterThan(2));

    final assembler = BridgeSyncAssembler();
    expect(() {
      for (var index = 0; index < frames.length; index++) {
        if (index == 1) continue; // drop one frame
        assembler.add(frames[index]);
      }
    }, throwsFormatException);
  });
}

Uint8List _encodeStream(BridgeSyncStream stream) {
  final length =
      BridgeSyncStart.size +
      stream.records.length * BridgeSampleRecord.size +
      BridgeSyncEnd.size;
  final out = Uint8List(length);
  final view = ByteData.sublistView(out);
  view.setUint32(0, stream.start.generation, Endian.little);
  view.setUint32(4, stream.start.minSeq, Endian.little);
  view.setUint32(8, stream.start.maxSeq, Endian.little);
  view.setUint32(12, stream.start.startSeq, Endian.little);
  view.setUint16(16, stream.start.count, Endian.little);
  view.setUint8(18, stream.start.recordSize);
  view.setUint8(19, stream.start.status);
  var offset = BridgeSyncStart.size;
  for (final record in stream.records) {
    out[offset] = record.seq & 0xFF;
    out[offset + 1] = (record.seq >> 8) & 0xFF;
    out[offset + 2] = (record.seq >> 16) & 0xFF;
    view.setUint32(offset + 3, record.unixS, Endian.little);
    for (var index = 0; index < 4; index++) {
      view.setInt16(
        offset + 7 + index * 2,
        record.tempsF10[index],
        Endian.little,
      );
    }
    out[offset + 15] = record.flags;
    offset += BridgeSampleRecord.size;
  }
  view.setUint8(offset, stream.end.status);
  view.setUint32(offset + 1, stream.end.nextSeq, Endian.little);
  view.setUint32(offset + 5, stream.end.minSeq, Endian.little);
  view.setUint32(offset + 9, stream.end.maxSeq, Endian.little);
  return out;
}

List<Uint8List> _frame(Uint8List stream) {
  const maxPayload = 64;
  final frames = <Uint8List>[];
  var frameSeq = 0;
  for (var offset = 0; offset < stream.length; offset += maxPayload) {
    final end = (offset + maxPayload).clamp(0, stream.length);
    final payload = Uint8List.sublistView(stream, offset, end);
    var flags = 0;
    if (offset == 0) flags |= syncFrameFlagStart;
    if (end == stream.length) flags |= syncFrameFlagEnd;
    final out = Uint8List(4 + payload.length);
    out[0] = 1;
    out[1] = frameSeq;
    out[2] = flags;
    out[3] = payload.length;
    out.setRange(4, out.length, payload);
    frames.add(out);
    frameSeq = (frameSeq + 1) & 0xFF;
  }
  return frames;
}
