/// V3.2 — the recorder resumes across a kill, and the report's four
/// criteria are computed the way they will be at the bench.
library;

import 'dart:convert';
import 'dart:io';

import 'package:soak/soak.dart';
import 'package:test/test.dart';

/// A synthesised /status + /debug/tasks pair with tunable heap and stack.
class FakeBridge {
  FakeBridge({
    this.baseFree = 92160,
    this.baseMin = 82000,
    this.baseBlock = 40960,
    this.slopePerCall = 0,
    this.worstMargin = 1200,
  });

  final int baseFree;
  final int baseMin;
  final int baseBlock;
  final int slopePerCall;
  final int worstMargin;
  int _call = 0;
  int packetsOk = 100;

  Future<Map<String, Object?>> fetch(String path) async {
    if (path == '/api/v1/status') {
      packetsOk += 3;
      return {
        'device': {'uptime_s': _call * 30, 'fw': '1.0.0'},
        'radio': {'packets_ok': packetsOk, 'packets_bad': 0},
        'storage': {'used_b': 94208 + _call * 512},
        'session': {'active': true},
        'ota': {'gate': 'not_applicable'},
        'alarms': <Object?>[],
      };
    }
    final free = baseFree + slopePerCall * _call;
    final min = baseMin + slopePerCall * _call;
    _call++;
    return {
      'heap': {
        'free_b': free,
        'min_free_b': min,
        'largest_free_block_b': baseBlock,
      },
      'tasks': [
        {'name': 'ws_push', 'stack_b': 4096, 'margin_b': worstMargin},
        {'name': 'app_ui', 'stack_b': 4096, 'margin_b': 1500},
      ],
    };
  }
}

