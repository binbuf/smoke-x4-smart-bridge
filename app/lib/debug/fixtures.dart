import 'dart:math' as math;

import '../domain/models.dart';

/// Debug/test-only fixture generators.
///
/// Production code must not import this file. The screenshot tool, widget
/// tests and the Experimental lab opt in through `demo_content.dart`.
class DebugFixtures {
  DebugFixtures._();
}

/// Stable fixture clock used by History and cook detection. Production replaces
/// it with the newest synced sample from the Bridge.
final DateTime fixtureNow = DateTime(2026, 10, 25, 18, 30);

/// A deterministic archive used by the review build. Production derives the
/// same shape from recorded samples (M3).
List<CookSession> buildCookSessions() {
  CookSession session(
    DateTime start,
    DateTime end, {
    int probes = 4,
    bool hasGap = false,
  }) {
    return CookSession(start: start, end: end, probes: probes, hasGap: hasGap);
  }

  return [
    session(
      DateTime(2026, 10, 25, 9, 10),
      DateTime(2026, 10, 25, 18, 30),
      hasGap: true,
    ),
    session(
      DateTime(2026, 10, 25, 1, 40),
      DateTime(2026, 10, 25, 7, 5),
      probes: 3,
    ),
    session(DateTime(2026, 10, 24, 10, 5), DateTime(2026, 10, 24, 19, 20)),
    session(
      DateTime(2026, 10, 23, 16, 30),
      DateTime(2026, 10, 24, 8, 10),
      hasGap: true,
    ),
    session(DateTime(2026, 10, 22, 11, 5), DateTime(2026, 10, 22, 20, 30)),
    session(
      DateTime(2026, 10, 20, 8, 45),
      DateTime(2026, 10, 20, 18, 20),
      probes: 3,
    ),
    session(
      DateTime(2026, 10, 19, 17, 40),
      DateTime(2026, 10, 20, 7, 15),
      hasGap: true,
    ),
    session(DateTime(2026, 10, 17, 9, 30), DateTime(2026, 10, 17, 19, 10)),
    session(
      DateTime(2026, 10, 14, 10, 15),
      DateTime(2026, 10, 14, 20, 5),
      probes: 2,
    ),
    session(DateTime(2026, 10, 11, 8, 20), DateTime(2026, 10, 11, 17, 45)),
    session(DateTime(2026, 10, 8, 12, 10), DateTime(2026, 10, 8, 21, 30)),
    session(
      DateTime(2026, 10, 4, 9, 0),
      DateTime(2026, 10, 4, 18, 15),
      probes: 3,
    ),
    session(DateTime(2026, 10, 1, 10, 30), DateTime(2026, 10, 1, 19, 40)),
  ];
}

CookSession? latestCookSession() {
  final cooks = buildCookSessions();
  return cooks.isEmpty ? null : cooks.first;
}

/// A cook is in progress while the newest recorded reading is still inside its
/// session. A long idle period ends the cook and turns it into a past cook.
CookSession? currentCookSession() {
  final latest = latestCookSession();
  if (latest == null) return null;
  final sinceEnd = fixtureNow.difference(latest.end);
  if (sinceEnd.isNegative && sinceEnd.inMinutes.abs() > 5) return null;
  if (sinceEnd.inMinutes > 15) return null;
  return latest;
}

bool isCookInProgress(CookSession cook) {
  final current = currentCookSession();
  if (current == null) return false;
  return current.start == cook.start && current.end == cook.end;
}

