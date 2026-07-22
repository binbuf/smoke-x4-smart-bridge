/// A2.7 — conversion round-trips without drift; gap boundaries exact at 45 s.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';

void main() {
  group('unit conversion', () {
    test('known anchor points', () {
      expect(c10ToF10(0), 320); // 0 °C = 32 °F
      expect(c10ToF10(1000), 2120); // 100 °C = 212 °F
      expect(c10ToF10(250), 770); // 25 °C = 77 °F
      expect(c10ToF10(-500), -580); // −50 °C = −58 °F (probe min)
      expect(f10ToC10(320), 0);
      expect(f10ToC10(2120), 1000);
      expect(f10ToC10(-580), -500);
    });

    test('C→F→C round-trips exactly across the whole probe range', () {
      // 0.1 °C is the coarser grid (0.18 °F), so storing °C sources as
      // canonical °F loses nothing: the write-path direction is lossless.
      for (var c10 = -500; c10 <= 3000; c10++) {
        expect(f10ToC10(c10ToF10(c10)), c10, reason: 'c10=$c10');
      }
    });

    test('F→C→F settles after one cycle — no cumulative drift', () {
      // °F→°C quantizes onto the coarser grid (±0.1 °F possible once), but
      // repeating the cycle must be a fixed point, never a drift.
      for (var f10 = -580; f10 <= 5720; f10++) {
        final once = c10ToF10(f10ToC10(f10));
        expect((once - f10).abs(), lessThanOrEqualTo(1), reason: 'f10=$f10');
        final twice = c10ToF10(f10ToC10(once));
        expect(twice, once, reason: 'f10=$f10 drifted on the second cycle');
      }
    });
  });

  group('gap detection', () {
    test('a delta of exactly 45 s is NOT a gap', () {
      expect(findGaps([0, 30, 75, 105]), isEmpty);
    });

    test('a delta of 46 s IS a gap, with exact boundaries', () {
      expect(findGaps([0, 30, 76, 106]), [(fromT: 30, toT: 76)]);
    });

    test('multiple gaps in one series', () {
      expect(
        findGaps([0, 30, 300, 330, 900]),
        [(fromT: 30, toT: 300), (fromT: 330, toT: 900)],
      );
    });

    test('a 30-minute dropout is one gap, boundaries intact', () {
      final ts = [
        for (var t = 0; t <= 600; t += 30) t,
        for (var t = 2400; t <= 3000; t += 30) t,
      ];
      expect(findGaps(ts), [(fromT: 600, toT: 2400)]);
    });

    test('degenerate inputs', () {
      expect(findGaps(const []), isEmpty);
      expect(findGaps(const [42]), isEmpty);
    });
  });
}
