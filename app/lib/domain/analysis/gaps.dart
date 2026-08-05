/// Holes in the recording, and why they are there (newapp §E.5).
///
/// The house rule is "never present stale data as current". This extends it:
/// **never hide a gap, and never mislabel one.** The two kinds look identical
/// on a chart and mean opposite things to the person looking at it:
///
///  * [GapReason.connectivity] — the phone was away. The bridge still has those
///    readings and the next sync will fill them in. *Wait, and it comes back.*
///  * [GapReason.bufferRollover] — the bridge's ring buffer wrapped past what
///    the phone had. **Nobody has that data any more, ever.** *Waiting will not
///    help; this is the one the user needs told plainly.*
///
/// Rendering both as one dashed line would tell someone to wait for something
/// that is not coming, which is the failure this file exists to prevent.
library;

import '../entities/entities.dart';

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

  /// The sentence in the statistics table. Names the consequence, not the
  /// mechanism.
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

  /// Exclusive of the samples either side: `fromT` is the last `t` before the
  /// hole and `toT` the first after it.
  final int fromT;
  final int toT;
  final GapReason reason;

  int get durationS => toT - fromT;
}

/// Compare the device's reported buffer extent against what this phone has and
/// decide whether anything was **lost** rather than merely missing (§E.5).
///
/// Returns null when there is nothing to report. Returns a [RecordedGap] with
/// [GapReason.bufferRollover] when `deviceMinT` has advanced past the phone's
/// high-water mark plus one — the device's oldest surviving sample is *newer*
/// than the next one we would have asked for, so the span between them exists
/// nowhere.
///
/// A phone that has never synced this session at all (`highWaterT < 0`) is not
/// a rollover: it has no claim on the earlier data, and the device is simply
/// serving what it has.
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
  // The device also has to still be recording forward for this to be a hole
  // rather than a bookkeeping artefact of an empty buffer.
  if (deviceMaxT != null && deviceMaxT < minT) {
    return null;
  }
  return RecordedGap(
    fromT: highWaterT,
    toT: minT,
    reason: GapReason.bufferRollover,
  );
}

/// Find the holes **inside** what the phone actually holds.
///
/// The threshold is derived from the session's own cadence rather than fixed,
/// so a cook retained at 5-minute buckets is not read as one continuous
/// dropout. [samplePeriodS] is the session header's cadence; anything more than
/// [toleranceFactor] periods apart is a hole.
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
        RecordedGap(
          fromT: prev,
          toT: next,
          reason: GapReason.connectivity,
        ),
      );
    }
  }
  return out;
}
