/// V3.2 — the report that closes the heap question.
///
/// The four criteria are fixed in docs/tasks/M6-hardening-and-release.md
/// BEFORE the run, because the real hazard here is reading a 24-hour trace
/// and deciding afterwards which number was the target. A 24-hour trace
/// can be made to support almost any conclusion if you pick the threshold
/// after seeing it.
///
///   * min_free_heap floor      >= 80 KB for the whole run
///   * free_heap slope          >= -256 B/h (under ~6 KB lost per day)
///   * largest_free_block floor >= 32 KB (fragmentation, R2)
///   * task stack headroom      every task >= 512 B margin
///
/// All four hold -> the 150 KB target was wrong (option 1). Any fail ->
/// options 2 and 3 (buffer counts, concurrency caps) become a design
/// conversation with a trace to argue from.
library;

import 'sample.dart';

const int heapFloorB = 80 * 1024;
const double heapSlopeFloorBPerH = -256.0;
const int largestBlockFloorB = 32 * 1024;
const int stackMarginFloorB = 512;

class Criterion {
  const Criterion({
    required this.name,
    required this.pass,
    required this.observed,
    required this.threshold,
  });

  final String name;
  final bool pass;

  /// The number, so a pass or a fail carries evidence rather than a
  /// verdict.
  final String observed;
  final String threshold;
}

class SoakReport {
  const SoakReport({
    required this.samples,
    required this.durationH,
    required this.criteria,
    required this.reconnects,
    required this.wsDrops,
    required this.packetsOk,
    required this.packetsBad,
    required this.storageGrowthB,
    required this.minFreeHeapFloorB,
    required this.freeHeapSlopeBPerH,
    required this.largestBlockFloorB,
    required this.worstTask,
    required this.worstTaskMarginB,
  });

  final int samples;
  final double durationH;
  final List<Criterion> criteria;
  final int reconnects;
  final int wsDrops;
  final int packetsOk;
  final int packetsBad;
  final int storageGrowthB;
  final int minFreeHeapFloorB;
  final double freeHeapSlopeBPerH;
  final int largestBlockFloorB;
  final String worstTask;
  final int worstTaskMarginB;

  /// An empty trace is not a pass. `every` over no criteria is vacuously
  /// true, and a soak that recorded nothing has proven nothing.
  bool get pass => criteria.isNotEmpty && criteria.every((c) => c.pass);
}

/// Least-squares slope of y against x, in y-units per x-unit. A leak is a
/// slope, not a level: 6 KB/day is invisible in a before-and-after pair
/// and obvious in a regression over 2,880 samples.
double leastSquaresSlope(List<double> xs, List<double> ys) {
  final n = xs.length;
  if (n < 2) return 0;
  var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
  for (var i = 0; i < n; i++) {
    sx += xs[i];
    sy += ys[i];
    sxx += xs[i] * xs[i];
    sxy += xs[i] * ys[i];
  }
  final denom = n * sxx - sx * sx;
  if (denom == 0) return 0;
  return (n * sxy - sx * sy) / denom;
}

