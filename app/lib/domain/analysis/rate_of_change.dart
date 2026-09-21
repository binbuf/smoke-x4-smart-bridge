/// N1.10 — rate of change.
///
/// Ordinary least squares over a rolling ten-minute window (twenty samples at
/// the nominal 30 s cadence). It returns `null`, not a number, when there are
/// fewer than twelve valid readings or the window spans a reception gap longer
/// than two minutes: **a rate computed from bad data is worse than none.**
///
/// Display floor: below ±0.6 °F/hr the answer is at the edge of meaningful and
/// reads as `~0` ([formatRate]). That is presentation, not this function's job.
library;

import 'series.dart';

const int rateWindowS = 600;
const int rateMinValidSamples = 12;
const int rateMaxGapS = 120;

/// The display floor, °F/hr.
const double rateZeroFloorFPerHr = 0.6;

/// °F per hour at [atT] (default: the last point's `t`), or null.
double? rateOfChange(List<TempPoint> series, {int? atT}) {
  if (series.isEmpty) {
    return null;
  }
  final endT = atT ?? series.last.t;
  final valid = windowedValid(series, endT, rateWindowS);
  if (valid.length < rateMinValidSamples) {
    return null;
  }
  for (var i = 1; i < valid.length; i++) {
    if (valid[i].t - valid[i - 1].t > rateMaxGapS) {
      return null;
    }
  }
  final fit = olsFit(valid);
  if (fit == null) {
    return null;
  }
  return fit.slope * 3600;
}

/// `null` for no rate, `~0° F/hr` inside the floor, else `+6.2° F/hr`.
String? formatRate(double? rateFPerHr) {
  if (rateFPerHr == null) {
    return null;
  }
  if (rateFPerHr.abs() < rateZeroFloorFPerHr) {
    return '~0° F/hr';
  }
  final sign = rateFPerHr > 0 ? '+' : '';
  return '$sign${rateFPerHr.toStringAsFixed(1)}° F/hr';
}
