import 'package:smoke_bridge/data/ble/ble_transport.dart';
import 'package:smoke_bridge/data/cache/sample_cache.dart';
import 'package:smoke_bridge/data/dto/records.g.dart';
import 'package:smoke_bridge/data/repo/sync_engine.dart';
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
}
