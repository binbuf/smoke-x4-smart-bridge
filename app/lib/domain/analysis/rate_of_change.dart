/// A2.2 — rate of change (design 09 §9.4).
///
/// Ordinary least-squares slope over a rolling 10-minute window (20 samples
/// at 30 s). Returns `null`, not a number, when the window has fewer than 12
/// valid samples or spans a reception gap longer than 2 minutes — a rate
/// computed from bad data is worse than none.
///
/// Display note: below ±0.6 °F/hr the result is at the edge of meaningful
/// and renders as `~0`; that is presentation, not this function's job.
library;

import 'series.dart';

const int rateWindowS = 600;
const int rateMinValidSamples = 12;
const int rateMaxGapS = 120;

/// °F per hour at [atT] (default: the last point's t), or null.
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
