/// N1.10–N1.14 — the analysis engines.
///
/// The null cases are the ones that matter: a rate from too few samples, an ETA
/// with a named refusal, a stall with hysteresis, time-in-band that excludes
/// gap time, and a chart that splits runs before decimating.
library;

import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

List<TempPoint> _constant({
  required int count,
  required double f,
  int start = 0,
  int step = 30,
}) => [for (var i = 0; i < count; i++) (t: start + i * step, f: f)];

void main() {
  group('N1.10 rate of change', () {
    test('an OLS slope over the 10-minute window', () {
      // 0.03 °F every 30 s = 3.6 °F/hr.
      final series = <TempPoint>[
        for (var i = 0; i < 21; i++) (t: i * 30, f: 100 + i * 0.03),
      ];
      expect(rateOfChange(series), closeTo(3.6, 0.01));
    });

    test('null on too few valid samples', () {
      final series = <TempPoint>[
        for (var i = 0; i < 5; i++) (t: i * 30, f: 100.0),
      ];
      expect(rateOfChange(series), isNull);
    });

    test('null when the window spans a gap over two minutes', () {
      final series = <TempPoint>[
        for (var i = 0; i < 12; i++) (t: i * 30, f: 100.0),
        (t: 500, f: 101.0),
      ];
      expect(rateOfChange(series), isNull);
    });

    test('the ±0.6 °F/hr display floor reads as ~0', () {
      expect(formatRate(null), isNull);
      expect(formatRate(0.4), '~0° F/hr');
      expect(formatRate(-0.4), '~0° F/hr');
      expect(formatRate(6.2), '+6.2° F/hr');
      expect(formatRate(-2), '-2.0° F/hr');
    });
  });

  group('N1.11 ETA', () {
    final food = <TempPoint>[
      for (var i = 0; i < 61; i++) (t: i * 30, f: 100 + i * 0.5),
    ];
    final pit = _constant(count: 61, f: 250);

    test('a 15-minute-rounded range, not a false-precision number', () {
      final result = etaToTarget(food: food, pit: pit, targetF: 200);
      expect(result, isA<EtaRange>());
      final range = result as EtaRange;
      expect(range.low.inSeconds % 900, 0);
      expect(range.high.inSeconds % 900, 0);
      expect(range.high, greaterThanOrEqualTo(range.low));
    });

    test('refuses with insufficient history', () {
      final short = <TempPoint>[
        for (var i = 0; i < 10; i++) (t: i * 30, f: 100.0),
      ];
      expect(
        etaToTarget(food: short, pit: pit, targetF: 200),
        const EtaUnavailable(EtaUnavailableReason.insufficientHistory),
      );
    });

    test('refuses a target at or above the pit', () {
      expect(
        etaToTarget(food: food, pit: pit, targetF: 300),
        const EtaUnavailable(EtaUnavailableReason.targetAtOrAbovePit),
      );
    });

    test('refuses while stalled', () {
      expect(
        etaToTarget(food: food, pit: pit, targetF: 200, stalled: true),
        const EtaUnavailable(EtaUnavailableReason.stalled),
      );
    });

    test('refuses a slope too flat to project', () {
      final flat = <TempPoint>[
        for (var i = 0; i <= 40; i++) (t: i * 30, f: 100.0),
        for (var i = 41; i < 61; i++) (t: i * 30, f: 100 + (i - 40) * 0.005),
      ];
      expect(
        etaToTarget(food: flat, pit: pit, targetF: 200),
        const EtaUnavailable(EtaUnavailableReason.slopeTooFlat),
      );
    });

    test('refuses when the probe moves away from the target', () {
      final falling = <TempPoint>[
        for (var i = 0; i <= 40; i++) (t: i * 30, f: 100 + i * 0.1),
        for (var i = 41; i < 61; i++) (t: i * 30, f: 104 - (i - 40) * 0.5),
      ];
      expect(
        etaToTarget(food: falling, pit: pit, targetF: 200),
        const EtaUnavailable(EtaUnavailableReason.notApproaching),
      );
    });
  });

  group('N1.12 stall detector', () {
    test('enters after 30 min of |slope| < 2 in the 140–180 band', () {
      final detector = StallDetector();
      var stalled = false;
      for (var t = 0; t <= 3600; t += 30) {
        stalled = detector.add(t, 155);
      }
      expect(stalled, isTrue);
      expect(detector.stalled, isTrue);
    });

    test('exits after 15 min over 4 °F/hr', () {
      final detector = StallDetector();
      for (var t = 0; t <= 3600; t += 30) {
        detector.add(t, 155);
      }
      expect(detector.stalled, isTrue);
      var stalled = true;
      for (var t = 3630; t <= 5400; t += 30) {
        stalled = detector.add(t, 155 + (t - 3600) / 30 * 0.5);
      }
      expect(stalled, isFalse);
    });

    test('a non-food role never stalls', () {
      final detector = StallDetector(role: ProbeRole.pit);
      for (var t = 0; t <= 3600; t += 30) {
        expect(detector.add(t, 155), isFalse);
      }
    });
  });

  group('N1.13 cook stats', () {
    test('duration, gaps, pit stats and time-in-band exclude gap time', () {
      final samples = <Sample>[
        for (final t in [0, 30, 60, 90, 120, 210, 240, 270, 300])
          Sample(t: t, tempsF10: [1000 + t, null, null, 2500]),
      ];
      final stats = cookStats(
        samples,
        marks: [const Mark(t: 100, kind: MarkKind.lidOpen)],
        probeConfig: const [
          Probe(
            jack: ProbeJack.four,
            role: ProbeRole.pit,
            alarmMinF10: 2250,
            alarmMaxF10: 2750,
          ),
          Probe(jack: ProbeJack.one, role: ProbeRole.food),
        ],
      );

      expect(stats.durationS, 300);
      expect(stats.sampleCount, 9);
      expect(stats.gaps, hasLength(1));
      expect(stats.gapSecondsTotal, 90);
      expect(stats.observedS, 210);
      expect(stats.pitMeanF, 250);
      expect(stats.pitStdDevF, 0);
      expect(stats.pitMinF, 250);
      expect(stats.pitMaxF, 250);
      // Gap interval 120→210 is skipped; everything else is in band.
      expect(stats.timeInBandS, 210);
      expect(stats.lidEvents, 1);

      final detached = stats.probes.firstWhere((p) => p.jack == ProbeJack.two);
      expect(detached.samples, 0);
      expect(detached.peakF, isNull, reason: 'detached is null, never 0 (I3)');

      final food = stats.probes.firstWhere((p) => p.jack == ProbeJack.one);
      expect(food.peakF, 130);
    });

    test('an empty session has no fabricated numbers', () {
      final stats = cookStats(const []);
      expect(stats.durationS, 0);
      expect(stats.pitMeanF, isNull);
      expect(stats.stallDurationS, isNull);
      expect(stats.probes, isEmpty);
    });
  });

  group('N1.14 decimation and chart series', () {
    test('LTTB keeps the endpoints and reduces the count', () {
      final data = <({int t, double f})>[
        for (var i = 0; i < 100; i++) (t: i, f: i.toDouble()),
      ];
      final out = lttb(data, 10);
      expect(out, hasLength(10));
      expect(out.first.t, 0);
      expect(out.last.t, 99);
    });

    test('runs are split at gaps before decimation', () {
      final samples = <Sample>[
        for (final t in [0, 30, 60, 90, 120, 600, 630, 660])
          Sample(t: t, tempsF10: [1000, null, null, null]),
      ];
      final model = buildChartSeries(
        samples,
        fromT: 0,
        toT: 700,
        probes: [ProbeJack.one, ProbeJack.two],
      );
      final one = model.series.firstWhere((s) => s.jack == ProbeJack.one);
      expect(one.runs, hasLength(2));
      expect(one.runs.first.toT, 120);
      expect(one.runs.last.fromT, 600);

      final two = model.series.firstWhere((s) => s.jack == ProbeJack.two);
      expect(two.isEmpty, isTrue, reason: 'detached probe has no points');
      expect(model.gaps, hasLength(1));
    });

    test('a wide range gets a min/max envelope', () {
      final samples = <Sample>[
        for (var i = 0; i < 1300; i++)
          Sample(t: i * 30, tempsF10: [1000 + (i % 50), null, null, null]),
      ];
      final model = buildChartSeries(
        samples,
        fromT: 0,
        toT: 1300 * 30,
        targetPoints: 200,
        probes: [ProbeJack.one],
      );
      expect(model.series.single.envelope, isNotEmpty);
      expect(model.series.single.rawCount, 1300);
    });

    test(
      'the crosshair returns the nearest real reading, never an invention',
      () {
        final samples = <Sample>[
          for (final t in [0, 30, 60, 90, 120])
            Sample(t: t, tempsF10: [1000 + t, null, null, null]),
        ];
        final model = buildChartSeries(
          samples,
          fromT: 0,
          toT: 200,
          probes: [ProbeJack.one],
        );
        final reading = crosshairAt(model, 95).single;
        expect(reading.f, closeTo(109, 1e-9));
        // Far from any sample, it admits there is nothing.
        expect(crosshairAt(model, 5000).single.f, isNull);
      },
    );
  });

  group('effective gap threshold', () {
    test('scales to the series cadence but never below the floor', () {
      expect(effectiveGapThresholdS(const []), 45);
      expect(effectiveGapThresholdS([0, 30, 60, 90, 120]), 45);
      expect(effectiveGapThresholdS([0, 300, 600, 900, 1200]), 450);
    });
  });
}
