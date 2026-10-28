import '../domain/models.dart';
import 'ble/bridge_link.dart';

/// One synced reading, normalised to the app's domain vocabulary.
class RecentSample {
  const RecentSample({
    required this.seq,
    required this.time,
    required this.tempsF,
    required this.clockValid,
    required this.billowsAttached,
  });

  final int seq;
  final DateTime time;

  /// P1–P4 in °F. `null` means detached or invalid, never 0 °F.
  final List<double?> tempsF;
  final bool clockValid;
  final bool billowsAttached;
}

/// V0's in-memory recent History.
///
/// The durable archive (cursors, generations, older pages and retention) is
/// T39–T41. This store only answers "what did this session sync?" and keeps the
/// approved History shell honest until then: the last 15 minutes from the
/// Bridge, four probe series, a gap whenever adjacent readings are more than
/// 90 s apart, and no invented values for a detached probe.
class RecentHistoryStore implements BridgeSyncSink {
  RecentHistoryStore({this.onChanged, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Called after a batch changes the store so History can repaint.
  final void Function()? onChanged;
  final DateTime Function() _now;

  final Map<int, RecentSample> _bySeq = <int, RecentSample>{};

  /// The V0 window. Only the recent pass is stored, so a wider selection can
  /// only honestly draw what it has; it never stretches or synthesises data.
  static const Duration recentWindow = Duration(minutes: 15);

  bool get hasRecords => _bySeq.isNotEmpty;

  bool get hasAnyReadings =>
      _bySeq.values.any((sample) => sample.tempsF.any((temp) => temp != null));

  DateTime? get newestAt {
    if (_bySeq.isEmpty) return null;
    return _bySeq.values
        .map((sample) => sample.time)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }

  DateTime? get oldestAt {
    if (_bySeq.isEmpty) return null;
    return _bySeq.values
        .map((sample) => sample.time)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  List<RecentSample> get samples {
    final values = _bySeq.values.toList()
      ..sort((a, b) {
        final byTime = a.time.compareTo(b.time);
        return byTime != 0 ? byTime : a.seq.compareTo(b.seq);
      });
    return values;
  }

  @override
  Future<void> accept(BridgeSyncBatch batch) async {
    for (final record in batch.records) {
      if (record.unixS == 0) continue;
      _bySeq[record.seq] = RecentSample(
        seq: record.seq,
        time: DateTime.fromMillisecondsSinceEpoch(
          record.unixS * 1000,
          isUtc: true,
        ).toLocal(),
        tempsF: <double?>[
          for (var index = 0; index < 4; index++)
            record.probeAttached(index) ? record.tempF(index) : null,
        ],
        clockValid: record.clockValid,
        billowsAttached: record.billowsAttached,
      );
    }
    onChanged?.call();
  }

  /// Seeds the in-memory sparkline window from the durable archive.
  ///
  /// Cold launch uses this once, before the link exists, so Live is not forced
  /// to claim `No history yet` while the phone already holds real readings. It
  /// is not a second sync path: the archive remains the source and later live
  /// notifications / sync batches replace the same seq.
  void seed(Iterable<RecentSample> values) {
    var changed = false;
    for (final sample in values) {
      _bySeq[sample.seq] = sample;
      changed = true;
    }
    if (changed) onChanged?.call();
  }

  /// Adds the reading carried by a `live` notification.
  ///
  /// Live notifications arrive between sync passes, so recording them keeps the
  /// Live sparklines and the History chart moving every few seconds instead of
  /// waiting for the next Bluetooth sync. A later sync of the same sequence
  /// replaces this sample with the Bridge's stored timestamp and flags.
  void recordLive({
    required int seq,
    required DateTime time,
    required List<double?> tempsF,
    required bool clockValid,
    required bool billowsAttached,
  }) {
    if (seq <= 0 || seq == 0xFFFFFFFF) return;
    _bySeq[seq] = RecentSample(
      seq: seq,
      time: time,
      tempsF: List<double?>.unmodifiable(tempsF),
      clockValid: clockValid,
      billowsAttached: billowsAttached,
    );
    onChanged?.call();
  }

  /// The last hour of one probe, ready for [ProbeSparkline]. Nulls are kept so
  /// a detached probe or a real transmission gap breaks the line.
  List<ChartPoint> sparkline(
    int probe, {
    Duration window = const Duration(hours: 1),
  }) {
    // The window follows the newest reading, not the wall clock, so a cold
    // launch with a stale-but-real archive still shows the last recorded hour
    // instead of an empty tile. A healthy link's newest reading is ~now.
    final now = _now();
    final newest = newestAt;
    final end = newest != null && newest.isBefore(now) ? newest : now;
    final start = end.subtract(window);
    return <ChartPoint>[
      for (final sample in samples)
        if (!sample.time.isBefore(start) && !sample.time.isAfter(end))
          ChartPoint(sample.time, sample.tempsF[probe]),
    ];
  }

  /// Builds the view shape used by the approved History screen.
  ///
  /// The requested range is the real chart window. In V0 that window may be
  /// wider than the readings the Bridge sent; the extra space simply stays
  /// empty. A range with no readings in it yields empty series, never a
  /// preview of some other period.
  HistoryFixture fixture({
    required HistoryRange range,
    DateTime? customStart,
    DateTime? customEnd,
    bool empty = false,
    bool estimated = false,
    bool missingFromBridge = false,
  }) {
    final now = _now();
    final (start, end) = _window(range, now, customStart, customEnd);
    final inWindow = empty
        ? const <RecentSample>[]
        : samples
              .where(
                (sample) =>
                    !sample.time.isBefore(start) && !sample.time.isAfter(end),
              )
              .toList();

    final series = <ChartSeries>[
      for (var probe = 0; probe < 4; probe++)
        ChartSeries(probe, <ChartPoint>[
          for (final sample in inWindow)
            ChartPoint(sample.time, sample.tempsF[probe]),
        ]),
    ];

    final gap = _largestGap(inWindow);
    final estimatedTimes = estimated || inWindow.any((s) => !s.clockValid);

    return HistoryFixture(
      start: start,
      end: end,
      series: series,
      gapStart: gap?.$1 ?? start,
      gapEnd: gap?.$2 ?? start,
      gapReason: HistoryGapReason.noSignal,
      estimated: estimatedTimes,
      missingFromBridge: missingFromBridge,
    );
  }

  (DateTime, DateTime) _window(
    HistoryRange range,
    DateTime now,
    DateTime? customStart,
    DateTime? customEnd,
  ) {
    if (range == HistoryRange.custom) {
      final rangeStart = customStart ?? oldestAt ?? now.subtract(recentWindow);
      final rangeEnd = customEnd ?? newestAt ?? now;
      return rangeEnd.isAfter(rangeStart)
          ? (rangeStart, rangeEnd)
          : (rangeEnd, rangeEnd);
    }
    final span = switch (range) {
      HistoryRange.oneHour => const Duration(hours: 1),
      HistoryRange.sixHours => const Duration(hours: 6),
      HistoryRange.twentyFourHours => const Duration(hours: 24),
      HistoryRange.twoDays => const Duration(days: 2),
      HistoryRange.custom => recentWindow,
    };
    return (now.subtract(span), now);
  }

  /// The widest hole between adjacent readings, used for the chart's gap band.
  /// The line itself breaks at every hole; this only names the most visible one
  /// in V0, where a single band is all the shell needs.
  (DateTime, DateTime)? _largestGap(List<RecentSample> values) {
    if (values.length < 2) return null;
    var widest = Duration.zero;
    (DateTime, DateTime)? found;
    for (var index = 1; index < values.length; index++) {
      final previous = values[index - 1].time;
      final current = values[index].time;
      final delta = current.difference(previous);
      if (delta > historyGapThreshold && delta > widest) {
        widest = delta;
        found = (previous, current);
      }
    }
    return found;
  }

  /// Everything this store currently holds, for the custom-range sheet.
  (DateTime, DateTime)? get range {
    final oldest = oldestAt;
    final newest = newestAt;
    if (oldest == null || newest == null) return null;
    return (oldest, newest);
  }
}
