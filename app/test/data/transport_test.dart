/// N15 — the transport, connection, sync and cache layers.
///
/// Pure Dart (`package:test`), so this runs in both `flutter test` and
/// `dart test test/data`. The HTTP half runs against a real loopback server
/// ([FakeBridgeServer]); the connection half runs against [MockTransport]
/// with injected failures, so failover is deterministic.
library;

import 'dart:async';

import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

import '../support/fake_bridge_server.dart';

class FakeTransportFactory implements TransportFactory {
  final Map<String, BridgeTransport Function()> http = {};
  BridgeTransport Function()? ble;
  final List<String> opened = [];

  @override
  Future<BridgeTransport?> openHttp(String host) async {
    opened.add('http:$host');
    return http[host]?.call();
  }

  @override
  Future<BridgeTransport?> openBle() async {
    opened.add('ble');
    return ble?.call();
  }
}

MockTransport _ok(String label, {TransportKind kind = TransportKind.http}) =>
    MockTransport(kind: kind, label: label);

MockTransport _failing(String label) {
  final t = _ok(label);
  t.device.failWith['status'] = const TransportException('network', 'no route');
  return t;
}

void main() {
  group('HttpTransport', () {
    late FakeBridgeServer server;
    late HttpTransport transport;

    setUp(() async {
      server = FakeBridgeServer();
      await server.start();
      transport = HttpTransport(baseUrl: server.baseUrl, token: 'secret-token');
    });

    tearDown(() async {
      await transport.close();
      await server.stop();
    });

    test('parses status identity, power, session and cook clock', () async {
      final s = await transport.status();
      expect(s.device.id, '480001');
      expect(s.device.fw, '1.4.2');
      expect(s.power.socPct, 71);
      expect(s.session.active, isTrue);
      expect(s.session.id, 1);
      expect(s.cookClock.set, isTrue);
      expect(s.cookClock.elapsedS, 60);
      expect(s.net.mode, 'ap');
      expect(s.pairing.paired, isTrue);
    });

    test('parses live probes and folds detached as null', () async {
      final live = await transport.live(windowS: 600);
      expect(live.t, 60);
      expect(live.probes, hasLength(1));
      expect(live.probes.first.role, ProbeRole.food);
      expect(live.probes.first.tempF10, 1100);
      expect(live.probes.first.rateFPerHr, 4.2);
      expect(server.requests, contains(('GET', '/api/v1/live')));
    });

    test('sessions and streamed ndjson samples with a from filter', () async {
      final sessions = await transport.sessions();
      expect(sessions, hasLength(1));
      expect(sessions.first.id, 1);
      expect(sessions.first.samplePeriodS, 30);

      final batches = await transport
          .samples(1, fromT: 30)
          .expand((b) => b)
          .toList();
      expect(batches.map((s) => s.t), [30, 60]);
      expect(batches.first.tempsF10, [1050, null, null, 2210]);
      expect(batches.first.billows, isTrue);
    });

    test('marks read and write, app-only kinds map to wire note', () async {
      final marks = await transport.marks(1);
      expect(marks.single.kind, MarkKind.wrapped);
      expect(marks.single.probe, 1);

      final posted = await transport.postMark(
        1,
        kind: MarkKind.spritz,
        probe: 2,
        text: 'mist',
      );
      // The device has no spritz slot; it is stored as a note today.
      expect(posted.kind, MarkKind.note);
      expect(posted.text, 'mist');
    });

    test('applyNetwork carries the password as a transient argument', () async {
      final res = await transport.applyNetwork(
        mode: 'sta',
        ssid: 'HomeNet-5G',
        psk: 'hunter2',
      );
      expect(res['accepted'], isTrue);
      expect(res['mode'], 'sta');
    });

    test('maps the protocol error envelope to a named exception', () async {
      server.failStatus = true;
      await expectLater(
        transport.status(),
        throwsA(
          isA<TransportException>()
              .having((e) => e.code, 'code', 'busy')
              .having((e) => e.status, 'status', 503)
              .having((e) => e.isDeviceRefusal, 'refusal', isTrue),
        ),
      );
    });

    test('sends the Bearer token', () async {
      await transport.status();
      expect(server.lastAuthHeader, 'Bearer secret-token');
    });

    test('streams hello and sample frames over the websocket', () async {
      final frames = await transport.events().take(2).toList();
      expect(frames.first.type, 'hello');
      expect(frames.last.type, 'sample');
      final sample = frames.last.toSample();
      expect(sample.t, 90);
      expect(sample.tempsF10, [1200, null, null, 2250]);
      expect(sample.unixMs, 1700000090000);
      expect(sample.billows, isTrue);
    });

    test('cook-clock round-trips and refuses two anchors', () async {
      final set = await transport.setCookClock(elapsedS: 42);
      expect(set.elapsedS, 42);
      final cleared = await transport.clearCookClock();
      expect(cleared.set, isFalse);
    });
  });

  group('MockTransport', () {
    test('records calls and consumes a status plan', () async {
      final t = MockTransport();
      t.device.statusPlan.addAll([
        const TransportException('timeout', 'first try'),
        {
          'device': {'id': 'late'},
        },
      ]);
      await expectLater(t.status(), throwsA(isA<TransportException>()));
      final s = await t.status();
      expect(s.device.id, 'late');
      expect(t.statusCount, 2);
    });

    test('sample frames parse into jack-aware samples', () {
      final event = TransportEvent('sample', {
        't': 12,
        'temp_f10': 1234,
        'probe': 2,
      });
      final sample = event.toSample();
      expect(sample.t, 12);
      expect(sample.tempsF10, [null, 1234, null, null]);
    });

    test('injected failures are named', () async {
      final t = MockTransport();
      t.device.failWith['live'] = const TransportException('busy', 'later');
      await expectLater(
        t.live(),
        throwsA(
          isA<TransportException>().having((e) => e.code, 'code', 'busy'),
        ),
      );
    });
  });

  group('ConnectionManager', () {
    test('a lane wins on status 200 and losers are closed', () async {
      final bad = _failing('cached');
      final good = _ok('mdns');
      final factory = FakeTransportFactory();
      factory.http['10.0.0.5'] = () => bad;
      factory.http['smokebridge.local'] = () => good;
      final manager = ConnectionManager(factory: factory, cachedIp: '10.0.0.5');

      final winner = await manager.raceOnce();
      expect(winner, same(good));
      expect(bad.closed, isTrue, reason: 'the failed lane must not leak');
      expect(good.closed, isFalse);
      expect(manager.attempts.map((a) => a.outcome), [
        ConnectionAttemptOutcome.probing,
        ConnectionAttemptOutcome.failed,
        ConnectionAttemptOutcome.probing,
        ConnectionAttemptOutcome.won,
      ]);
      await manager.dispose();
    });

    test('manual lane outranks the rest', () async {
      final manual = _ok('manual');
      final mdns = _ok('mdns');
      final factory = FakeTransportFactory();
      factory.http['192.168.1.9'] = () => manual;
      factory.http['smokebridge.local'] = () => mdns;
      final manager = ConnectionManager(
        factory: factory,
        manualBaseUrl: 'http://192.168.1.9',
        cachedIp: '10.0.0.5',
      );
      final winner = await manager.raceOnce();
      expect(winner, same(manual));
      expect(factory.opened, ['http:192.168.1.9']);
      await manager.dispose();
    });

    test('falls through to BLE when every HTTP lane misses', () async {
      final ble = _ok('ble', kind: TransportKind.ble);
      final factory = FakeTransportFactory()..ble = () => ble;
      final manager = ConnectionManager(factory: factory);
      final winner = await manager.raceOnce();
      expect(winner, same(ble));
      await manager.dispose();
    });

    test('backoff is spent between failed passes', () async {
      final factory = FakeTransportFactory();
      final slept = <Duration>[];
      final manager = ConnectionManager(
        factory: factory,
        sleep: (d) async => slept.add(d),
      );
      final winner = await manager.connect(maxPasses: 3);
      expect(winner, isNull);
      expect(slept, [const Duration(seconds: 1), const Duration(seconds: 2)]);
      await manager.dispose();
    });

    test('can skip the BLE lane', () async {
      final ble = _ok('ble', kind: TransportKind.ble);
      final factory = FakeTransportFactory()..ble = () => ble;
      final manager = ConnectionManager(factory: factory);
      expect(await manager.raceOnce(includeBle: false), isNull);
      expect(factory.opened, isNot(contains('ble')));
      await manager.dispose();
    });
  });

  group('ConnectionSupervisor', () {
    test('auto leads on BLE then upgrades to Wi-Fi, BLE held warm', () async {
      final ble = _ok('ble', kind: TransportKind.ble);
      final wifi = _ok('wifi');
      final factory = FakeTransportFactory();
      factory.ble = () => ble;
      factory.http['smokebridge.local'] = () => wifi;
      final supervisor = ConnectionSupervisor(
        manager: ConnectionManager(factory: factory),
        factory: factory,
      );

      final active = await supervisor.start();
      expect(active, same(wifi));
      expect(supervisor.active!.kind, TransportKind.http);
      expect(supervisor.bleWarm, isTrue);
      expect(ble.closed, isFalse, reason: 'warm, not closed');
      expect(supervisor.current.activeLabel, 'wifi');
      await supervisor.dispose();
    });

    test('wifi preference never opens BLE', () async {
      final wifi = _ok('wifi');
      final factory = FakeTransportFactory();
      factory.ble = () => _ok('ble', kind: TransportKind.ble);
      factory.http['smokebridge.local'] = () => wifi;
      final supervisor = ConnectionSupervisor(
        manager: ConnectionManager(factory: factory),
        factory: factory,
        preferred: TransportPreference.wifi,
      );
      final active = await supervisor.start();
      expect(active, same(wifi));
      expect(factory.opened, isNot(contains('ble')));
      await supervisor.dispose();
    });

    test('failover from a dead Wi-Fi to the warm BLE', () async {
      final ble = _ok('ble', kind: TransportKind.ble);
      final wifi = _ok('wifi');
      final factory = FakeTransportFactory();
      factory.ble = () => ble;
      factory.http['smokebridge.local'] = () => wifi;
      final supervisor = ConnectionSupervisor(
        manager: ConnectionManager(factory: factory),
        factory: factory,
      );
      await supervisor.start();
      expect(await supervisor.verifyActive(), isTrue);

      wifi.device.failWith['status'] = const TransportException(
        'network',
        'wifi dropped',
      );
      expect(await supervisor.verifyActive(), isFalse);
      final next = await supervisor.failover();
      expect(next, same(ble));
      expect(supervisor.active!.kind, TransportKind.ble);
      expect(supervisor.bleWarm, isFalse);
      await supervisor.dispose();
    });
  });

  group('SyncEngine + InMemorySampleCache', () {
    final bridge = 'X4-480001';

    test('first sync backfills, the second is idempotent', () async {
      final cache = InMemorySampleCache();
      final device = MockBridgeDevice(
        samples: {
          1: const [
            Sample(t: 0, tempsF10: [1000, null, null, 2200]),
            Sample(t: 30, tempsF10: [1010, null, null, 2210]),
            Sample(t: 60, tempsF10: [1020, null, null, 2220]),
          ],
        },
      );
      final transport = MockTransport(device: device);

      final first = await SyncEngine().syncSession(
        transport,
        bridgeId: bridge,
        session: MockBridgeDevice.defaultSession,
        cache: cache,
      );
      expect(first.inserted, 3);
      expect(await cache.sampleCount(bridge, 1), 3);

      final second = await SyncEngine().syncSession(
        transport,
        bridgeId: bridge,
        session: MockBridgeDevice.defaultSession,
        cache: cache,
      );
      expect(second.fetched, 0);
      expect(second.inserted, 0);
      expect(await cache.sampleCount(bridge, 1), 3);
    });

    test('a cached row is never rewritten (I10)', () async {
      final cache = InMemorySampleCache();
      await cache.upsertSamples(bridge, 1, const [
        Sample(t: 0, tempsF10: [1111]),
      ]);
      await cache.upsertSamples(bridge, 1, const [
        Sample(t: 0, tempsF10: [9999]),
      ]);
      final rows = await cache.samples(bridge, 1);
      expect(rows.single.tempsF10.single, 1111);
    });

    test('rollover records a permanent gap before upsert', () async {
      final cache = InMemorySampleCache();
      await cache.upsertSamples(bridge, 1, const [
        Sample(t: 0, tempsF10: [1]),
        Sample(t: 30, tempsF10: [2]),
      ]);
      final device = MockBridgeDevice(
        samples: {
          1: const [
            Sample(t: 100, tempsF10: [3]),
            Sample(t: 130, tempsF10: [4]),
          ],
        },
      );

      final result = await SyncEngine().syncSession(
        MockTransport(device: device),
        bridgeId: bridge,
        session: MockBridgeDevice.defaultSession,
        cache: cache,
      );
      expect(result.rollover, isNotNull);
      expect(result.rollover!.reason, GapReason.bufferRollover);
      expect(result.rollover!.fromT, 30);
      expect(result.rollover!.toT, 100);
      expect(await cache.gaps(bridge, 1), hasLength(1));
      expect(await cache.maxT(bridge, 1), 130);
    });

    test('a closed, fully cached session is skipped', () async {
      final cache = InMemorySampleCache();
      await cache.upsertSamples(bridge, 1, const [
        Sample(t: 0, tempsF10: [1]),
        Sample(t: 60, tempsF10: [2]),
      ]);
      const session = SessionInfo(
        id: 1,
        name: 'done',
        startedUnixMs: 1000000,
        endedUnixMs: 1060000,
        samplePeriodS: 30,
        sampleCount: 2,
        numProbes: 4,
        probes: [],
        closed: true,
        pinned: false,
        markCount: 0,
      );
      final result = await SyncEngine().syncSession(
        MockTransport(),
        bridgeId: bridge,
        session: session,
        cache: cache,
      );
      expect(result.skipped, isTrue);
      expect(result.fetched, 0);
    });

    test('connectivity gaps are recorded for a jump in cadence', () async {
      final cache = InMemorySampleCache();
      final device = MockBridgeDevice(
        samples: {
          1: const [
            Sample(t: 0, tempsF10: [1]),
            Sample(t: 30, tempsF10: [2]),
            Sample(t: 200, tempsF10: [3]),
            Sample(t: 230, tempsF10: [4]),
          ],
        },
      );
      await SyncEngine().syncSession(
        MockTransport(device: device),
        bridgeId: bridge,
        session: MockBridgeDevice.defaultSession,
        cache: cache,
      );
      final gaps = await cache.gaps(bridge, 1);
      expect(gaps.single.reason, GapReason.connectivity);
      expect(gaps.single.fromT, 30);
      expect(gaps.single.toT, 200);
    });
  });

  group('cook membership and CSV', () {
    test('samplesInWindow selects by wall clock, not session seconds', () {
      const samples = [
        Sample(t: 0, tempsF10: [1]),
        Sample(t: 10, tempsF10: [2]),
        Sample(t: 20, tempsF10: [3]),
      ];
      final window = samplesInWindow(
        samples,
        sessionStartedUnixMs: 1000,
        startUnixMs: 1000,
        endUnixMs: 11000,
      );
      expect(window.map((s) => s.t), [0, 10]);
    });

    test('no clock means no membership (I11)', () {
      const samples = [
        Sample(t: 0, tempsF10: [1]),
      ];
      expect(
        samplesInWindow(samples, sessionStartedUnixMs: null, startUnixMs: 0),
        isEmpty,
      );
    });

    test('cache CSV is byte-compatible with the device format', () async {
      final cache = InMemorySampleCache();
      await cache.upsertSamples('b', 1, const [
        Sample(
          t: 0,
          tempsF10: [680, null, null, 920],
          billows: true,
          rssi: -60,
        ),
      ]);
      final csv = await exportCookCsvFromCache(
        cache: cache,
        bridgeId: 'b',
        sessionId: 1,
        sessionStartedUnixMs: 1700000000000,
        startUnixMs: 1700000000000,
      );
      final lines = csv.trim().split('\n');
      expect(lines.first, cookCsvHeader);
      expect(lines[1], '0,2023-11-14T22:13:20.000Z,68.0,,,92.0,1,-60');
    });
  });

  group('BridgeSession', () {
    test('start runs status → sync → live and caches the backfill', () async {
      final cache = InMemorySampleCache();
      final device = MockBridgeDevice(
        samples: {
          1: const [
            Sample(t: 0, tempsF10: [1000]),
          ],
        },
      );
      final session = BridgeSession(
        transport: MockTransport(device: device),
        bridgeId: 'X4-480001',
        cache: cache,
        statusPollInterval: const Duration(hours: 1),
      );
      addTearDown(session.stop);

      await session.start();
      expect(session.status!.session.id, 1);
      expect(session.live!.probes, hasLength(1));
      expect(await cache.sampleCount('X4-480001', 1), 1);
    });

    test('a pushed sample is cached and emitted', () async {
      final cache = InMemorySampleCache();
      final transport = MockTransport();
      final session = BridgeSession(
        transport: transport,
        bridgeId: 'b',
        cache: cache,
        statusPollInterval: const Duration(hours: 1),
      );
      addTearDown(session.stop);
      await session.start();

      final seen = <Sample>[];
      final sub = session.samples.listen(seen.add);
      transport.emitSample(
        const Sample(t: 999, tempsF10: [1234], unixMs: 1700000999000),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      expect(seen.single.t, 999);
      expect(await cache.sampleCount('b', 1), 1);
    });

    test('a failed status poll raises link loss', () async {
      final transport = MockTransport();
      final session = BridgeSession(
        transport: transport,
        bridgeId: 'b',
        cache: InMemorySampleCache(),
        statusPollInterval: const Duration(hours: 1),
      );
      addTearDown(session.stop);
      await session.start();

      final lost = session.linkLost.first;
      transport.device.failWith['status'] = const TransportException(
        'network',
        'gone',
      );
      expect(await session.pollStatus(), isFalse);
      await lost;
    });
  });
}
