/// N1.10/N1.13 — the shared series types and least-squares helper.
///
/// Every analysis engine is a pure function over `(t, value)` points, so none
/// of them needs a Flutter binding and all of them are desk-testable.
library;

import 'dart:math';

/// One point of a probe's series: seconds-into-session and °F, `null` when the
/// jack was detached.
typedef TempPoint = ({int t, double? f});

/// A non-null point, after filtering.
typedef ValuePoint = ({int t, double f});

/// An ordinary-least-squares fit `value = slope·t + intercept`.
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

  /// Standard error of [slope]; 0 when there are fewer than three points.
  final double slopeStdError;
  final int n;
}

/// Fits [pts]. Returns null for fewer than two points or coincident timestamps.
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

/// The valid points of [series] with `t` in `(endT - windowS, endT]`.
List<ValuePoint> windowedValid(
  List<TempPoint> series,
  int endT,
  int windowS,
) => [
  for (final p in series)
    if (p.t > endT - windowS && p.t <= endT && p.f != null) (t: p.t, f: p.f!),
];
