/// A2.6 — LTTB against an independent reference implementation, plus the
/// spike-survival property that justifies its existence.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';

/// Independent reference LTTB, transcribed directly from Sveinn
/// Steinarsson's canonical downsample.js — deliberately written in its
/// index-juggling style rather than ours.
List<({int t, double f})> referenceLttb(
  List<({int t, double f})> data,
  int threshold,
) {
  final n = data.length;
  if (threshold >= n || threshold == 0) {
    return List.of(data);
  }
  final sampled = <({int t, double f})>[];
  final every = (n - 2) / (threshold - 2);
  var a = 0;
  sampled.add(data[a]);
  for (var i = 0; i < threshold - 2; i++) {
    var avgX = 0.0;
    var avgY = 0.0;
    var avgRangeStart = ((i + 1) * every).floor() + 1;
    var avgRangeEnd = ((i + 2) * every).floor() + 1;
    avgRangeEnd = avgRangeEnd < n ? avgRangeEnd : n;
    final avgRangeLength = avgRangeEnd - avgRangeStart;
    for (; avgRangeStart < avgRangeEnd; avgRangeStart++) {
      avgX += data[avgRangeStart].t;
      avgY += data[avgRangeStart].f;
    }
    avgX /= avgRangeLength;
    avgY /= avgRangeLength;

    var rangeOffs = (i * every).floor() + 1;
    final rangeTo = ((i + 1) * every).floor() + 1;
    final pointAX = data[a].t.toDouble();
    final pointAY = data[a].f;

    var maxArea = -1.0;
    var nextA = rangeOffs;
    for (; rangeOffs < rangeTo; rangeOffs++) {
      final area = ((pointAX - avgX) * (data[rangeOffs].f - pointAY) -
                  (pointAX - data[rangeOffs].t) * (avgY - pointAY))
              .abs() *
          0.5;
      if (area > maxArea) {
        maxArea = area;
        nextA = rangeOffs;
      }
    }
    sampled.add(data[nextA]);
    a = nextA;
  }
  sampled.add(data[n - 1]);
  return sampled;
}

void main() {
  List<({int t, double f})> randomWalk(int n, int seed) {
    final rand = Random(seed);
    var v = 200.0;
    return [
      for (var i = 0; i < n; i++)
        (t: i * 30, f: v += (rand.nextDouble() - 0.5) * 3),
    ];
  }

  test('matches the reference implementation on a shared input', () {
    for (final seed in [1, 7, 42]) {
      final data = randomWalk(500, seed);
      for (final threshold in [10, 50, 123]) {
        expect(lttb(data, threshold), referenceLttb(data, threshold),
            reason: 'seed $seed threshold $threshold');
      }
    }
  });

  test('a lid-open spike survives 2,880 → 400', () {
    // A smooth 24-hour cook with one violent single-sample excursion —
    // exactly what naive stride decimation steps over.
    final data = <({int t, double f})>[
      for (var i = 0; i < 2880; i++)
        (
          t: i * 30,
          f: i == 1500 ? 210.0 : 250 + 4 * sin(i / 120),
        ),
    ];
    final out = lttb(data, 400);
    expect(out.length, 400);
    expect(out.any((p) => p.t == 1500 * 30 && p.f == 210.0), isTrue,
        reason: 'the spike must survive decimation');
  });

  test('keeps endpoints and hits the exact threshold', () {
    final data = randomWalk(2880, 3);
    final out = lttb(data, 400);
    expect(out.length, 400);
    expect(out.first, data.first);
    expect(out.last, data.last);
    // Ordered and drawn from the input.
    for (var i = 1; i < out.length; i++) {
      expect(out[i].t, greaterThan(out[i - 1].t));
    }
  });

  test('small inputs pass through untouched', () {
    final data = randomWalk(5, 1);
    expect(lttb(data, 10), data);
    expect(lttb(data, 5), data);
  });

  test('threshold below 3 is an error, not silent garbage', () {
    final data = randomWalk(10, 1);
    expect(() => lttb(data, 2), throwsArgumentError);
  });
}
