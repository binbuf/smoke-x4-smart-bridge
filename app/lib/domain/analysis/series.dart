/// Shared series types and the least-squares helper (design 09 §9.4).
library;

import 'dart:math';

/// One point of a probe's time series: seconds-into-session and °F, with
/// `null` for a detached/invalid reading.
typedef TempPoint = ({int t, double? f});

/// A non-null point (post-filtering).
typedef ValuePoint = ({int t, double f});

/// An ordinary-least-squares line fit over (t, value).
class OlsFit {
  const OlsFit({
    required this.slope,
    required this.intercept,
    required this.slopeStdError,
    required this.n,
  });

  /// Units per second.
  final double slope;
  final double intercept;

  /// Standard error of [slope] (units per second); 0 when n < 3.
  final double slopeStdError;
  final int n;
}

/// Fits value = slope·t + intercept. Returns null when fewer than two
/// points or all timestamps coincide.
OlsFit? olsFit(List<ValuePoint> pts) {
  final n = pts.length;
  if (n < 2) {
    return null;
  }
  var sumT = 0.0;
  var sumV = 0.0;
  for (final p in pts) {
    sumT += p.t;
    sumV += p.f;
  }
  final meanT = sumT / n;
  final meanV = sumV / n;
  var sxx = 0.0;
  var sxy = 0.0;
  for (final p in pts) {
    final dt = p.t - meanT;
    sxx += dt * dt;
    sxy += dt * (p.f - meanV);
  }
  if (sxx == 0) {
    return null;
  }
  final slope = sxy / sxx;
  final intercept = meanV - slope * meanT;

  var se = 0.0;
  if (n > 2) {
    var ssr = 0.0;
    for (final p in pts) {
      final resid = p.f - (slope * p.t + intercept);
      ssr += resid * resid;
    }
    se = sqrt((ssr / (n - 2)) / sxx);
  }
  return OlsFit(slope: slope, intercept: intercept, slopeStdError: se, n: n);
}

/// The valid (non-null) points of [series] with `t` in `(endT - windowS, endT]`.
List<ValuePoint> windowedValid(
  List<TempPoint> series,
  int endT,
  int windowS,
) => [
  for (final p in series)
    if (p.t > endT - windowS && p.t <= endT && p.f != null) (t: p.t, f: p.f!),
];
