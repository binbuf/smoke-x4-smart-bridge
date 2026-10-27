// Shared app/domain vocabulary. This file is Flutter-free so formatters, view
// state builders and test fixtures can depend on the same types.

import 'dart:math' as math;

enum AppTab { live, history, settings }

enum ConnectionPhase {
  live,
  stale,
  syncing,
  reconnecting,
  failed,
  offline,
  blocked,
  setup,
}

enum BlockReason {
  none,
  bluetoothOff,
  permissionDenied,
  permissionBlocked,
  unsupportedPhone,
}

enum ProbeHealth { live, aging, stale, frozen }

enum ProbePresence { all, detachedP3, none }

enum BillowsAttachment { unknown, attached, detached }

enum Units { fahrenheit, celsius }

enum HistoryRange { oneHour, sixHours, twentyFourHours, twoDays, custom }

enum ConnectionEventKind {
  bridgeConnected,
  bridgeLost,
  smokeXPaired,
  smokeXLost,
  billowsConnected,
  billowsLost,
  repair,
  sync,
}

enum HistorySort { probe, hottest, highestMax, recent, sinceCookStart }

enum SyncState { idle, recent, backfill, complete, error }

enum SmokeXStatus { pairedLive, pairedLost, unpaired }

enum SettingsSaveState { idle, saving, saved, error }

enum SetupStep {
  noBridge,
  permissionPrimer,
  bluetoothOff,
  permissionDenied,
  permissionBlocked,
  unsupportedPhone,
  scanning,
  noResults,
  connectionFailed,
  results,
  protocolMismatch,
  passkey,
  bonding,
  bondWrongCode,
  bondTimeout,
  bondStale,
  bondStoreFull,
  firstSync,
  savedData,
}

class ConnectionEvent {
  const ConnectionEvent({
    required this.title,
    required this.detail,
    required this.time,
    required this.kind,
  });

  final String title;
  final String detail;
  final DateTime time;
  final ConnectionEventKind kind;
}

class Probe {
  const Probe({
    required this.number,
    required this.tempF,
    required this.health,
  });

  final int number;
  final double? tempF;
  final ProbeHealth health;

  bool get connected => tempF != null;
}

/// One point in a series. `null` means "no reading" so the chart leaves a gap
/// rather than connecting across missing data.
class ChartPoint {
  const ChartPoint(this.time, this.valueF);

  final DateTime time;
  final double? valueF;
}

class ChartSeries {
  const ChartSeries(this.index, this.points);

  final int index;
  final List<ChartPoint> points;
}

enum HistoryGapReason { noSignal, bridgeOff, bridgeRotated }

/// Design rule 06 §6.6: a line never crosses an interval longer than this
/// between adjacent readings. The chart and the recent-history store share it.
const Duration historyGapThreshold = Duration(seconds: 90);

/// Splits a series into drawable runs. A `null` value always breaks the line;
/// so does an adjacent-sample delta greater than [maxDelta] (90 s by default).
/// Nothing is invented to bridge either kind of gap.
List<List<ChartPoint>> historySeriesSegments(
  ChartSeries series, {
  Duration maxDelta = historyGapThreshold,
}) {
  final runs = <List<ChartPoint>>[];
  List<ChartPoint>? current;
  DateTime? previousTime;
  for (final point in series.points) {
    if (point.valueF == null) {
      current = null;
      previousTime = null;
      continue;
    }
    final delta = previousTime == null
        ? Duration.zero
        : point.time.difference(previousTime);
    if (current == null || delta.isNegative || delta > maxDelta) {
      current = <ChartPoint>[];
      runs.add(current);
    }
    current.add(point);
    previousTime = point.time;
  }
  return runs;
}

/// The data shape a History view renders. Production fills it from SQLite/sync;
/// review builds fill it from the debug fixture adapter.
class HistoryFixture {
  const HistoryFixture({
    required this.start,
    required this.end,
    required this.series,
    required this.gapStart,
    required this.gapEnd,
    required this.gapReason,
    required this.estimated,
    required this.missingFromBridge,
  });

  final DateTime start;
  final DateTime end;
  final List<ChartSeries> series;
  final DateTime gapStart;
  final DateTime gapEnd;
  final HistoryGapReason gapReason;
  final bool estimated;
  final bool missingFromBridge;

  bool get hasValues =>
      series.any((item) => item.points.any((point) => point.valueF != null));

  bool seriesHasValues(int probe) =>
      series[probe].points.any((point) => point.valueF != null);
}

/// A detectable cook in the recorded archive. Cooks are inferred from the
/// readings themselves (continuous runs separated by long idle periods), not
/// named or scheduled by the user.
class CookSession {
  const CookSession({
    required this.start,
    required this.end,
    required this.probes,
    required this.hasGap,
  });

  final DateTime start;
  final DateTime end;
  final int probes;
  final bool hasGap;

  Duration get duration => end.difference(start);
}

class ProbeRangeStats {
  const ProbeRangeStats({
    required this.probe,
    required this.first,
    required this.last,
    required this.min,
    required this.max,
    required this.average,
    required this.readingCount,
    required this.lastSampleAt,
  });

  final int probe;
  final double? first;
  final double? last;
  final double? min;
  final double? max;
  final double? average;
  final int readingCount;
  final DateTime? lastSampleAt;

  bool get hasData => last != null;

  double? get change {
    if (first == null || last == null) return null;
    return last! - first!;
  }

  static ProbeRangeStats fromSeries(ChartSeries series) {
    final values = <double>[];
    DateTime? lastAt;
    for (final point in series.points) {
      if (point.valueF == null) continue;
      values.add(point.valueF!);
      lastAt = point.time;
    }
    if (values.isEmpty) {
      return ProbeRangeStats(
        probe: series.index + 1,
        first: null,
        last: null,
        min: null,
        max: null,
        average: null,
        readingCount: 0,
        lastSampleAt: null,
      );
    }
    final total = values.fold<double>(0, (sum, value) => sum + value);
    return ProbeRangeStats(
      probe: series.index + 1,
      first: values.first,
      last: values.last,
      min: values.reduce(math.min),
      max: values.reduce(math.max),
      average: total / values.length,
      readingCount: values.length,
      lastSampleAt: lastAt,
    );
  }
}
