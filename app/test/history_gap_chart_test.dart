import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/domain/models.dart';
import 'package:smoke_bridge/widgets/probe_chart.dart';

final DateTime _now = DateTime(2026, 10, 27, 12);

void main() {
  const chart = Rect.fromLTRB(44, 14, 300, 270);

  HistoryGapBand band(Duration startAgo, Duration length) => HistoryGapBand(
    start: _now.subtract(startAgo),
    end: _now.subtract(startAgo).add(length),
    reason: HistoryGapReason.bridgeRotated,
  );

  test('a wide Not synced band renders its approved label', () {
    final rect = historyGapBandRect(
      gap: band(const Duration(hours: 8), const Duration(hours: 6)),
      chart: chart,
      viewStart: _now.subtract(const Duration(hours: 24)),
      viewEnd: _now,
    );
    expect(rect, isNotNull);
    expect(rect!.width, greaterThan(58));
    expect(
      historyGapBandShowsLabel(rect, HistoryGapReason.bridgeRotated),
      isTrue,
    );
    expect(HistoryGapReason.bridgeRotated.label, 'Not synced');
  });

  test(
    'a narrow permanent loss keeps the Not synced label and a visible band',
    () {
      final rect = historyGapBandRect(
        gap: band(const Duration(minutes: 30), const Duration(minutes: 2)),
        chart: chart,
        viewStart: _now.subtract(const Duration(hours: 24)),
        viewEnd: _now,
      );
      expect(rect, isNotNull);
      expect(rect!.width, greaterThanOrEqualTo(2));
      expect(
        historyGapBandShowsLabel(rect, HistoryGapReason.bridgeRotated),
        isTrue,
        reason: 'the permanent-loss label must not vanish at 24 h',
      );
      expect(
        HistoryGapReason.bridgeRotated.explanation,
        contains('can’t be recovered'),
      );
    },
  );

  test('a narrow inferred hole is not labelled at 24 h', () {
    final rect = historyGapBandRect(
      gap: band(const Duration(minutes: 30), const Duration(minutes: 2)),
      chart: chart,
      viewStart: _now.subtract(const Duration(hours: 24)),
      viewEnd: _now,
    );
    expect(rect, isNotNull);
    expect(historyGapBandShowsLabel(rect!, HistoryGapReason.noSignal), isFalse);
  });

  test('a band outside the viewport has no geometry', () {
    expect(
      historyGapBandRect(
        gap: band(const Duration(days: 2), const Duration(minutes: 10)),
        chart: chart,
        viewStart: _now.subtract(const Duration(hours: 1)),
        viewEnd: _now,
      ),
      isNull,
    );
  });
}
