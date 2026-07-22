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

  test('GET /status matches the status.json fixture shape', () async {
    final (code, body) = await getJson(server, '/api/v1/status');
    expect(code, 200);
    expectSameShape(body, fixtureJson('status.json'));
  });

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
