/// N1.11 — ETA to target under two models.
///
/// Linear early; Newton cooling once the food is within about 60 °F of the pit,
/// because meat approaches pit temperature asymptotically and
/// `(target − current) / slope` is wrong in the back half of every cook.
///
/// A confidently wrong ETA is worse than none, so the guard rails are the
/// feature: enough history, a meaningful slope, no stall, and a target the pit
/// can actually reach. The answer is a **range** rounded to 15 minutes, or a
/// **named refusal** ([EtaUnavailableReason]) — never a silent null.
library;

import 'dart:math';

import 'rate_of_change.dart';
import 'series.dart';

/// The result of an ETA query: a rounded range or a named refusal.
sealed class EtaResult {
  const EtaResult();
}

/// `5h 45m – 7h 00m`; [low] ≤ [high], both multiples of 15 minutes.
class EtaRange extends EtaResult {
  const EtaRange(this.low, this.high);

  final Duration low;
  final Duration high;

  @override
  bool operator ==(Object other) =>
      other is EtaRange && other.low == low && other.high == high;

  @override
  int get hashCode => Object.hash(low, high);

  @override
  String toString() => 'EtaRange($low – $high)';
}

/// Why an ETA could not be given. Never a bare "unavailable".
enum EtaUnavailableReason {
  /// Under 30 minutes of session history.
  insufficientHistory,

  /// `|slope|` under 1 °F/hr — projecting noise.
  slopeTooFlat,

  /// A stall is in progress.
  stalled,

  /// Target at or above the current pit: the pit cannot get it there.
  targetAtOrAbovePit,

  /// The probe is moving away from the target.
  notApproaching,
}

class EtaUnavailable extends EtaResult {
  const EtaUnavailable(this.reason);

  final EtaUnavailableReason reason;

  @override
  bool operator ==(Object other) =>
      other is EtaUnavailable && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'EtaUnavailable($reason)';
}

/// Model-selection boundary: within this many °F of pit, Newton takes over.
const double etaNewtonBandF = 60;

const int etaMinHistoryS = 1800;
const double etaMinSlopeFPerHr = 1;

/// Beyond this the number is fiction.
const Duration etaMaxHorizon = Duration(hours: 24);

/// The two probe series for one analysis, already in session-seconds.
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
  final slowS = slopeLow > 0
      ? remainF / slopeLow
      : etaMaxHorizon.inSeconds.toDouble();
  return _range(fastS, slowS);
}

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
    return const EtaUnavailable(EtaUnavailableReason.notApproaching);
  }
  final k = -fit.slope; // per second
  final kLow = -(fit.slope + 1.96 * fit.slopeStdError);
  final kHigh = -(fit.slope - 1.96 * fit.slopeStdError);

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
