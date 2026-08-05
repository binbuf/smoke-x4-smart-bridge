/// T3.1 — /status, /live, /sessions served from a fixture; responses match
/// the P2.3 fixtures byte-for-byte in shape; /live emits null — never 0 —
/// for a detached probe.
library;

import 'package:cookgen/cookgen.dart';
import 'package:sim/sim.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late SimServer server;

  setUp(() async {
    final cook = GeneratedCook(
      header: SmkFile.read(
        '${repoRoot()}/protocol/fixtures/brisket-18h.smk',
      ).header,
      samples: SmkFile.read(
        '${repoRoot()}/protocol/fixtures/brisket-18h.smk',
      ).samples,
      marks: SmkFile.read(
        '${repoRoot()}/protocol/fixtures/brisket-18h.smk',
      ).marks,
    );
    final endT = cook.samples.last.t;
    server = await startServer(SimState(cook: cook, nowMs: pastEndClock(endT)));
  });

  test('GET /debug/novelty serves plain text novelty lines (F4.4)', () async {
    final (code, text) = await getText(server, '/api/v1/debug/novelty');
    expect(code, 200);
    // The on-device line format: <t_ms> <reason> <value> <payload>.
    expect(text, contains(' sync '));
    expect(text, contains(' first state26 '));
    final lines = text.trim().split('\n');
    for (final line in lines) {
      expect(RegExp(r'^\d+ \w+ ').hasMatch(line), isTrue, reason: line);
    }
  });

  test('GET /status matches the status.json fixture shape', () async {
    final (code, body) = await getJson(server, '/api/v1/status');
    expect(code, 200);
    expectSameShape(body, fixtureJson('status.json'));
  });

  test(
    '/cook-clock: unset until the app confirms, adjustable, clearable',
    () async {
      // A replayed cook is running and samples are on "flash" — and the clock
      // is STILL unset, because recording and "a cook is happening" are
      // different claims and only the app can make the second one.
      var (code, body) = await getJson(server, '/api/v1/cook-clock');
      expect(code, 200);
      expect((body! as Map)['set'], isFalse);
      // null, never 0: zero is a cook that started this instant.
      expect((body as Map)['elapsed_s'], isNull);

      // "The cook is already five minutes in."
      (code, body) = await postJson(server, '/api/v1/cook-clock', {
        'elapsed_s': 300,
      });
      expect(code, 200);
      expect((body! as Map)['elapsed_s'], 300);

      // Re-posting ADJUSTS rather than conflicting — the app corrects the
      // start time mid-cook.
      (code, body) = await postJson(server, '/api/v1/cook-clock', {
        'elapsed_s': 7200,
      });
      expect(code, 200);
      expect((body! as Map)['elapsed_s'], 7200);

      // Exactly one field, and the bound is the device's 99:59.
      (code, _) = await postJson(server, '/api/v1/cook-clock', {});
      expect(code, 400);
      (code, _) = await postJson(server, '/api/v1/cook-clock', {
        'elapsed_s': 10,
        'started_unix_ms': 1774094400000,
      });
      expect(code, 400);
      (code, _) = await postJson(server, '/api/v1/cook-clock', {
        'elapsed_s': kCookClockMaxElapsedS + 1,
      });
      expect(code, 400);

      // DELETE blanks it and is idempotent.
      (code, body) = await deleteJson(server, '/api/v1/cook-clock');
      expect(code, 200);
      expect((body! as Map)['set'], isFalse);
      (code, _) = await deleteJson(server, '/api/v1/cook-clock');
      expect(code, 200);
    },
  );

  test('GET /live matches the live fixture shape', () async {
    final (code, body) = await getJson(server, '/api/v1/live?window=7200');
    expect(code, 200);
    final live = body! as Map;
    final fixture = fixtureJson('live-two-detached.json')! as Map;
    // Top level + recent shape.
    expect(live.keys.toSet(), fixture.keys.toSet());
    expectSameShape(live['recent'], fixture['recent']);
    expectSameShape(live['billows'], fixture['billows']);
    // Probes come in two shapes (attached/detached) — compare per form.
    final attachedTemplate = (fixture['probes'] as List).firstWhere(
      (p) => p['attached'] == true,
    );
    final detachedTemplate = (fixture['probes'] as List).firstWhere(
      (p) => p['attached'] == false,
    );
    for (final p in live['probes'] as List) {
      final probe = p as Map;
      if (probe['attached'] == true) {
        expect(
          probe.keys.toSet().difference({
            ...attachedTemplate.keys,
            'eta_s',
            'state',
            'min_f10',
            'max_f10',
          }),
          isEmpty,
          reason: 'unexpected attached-probe keys',
        );
        expect(probe['temp_f10'], isNotNull);
      } else {
        expect(probe.keys.toSet(), detachedTemplate.keys.toSet());
        expect(probe['temp_f10'], isNull);
      }
    }
  });

  test('a detached probe is null, NEVER 0 — anywhere in /live', () async {
    final detached = scenarioState('detached', nowMs: pastEndClock(7200));
    final s = await startServer(detached);
    final (_, body) = await getJson(s, '/api/v1/live?window=7200');
    final live = body! as Map;
    for (final p in live['probes'] as List) {
      final probe = p as Map;
      if (probe['attached'] == false) {
        expect(probe['temp_f10'], isNull);
        expect(probe['temp_f10'], isNot(0));
      }
    }
    final series = (live['recent'] as Map)['series'] as List;
    for (final probeSeries in series) {
      if (probeSeries == null) {
        continue;
      }
      for (final v in probeSeries as List) {
        expect(v, isNot(0), reason: 'a detached sample must be null, not 0');
      }
    }
  });

  test('GET /sessions lists the cook', () async {
    final (code, body) = await getJson(server, '/api/v1/sessions');
    expect(code, 200);
    final sessions = (body! as Map)['sessions'] as List;
    expect(sessions, hasLength(1));
    final s = sessions.single as Map;
    expect(s['id'], 27);
    expect(s['name'], 'Brisket 18h (synthetic)');
    expect(s['closed'], isTrue);
    expect(s['sample_count'], greaterThan(2000));
  });

  test('unknown session is the documented 404 envelope', () async {
    final (code, body) = await getJson(server, '/api/v1/sessions/999');
    expect(code, 404);
    expectSameShape(body, fixtureJson('error-session_not_found.json'));
  });

  test('every error is JSON — even a bad route', () async {
    final (code, body) = await getJson(server, '/api/v1/nope');
    expect(code, 404);
    expect((body! as Map)['error'], isNotNull);
  });

  test('captive-portal shims answer (05 §5.8.1)', () async {
    final (c1, _) = await getText(server, '/generate_204');
    expect(c1, 204);
    final (c2, t2) = await getText(server, '/ncsi.txt');
    expect(c2, 200);
    expect(t2, 'Microsoft NCSI');
    final (c3, t3) = await getText(server, '/hotspot-detect.html');
    expect(c3, 200);
    expect(t3, contains('Success'));
  });
}
