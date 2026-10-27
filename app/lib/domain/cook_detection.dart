import 'models.dart';

/// One bucket of activity in the recorded archive, used only by cook
/// detection. `start`/`end` are the real first and last recorded timestamps in
/// the bucket, so a detected cook keeps exact clock times even though the
/// activity scan itself is downsampled.
class CookActivity {
  const CookActivity({
    required this.start,
    required this.end,
    required this.probes,
  });

  final DateTime start;
  final DateTime end;

  /// Distinct probes that reported at least one valid value in this bucket.
  final int probes;
}

/// A cook is an unbroken run of recorded readings: new readings keep arriving
/// at the normal cadence. [maxIdle] is deliberately much longer than the 30 s
/// sample cadence so one missed packet never ends a cook. Readings separated by
/// more than that are different cooks.
class CookDetection {
  const CookDetection({
    this.maxIdle = const Duration(minutes: 30),
    this.minimumDuration = const Duration(minutes: 10),
    this.missingThreshold = const Duration(minutes: 10),
  });

  final Duration maxIdle;
  final Duration minimumDuration;

  /// A hole wider than this inside a run means the cook is missing readings.
  /// Bucketed activity is coarser than the raw 30 s cadence, so this must stay
  /// well above one bucket.
  final Duration missingThreshold;

  /// Newest cook first. [gapSpans] are archive gap bands; a gap that overlaps a
  /// cook marks it as having missing readings.
  List<CookSession> detect(
    List<CookActivity> activity, {
    List<({DateTime start, DateTime end})> gapSpans = const [],
  }) {
    if (activity.isEmpty) return const <CookSession>[];
    final sorted = List<CookActivity>.of(activity)
      ..sort((a, b) => a.start.compareTo(b.start));

    final cooks = <CookSession>[];
    var start = sorted.first.start;
    var end = sorted.first.end;
    var probes = sorted.first.probes;
    var missing = false;

    void close() {
      if (end.difference(start) >= minimumDuration) {
        cooks.add(
          CookSession(
            start: start,
            end: end,
            probes: probes,
            hasGap: missing,
          ),
        );
      }
    }

    for (final bucket in sorted.skip(1)) {
      final idle = bucket.start.difference(end);
      if (idle > maxIdle) {
        close();
        start = bucket.start;
        end = bucket.end;
        probes = bucket.probes;
        missing = false;
        continue;
      }
      if (idle > missingThreshold) missing = true;
      if (bucket.end.isAfter(end)) end = bucket.end;
      if (bucket.probes > probes) probes = bucket.probes;
    }
    close();

    if (gapSpans.isNotEmpty && cooks.isNotEmpty) {
      final withGaps = <CookSession>[];
      for (final cook in cooks) {
        final overlapped = gapSpans.any(
          (span) =>
              span.start.isBefore(cook.end) && span.end.isAfter(cook.start),
        );
        withGaps.add(
          overlapped == cook.hasGap
              ? cook
              : CookSession(
                  start: cook.start,
                  end: cook.end,
                  probes: cook.probes,
                  hasGap: overlapped,
                ),
        );
      }
      return withGaps.reversed.toList(growable: false);
    }

    return cooks.reversed.toList(growable: false);
  }
}