void main() {
  group('recorder (V3.2)', () {
    test(
      'survives a mid-run kill without losing or duplicating a sample',
      () async {
        final dir = Directory.systemTemp.createTempSync('soak');
        addTearDown(() => dir.deleteSync(recursive: true));
        final trace = '${dir.path}/t.ndjson';

        // First "process": writes 5 samples, then is "killed".
        var bridge = FakeBridge();
        var rec = Recorder(fetch: bridge.fetch, tracePath: trace);
        var seq = rec.lastSeqOnDisk() + 1;
        for (var i = 0; i < 5; i++) {
          await rec.pollOnce(seq++);
        }

        // A torn final line, as a real kill mid-write would leave.
        File(trace).writeAsStringSync('{"seq":5,"wall', mode: FileMode.append);

        // Second "process": resumes. The torn line is neither counted nor
        // duplicated, and the sequence continues.
        bridge = FakeBridge();
        rec = Recorder(fetch: bridge.fetch, tracePath: trace);
        final resume = rec.lastSeqOnDisk() + 1;
        expect(resume, 5, reason: 'the torn line 5 does not count');
        for (var i = 0; i < 5; i++) {
          await rec.pollOnce(resume + i);
        }

        final samples = Recorder.readTrace(trace);
        expect(samples.map((s) => s.seq), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
        // No duplicate seq, no gap.
        expect(samples.map((s) => s.seq).toSet().length, samples.length);
      },
    );

    test('a torn line is dropped, not fatal', () {
      final dir = Directory.systemTemp.createTempSync('soak');
      addTearDown(() => dir.deleteSync(recursive: true));
      final trace = '${dir.path}/t.ndjson';
      File(trace).writeAsStringSync(
        '${jsonEncode({'seq': 0, 'wall_ms': 0})}\n{"seq":1,"wa',
      );
      final samples = Recorder.readTrace(trace);
      expect(samples, hasLength(1));
      expect(samples.single.seq, 0);
    });
  });

  group('report (V3.2 → V3.3)', () {
    // 24 h at 30 s = 2,880 samples.
    List<SoakSample> trace({
      required int baseFree,
      required int baseMin,
      required int baseBlock,
      required double slopePerHour,
      required int worstMargin,
      double noiseAmpB = 0,
    }) {
      const n = 2880;
      const stepMs = 30000;
      final out = <SoakSample>[];
      for (var i = 0; i < n; i++) {
        final h = i * stepMs / 3600000.0;
        // A deterministic zero-mean wobble, so "noise" is not a leak.
        final noise = noiseAmpB * (i.isEven ? 1 : -1);
        final free = (baseFree + slopePerHour * h + noise).round();
        out.add(
          SoakSample(
            seq: i,
            wallMs: i * stepMs,
            uptimeS: i * 30,
            freeHeap: free,
            minFreeHeap: baseMin,
            largestFreeBlock: baseBlock,
            packetsOk: 100 + i * 3,
            packetsBad: 0,
            storageUsedB: 94208 + i * 16,
            reconnects: 0,
            wsDrops: 0,
            alarms: 0,
            sessionActive: true,
            fw: '1.0.0',
            gate: 'not_applicable',
            tasks: [
              TaskRow(name: 'ws_push', stackB: 4096, marginB: worstMargin),
              const TaskRow(name: 'app_ui', stackB: 4096, marginB: 1500),
            ],
          ),
        );
      }
      return out;
    }

    test('a healthy soak passes all four', () {
      final r = evaluate(
        trace(
          baseFree: 92160,
          baseMin: 82000,
          baseBlock: 40960,
          slopePerHour: -50,
          worstMargin: 1200,
        ),
      );
      expect(r.pass, isTrue);
      expect(r.criteria.every((c) => c.pass), isTrue);
      expect(r.durationH, closeTo(24, 0.1));
    });

    test('a 6 KB/day leak fails the slope, and equal noise does not', () {
      // -6 KB/day = -256 B/h, exactly the floor; go past it.
      final leaking = evaluate(
        trace(
          baseFree: 120000,
          baseMin: 82000,
          baseBlock: 40960,
          slopePerHour: -300, // ~7.2 KB/day
          worstMargin: 1200,
        ),
      );
      final slopeCrit = leaking.criteria.firstWhere(
        (c) => c.name == 'free_heap slope',
      );
      expect(
        slopeCrit.pass,
        isFalse,
        reason: 'a real leak is a slope the regression sees',
      );

      // The SAME amplitude of movement, but zero-mean noise rather than a
      // trend. This is the whole reason the slope is computed rather than
      // differenced: a before/after pair cannot tell these apart.
      final noisy = evaluate(
        trace(
          baseFree: 120000,
          baseMin: 82000,
          baseBlock: 40960,
          slopePerHour: 0,
          worstMargin: 1200,
          noiseAmpB: 4000,
        ),
      );
      final noiseSlope = noisy.criteria.firstWhere(
        (c) => c.name == 'free_heap slope',
      );
      expect(
        noiseSlope.pass,
        isTrue,
        reason: 'noise of the same amplitude is not a leak',
      );
    });

    test('a single dip below the heap floor fails the floor', () {
      final t = trace(
        baseFree: 120000,
        baseMin: 82000,
        baseBlock: 40960,
        slopePerHour: 0,
        worstMargin: 1200,
      );
      // One sample below 80 KB — a floor is a floor.
      final dipped = [...t];
      dipped[1440] = SoakSample(
        seq: t[1440].seq,
        wallMs: t[1440].wallMs,
        uptimeS: t[1440].uptimeS,
        freeHeap: t[1440].freeHeap,
        minFreeHeap: 79 * 1024,
        largestFreeBlock: t[1440].largestFreeBlock,
        packetsOk: t[1440].packetsOk,
        packetsBad: 0,
        storageUsedB: t[1440].storageUsedB,
        reconnects: 0,
        wsDrops: 0,
        alarms: 0,
        sessionActive: true,
        fw: '1.0.0',
        gate: 'not_applicable',
        tasks: t[1440].tasks,
      );
      final r = evaluate(dipped);
      final floor = r.criteria.firstWhere(
        (c) => c.name == 'min_free_heap floor',
      );
      expect(floor.pass, isFalse);
    });

    test('a task at 400 B of margin fails the stack criterion', () {
      final r = evaluate(
        trace(
          baseFree: 120000,
          baseMin: 82000,
          baseBlock: 40960,
          slopePerHour: 0,
          worstMargin: 400,
        ),
      );
      final stack = r.criteria.firstWhere(
        (c) => c.name == 'task stack headroom',
      );
      expect(stack.pass, isFalse);
      expect(r.worstTask, 'ws_push');
    });

    test('fragmentation fails even when total free heap is healthy', () {
      // R2: 90 KB free but the largest block under 32 KB cannot allocate
      // a TLS buffer, and every heap total still looks fine.
      final r = evaluate(
        trace(
          baseFree: 120000,
          baseMin: 90 * 1024,
          baseBlock: 24 * 1024,
          slopePerHour: 0,
          worstMargin: 1200,
        ),
      );
      final frag = r.criteria.firstWhere(
        (c) => c.name == 'largest_free_block floor',
      );
      expect(frag.pass, isFalse);
    });

    test(
      'the report renders the same verdict from a file as from memory',
      () async {
        final dir = Directory.systemTemp.createTempSync('soak');
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = '${dir.path}/t.ndjson';
        final samples = trace(
          baseFree: 92160,
          baseMin: 82000,
          baseBlock: 40960,
          slopePerHour: -50,
          worstMargin: 1200,
        );
        final sink = File(path).openWrite();
        for (final s in samples) {
          sink.writeln(jsonEncode(s.toJson()));
        }
        await sink.close();
        final fromFile = evaluate(Recorder.readTrace(path));
        final fromMem = evaluate(samples);
        expect(fromFile.pass, fromMem.pass);
        expect(fromFile.minFreeHeapFloorB, fromMem.minFreeHeapFloorB);
        expect(renderMarkdown(fromFile), renderMarkdown(fromMem));
      },
    );
  });
}
