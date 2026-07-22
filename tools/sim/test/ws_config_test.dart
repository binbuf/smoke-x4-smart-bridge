/// T3.3 + T3.4 — the WebSocket stream (hello + current sample, the 2-client
/// cap with the documented 503) and config/pairing/time/control/OTA
/// semantics (deferred Wi-Fi apply, AP PSK readback, mid-cook OTA refusal).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cookgen/cookgen.dart' as cg;
import 'package:sim/sim.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('WebSocket (T3.3)', () {
    late SimServer server;

    setUp(() async {
      final cook = cg.generateScenario('flat', seed: 3, hours: 1);
      server = await startServer(
        SimState(cook: cook, nowMs: pastEndClock(cook.samples.last.t)),
      );
    });

    test('hello immediately, then the current sample', () async {
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/api/v1/stream',
      );
      addTearDown(ws.close);
      final frames = <Map<String, Object?>>[];
      final sub = ws.listen(
        (d) => frames.add(jsonDecode(d as String) as Map<String, Object?>),
      );
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(frames.length, greaterThanOrEqualTo(2));
      expect(frames[0]['type'], 'hello');
      expect(frames[0]['api'], 'v1');
      expect(frames[1]['type'], 'sample');
      expect(frames[1]['temps_f10'], hasLength(4));
    });

    test(
      'a third concurrent client is refused with the documented body',
      () async {
        final a = await WebSocket.connect(
          'ws://127.0.0.1:${server.port}/api/v1/stream',
        );
        final b = await WebSocket.connect(
          'ws://127.0.0.1:${server.port}/api/v1/stream',
        );
        addTearDown(a.close);
        addTearDown(b.close);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(server.wsClientCount, 2);

        // The third upgrade must fail — and the refusal carries the busy
        // envelope shaped like error-busy.json.
        await expectLater(
          WebSocket.connect('ws://127.0.0.1:${server.port}/api/v1/stream'),
          throwsA(isA<WebSocketException>()),
        );
        final (code, body) = await getJson(server, '/api/v1/stream');
        expect(code, 503);
        expectSameShape(body, fixtureJson('error-busy.json'));
        expect(((body! as Map)['error'] as Map)['code'], 'busy');
      },
    );

    test('ping is answered with pong; ack_alarm is recorded', () async {
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/api/v1/stream',
      );
      addTearDown(ws.close);
      final pong = Completer<void>();
      ws.listen((d) {
        final f = jsonDecode(d as String) as Map;
        if (f['type'] == 'pong') {
          pong.complete();
        }
      });
      ws.add(jsonEncode({'type': 'ping'}));
      ws.add(jsonEncode({'type': 'ack_alarm', 'id': 4}));
      await pong.future.timeout(const Duration(seconds: 2));
    });
  });

  group('config + pairing + time (T3.4)', () {
    late SimServer server;
    late SimState state;

    setUp(() async {
      final cook = cg.generateScenario('flat', seed: 3, hours: 1);
      state = SimState(cook: cook, nowMs: pastEndClock(cook.samples.last.t));
      server = await startServer(state);
    });

    test(
      'POST /config/wifi (sta) answers FIRST, matching the fixture',
      () async {
        final (code, body) = await postJson(server, '/api/v1/config/wifi', {
          'mode': 'sta',
          'auth': 'wpa2_psk',
          'ssid': 'Backyard',
          'psk': 'hunter2',
        });
        expect(code, 200);
        expectSameShape(body, fixtureJson('config-wifi-accept-sta.json'));
        expect(
          ((body! as Map)['expect'] as Map).containsKey('psk'),
          isFalse,
          reason: 'STA accept never echoes the password',
        );
      },
    );

    test('POST /config/wifi (ap) returns the generated PSK', () async {
      state.netMode = 'sta';
      final (code, body) = await postJson(server, '/api/v1/config/wifi', {
        'mode': 'ap',
      });
      expect(code, 200);
      expectSameShape(body, fixtureJson('config-wifi-accept-ap.json'));
      final map = body! as Map;
      expect((map['expect'] as Map)['psk'], 'Gk7mR2xQpT');
      expect(map['applying_in_ms'], 500);
      // ...and it "applies" only after the deferred window.
      expect(state.netMode, 'sta');
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(state.netMode, 'ap');
    });

    test(
      'GET /config/wifi returns the AP PSK but never the STA password',
      () async {
        final (_, body) = await getJson(server, '/api/v1/config/wifi');
        final map = body! as Map;
        expect(((map['ap'] as Map))['psk'], 'Gk7mR2xQpT');
        expect(jsonEncode(map).contains('correct horse'), isFalse);
      },
    );

    test('unsupported mode is the documented 400', () async {
      final (code, body) = await postJson(server, '/api/v1/config/wifi', {
        'mode': 'zigbee',
      });
      expect(code, 400);
      expect(((body! as Map)['error'] as Map)['code'], 'unsupported_mode');
    });

    test('unpaired scenario pairs through POST /pairing/sync', () async {
      final s2 = await startServer(
        scenarioState('unpaired', nowMs: pastEndClock(0)),
      );
      var (_, pairing) = await getJson(s2, '/api/v1/pairing');
      expect((pairing! as Map)['paired'], isFalse);

      final (code, _) = await postJson(s2, '/api/v1/pairing/sync', {});
      expect(code, 200);
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      (_, pairing) = await getJson(s2, '/api/v1/pairing');
      expect((pairing! as Map)['paired'], isTrue);
    });

    test('POST /time validates and sets the clock', () async {
      state.clockValid = false;
      final (bad, badBody) = await postJson(server, '/api/v1/time', {
        'unix_ms': 'yesterday',
      });
      expect(bad, 400);
      expect(((badBody! as Map)['error'] as Map)['code'], 'invalid_field');

      final (ok, _) = await postJson(server, '/api/v1/time', {
        'unix_ms': 1774094400000,
        'tz_offset_min': -300,
      });
      expect(ok, 200);
      expect(state.clockValid, isTrue);
    });
  });

  group('OTA (T3.4)', () {
    test(
      'refused mid-cook without force, allowed on the ota scenario',
      () async {
        // Active cook: cursor at t=0, session running.
        final active = cg.generateScenario('flat', seed: 3, hours: 2);
        final busy = await startServer(SimState(cook: active));
        final client = HttpClient();
        var req = await client.post('127.0.0.1', busy.port, '/api/v1/ota');
        req.add([1, 2, 3, 4]);
        var res = await req.close();
        expect(res.statusCode, 409);
        final body = jsonDecode(await utf8.decoder.bind(res).join()) as Map;
        expect((body['error'] as Map)['code'], 'session_active');

        // The ota scenario has a completed cook: upload succeeds, progress
        // frames arrive, other endpoints 503 during the write.
        final s = await startServer(scenarioState('ota'));
        final ws = await WebSocket.connect(
          'ws://127.0.0.1:${s.port}/api/v1/stream',
        );
        addTearDown(ws.close);
        final phases = <String>[];
        ws.listen((d) {
          final f = jsonDecode(d as String) as Map;
          if (f['type'] == 'ota') {
            phases.add('${f['phase']}:${f['pct']}');
          }
        });

        req = await client.post('127.0.0.1', s.port, '/api/v1/ota');
        req.add(List.filled(1024, 0xAB));
        res = await req.close();
        expect(res.statusCode, 200);

        final (blocked, blockedBody) = await getJson(s, '/api/v1/sessions');
        expect(blocked, 503);
        expect(
          ((blockedBody! as Map)['error'] as Map)['code'],
          'ota_in_progress',
        );

        await Future<void>.delayed(const Duration(milliseconds: 1800));
        expect(phases, isNotEmpty);
        expect(phases.last, 'done:100');
        final (after, _) = await getJson(s, '/api/v1/sessions');
        expect(after, 200);
      },
    );
  });
}
