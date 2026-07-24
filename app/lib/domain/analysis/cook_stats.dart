/// A11.1 — cook statistics (design 09 §9.4, 08 §8.6).
///
/// Computed on session close and shown on the detail screen. **This is
/// what makes cooks comparable, which is what makes the whole thing more
/// than a thermometer with a screen.**
///
/// Every value that cannot honestly be computed is `null`. A session with
/// no `pit`-role probe has no pit σ; a session that is one long dropout
/// has no time in band. Saying so is the correct answer, and it is the
/// same discipline A2.3 applied to the ETA: a confidently wrong number is
/// worse than none.
library;

import 'dart:math';

import '../entities/entities.dart';
import 'chart_series.dart';
import 'series.dart';
import 'stall.dart';
import 'units.dart';

class ProbeStats {
  const ProbeStats({
    required this.probe,
    this.startF,
    this.endF,
    this.peakF,
    this.minF,
    this.samples = 0,
  });

  final int probe;

  /// All null when the probe was detached for the whole session — never 0.
  final double? startF;
  final double? endF;
  final double? peakF;
  final double? minF;

  /// How many valid readings this probe contributed.
  final int samples;

  bool get attachedEver => samples > 0;
}

class CookStats {
  const CookStats({
    required this.durationS,
    required this.sampleCount,
    required this.gaps,
    required this.gapSecondsTotal,
    required this.probes,
    this.pitMeanF,
    this.pitStdDevF,
    this.pitMinF,
    this.pitMaxF,
    this.timeInBandS,
    this.stallDurationS,
    this.lidEvents = 0,
  });

  /// Wall time from the first to the last sample, gaps included — the
  /// cook took as long as it took.
  final int durationS;
  final int sampleCount;

  /// Reception gaps (`t` delta > 45 s), and their total. `sampleCount`
  /// alone cannot tell you a cook was half missing; this pair can.
  final List<Gap> gaps;
  final int gapSecondsTotal;

  final List<ProbeStats> probes;

  /// Null when no probe carried the `pit` role.
  final double? pitMeanF;
  final double? pitStdDevF;
  final double? pitMinF;
  final double? pitMaxF;

  /// Seconds the pit spent inside its configured alarm band. **Gap time
  /// is excluded** — a dropout is not evidence the pit behaved.
  final int? timeInBandS;

  /// Null when the food probe never stalled (or when there was no food
  /// probe to stall).
  final int? stallDurationS;
  final int lidEvents;

  /// Time actually observed, i.e. duration minus the holes.
  int get observedS => durationS - gapSecondsTotal;
}

/// Computes the §9.4 list over a session's [samples] and [marks].
///
/// [probeConfig] supplies roles and the pit's alarm band; without it the
/// pit-specific rows come back null rather than guessing which jack was
/// the pit.
CookStats cookStats(
  List<Sample> samples, {
  List<Mark> marks = const [],
  List<Probe> probeConfig = const [],

  /// Null derives it from the cook's own cadence, so a session retained
  /// at 5-minute buckets is not counted as one continuous dropout.
  int? gapThresholdS,
}) {
  if (samples.isEmpty) {
    return const CookStats(
      durationS: 0,
      sampleCount: 0,
      gaps: [],
      gapSecondsTotal: 0,
      probes: [],
    );
  }

  final threshold =
      gapThresholdS ?? effectiveGapThresholdS(samples.map((s) => s.t));
  final gaps = findGaps(samples.map((s) => s.t), thresholdS: threshold);
  final gapTotal = gaps.fold<int>(0, (a, g) => a + (g.toT - g.fromT));

  final probeStats = <ProbeStats>[];
  for (var p = 1; p <= 4; p++) {
    final vals = <ValuePoint>[
      for (final s in samples)
        if (probeValue(s, p) != null) (t: s.t, f: probeValue(s, p)! / 10.0),
    ];
    if (vals.isEmpty) {
      probeStats.add(ProbeStats(probe: p));
      continue;
    }
    var lo = vals.first.f;
    var hi = vals.first.f;
    for (final v in vals) {
      lo = min(lo, v.f);
      hi = max(hi, v.f);
    }
    probeStats.add(
      ProbeStats(
        probe: p,
        startF: vals.first.f,
        endF: vals.last.f,
        peakF: hi,
        minF: lo,
        samples: vals.length,
      ),
    );
  }

  final pit = probeConfig.where((p) => p.role == ProbeRole.pit).firstOrNull;
  double? mean;
  double? sd;
  double? pitMin;
  double? pitMax;
  int? inBand;
  if (pit != null) {
    final vals = <ValuePoint>[
      for (final s in samples)
        if (probeValue(s, pit.n) != null)
          (t: s.t, f: probeValue(s, pit.n)! / 10.0),
    ];
    if (vals.isNotEmpty) {
      mean = vals.fold<double>(0, (a, v) => a + v.f) / vals.length;
      sd = sqrt(
        vals.fold<double>(0, (a, v) => a + pow(v.f - mean!, 2)) / vals.length,
      );
      pitMin = vals.map((v) => v.f).reduce(min);
      pitMax = vals.map((v) => v.f).reduce(max);
      final lo = pit.alarmMinF10;
      final hi = pit.alarmMaxF10;
      if (lo != null && hi != null) {
        var seconds = 0;
        for (var i = 1; i < vals.length; i++) {
          final dt = vals[i].t - vals[i - 1].t;
          // Gap time is not evidence: skip any interval wider than the
          // gap threshold rather than crediting the pit for a dropout.
          if (dt > threshold) {
            continue;
          }
          final f10 = vals[i].f * 10;
          if (f10 >= lo && f10 <= hi) {
            seconds += dt;
          }
        }
        inBand = seconds;
      }
    }
  }

  // Stall and lid-open are already detected elsewhere and written to the
  // session as marks (09 §9.4) — counting the marks keeps one source of
  // truth rather than re-running the detectors with different windows.
  final lids = marks.where((m) => m.kind == MarkKind.lidOpen).length;
  int? stallS;
  final food = probeConfig.where((p) => p.role == ProbeRole.food).firstOrNull;
  if (food != null) {
    final detector = StallDetector();
    int? enteredAt;
    var total = 0;
    for (final s in samples) {
      final v = probeValue(s, food.n);
      final stalled = detector.add(s.t, v == null ? null : v / 10.0);
      if (stalled && enteredAt == null) {
        enteredAt = s.t;
      } else if (!stalled && enteredAt != null) {
        total += s.t - enteredAt;
        enteredAt = null;
      }
    }
    if (enteredAt != null) {
      total += samples.last.t - enteredAt;
    }
    stallS = total > 0 ? total : null;
  }

  return CookStats(
    durationS: samples.last.t - samples.first.t,
    sampleCount: samples.length,
    gaps: gaps,
    gapSecondsTotal: gapTotal,
    probes: probeStats,
    pitMeanF: mean,
    pitStdDevF: sd,
    pitMinF: pitMin,
    pitMaxF: pitMax,
    timeInBandS: inBand,
    stallDurationS: stallS,
    lidEvents: lids,
  );
}
