/// T3.2 — the streamed samples workhorse: four formats, range/stride/bucket
/// params, minmax envelopes, exact bucket counts, byte-identical bin, empty
/// (never 0) CSV fields for detached probes, and computed gaps.
library;

import 'dart:convert';
import 'dart:io';

import 'package:cookgen/cookgen.dart' as cg;
import 'package:sim/sim.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('24-hour fixture', () {
    late SimServer server;

    setUp(() async {
      final cook = cg.generateScenario('flat', seed: 5, hours: 24);
      server = await startServer(
        SimState(cook: cook, nowMs: pastEndClock(cook.samples.last.t)),
      );
    });

    test('returns exactly 960 buckets at bucket=90&agg=minmax', () async {
      final (code, body) = await getJson(
        server,
        '/api/v1/sessions/27/samples?bucket=90&agg=minmax&format=json',
      );
      expect(code, 200);
      final map = body! as Map;
      expect(map['count'], 960);
      expect(map['agg'], 'minmax');
      final series = map['series'] as List;
      expect(series, hasLength(4));
      for (final s in series) {
        expect((s as Map)['min'], hasLength(960));
        expect(s['mean'], hasLength(960));
        expect(s['max'], hasLength(960));
      }
      // The envelope is a real envelope.
      final pit = series.first as Map;
      for (var b = 0; b < 960; b++) {
        final lo = (pit['min'] as List)[b];
        final mid = (pit['mean'] as List)[b];
        final hi = (pit['max'] as List)[b];
        if (lo != null) {
          expect(lo as int, lessThanOrEqualTo(mid as int));
          expect(mid, lessThanOrEqualTo(hi as int));
        }
      }
      expect(map['gaps'], isEmpty, reason: 'no dropout in this fixture');
    });

    test('bucketed shape matches the samples-bucketed-gaps fixture', () async {
      final (_, body) = await getJson(
        server,
        '/api/v1/sessions/27/samples'
        '?from=0&to=900&bucket=90&agg=minmax&format=json&probes=1,2',
      );
      expectSameShape(body, fixtureJson('samples-bucketed-gaps.json'));
    });
  });

  group('brisket file', () {
    final path = '${repoRoot()}/protocol/fixtures/brisket-18h.smk';
    late SimServer server;

    setUp(() async {
      final state = SimState(
        cook: (() {
          final f = cg.SmkFile.read(path);
          return cg.GeneratedCook(
            header: f.header,
            samples: f.samples,
            marks: f.marks,
          );
        })(),
        nowMs: pastEndClock(cg.SmkFile.read(path).samples.last.t),
      );
      server = await startServer(state);
    });

    test('format=bin is byte-identical to the stored records', () async {
      final (code, bytes) = await getBytes(
        server,
        '/api/v1/sessions/27/samples?format=bin',
      );
      expect(code, 200);
      final file = File(path).readAsBytesSync();
      expect(bytes, file.sublist(256), reason: 'the raw 16-byte records');
    });

    test('csv: header line, detached probes as EMPTY fields', () async {
      final (code, text) = await getText(
        server,
        '/api/v1/sessions/27/samples?format=csv',
      );
      expect(code, 200);
      final lines = const LineSplitter().convert(text);
      expect(lines.first, 't_s,iso8601,p1_f,p2_f,p3_f,p4_f,billows,rssi');
      // The detach window (9 h → 9 h 40 m) has empty p4 fields.
      final inWindow = lines.where((l) {
        final t = int.tryParse(l.split(',').first) ?? -1;
        return t >= 9 * 3600 && t < 9 * 3600 + 2400;
      });
      expect(inWindow, isNotEmpty);
      for (final line in inWindow) {
        final p4 = line.split(',')[5];
        expect(p4, isEmpty, reason: 'detached is empty, never 0: $line');
      }
    });

    test('ndjson: one JSON object per line, nulls preserved', () async {
      final (code, text) = await getText(
        server,
        '/api/v1/sessions/27/samples?format=ndjson&from=32400&to=33000',
      );
      expect(code, 200);
      final lines = const LineSplitter().convert(text);
      expect(lines, isNotEmpty);
      for (final line in lines) {
        final obj = jsonDecode(line) as Map;
        expect(obj['temps_f10'], hasLength(4));
        expect((obj['temps_f10'] as List)[3], isNull);
      }
    });

    test('from/to/stride select and thin', () async {
      final (_, whole) = await getBytes(
        server,
        '/api/v1/sessions/27/samples?format=bin&from=0&to=3600',
      );
      final (_, strided) = await getBytes(
        server,
        '/api/v1/sessions/27/samples?format=bin&from=0&to=3600&stride=4',
      );
      expect(whole.length % 16, 0);
      expect(strided.length % 16, 0);
      expect(strided.length, lessThan(whole.length ~/ 3));
    });

    test('json format carries computed gaps (t deltas > 45 s)', () async {
      final (_, body) = await getJson(
        server,
        '/api/v1/sessions/27/samples?format=json',
      );
      final gaps = (body! as Map)['gaps'] as List;
      expect(gaps, isNotEmpty, reason: '~1% dropout in the brisket fixture');
      for (final g in gaps) {
        final gap = g as Map;
        expect((gap['to'] as int) - (gap['from'] as int), greaterThan(45));
      }
    });

    test('bad params are invalid_field, not a 500', () async {
      final (code, body) = await getJson(
        server,
        '/api/v1/sessions/27/samples?agg=zebra',
      );
      expect(code, 400);
      expect(((body! as Map)['error'] as Map)['code'], 'invalid_field');
    });
  });

  test('flaky scenario produces gaps that the A2.7 rule detects', () async {
    final state = scenarioState(
      'flaky',
      dropPct: 15,
      nowMs: pastEndClock(4 * 3600),
    );
    final server = await startServer(state);
    final (_, body) = await getJson(
      server,
      '/api/v1/sessions/27/samples?format=json',
    );
    final gaps = (body! as Map)['gaps'] as List;
    expect(gaps.length, greaterThan(5));
    // A2.7's exact boundary: every reported gap exceeds 45 s.
    for (final g in gaps) {
      final gap = g as Map;
      expect((gap['to'] as int) - (gap['from'] as int), greaterThan(45));
    }
  });
}
