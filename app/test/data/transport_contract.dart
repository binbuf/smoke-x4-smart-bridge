/// A6.2 — the shared, capability-aware behavioural contract.
///
/// "The UI never knows how it is talking to the bridge" (08 §8.1) is the
/// claim the whole architecture rests on. This file is where that claim is
/// *checked*: one parameterised harness runs against `MockTransport`,
/// `HttpTransport`, and `BleTransport`, so the three cannot drift apart
/// unnoticed.
///
/// It is capability-AWARE rather than lowest-common-denominator. A
/// transport that says `fullHistory: false` is not excused from
/// `sessions()` — it is required to fail in the one typed way the UI
/// knows how to render. The flag and the behaviour are asserted together,
/// which is the only way a capability flag means anything.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/transport/ble_transport.dart'
    show BridgeUnsupportedException;
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';

/// Builds a connected, ready transport. Called fresh per test.
typedef TransportFactory = Future<BridgeTransport> Function();

void runTransportContract({
  required String name,
  required TransportFactory create,

  /// A session id the transport can serve, for the full-history cases.
  int? sessionId,
}) {
  group('transport contract [$name]', () {
    test('capabilities are internally consistent', () async {
      final t = await create();
      final c = t.capabilities;
      // Anything that can serve a 2-hour preview can serve live state;
      // anything that can take an OTA can serve full history. Neither
      // combination has ever made sense; asserting it stops a future
      // transport from declaring one.
      if (c.historyPreview) {
        expect(c.liveState, isTrue);
      }
      if (c.ota) {
        expect(c.fullHistory, isTrue);
      }
      await t.close();
    });

    test('status() identifies the bridge', () async {
      final t = await create();
      final s = await t.status();
      expect(s.deviceId, isNotEmpty);
      expect(s.numProbes, anyOf(2, 4));
      await t.close();
    });

    test('live() gives four slots, and a detached probe is null', () async {
      final t = await create();
      final live = await t.live();
      expect(live.tempsF10, hasLength(4));
      // THE invariant, on every transport: a detached probe must surface
      // as null. Zero is a real temperature and a real trap.
      expect(live.tempsF10.where((v) => v == 0), isEmpty);
      await t.close();
    });

    test('sessions() honours the fullHistory capability', () async {
      final t = await create();
      if (t.capabilities.fullHistory) {
        expect(await t.sessions(), isA<List<CookSession>>());
      } else {
        // Typed, so the UI renders "full history needs Wi-Fi" instead of
        // an error dialog — the notice A3.1 built for this moment.
        expect(() => t.sessions(), throwsA(isA<BridgeUnsupportedException>()));
      }
      await t.close();
    });

    test('samples() honours the fullHistory capability', () async {
      final t = await create();
      if (!t.capabilities.fullHistory) {
        expect(
          () => t.samples(sessionId ?? 1).toList(),
          throwsA(isA<BridgeUnsupportedException>()),
        );
      } else if (sessionId != null) {
        final batches = await t.samples(sessionId).toList();
        expect(batches, isNotEmpty);
      }
      await t.close();
    });

    test('close() releases without throwing', () async {
      final t = await create();
      await t.close();
    });
  });
}
