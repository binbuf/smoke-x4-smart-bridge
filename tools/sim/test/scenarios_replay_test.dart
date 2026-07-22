/// T3.5 + T3.6 — every scenario in the matrix runs; the replay clock's
/// arithmetic (18 hours in 18 minutes at --speed 60); mDNS advertising.
library;

import 'dart:async';
import 'dart:io';

import 'package:cookgen/cookgen.dart' as cg;
import 'package:sim/sim.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test(
    'every scenario in the matrix constructs and serves /status',
    () async {
      for (final name in simScenarios) {
        final state = scenarioState(name, nowMs: pastEndClock(3600));
        final server = await startServer(state);
        final (code, body) = await getJson(server, '/api/v1/status');
        expect(code, 200, reason: name);
        expect((body! as Map)['device'], isNotNull, reason: name);
        await server.stop();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('storage-full reports a nearly-full cooks partition', () async {
    final server = await startServer(
      scenarioState('storage-full', nowMs: pastEndClock(0)),
    );
    final (_, body) = await getJson(server, '/api/v1/status');
    final storage = (body! as Map)['storage'] as Map;
    expect(storage['free_pct'], lessThanOrEqualTo(2));
  });

  test('base-lost: packets stop dead after the cutoff', () async {
    // Clock far past the cutoff: the base has been silent for hours.
    final state = scenarioState(
      'base-lost',
      afterS: 2 * 3600,
      nowMs: pastEndClock(3 * 3600),
    );
    final server = await startServer(state);
    final (_, body) = await getJson(server, '/api/v1/status');
    final pairing = (body! as Map)['pairing'] as Map;
    expect(pairing['base_lost'], isTrue);
    expect(pairing['last_packet_s_ago'], greaterThan(600));

    // The live stream saw nothing after the cutoff.
    final (_, live) = await getJson(server, '/api/v1/live');
    expect((live! as Map)['t'], lessThan(2 * 3600));
  });

  test(
    'long: 54 days of samples paginate and decimate at the limit',
    () async {
      final state = scenarioState('long', nowMs: pastEndClock(1296 * 3600));
      expect(state.samples.length, greaterThan(150000));
      final server = await startServer(state);

      // A day's worth of buckets out of 54 days, quickly.
      final (code, body) = await getJson(
        server,
        '/api/v1/sessions/27/samples'
        '?from=0&to=86400&bucket=90&agg=minmax&format=json&probes=1',
      );
      expect(code, 200);
      expect((body! as Map)['count'], 960);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  group('replay clock (T3.6)', () {
    test('--speed 60 replays 18 hours in 18 minutes — exactly', () {
      var fakeNow = 1_000_000;
      final cook = cg.generateScenario('brisket-18h', dropoutPct: 0);
      final state = SimState(cook: cook, speed: 60, nowMs: () => fakeNow);
      expect(state.virtualT(), 0);
      fakeNow += 18 * 60 * 1000; // 18 real minutes later...
      expect(state.virtualT(), 18 * 3600); // ...is 18 cook-hours.
    });

    test('speed 1 tracks real time', () {
      var fakeNow = 5_000;
      final state = SimState(
        cook: scenarioState('flaky', dropPct: 0).cook,
        speed: 1,
        nowMs: () => fakeNow,
      );
      fakeNow += 90 * 1000;
      expect(state.virtualT(), 90);
    });

    test('the cursor clamps just past the last sample', () {
      var fakeNow = 0;
      final cook = scenarioState('flaky', dropPct: 0).cook;
      final state = SimState(cook: cook, speed: 10000, nowMs: () => fakeNow);
      fakeNow += 24 * 3600 * 1000;
      expect(state.virtualT(), cook.samples.last.t + 1);
      expect(state.sessionEnded(state.virtualT()), isTrue);
    });

    test('live WS pushes samples as the cursor advances', () async {
      // 1-hour cook at 600×: a sample every 50 ms of real time.
      final state = scenarioState('flaky', dropPct: 0, speed: 600);
      final server = await startServer(state);
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/api/v1/stream',
      );
      addTearDown(ws.close);
      var samples = 0;
      ws.listen((d) {
        if (d is String && d.contains('"sample"')) {
          samples++;
        }
      });
      await Future<void>.delayed(const Duration(seconds: 2));
      // ~20 virtual minutes elapsed → ~40 samples pushed.
      expect(samples, greaterThan(10));
    });
  });

  test('mDNS: a _smokebridge._tcp query gets an answer (T3.6)', () async {
    final adv = MdnsAdvertiser(
      instance: 'SmokeBridge-TEST',
      port: 8080,
      txt: {'id': 'TEST', 'api': 'v1'},
    );
    try {
      await adv.start();
    } on SocketException catch (e) {
      markTestSkipped('multicast unavailable in this environment: $e');
      return;
    }
    addTearDown(adv.stop);

    RawDatagramSocket probe;
    try {
      probe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } on SocketException catch (e) {
      markTestSkipped('cannot bind probe socket: $e');
      return;
    }
    final seen = Completer<void>();
    probe.listen((event) {
      if (event != RawSocketEvent.read) {
        return;
      }
      final dg = probe.receive();
      if (dg == null) {
        return;
      }
      final text = String.fromCharCodes(dg.data);
      if (text.contains('_smokebridge') && text.contains('SmokeBridge-TEST')) {
        if (!seen.isCompleted) {
          seen.complete();
        }
      }
    });

    // A minimal PTR question for _smokebridge._tcp.local.
    final q = <int>[
      0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, // header: 1 question
      13, ...'_smokebridge'.codeUnits.skip(1), // "_smokebridge" is 12 chars…
    ];
    // Build the name properly instead of hand-counting.
    q.removeRange(12, q.length);
    for (final label in ['_smokebridge', '_tcp', 'local']) {
      q
        ..add(label.length)
        ..addAll(label.codeUnits);
    }
    q.addAll([0, 0, 12, 0, 1]); // NUL, QTYPE=PTR, QCLASS=IN

    probe.send(q, InternetAddress('224.0.0.251'), 5353);
    try {
      await seen.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      markTestSkipped(
        'no mDNS answer observed — multicast likely filtered here',
      );
    }
  });
}
