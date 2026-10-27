import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/ble/bridge_link.dart';
import 'package:smoke_bridge/data/ble/bridge_protocol.dart';
import 'package:smoke_bridge/data/recent_history_store.dart';
import 'package:smoke_bridge/domain/models.dart';

import 'support/recent_history.dart';

final DateTime _now = DateTime.utc(2026, 10, 27, 12);

Future<RecentHistoryStore> _syncedStore({DateTime Function()? now}) async {
  final store = RecentHistoryStore(now: now ?? () => _now);
  await store.accept(
    BridgeSyncBatch(
      records: <BridgeSampleRecord>[
        for (final record in buildThirtyRecentRecords(_now))
          BridgeSampleRecord(
            seq: record.seq,
            unixS: record.unixS,
            tempsF10: record.temp,
            flags: record.flags,
          ),
      ],
      startSeq: 100,
      endSeq: 129,
      nextSeq: 130,
      direction: BridgeSyncDirection.backward,
      generation: 1,
    ),
  );
  return store;
}

void main() {
  test('a 30-record sync stores four series with one detached probe', () async {
    final store = await _syncedStore();

    expect(store.hasRecords, isTrue);
    expect(store.hasAnyReadings, isTrue);
    expect(store.samples, hasLength(30));

    final fixture = store.fixture(range: HistoryRange.oneHour);
    expect(fixture.series, hasLength(4));
    expect(fixture.series[0].points, hasLength(30));
    expect(fixture.series[1].points, hasLength(30));
    expect(fixture.series[2].points, hasLength(30));
    expect(fixture.series[3].points, hasLength(30));

    // P3 is detached: absent, never 0 °F.
    expect(
      fixture.series[2].points.every((point) => point.valueF == null),
      isTrue,
    );
    expect(
      fixture.series[0].points.every((point) => point.valueF != null),
      isTrue,
    );
    expect(
      ProbeRangeStats.fromSeries(fixture.series[2]).last,
      isNull,
      reason: 'a detached probe has no latest reading',
    );
  });

  test('adjacent readings more than 90 s apart never share a line', () async {
    final store = await _syncedStore();
    final fixture = store.fixture(range: HistoryRange.oneHour);

    for (final index in <int>[0, 1, 3]) {
      final runs = historySeriesSegments(fixture.series[index]);
      expect(
        runs,
        hasLength(2),
        reason: 'P${index + 1} must break at the >90 s gap',
      );
      expect(runs[0].length, 15);
      expect(runs[1].length, 15);
    }
    expect(historySeriesSegments(fixture.series[2]), isEmpty);

    // The chart's gap band names the widest hole without inventing readings.
    expect(fixture.gapStart, isNot(fixture.gapEnd));
    expect(
      fixture.gapEnd.difference(fixture.gapStart),
      greaterThan(historyGapThreshold),
    );
  });

  test('selections beyond the recent window keep the same honest data', () async {
    final store = await _syncedStore();

    final day = store.fixture(range: HistoryRange.twentyFourHours);
    expect(day.hasValues, isTrue);
    expect(historySeriesSegments(day.series[0]), hasLength(2));

    final outside = store.fixture(
      range: HistoryRange.custom,
      customStart: _now.subtract(const Duration(days: 3)),
      customEnd: _now.subtract(const Duration(days: 2)),
    );
    expect(outside.hasValues, isFalse);
    expect(
      outside.series.every((series) => series.points.isEmpty),
      isTrue,
      reason: 'an out-of-range selection must not show another period',
    );
  });

  test('empty store and empty request never invent a series', () async {
    final store = RecentHistoryStore(now: () => _now);
    final fixture = store.fixture(range: HistoryRange.oneHour);

    expect(store.hasRecords, isFalse);
    expect(store.hasAnyReadings, isFalse);
    expect(fixture.hasValues, isFalse);
    expect(fixture.series, hasLength(4));
  });
}