HistoryFixture buildHistoryFixture(
  HistoryRange range, {
  bool empty = false,
  bool oneProbe = false,
  bool estimated = false,
  bool missingFromBridge = false,
  bool hasGap = true,
  DateTime? customStart,
  DateTime? customEnd,
}) {
  final now = fixtureNow;
  final Duration span;
  final int count;
  final double gapPosition;
  final double gapWidth;
  switch (range) {
    case HistoryRange.oneHour:
      span = const Duration(hours: 1);
      count = 60;
      gapPosition = 0.38;
      gapWidth = 0.08;
      break;
    case HistoryRange.sixHours:
      span = const Duration(hours: 6);
      count = 72;
      gapPosition = 0.46;
      gapWidth = 0.05;
      break;
    case HistoryRange.twentyFourHours:
      span = const Duration(hours: 24);
      count = 96;
      gapPosition = 0.52;
      gapWidth = 0.04;
      break;
    case HistoryRange.twoDays:
      span = const Duration(days: 2);
      count = 96;
      gapPosition = 0.48;
      gapWidth = 0.04;
      break;
    case HistoryRange.custom:
      final start = customStart ?? now.subtract(const Duration(hours: 24));
      final end = customEnd ?? now;
      span = end.difference(start).isNegative
          ? const Duration(hours: 24)
          : end.difference(start);
      count = (span.inMinutes ~/ 30).clamp(24, 240);
      gapPosition = 0.42;
      gapWidth = 0.04;
      break;
  }

  final start = range == HistoryRange.custom
      ? (customStart ?? now.subtract(span))
      : now.subtract(span);
  final end = range == HistoryRange.custom ? (customEnd ?? now) : now;
  final effectiveSpan = end.difference(start);
  final gapStart = hasGap
      ? start.add(
          Duration(
            milliseconds: (effectiveSpan.inMilliseconds * gapPosition).round(),
          ),
        )
      : start;
  final gapEnd = hasGap
      ? start.add(
          Duration(
            milliseconds:
                (effectiveSpan.inMilliseconds * (gapPosition + gapWidth)).round(),
          ),
        )
      : start;

  const bases = [165.0, 164.0, 151.0, 224.0];
  const amplitudes = [12.0, 10.0, 15.0, 18.0];

  final series = <ChartSeries>[];
  for (var probe = 0; probe < 4; probe++) {
    if (empty || (oneProbe && probe < 3)) {
      series.add(ChartSeries(probe, const []));
      continue;
    }
    final points = <ChartPoint>[];
    for (var i = 0; i <= count; i++) {
      final ratio = i / count;
      final time = start.add(
        Duration(milliseconds: (effectiveSpan.inMilliseconds * ratio).round()),
      );
      final inGap = hasGap && time.isAfter(gapStart) && time.isBefore(gapEnd);
      final drift = (range == HistoryRange.twoDays || range == HistoryRange.custom)
          ? math.sin(ratio * math.pi * 2) * 4
          : 0.0;
      final value =
          bases[probe] +
          amplitudes[probe] * math.sin(ratio * math.pi * 4 + probe * 1.2) +
          math.sin(ratio * math.pi * 17 + probe) * 1.7 +
          drift;
      points.add(ChartPoint(time, inGap ? null : value));
    }
    series.add(ChartSeries(probe, points));
  }

  return HistoryFixture(
    start: start,
    end: end,
    series: series,
    gapStart: gapStart,
    gapEnd: gapEnd,
    gapReason: missingFromBridge
        ? HistoryGapReason.bridgeRotated
        : HistoryGapReason.noSignal,
    estimated: estimated,
    missingFromBridge: missingFromBridge,
  );
}

/// Sparklines use their own relative scale. They deliberately contain no axes
/// or labels; the tile supplies the range and the trend.
List<ChartPoint> buildSparklinePoints(
  int probe, {
  bool hasData = true,
  int count = 60,
}) {
  if (!hasData) return const [];
  final now = fixtureNow;
  const span = Duration(hours: 1);
  const bases = [165.0, 164.0, 151.0, 224.0];
  const amplitudes = [4.0, 3.0, 5.0, 6.0];
  final start = now.subtract(span);
  return List<ChartPoint>.generate(count + 1, (index) {
    final ratio = index / count;
    final time = start.add(
      Duration(milliseconds: (span.inMilliseconds * ratio).round()),
    );
    final value =
        bases[probe] +
        amplitudes[probe] * math.sin(ratio * math.pi * 2.4 + probe * 0.8) +
        math.sin(ratio * math.pi * 11 + probe) * 1.1;
    return ChartPoint(time, value);
  });
}