SoakReport evaluate(List<SoakSample> samples) {
  if (samples.isEmpty) {
    return const SoakReport(
      samples: 0,
      durationH: 0,
      criteria: [],
      reconnects: 0,
      wsDrops: 0,
      packetsOk: 0,
      packetsBad: 0,
      storageGrowthB: 0,
      minFreeHeapFloorB: 0,
      freeHeapSlopeBPerH: 0,
      largestBlockFloorB: 0,
      worstTask: '',
      worstTaskMarginB: 0,
    );
  }

  final first = samples.first;
  final last = samples.last;
  final durationH = (last.wallMs - first.wallMs) / 3600000.0;

  // The floor is a floor: a single sample below it fails the criterion.
  var minHeapFloor = 1 << 30;
  var minBlockFloor = 1 << 30;
  var worstTask = '';
  var worstMargin = 1 << 30;
  for (final s in samples) {
    if (s.minFreeHeap < minHeapFloor) minHeapFloor = s.minFreeHeap;
    if (s.largestFreeBlock < minBlockFloor) {
      minBlockFloor = s.largestFreeBlock;
    }
    for (final t in s.tasks) {
      if (t.marginB < worstMargin) {
        worstMargin = t.marginB;
        worstTask = t.name;
      }
    }
  }

  final xs = [for (final s in samples) (s.wallMs - first.wallMs) / 3600000.0];
  final ys = [for (final s in samples) s.freeHeap.toDouble()];
  final slope = leastSquaresSlope(xs, ys);

  final criteria = <Criterion>[
    Criterion(
      name: 'min_free_heap floor',
      pass: minHeapFloor >= heapFloorB,
      observed: '${(minHeapFloor / 1024).toStringAsFixed(1)} KB',
      threshold: '>= ${heapFloorB ~/ 1024} KB',
    ),
    Criterion(
      name: 'free_heap slope',
      pass: slope >= heapSlopeFloorBPerH,
      observed: '${slope.toStringAsFixed(1)} B/h',
      threshold: '>= ${heapSlopeFloorBPerH.toStringAsFixed(0)} B/h',
    ),
    Criterion(
      name: 'largest_free_block floor',
      pass: minBlockFloor >= largestBlockFloorB,
      observed: '${(minBlockFloor / 1024).toStringAsFixed(1)} KB',
      threshold: '>= ${largestBlockFloorB ~/ 1024} KB',
    ),
    Criterion(
      name: 'task stack headroom',
      pass: worstMargin >= stackMarginFloorB,
      observed: '$worstTask $worstMargin B',
      threshold: '>= $stackMarginFloorB B (every task)',
    ),
  ];

  return SoakReport(
    samples: samples.length,
    durationH: durationH,
    criteria: criteria,
    reconnects: last.reconnects,
    wsDrops: last.wsDrops,
    packetsOk: last.packetsOk - first.packetsOk,
    packetsBad: last.packetsBad - first.packetsBad,
    storageGrowthB: last.storageUsedB - first.storageUsedB,
    minFreeHeapFloorB: minHeapFloor,
    freeHeapSlopeBPerH: slope,
    largestBlockFloorB: minBlockFloor,
    worstTask: worstTask,
    worstTaskMarginB: worstMargin,
  );
}

/// The Markdown block that lands in docs/hardware-verified.md.
String renderMarkdown(SoakReport r) {
  if (r.samples == 0) {
    return '### V3.3 — 24-hour soak\n\n'
        'No samples recorded — nothing to evaluate. (A bridge running '
        'firmware older than F14 has no /api/v1/debug/tasks; flash the '
        'release image first.)\n';
  }
  final b = StringBuffer()
    ..writeln('### V3.3 — 24-hour soak')
    ..writeln()
    ..writeln(
      '- Duration: ${r.durationH.toStringAsFixed(1)} h, '
      '${r.samples} samples',
    )
    ..writeln(
      '- Reconnects: ${r.reconnects} · WebSocket drops: '
      '${r.wsDrops}',
    )
    ..writeln('- Packets: ${r.packetsOk} ok / ${r.packetsBad} bad')
    ..writeln(
      '- Storage growth: '
      '${(r.storageGrowthB / 1024).toStringAsFixed(1)} KB',
    )
    ..writeln()
    ..writeln('| Criterion | Threshold | Observed | Verdict |')
    ..writeln('| --- | --- | --- | --- |');
  for (final c in r.criteria) {
    b.writeln(
      '| ${c.name} | ${c.threshold} | ${c.observed} | '
      '${c.pass ? 'PASS' : 'FAIL'} |',
    );
  }
  b
    ..writeln()
    ..writeln(
      r.pass
          ? '**All four hold → the 150 KB target was wrong (option 1). '
                'Correct 01 §1.4 to the measured floor with NimBLE\'s real '
                '≈ 90–100 KB beside it.**'
          : '**A criterion failed → options 2 and 3 (buffer counts, '
                'concurrency caps) are now a design conversation, with this '
                'trace to argue from.**',
    );
  return b.toString();
}
