/// A7: the candidate race (each lane winning, manual pre-emption,
/// all-fail → offline, cache updates), TXT parsing incl. malformed
/// advertisements, and the exact backoff ladder under a fake clock.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/transport/connection_manager.dart';
import 'package:smoke_bridge/data/transport/discovery.dart';

class _FakeDiscovery implements DiscoverySource {
  _FakeDiscovery(this.bridges);
  final List<DiscoveredBridge> bridges;

  @override
  Stream<DiscoveredBridge> discover() => Stream.fromIterable(bridges);
}

/// The fake clock: records every asked delay; delays matching `hold` (all
/// of them by default) stay open until released, the rest complete
/// instantly. Race-timeout delays must ALWAYS be held in these tests —
/// an instantly-completing timeout would race the async probes and turn
/// Offline into a coin flip (and reconnect() into a busy loop).
class _FakeDelay {
  _FakeDelay({bool Function(Duration)? hold}) : _hold = hold ?? ((_) => true);

  final bool Function(Duration) _hold;
  final asked = <Duration>[];
  final _gates = <Completer<void>>[];

  Future<void> call(Duration d) {
    asked.add(d);
    if (!_hold(d)) {
      return Future.value();
    }
    final gate = Completer<void>();
    _gates.add(gate);
    return gate.future;
  }

  void releaseAll() {
    for (final g in _gates) {
      if (!g.isCompleted) {
        g.complete();
      }
    }
    _gates.clear();
  }
}

