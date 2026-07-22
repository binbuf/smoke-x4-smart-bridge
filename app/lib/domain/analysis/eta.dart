/// A2.3 — ETA to target under two models (design 09 §9.4).
///
/// Linear early; Newton cooling once the food is within ~60 °F of pit
/// temperature, because meat approaches pit temperature asymptotically and
/// naive `(target − current) / slope` is wrong in the back half of every
/// cook.
///
/// A confidently wrong ETA is worse than none, so the guard rails are the
/// feature: enough history, a meaningful slope, no stall, and a target the
/// pit can actually reach. The answer is a **range** from the fit's standard
/// error, rounded to 15 minutes — never `6h 23m`; the physics does not
/// support that precision.
library;

import 'dart:math';

import 'rate_of_change.dart';
import 'series.dart';

sealed class EtaResult {
  const EtaResult();
}

/// "5h 45m – 7h 00m". [low] ≤ [high]; both multiples of 15 minutes.
class EtaRange extends EtaResult {
  const EtaRange(this.low, this.high);
  final Duration low;
  final Duration high;

  @override
  String toString() => 'EtaRange($low – $high)';
}

enum EtaUnavailableReason {
  /// Less than 30 minutes of session history.
  insufficientHistory,

  /// |slope| under 1 °F/hr — projecting noise.
  slopeTooFlat,

  /// A stall is in progress: "stalled — ETA unavailable".
  stalled,

  /// target ≥ current pit temperature: "not at this pit temperature" is the
  /// correct answer, and the one the app shows.
  targetAtOrAbovePit,

  /// The probe is moving away from the target.
  notApproaching,
}

class EtaUnavailable extends EtaResult {
  const EtaUnavailable(this.reason);
  final EtaUnavailableReason reason;

  @override
  String toString() => 'EtaUnavailable($reason)';
}

/// Model-selection boundary: within this many °F of pit, Newton takes over.
const double etaNewtonBandF = 60;

/// Guard thresholds.
const int etaMinHistoryS = 1800;
const double etaMinSlopeFPerHr = 1;

/// Cap on the projected range — beyond this the number is fiction.
const Duration etaMaxHorizon = Duration(hours: 24);

EtaResult etaToTarget({
  required List<TempPoint> food,
  required List<TempPoint> pit,
  required double targetF,
  bool stalled = false,
}) {
  final foodValid = [
    for (final p in food)
      if (p.f != null) (t: p.t, f: p.f!),
  ];
  if (foodValid.isEmpty ||
      foodValid.last.t - foodValid.first.t < etaMinHistoryS) {
    return const EtaUnavailable(EtaUnavailableReason.insufficientHistory);
  }
  if (stalled) {
    return const EtaUnavailable(EtaUnavailableReason.stalled);
  }

  final nowT = foodValid.last.t;
  final current = foodValid.last.f;

  final pitRecent = windowedValid(pit, nowT, rateWindowS);
  if (pitRecent.isEmpty) {
    return const EtaUnavailable(EtaUnavailableReason.insufficientHistory);
  }
  final pitAvg =
      pitRecent.fold<double>(0, (a, p) => a + p.f) / pitRecent.length;
  if (targetF >= pitAvg) {
    return const EtaUnavailable(EtaUnavailableReason.targetAtOrAbovePit);
  }

  if (current >= targetF) {
    return const EtaRange(Duration.zero, Duration.zero);
  }

  final slope = rateOfChange(food, atT: nowT);
  if (slope == null) {
    return const EtaUnavailable(EtaUnavailableReason.insufficientHistory);
  }
  if (slope.abs() < etaMinSlopeFPerHr) {
    return const EtaUnavailable(EtaUnavailableReason.slopeTooFlat);
  }
  if (slope <= 0) {
    return const EtaUnavailable(EtaUnavailableReason.notApproaching);
  }

  if (pitAvg - current > etaNewtonBandF) {
    return _linear(food, nowT, current, targetF);
  }
  return _newton(foodValid, nowT, pitAvg, current, targetF);
}

/// Early-cook model: project the 10-minute OLS slope, range from its
/// standard error.
EtaResult _linear(
  List<TempPoint> food,
  int nowT,
  double current,
  double targetF,
) {
  final window = windowedValid(food, nowT, rateWindowS);
  final fit = olsFit(window)!;
  final remainF = targetF - current;

  final slopeLow = fit.slope - 1.96 * fit.slopeStdError; // °F/s
  final slopeHigh = fit.slope + 1.96 * fit.slopeStdError;
  final fastS = remainF / slopeHigh;
  final slowS =
      slopeLow > 0 ? remainF / slopeLow : etaMaxHorizon.inSeconds.toDouble();
  return _range(fastS, slowS);
}

/// Back-half model: T(t) = T_pit − (T_pit − T₀)·e^(−k·t). Fit k by
/// regressing ln(T_pit − T) against t over the last 60 minutes, then
/// t_remain = (1/k)·ln((T_pit − T_target)/(T_pit − T_current)).
EtaResult _newton(
  List<ValuePoint> foodValid,
  int nowT,
  double pitAvg,
  double current,
  double targetF,
) {
  final pts = <ValuePoint>[
    for (final p in foodValid)
      if (p.t > nowT - 3600 && pitAvg - p.f > 0.5)
        (t: p.t, f: log(pitAvg - p.f)),
  ];
  final fit = pts.length >= rateMinValidSamples ? olsFit(pts) : null;
  if (fit == null || fit.slope >= 0) {
    // ln(T_pit − T) must fall over time if the food is approaching the pit.
    return const EtaUnavailable(EtaUnavailableReason.notApproaching);
  }
  final k = -fit.slope; // per second
  final kLow = -(fit.slope + 1.96 * fit.slopeStdError); // slower approach
  final kHigh = -(fit.slope - 1.96 * fit.slopeStdError); // faster approach

  double remainAt(double kk) => kk <= 0
      ? etaMaxHorizon.inSeconds.toDouble()
      : log((pitAvg - targetF) / (pitAvg - current)).abs() / kk;

  final mid = remainAt(k);
  final fastS = min(remainAt(kHigh), mid);
  final slowS = max(remainAt(kLow), mid);
  return _range(fastS, slowS);
}

EtaResult _range(double fastS, double slowS) {
  Duration roundQuarter(double s) {
    final clamped = s.clamp(0, etaMaxHorizon.inSeconds.toDouble());
    final quarters = (clamped / 900).round();
    return Duration(seconds: quarters * 900);
  }

  final low = roundQuarter(fastS);
  final high = roundQuarter(slowS);
  return EtaRange(low, high < low ? low : high);
}
