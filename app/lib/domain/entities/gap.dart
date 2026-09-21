/// N1.18 — holes in the recording, and why they are there.
///
/// The two kinds look identical on a chart and mean opposite things:
///
///  * [GapReason.connectivity] — the phone was away. The bridge still has those
///    readings and the next sync fills them in. *Wait and it comes back.*
///  * [GapReason.bufferRollover] — the bridge's ring wrapped past what the phone
///    had. **Nobody has that data any more, ever.** *Waiting will not help.*
///
/// Presenting both as one dashed line would tell someone to wait for something
/// that is not coming.
library;

import 'sample.dart';

/// A reception gap between two surrounding samples, exclusive of both ends.
typedef Gap = ({int fromT, int toT});

/// Why the recording has a hole.
enum GapReason {
  /// Recoverable — the device still holds it.
  connectivity,

  /// Permanent — the device overwrote it.
  bufferRollover;

  String get label => switch (this) {
    GapReason.connectivity => 'Not synced yet',
    GapReason.bufferRollover => 'Buffer rolled over',
  };

  String get explanation => switch (this) {
    GapReason.connectivity =>
      'The bridge still has these readings — they arrive on the next sync.',
    GapReason.bufferRollover =>
      'The bridge recorded over these before the app could fetch them. They '
          'are gone for good.',
  };

  bool get isPermanent => this == GapReason.bufferRollover;
}

/// A recorded hole in one session, in session-relative seconds.
class RecordedGap {
  const RecordedGap({
    required this.fromT,
    required this.toT,
    required this.reason,
  });

  /// `fromT` is the last `t` before the hole, `toT` the first after it.
  final int fromT;
  final int toT;
  final GapReason reason;

  int get durationS => toT - fromT;

  /// The anonymous chart-level gap, without a reason attached.
  Gap get asGap => (fromT: fromT, toT: toT);
}

/// Gaps in an ordered `t` sequence. A delta strictly greater than
/// [thresholdS] (default 45 s — 1.5× the nominal 30 s cadence) means packets
/// were missed and the chart must draw a break, not a line across the hole.
List<Gap> findGaps(Iterable<int> ts, {int thresholdS = 45}) {
  final gaps = <Gap>[];
  int? prev;
  for (final t in ts) {
    if (prev != null && t - prev > thresholdS) {
      gaps.add((fromT: prev, toT: t));
    }
    prev = t;
  }
  return gaps;
}

/// Compare the device's buffer extent against what this phone has and decide
/// whether anything was **lost** rather than merely missing.
///
/// Returns null when there is nothing to report; otherwise a permanent
/// [GapReason.bufferRollover] gap. A phone that has never synced the session
/// ([highWaterT] < 0) is not a rollover — it has no claim on the earlier data.
RecordedGap? detectRollover({
  required int highWaterT,
  required int? deviceMinT,
  required int? deviceMaxT,
}) {
  final minT = deviceMinT;
  if (minT == null || highWaterT < 0) {
    return null;
  }
  if (minT <= highWaterT + 1) {
    return null; // contiguous — the next fetch joins cleanly
  }
  if (deviceMaxT != null && deviceMaxT < minT) {
    return null;
  }
  return RecordedGap(
    fromT: highWaterT,
    toT: minT,
    reason: GapReason.bufferRollover,
  );
}

/// Find the holes **inside** what the phone actually holds, derived from the
/// session's own cadence so a cook retained at 5-minute buckets is not read as
/// one continuous dropout.
List<RecordedGap> detectConnectivityGaps(
  List<Sample> samples, {
  int samplePeriodS = 30,
  double toleranceFactor = 2.5,
}) {
  if (samples.length < 2) {
    return const [];
  }
  final period = samplePeriodS < 1 ? 30 : samplePeriodS;
  final threshold = (period * toleranceFactor).round();
  final out = <RecordedGap>[];
  for (var i = 1; i < samples.length; i++) {
    final prev = samples[i - 1].t;
    final next = samples[i].t;
    if (next - prev > threshold) {
      out.add(
        RecordedGap(fromT: prev, toT: next, reason: GapReason.connectivity),
      );
    }
  }
  return out;
}
