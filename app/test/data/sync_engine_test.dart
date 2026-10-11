import 'package:smoke_bridge/data/ble/ble_transport.dart';
import 'package:smoke_bridge/data/cache/sample_cache.dart';
import 'package:smoke_bridge/data/dto/records.g.dart';
import 'package:smoke_bridge/data/repo/sync_engine.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

import '../support/fake_peripheral.dart';

Future<BleTransport> _connected(FakeBridgeState state) async {
  final fake = FakePeripheral(state: state);
  await fake.connect('AA:BB:CC:DD:AA:BB');
  await fake.bond();
  await fake.requestMtu(247);
  final transport = BleTransport(fake);
  await transport.start();
  return transport;
}

void main() {
  group('SyncEngine high-water delta', () {
    test('first sync of a closed cook fetches it all, exactly once', () async {
      final state = FakeBridgeState();
      state.recordCook(hours: 2, closed: true);
      final t = await _connected(state);
      final cache = InMemorySampleCache();
      final session = (await t.sessions()).single;

      final first = await SyncEngine().syncSession(
        t,
        bridgeId: 'A4F2',
        session: session,
        cache: cache,
      );
      expect(first.fetched, 2 * 120);
      expect(first.inserted, 2 * 120);
      expect(await cache.sampleCount('A4F2', 0x1A), 2 * 120);

      // A closed, fully-cached session is skipped.
      final second = await SyncEngine().syncSession(
        t,
        bridgeId: 'A4F2',
        session: session,
        cache: cache,
      );
      expect(second.skipped, isTrue);
      expect(second.inserted, 0);
      await t.close();
    });

    test('a re-sync only transfers the seconds not yet stored', () async {
      final state = FakeBridgeState();
      const id = 0x1A;
      state.recordCook(hours: 1); // open
      final t = await _connected(state);
      final cache = InMemorySampleCache();
      var session = (await t.sessions()).single;

      await SyncEngine().syncSession(
        t,
        bridgeId: 'A4F2',
        session: session,
        cache: cache,
      );
      final baseline = await cache.sampleCount('A4F2', id);
      expect(baseline, 120);

      // The bridge keeps recording: ten more samples land while we were away.
      final recs = state.cooks[id]!;
      for (var i = 0; i < 10; i++) {
        recs.add(
          SampleRec(
            t: (120 + i) * 30,
            temp: [2100, 1650, tempDetached, 900],
            rssi: -70,
          ),
        );
      }
      state.cookHeaders[id] = HistorySession(
        sessionId: id,
        startedUnixMs: 1774051200000,
        sampleCount: recs.length,
        samplePeriodS: 30,
        numProbes: 4,
        flags: 0x01,
        nameRaw: state.cookHeaders[id]!.nameRaw,
      );
      session = (await t.sessions()).single;

      final delta = await SyncEngine().syncSession(
        t,
        bridgeId: 'A4F2',
        session: session,
        cache: cache,
      );
      expect(delta.fetched, 10);
      expect(delta.inserted, 10);
      expect(await cache.sampleCount('A4F2', id), 130);
      await t.close();
    });
  });

  group('SyncEngine holes', () {
    test(
      'a device buffer that rolled past the high-water is permanent',
      () async {
        final state = FakeBridgeState();
        const id = 0x1A;
        state.recordCook(hours: 1); // open; t = 0, 30, … 3570
        // The ring wrapped: the device's earliest retained row is now t=60.
        state.cooks[id]!.removeRange(0, 2);
        final t = await _connected(state);
        final cache = InMemorySampleCache();
        // The phone already holds t=30 from an earlier sync.
        await cache.upsertSamples('A4F2', id, const [
          Sample(t: 30, tempsF10: [2000, 1600, null, 900]),
        ]);
        final session = (await t.sessions()).single;

        await SyncEngine().syncSession(
          t,
          bridgeId: 'A4F2',
          session: session,
          cache: cache,
        );

        final gaps = await cache.gaps('A4F2', id);
        expect(gaps, hasLength(1));
        expect(gaps.single.reason, GapReason.bufferRollover);
        expect(gaps.single.fromT, 30);
        expect(gaps.single.toT, 60);
        await t.close();
      },
    );

    test('a hole in the device stream is a permanent base-lost gap', () async {
      final state = FakeBridgeState();
      const id = 0x1A;
      state.recordCook(hours: 2); // t = 0, 30, … 7170
      // The base was lost for ~5 min: the bridge recorded nothing 300..600.
      state.cooks[id]!.removeWhere((r) => r.t >= 300 && r.t <= 600);
      final t = await _connected(state);
      final cache = InMemorySampleCache();
      final session = (await t.sessions()).single;

      await SyncEngine().syncSession(
        t,
        bridgeId: 'A4F2',
        session: session,
        cache: cache,
      );

      final gaps = await cache.gaps('A4F2', id);
      final hole = gaps.singleWhere((g) => g.reason == GapReason.baseLost);
      expect(hole.fromT, 270);
      expect(hole.toT, 630);
      expect(hole.reason.isPermanent, isTrue);
      expect(
        gaps.where((g) => g.reason == GapReason.connectivity),
        isEmpty,
        reason: 'a device-side hole must not be presented as recoverable',
      );
      await t.close();
    });
  });
}
