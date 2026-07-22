import 'dart:io';

import 'package:bridge_protocol/bridge_protocol.dart';
import 'package:cookgen/cookgen.dart';
import 'package:test/test.dart';

void main() {
  group('determinism', () {
    test('same seed → byte-identical output', () {
      final a = generateScenario('brisket-18h', seed: 42);
      final b = generateScenario('brisket-18h', seed: 42);
      expect(a.smkBytes(), b.smkBytes());
      expect(a.mrkBytes(), b.mrkBytes());
    });

    test('different seed → different bytes', () {
      final a = generateScenario('brisket-18h', seed: 42);
      final b = generateScenario('brisket-18h', seed: 43);
      expect(a.smkBytes(), isNot(equals(b.smkBytes())));
    });
  });

  group('thermal model (T2.1)', () {
    final cook = generateScenario('flat', seed: 7, hours: 4);
    final pit = [
      for (final s in cook.samples)
        if (s.tempOrNull(0) != null) s.temp[0] / 10.0,
    ];

    test('pit trace has plausible variance and stays in band', () {
      // Skip the come-up; judge the steady state.
      final steady = pit.skip(pit.length ~/ 4).toList();
      final mean = steady.reduce((a, b) => a + b) / steady.length;
      final varSum = steady.fold<double>(
        0,
        (a, v) => a + (v - mean) * (v - mean),
      );
      final sigma = varSum / steady.length;
      expect(mean, inInclusiveRange(230, 265));
      expect(sigma, greaterThan(0.05), reason: 'a real pit wanders');
      expect(sigma, lessThan(120), reason: 'but not wildly');
      expect(steady.every((v) => v > 200 && v < 300), isTrue);
    });

    test('food probe converges asymptotically toward pit', () {
      final food = [
        for (final s in cook.samples)
          if (s.tempOrNull(1) != null) s.temp[1] / 10.0,
      ];
      // Gap to pit shrinks monotonically-ish over quarters, never overshoots.
      double gapAt(double frac) {
        final i = (food.length * frac).floor().clamp(0, food.length - 1);
        return pit[i] - food[i];
      }

      expect(gapAt(0.1), greaterThan(gapAt(0.4)));
      expect(gapAt(0.4), greaterThan(gapAt(0.9)));
      expect(
        food.every((v) => v < 300),
        isTrue,
        reason: 'never above pit band',
      );
      // Early slope is much steeper than late slope (asymptotic approach).
      final early = food[20] - food[10];
      final late = food[food.length - 10] - food[food.length - 20];
      expect(early, greaterThan(late));
    });
  });

  group('event repertoire (T2.2)', () {
    test('stall: |slope| < 2 °F/hr sustained inside the window', () {
      final cook = generateScenario('stall', seed: 42);
      // Window 2 h → 5 h; probe 1 (Brisket). Compare 30-min-apart samples.
      final byT = {for (final s in cook.samples) s.t: s};
      final mid = 3 * 3600 + 1800;
      final a = byT[mid]!.temp[1] / 10.0;
      final b = byT[mid + 1800]!.temp[1] / 10.0;
      final slopePerHr = (b - a) * 2;
      expect(slopePerHr.abs(), lessThan(2));
      expect(a, inInclusiveRange(140, 180));
    });

    test('lid-open: pit drops ≥ 25 °F within 3 min and recovers ≥ 50 %', () {
      final cook = generateScenario('lid-open', seed: 42);
      final byT = {for (final s in cook.samples) s.t: s};
      final before = byT[3570]!.temp[0] / 10.0;
      final low = byT[3600 + 120]!.temp[0] / 10.0; // full drop by +2 min
      expect(before - low, greaterThanOrEqualTo(25));
      final after = byT[3600 + 1200]!.temp[0] / 10.0; // +20 min
      expect(after - low, greaterThanOrEqualTo((before - low) * 0.5));
    });

    test('detach: sentinel on the wire, never 0', () {
      final cook = generateScenario('detached', seed: 42);
      final inWindow = cook.samples
          .where((s) => s.t >= 1800 && s.t < 3600)
          .toList();
      expect(inWindow, isNotEmpty);
      for (final s in inWindow) {
        expect(s.temp[1], tempDetached);
        expect(s.tempOrNull(1), isNull);
        expect(s.temp[1], isNot(0));
      }
      // Outside the window the probe reads again.
      final after = cook.samples.firstWhere((s) => s.t >= 3630);
      expect(after.tempOrNull(1), isNotNull);
    });

    test('dropout: omitted samples leave t-deltas > 45 s', () {
      final cook = generateScenario('flat', seed: 42, dropoutPct: 5);
      var gaps = 0;
      for (var i = 1; i < cook.samples.length; i++) {
        final dt = cook.samples[i].t - cook.samples[i - 1].t;
        expect(dt % 30, 0, reason: 'gaps are whole missing periods');
        if (dt > 45) gaps++;
      }
      expect(gaps, greaterThan(0));
    });

    test('celsius switch: flag flips exactly once, values have no cliff', () {
      final cook = generateScenario('celsius', seed: 42);
      var flips = 0;
      for (var i = 1; i < cook.samples.length; i++) {
        final was = cook.samples[i - 1].sourceCelsius;
        final now = cook.samples[i].sourceCelsius;
        if (was != now) {
          flips++;
          // Canonical °F on both sides of the switch: no unit cliff.
          final delta = (cook.samples[i].temp[0] - cook.samples[i - 1].temp[0])
              .abs();
          expect(delta, lessThan(50), reason: 'no 20°-looking cliff');
        }
      }
      expect(flips, 1);
    });
  });

  group('emission (T2.3)', () {
    test('brisket-18h validates end-to-end through the wire format', () {
      final cook = generateScenario('brisket-18h', seed: 42);
      final bytes = cook.smkBytes();
      final parsed = SmkFile.parse(bytes);

      expect(parsed.header.magicOk, isTrue);
      expect(parsed.header.crcOk, isTrue);
      expect(parsed.header.recLen, 16);
      expect(parsed.header.sampleCount, cook.samples.length);
      expect(parsed.samples.length, cook.samples.length);
      for (final s in parsed.samples) {
        expect(s.crcOk, isTrue);
      }
      // Monotonic t.
      for (var i = 1; i < parsed.samples.length; i++) {
        expect(parsed.samples[i].t, greaterThan(parsed.samples[i - 1].t));
      }
      // ~18 h at 30 s with ~1% dropout.
      expect(parsed.samples.length, inInclusiveRange(2050, 2161));
      // The detached window is sentinels, never zeros.
      final detachWindow = parsed.samples.where(
        (s) => s.t >= 9 * 3600 && s.t < 9 * 3600 + 2400,
      );
      expect(detachWindow.every((s) => s.temp[3] == tempDetached), isTrue);
    });

    test('committed fixture matches regeneration (seed 42)', () {
      final fixture = File('../../protocol/fixtures/brisket-18h.smk');
      expect(
        fixture.existsSync(),
        isTrue,
        reason:
            'regenerate with: dart run cookgen --scenario brisket-18h '
            '--seed 42 --out protocol/fixtures/brisket-18h.smk',
      );
      final cook = generateScenario('brisket-18h', seed: 42);
      expect(fixture.readAsBytesSync(), cook.smkBytes());
      final mrk = File('../../protocol/fixtures/brisket-18h.mrk');
      expect(mrk.readAsBytesSync(), cook.mrkBytes());
    });

    test('marks carry UTF-8 text and valid CRCs', () {
      final cook = generateScenario('brisket-18h', seed: 42);
      expect(cook.marks.length, 4);
      for (final m in cook.marks) {
        final decoded = MarkRec.decode(m.encode());
        expect(decoded.crcOk, isTrue);
      }
      expect(cook.marks[1].text, 'wrapped');
      expect(cook.marks[1].kindEnum, MarkKind.wrapped);
    });
  });
}
