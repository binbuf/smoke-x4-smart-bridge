/// A4.3: the delta-sync engine. A simulated three-hour disconnect and
/// reconnect transfers exactly 360 samples, and a restart mid-sync resumes
/// without duplicating rows.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dto/dto.dart';
import 'package:smoke_bridge/data/local/database.dart';
import 'package:smoke_bridge/data/repos/sync_engine.dart';
import 'package:smoke_bridge/data/transport/ble_transport.dart';
import 'package:smoke_bridge/data/transport/mock_transport.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';

import 'fake_peripheral.dart';
import 'records_parity_test.dart' show repoRoot;

void main() {
  late Uint8List fullBytes;
  late int fullCount;

  setUpAll(() {
    fullBytes = File(
      '${repoRoot()}/protocol/fixtures/brisket-18h.smk',
    ).readAsBytesSync();
    fullCount = (fullBytes.length - SessionHeader.size) ~/ SampleRec.size;
  });

  /// The device as it looked N samples ago: same header, shorter body.
  Uint8List truncated(int missing) => Uint8List.sublistView(
    fullBytes,
    0,
    fullBytes.length - missing * SampleRec.size,
  );

  test('first sync pulls the whole cook; a re-sync moves zero bytes', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final transport = MockTransport.fromSmkBytes(fullBytes);

    final first = await SyncEngine(db, transport).sync();
    expect(first.sessionsSeen, 1);
    expect(first.samplesInserted, fullCount);

    final second = await SyncEngine(db, transport).sync();
    expect(second.samplesInserted, 0); // closed + fully cached: free
  });

  test('a three-hour disconnect transfers exactly 360 samples', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Sync while the cook was 360 samples (3 h at 30 s) from its end...
    final before = MockTransport.fromSmkBytes(truncated(360));
    final r1 = await SyncEngine(db, before).sync();
    expect(r1.samplesInserted, fullCount - 360);

    // ...then reconnect after the cook finished: only the delta moves.
    final after = MockTransport.fromSmkBytes(fullBytes);
    final r2 = await SyncEngine(db, after).sync();
    expect(r2.samplesInserted, 360);
    expect(r2.sessionsSynced, 1);

    final status = await after.status();
    final total = await db.sampleDao.count(status.deviceId, 27);
    expect(total, fullCount); // complete, no holes
  });

  test('a restart mid-sync resumes without duplicating rows', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // "Crash" partway: a sync that only saw the first part of the cook.
    final partial = MockTransport.fromSmkBytes(truncated(1000));
    await SyncEngine(db, partial).sync();
    final status = await partial.status();
    final afterCrash = await db.sampleDao.count(status.deviceId, 27);
    expect(afterCrash, fullCount - 1000);

    // The retry re-reads nothing it already has and lands the rest —
    // primary keys make the insert idempotent even on overlap.
    final full = MockTransport.fromSmkBytes(fullBytes);
    final retry = await SyncEngine(db, full).sync();
    expect(retry.samplesInserted, 1000);
    expect(await db.sampleDao.count(status.deviceId, 27), fullCount);

    // No duplicates: every (session, t) appears exactly once.
    final dupes = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM (SELECT session_id, t, COUNT(*) c '
          'FROM samples GROUP BY bridge_id, session_id, t HAVING c > 1)',
        )
        .getSingle();
    expect(dupes.data['n'], 0);
  });

  test('a cache that starts partway into a cook is repaired', () async {
    // Board-found on the A15.5 bench sitting. The BLE lane serves the last
    // two hours only, so onboarding over Bluetooth and then reaching the
    // bridge over Wi-Fi leaves a cache whose lowest `t` is hours into the
    // cook. `cachedMax + 1` starts above the hole and never looks down, so
    // the dashboard read 8 h for a 16 h cook and would have kept doing so.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final transport = MockTransport.fromSmkBytes(fullBytes);
    final status = await transport.status();

    // Seed the cache the way the BLE lane leaves it: the tail only.
    final tail = <Sample>[];
    await for (final batch in transport.samples(27, fromT: 0)) {
      tail.addAll(batch);
    }
    final recent = tail.sublist(tail.length - 240);
    await db.sessionDao.upsertBridge(status.deviceId);
    await db.sessionDao.upsertSessions(status.deviceId, [
      ...await transport.sessions(),
    ]);
    await db.sampleDao.insertSamples(status.deviceId, 27, recent);
    expect(await db.sampleDao.minT(status.deviceId, 27), greaterThan(0));

    final report = await SyncEngine(db, transport).sync();

    // A full refetch, not a delta: the batches carry every sample, and the
    // upsert reports what it wrote rather than what was new.
    expect(report.samplesInserted, fullCount);
    expect(await db.sampleDao.count(status.deviceId, 27), fullCount);
    expect(await db.sampleDao.minT(status.deviceId, 27), 0);

    // Repairing the hole must not double any row it already had.
    final dupes = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM (SELECT session_id, t, COUNT(*) c '
          'FROM samples GROUP BY bridge_id, session_id, t HAVING c > 1)',
        )
        .getSingle();
    expect(dupes.data['n'], 0);
  });

  // ── A27: the same engine, over Bluetooth ──────────────────────────
  //
  // Before §5.10 this was not merely slower over BLE, it was impossible:
  // `sessions()` and `samples()` both threw, so a BLE-first connection
  // synced NOTHING. These are the tests that say it now works.

  group('over BLE', () {
    Future<BleTransport> bleTo(FakeBridgeState state) async {
      final fake = FakePeripheral(state: state);
      await fake.connect('AA:BB:CC:DD:A4:F2');
      await fake.bond();
      await fake.requestMtu(247);
      final t = BleTransport(fake);
      await t.start();
      return t;
    }

    test('an overnight cook lands in the cache with no Wi-Fi', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final state = FakeBridgeState()..recordCook(hours: 12);
      final t = await bleTo(state);
      addTearDown(t.close);

      final report = await SyncEngine(db, t).sync();

      expect(report.sessionsSeen, 1);
      expect(report.samplesInserted, 1440);
      expect(await db.sampleDao.count('A4F2', 0x1A), 1440);
      expect(await db.sampleDao.minT('A4F2', 0x1A), 0);
      expect(await db.sampleDao.maxT('A4F2', 0x1A), 1439 * 30);

      // And it reads back the way the chart wants it, from drift alone.
      final range = await db.sampleDao.range('A4F2', 0x1A);
      expect(range, hasLength(1440));
      expect(range.first.tempsF10[2], isNull, reason: 'detached stays null');
    });

    test('reconnecting mid-cook moves only the delta', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Sync six hours in...
      final early = FakeBridgeState()..recordCook(hours: 6);
      final t1 = await bleTo(early);
      final r1 = await SyncEngine(db, t1).sync();
      expect(r1.samplesInserted, 720);
      await t1.close();

      // ...then again after the cook ran another six.
      final later = FakeBridgeState()..recordCook(hours: 12);
      final t2 = await bleTo(later);
      addTearDown(t2.close);
      final r2 = await SyncEngine(db, t2).sync();

      expect(r2.samplesInserted, 720, reason: 'only the new six hours');
      expect(await db.sampleDao.count('A4F2', 0x1A), 1440);
    });

    test('a finished, fully cached cook costs nothing to re-sync', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final state = FakeBridgeState()..recordCook(hours: 12, closed: true);
      final t = await bleTo(state);
      addTearDown(t.close);

      expect((await SyncEngine(db, t).sync()).samplesInserted, 1440);
      expect((await SyncEngine(db, t).sync()).samplesInserted, 0);
    });

    test('the cache survives the bridge purging the cook', () async {
      // The whole point of keeping a local copy: the bridge deletes old
      // sessions under its own retention (04 §4.7), and the phone does not.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final state = FakeBridgeState()..recordCook(hours: 12, closed: true);
      final t1 = await bleTo(state);
      await SyncEngine(db, t1).sync();
      await t1.close();

      final wiped = FakeBridgeState(); // the bridge remembers nothing
      final t2 = await bleTo(wiped);
      addTearDown(t2.close);
      await SyncEngine(db, t2).sync();

      expect(await db.sampleDao.count('A4F2', 0x1A), 1440);
      expect(await db.sessionDao.allSessions('A4F2'), hasLength(1));
    });

    test('clearing the cache is the one thing that removes it', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final state = FakeBridgeState()..recordCook(hours: 12, closed: true);
      final t = await bleTo(state);
      addTearDown(t.close);
      await SyncEngine(db, t).sync();

      final before = await db.cacheStats();
      expect(before.sessions, 1);
      expect(before.samples, 1440);
      expect(before.approxBytes, greaterThan(0));

      await db.clearCachedCooks();

      final after = await db.cacheStats();
      expect(after.isEmpty, isTrue);
      expect(await db.sampleDao.count('A4F2', 0x1A), 0);
      // The bridge is untouched, and the pairing survives — so the next
      // sync refills rather than starting over.
      expect(await db.sessionDao.knownBridgeId(), 'A4F2');
      expect((await SyncEngine(db, t).sync()).samplesInserted, 1440);
    });
  });
}
