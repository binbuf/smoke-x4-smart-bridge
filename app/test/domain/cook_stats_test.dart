/// A11.1 — cook statistics (09 §9.4).
///
/// The seeded cook with a known answer, then the four shapes that make a
/// statistic un-computable — and where the honest answer is `null`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';

import '../support/shapes.dart';

void main() {
  test('a seeded cook computes the §9.4 list', () {
    final cook = syntheticCook(hours: 12);
    final stats = cookStats(cook, probeConfig: pitAndFood);

    expect(stats.durationS, 12 * 3600 - 30);
    expect(stats.sampleCount, cook.length);
    expect(stats.gaps, isEmpty);
    expect(stats.gapSecondsTotal, 0);
    // Pit orbits 250 °F by construction.
    expect(stats.pitMeanF, closeTo(250, 3));
    expect(stats.pitStdDevF, greaterThan(0));
    expect(stats.pitMinF, lessThan(stats.pitMaxF!));
    // Probe 2 climbs from ~60 °F to ~203 °F.
    final p2 = stats.probes.firstWhere((p) => p.probe == 2);
    expect(p2.startF, closeTo(60, 2));
    expect(p2.peakF, greaterThan(180));
    // Probes 3 and 4 were never plugged in.
    expect(stats.probes.firstWhere((p) => p.probe == 3).attachedEver, isFalse);
    expect(stats.probes.firstWhere((p) => p.probe == 3).peakF, isNull);
  });

  test('gap time is excluded from time-in-band', () {
    final whole = syntheticCook(hours: 6);
    final holed = withGap(whole, fromT: 3600, toT: 9000);
    final a = cookStats(whole, probeConfig: pitAndFood).timeInBandS!;
    final b = cookStats(holed, probeConfig: pitAndFood).timeInBandS!;
    // A dropout is not evidence the pit behaved.
    expect(b, lessThan(a));
    expect(cookStats(holed).gapSecondsTotal, 5400);
  });

  test('a stall is detected and its duration reported', () {
    final stats = cookStats(syntheticCook(hours: 12), probeConfig: pitAndFood);
    expect(stats.stallDurationS, isNotNull);
    expect(stats.stallDurationS, greaterThan(1800));
  });

  test('lid events come from the marks, not from a second detector', () {
    final stats = cookStats(
      syntheticCook(hours: 2),
      marks: const [
        Mark(t: 600, kind: MarkKind.lidOpen),
        Mark(t: 3000, kind: MarkKind.lidOpen),
        Mark(t: 3600, kind: MarkKind.wrapped),
      ],
      probeConfig: pitAndFood,
    );
    expect(stats.lidEvents, 2);
  });

  group('the shapes with no answer', () {
    test('an empty session', () {
      final s = cookStats(const []);
      expect(s.durationS, 0);
      expect(s.sampleCount, 0);
      expect(s.probes, isEmpty);
      expect(s.pitMeanF, isNull);
    });

    test('a session of one sample', () {
      final s = cookStats(const [
        Sample(t: 0, tempsF10: [2400, null, null, null]),
      ], probeConfig: pitAndFood);
      expect(s.durationS, 0);
      expect(s.sampleCount, 1);
      expect(s.pitMeanF, closeTo(240, 1e-9));
      expect(s.pitStdDevF, 0);
    });

    test('a session that is entirely one gap', () {
      final s = cookStats(const [
        Sample(t: 0, tempsF10: [2400, null, null, null]),
        Sample(t: 7200, tempsF10: [2400, null, null, null]),
      ], probeConfig: pitAndFood);
      expect(s.gaps, hasLength(1));
      expect(s.gapSecondsTotal, 7200);
      expect(s.observedS, 0);
      // Two samples 2 hours apart is no evidence of time in band.
      expect(s.timeInBandS, 0);
    });

    test('no pit role means no pit statistics, not a guess', () {
      final s = cookStats(
        syntheticCook(hours: 3),
        probeConfig: const [Probe(n: 2, role: ProbeRole.food)],
      );
      expect(s.pitMeanF, isNull);
      expect(s.pitStdDevF, isNull);
      expect(s.timeInBandS, isNull);
      // Per-probe rows still exist: those need no role.
      expect(s.probes.firstWhere((p) => p.probe == 1).attachedEver, isTrue);
    });

    test('a pit with no band configured has no time-in-band', () {
      final s = cookStats(
        syntheticCook(hours: 3),
        probeConfig: const [Probe(n: 1, role: ProbeRole.pit)],
      );
      expect(s.pitMeanF, isNotNull);
      expect(s.timeInBandS, isNull);
    });
  });
}
