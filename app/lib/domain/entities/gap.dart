/// N1.18 — holes in the recording, and why they are there.
///
/// The kinds look identical on a chart and mean opposite things:
///
///  * [GapReason.connectivity] — the phone was away. The bridge still has those
///    readings and the next sync fills them in. *Wait and it comes back.*
///  * [GapReason.baseLost] — the base station stopped reporting, so the bridge
///    never recorded them. **Nobody has that data.** *Waiting will not help.*
///  * [GapReason.bufferRollover] — the bridge's ring wrapped past what the phone
///    had. **Nobody has that data any more, ever.** *Waiting will not help.*
///
/// Presenting them as one dashed line would tell someone to wait for something
/// that is not coming.
library;

/// Why the recording has a hole.
enum GapReason {
  /// Recoverable — the device still holds it. The phone was away and has not
  /// fetched this range yet; the bridge recorded it throughout.
  connectivity,

  /// Permanent — the base station stopped reporting, so the bridge never
  /// recorded these readings. Nothing to wait for.
  baseLost,

  /// Permanent — the device overwrote it.
  bufferRollover;

  String get label => switch (this) {
    GapReason.connectivity => 'Not synced yet',
    GapReason.baseLost => 'Base lost',
    GapReason.bufferRollover => 'Buffer rolled over',
  };

  String get explanation => switch (this) {
    GapReason.connectivity =>
      'The bridge still has these readings — they arrive on the next sync.',
    GapReason.baseLost =>
      'The bridge lost contact with the base station here, so these readings '
          'were never recorded. They are gone for good.',
    GapReason.bufferRollover =>
      'The bridge recorded over these before the app could fetch them. They '
          'are gone for good.',
  };

  bool get isPermanent =>
      this == GapReason.baseLost || this == GapReason.bufferRollover;
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