void main() {
  Map<String, Uint8List?> txt(Map<String, String> m) =>
      m.map((k, v) => MapEntry(k, Uint8List.fromList(v.codeUnits)));

  group('TXT parsing', () {
    test('full advertisement', () {
      final b = bridgeFromTxt(
        '192.168.1.50',
        80,
        txt({
          'id': 'A4F2',
          'fw': '1.0.0',
          'probes': '4',
          'paired': '1',
          'session': '27',
          'mode': 'sta',
        }),
      );
      expect(b.id, 'A4F2');
      expect(b.probes, 4);
      expect(b.paired, isTrue);
      expect(b.cooking, isTrue);
      expect(b.sessionId, 27);
      expect(b.baseUrl, 'http://192.168.1.50');
    });

    test('missing and unknown keys default; malformed degrades', () {
      final b = bridgeFromTxt(
        'h',
        8080,
        txt({'probes': 'not-a-number', 'future_key': 'whatever'}),
      );
      expect(b.probes, 0);
      expect(b.paired, isFalse);
      expect(b.cooking, isFalse);
      expect(b.baseUrl, 'http://h:8080');
      // A null value (nsd delivers those) must not throw either.
      final c = bridgeFromTxt('h', 80, {'id': null});
      expect(c.id, '');
    });
  });

  group('the race', () {
    test('cached IP wins the happy path and refreshes the cache', () async {
      final cached = <String>[];
      final mgr = ConnectionManager(
        probe: (url) async => url == 'http://10.0.0.7',
        writeCache: (url) async => cached.add(url),
        cachedBaseUrl: 'http://10.0.0.7',
        delay: _FakeDelay().call,
      );
      final outcome = await mgr.race();
      expect(outcome, isA<Connected>());
      final c = outcome as Connected;
      expect(c.lane, ConnectionLane.cachedIp);
      expect(cached, ['http://10.0.0.7']);
    });

    test('the mDNS lane wins when the cache is cold', () async {
      final mgr = ConnectionManager(
        probe: (url) async => url == 'http://192.168.1.60',
        writeCache: (_) async {},
        discovery: _FakeDiscovery(const [
          DiscoveredBridge(host: '192.168.1.60', port: 80, id: 'A4F2'),
        ]),
        delay: _FakeDelay().call,
      );
      final outcome = await mgr.race();
      expect((outcome as Connected).lane, ConnectionLane.mdns);
    });

    test('the AP default wins when only the AP answers', () async {
      final mgr = ConnectionManager(
        probe: (url) async => url == 'http://192.168.4.1',
        writeCache: (_) async {},
        delay: _FakeDelay().call,
      );
      final outcome = await mgr.race();
      expect((outcome as Connected).lane, ConnectionLane.apDefault);
    });

    test('manual entry pre-empts a race in flight', () async {
      final probing = Completer<void>();
      final mgr = ConnectionManager(
        probe: (url) async {
          if (url == 'http://172.16.0.9') {
            return true; // only the manual address works
          }
          if (!probing.isCompleted) {
            probing.complete();
          }
          await Completer<void>().future; // every other lane hangs
          return false;
        },
        writeCache: (_) async {},
        cachedBaseUrl: 'http://10.0.0.7',
        delay: _FakeDelay().call, // holds: only MANUAL can end this race
      );
      final raceF = mgr.race();
      await probing.future; // the race is genuinely in flight
      mgr.enterManual('http://172.16.0.9');
      final outcome = await raceF;
      expect((outcome as Connected).lane, ConnectionLane.manual);
      expect(outcome.baseUrl, 'http://172.16.0.9');
    });

    test('an empty discovery stream degrades silently', () async {
      final mgr = ConnectionManager(
        probe: (url) async => url == 'http://192.168.4.1',
        writeCache: (_) async {},
        discovery: _FakeDiscovery(const []),
        delay: _FakeDelay().call,
      );
      final outcome = await mgr.race();
      expect((outcome as Connected).lane, ConnectionLane.apDefault);
    });

    test('all lanes failing falls to offline', () async {
      final mgr = ConnectionManager(
        probe: (_) async => false,
        writeCache: (_) async {},
        cachedBaseUrl: 'http://10.0.0.7',
        delay: _FakeDelay().call,
      );
      expect(await mgr.race(), isA<Offline>());
    });
  });

  group('reconnect backoff (A7.3)', () {
    test('the ladder is exactly 1,2,4,8,15,30 then capped', () {
      expect(
        [for (var i = 0; i < 8; i++) backoffDelay(i).inSeconds],
        [1, 2, 4, 8, 15, 30, 30, 30],
      );
    });

    test('reconnect retries on the ladder and returns on success', () async {
      var calls = 0;
      // Hold the 99 s race timeouts (Offline must come from the
      // deterministic all-lanes-done path); ladder waits tick instantly.
      final delay = _FakeDelay(hold: (d) => d.inSeconds == 99);
      final mgr = ConnectionManager(
        probe: (url) async {
          if (url != 'http://192.168.4.1') {
            return false;
          }
          calls++;
          return calls >= 4; // succeed on the 4th race
        },
        writeCache: (_) async {},
        delay: delay.call,
      );
      final c = await mgr.reconnect(raceTimeout: const Duration(seconds: 99));
      expect(c.lane, ConnectionLane.apDefault);
      expect(calls, 4);
      final waits = delay.asked.where((d) => d.inSeconds != 99).toList();
      expect(waits.map((d) => d.inSeconds), [1, 2, 4]);
      delay.releaseAll();
    });

    test('a connectivity event mid-wait reconnects immediately', () async {
      var calls = 0;
      // EVERY delay is held: the fake clock never advances, so the only
      // thing that can possibly end the backoff wait is the kick.
      final delay = _FakeDelay(); // default: every delay held
      final connectivity = StreamController<void>.broadcast();
      final mgr = ConnectionManager(
        probe: (url) async {
          if (url != 'http://192.168.4.1') {
            return false;
          }
          calls++;
          return calls >= 2; // fail once, succeed after the kick
        },
        writeCache: (_) async {},
        delay: delay.call,
        connectivityChanges: connectivity.stream,
      );
      final f = mgr.reconnect();
      // Let the first race fail (Offline via all-lanes-done, no clock
      // needed) and the backoff wait engage.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 1);
      connectivity.add(null); // the kick — with time frozen
      final c = await f;
      expect(c.lane, ConnectionLane.apDefault);
      expect(calls, 2);
      delay.releaseAll();
      await connectivity.close();
    });
  });
}
