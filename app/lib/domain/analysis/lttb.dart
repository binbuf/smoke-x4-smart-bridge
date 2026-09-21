/// N1.14 — Largest-Triangle-Three-Buckets decimation.
///
/// Naive stride decimation steps straight over a lid-open spike; LTTB keeps the
/// point in each bucket that forms the largest triangle with its neighbours, so
/// peaks and troughs survive at roughly two points per pixel.
library;

/// Downsamples [data] (ordered by `t`) to [threshold] points. The first and
/// last points are always kept. [threshold] ≥ 3; fewer input points than the
/// threshold come back unchanged.
List<({int t, double f})> lttb(List<({int t, double f})> data, int threshold) {
  if (threshold >= data.length || data.length < 3) {
    return List.of(data);
  }
  if (threshold < 3) {
    throw ArgumentError.value(threshold, 'threshold', 'must be ≥ 3');
  }

  final sampled = <({int t, double f})>[data.first];
  final bucketSize = (data.length - 2) / (threshold - 2);
  var prev = data.first;

  for (var i = 0; i < threshold - 2; i++) {
    final rangeStart = (i * bucketSize).floor() + 1;
    final rangeEnd = ((i + 1) * bucketSize).floor() + 1;

    // The average of the NEXT bucket is the triangle's third vertex.
    final nextStart = rangeEnd;
    final nextEnd = (((i + 2) * bucketSize).floor() + 1).clamp(0, data.length);
    var avgT = 0.0;
    var avgF = 0.0;
    final nextLen = nextEnd - nextStart;
    if (nextLen > 0) {
      for (var j = nextStart; j < nextEnd; j++) {
        avgT += data[j].t;
        avgF += data[j].f;
      }
      avgT /= nextLen;
      avgF /= nextLen;
    } else {
      avgT = data.last.t.toDouble();
      avgF = data.last.f;
    }

    var maxArea = -1.0;
    var chosen = data[rangeStart];
    for (var j = rangeStart; j < rangeEnd; j++) {
      final area =
          ((prev.t - avgT) * (data[j].f - prev.f) -
                  (prev.t - data[j].t) * (avgF - prev.f))
              .abs();
      if (area > maxArea) {
        maxArea = area;
        chosen = data[j];
      }
    }
    sampled.add(chosen);
    prev = chosen;
  }

  sampled.add(data.last);
  return sampled;
}
