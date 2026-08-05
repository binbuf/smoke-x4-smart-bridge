/// Holes in the recording, and the difference between the two kinds
/// (newapp §E.5).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/analysis/gaps.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';

Sample _s(int t) => Sample(t: t, tempsF10: const [700, null, null, null]);

void main() {
  group('rollover detection', () {
    test('a contiguous device buffer is not a rollover', () {
      expect(
        detectRollover(highWaterT: 100, deviceMinT: 0, deviceMaxT: 500),
        isNull,
      );
      expect(
        detectRollover(highWaterT: 100, deviceMinT: 101, deviceMaxT: 500),
        isNull,
        reason: 'minT == highWater + 1 joins cleanly',
      );
    });

    test('a device whose oldest sample is past our mark is a rollover', () {
      final gap = detectRollover(
        highWaterT: 100,
        deviceMinT: 400,
        deviceMaxT: 900,
      );
      expect(gap, isNotNull);
      expect(gap!.reason, GapReason.bufferRollover);
      expect(gap.fromT, 100);
      expect(gap.toT, 400);
      expect(gap.durationS, 300);
    });

    test('a phone that never synced this session has nothing to lose', () {
      expect(
        detectRollover(highWaterT: -1, deviceMinT: 400, deviceMaxT: 900),
        isNull,
        reason:
            'it has no claim on the earlier data — the device is simply '
            'serving what it has, and inventing a permanent hole here would '
            'tell a first-time user data was destroyed',
      );
    });

    test('an unknown device minimum never invents a hole', () {
      expect(
        detectRollover(highWaterT: 100, deviceMinT: null, deviceMaxT: 900),
        isNull,
      );
    });

    test('an empty buffer is not a rollover', () {
      expect(
        detectRollover(highWaterT: 100, deviceMinT: 400, deviceMaxT: 300),
        isNull,
      );
    });
  });

  group('the two reasons say different things', () {
    test('only rollover is permanent', () {
      expect(GapReason.bufferRollover.isPermanent, isTrue);
      expect(GapReason.connectivity.isPermanent, isFalse);
    });

    test('the connectivity explanation promises the data is coming', () {
      expect(GapReason.connectivity.explanation, contains('next sync'));
    });

    test('the rollover explanation does not', () {
      expect(GapReason.bufferRollover.explanation, contains('gone for good'));
      expect(GapReason.bufferRollover.explanation, isNot(contains('sync')));
    });
  });

  group('connectivity gaps inside what we hold', () {
    test('a cadence-sized step is not a gap', () {
      final gaps = detectConnectivityGaps(
        [_s(0), _s(30), _s(60), _s(90)],
        samplePeriodS: 30,
      );
      expect(gaps, isEmpty);
    });

    test('a thirty-minute dropout is one gap with exact bounds', () {
      final gaps = detectConnectivityGaps(
        [_s(0), _s(30), _s(1830), _s(1860)],
        samplePeriodS: 30,
      );
      expect(gaps.length, 1);
      expect(gaps.single.fromT, 30);
      expect(gaps.single.toT, 1830);
      expect(gaps.single.reason, GapReason.connectivity);
    });

    test('the threshold scales with the cook’s own cadence', () {
      // A session retained at 5-minute buckets must not read as one continuous
      // dropout — the exact failure the derived threshold exists to prevent.
      final coarse = [for (var i = 0; i < 10; i++) _s(i * 300)];
      expect(detectConnectivityGaps(coarse, samplePeriodS: 300), isEmpty);
      expect(
        detectConnectivityGaps(coarse, samplePeriodS: 30),
        isNotEmpty,
        reason: 'the same series at 30 s cadence would be all holes',
      );
    });

    test('degenerate inputs return nothing rather than throwing', () {
      expect(detectConnectivityGaps(const []), isEmpty);
      expect(detectConnectivityGaps([_s(0)]), isEmpty);
      expect(detectConnectivityGaps([_s(0), _s(30)], samplePeriodS: 0),
          isEmpty);
    });
  });
}
