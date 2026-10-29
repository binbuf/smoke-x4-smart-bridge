import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/app/formatters.dart';
import 'package:smoke_bridge/data/db/sample_dao.dart';
import 'package:smoke_bridge/domain/content.dart';
import 'package:smoke_bridge/features/settings/settings_views.dart';
import 'package:smoke_bridge/theme/app_theme.dart';

final DateTime _now = DateTime(2026, 10, 27, 12);

class _FixedContent implements BridgeContent {
  const _FixedContent();

  @override
  DateTime get now => _now;

  @override
  List<double?> get probeTemps => const <double?>[null, null, null, null];

  @override
  HistoryWindow get historyWindow =>
      HistoryWindow(start: _now.subtract(const Duration(days: 30)), end: _now);

  @override
  int get bridgeRecords => 0;

  @override
  int get bridgeCapacity => 0;

  @override
  int get phoneRecords => 0;

  @override
  String get savedDataRange => '—';

  @override
  String get savedDataSize => '0 B';

  @override
  List<ChartPoint> sparkline(int probe, {required bool hasData}) => const [];

  @override
  HistoryFixture history(
    HistoryRange range, {
    required bool empty,
    required bool oneProbe,
    required bool estimated,
    required bool missingFromBridge,
    required bool hasGap,
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    throw UnsupportedError('the durable archive owns this test');
  }

  @override
  List<CookSession> cooks() => const <CookSession>[];
}

StoredSample _sample(int seq, DateTime time) => StoredSample(
  bridgeId: 'bridge-a',
  generation: 1,
  seq: seq,
  unixS: time.millisecondsSinceEpoch ~/ 1000,
  recordedMs: time.millisecondsSinceEpoch,
  timeEstimated: 0,
  tempsF10: const <int?>[2250, 1650, null, 1800],
  flags: 0x1F,
);

/// Read/delete seam for the screen test. It mirrors the DAO's half-open range
/// contract without a real database, so the widget test never waits on FFI.
class _FakeDao implements SampleDao {
  _FakeDao(this.samples);

  final List<StoredSample> samples;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not used here');

  @override
  Future<int> countSamples({
    String? bridgeId,
    int? generation,
    int? fromMs,
    int? toMs,
  }) async => _matching(fromMs: fromMs, toMs: toMs).length;

  @override
  Future<List<StoredSample>> samplesInRange({
    required int fromMs,
    required int toMs,
    String? bridgeId,
    int? generation,
    int? limit,
    bool ascending = true,
  }) async {
    final rows = _matching(fromMs: fromMs, toMs: toMs)
      ..sort(
        (a, b) => ascending
            ? a.recordedMs.compareTo(b.recordedMs)
            : b.recordedMs.compareTo(a.recordedMs),
      );
    return limit == null ? rows : rows.take(limit).toList();
  }

  @override
  Future<SampleExtent?> extent({String? bridgeId, int? generation}) async {
    if (samples.isEmpty) return null;
    final sorted = <StoredSample>[...samples]
      ..sort((a, b) => a.recordedMs.compareTo(b.recordedMs));
    return SampleExtent(
      count: sorted.length,
      minSeq: sorted.first.seq,
      maxSeq: sorted.last.seq,
      minRecordedMs: sorted.first.recordedMs,
      maxRecordedMs: sorted.last.recordedMs,
    );
  }

  @override
  Future<HistoryDeletion> deleteRange({
    required int fromMs,
    required int toMs,
    String? bridgeId,
    int? generation,
  }) async {
    final before = samples.length;
    samples.removeWhere(
      (row) => row.recordedMs >= fromMs && row.recordedMs < toMs,
    );
    return HistoryDeletion(
      samplesDeleted: before - samples.length,
      gapsDeleted: 0,
      gapsTrimmed: 0,
    );
  }

  @override
  Future<SavedBridge?> savedBridge() async => null;

  @override
  Future<void> updateSyncCursors({
    required String bridgeId,
    required int generation,
    required int? cursorAfter,
    required int? cursorBefore,
    required int? deviceMinSeq,
    required int? deviceMaxSeq,
    required int lastSeenMs,
  }) async {}

  List<StoredSample> _matching({int? fromMs, int? toMs}) => <StoredSample>[
    for (final row in samples)
      if ((fromMs == null || row.recordedMs >= fromMs) &&
          (toMs == null || row.recordedMs < toMs))
        row,
  ];
}

Future<void> _pumpScreen(
  WidgetTester tester,
  BridgeController controller,
) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: HistoryStorageScreen(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late BridgeController controller;

  tearDown(() {
    controller.dispose();
  });

  testWidgets('shows the phone and Bridge copies as separate real summaries', (
    tester,
  ) async {
    final dao = _FakeDao(<StoredSample>[
      _sample(0, _now.subtract(const Duration(days: 31))),
      _sample(1, _now.subtract(const Duration(days: 2))),
      _sample(2, _now.subtract(const Duration(hours: 1))),
    ]);
    controller = BridgeController(
      content: const _FixedContent(),
      sampleDao: dao,
    )..phase = ConnectionPhase.live;
    controller
      ..bridgeRecords = 24810
      ..bridgeCapacity = 338400
      ..bridgeOldestReadingAt = DateTime(2026, 10, 17, 8, 14)
      ..bridgeNewestReadingAt = DateTime(2026, 10, 25, 18, 30);

    await _pumpScreen(tester, controller);

    expect(find.text('History on this phone'), findsOneWidget);
    expect(find.text('History on the Bridge'), findsOneWidget);
    expect(find.text('Readings'), findsNWidgets(2));
    expect(find.text('Storage used'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('216 B'), findsOneWidget);
    expect(find.text('24,810 of 338,400'), findsOneWidget);
    expect(find.text('7.3%'), findsOneWidget);
    expect(find.text('Oct 17, 2026 at 8:14 AM'), findsOneWidget);
    expect(find.text('Oct 25, 2026 at 6:30 PM'), findsOneWidget);
    expect(find.text('Two separate copies'), findsNothing);
    expect(find.textContaining('even if the Bridge is reset'), findsNothing);
    expect(find.textContaining('records'), findsNothing);
  });

  testWidgets(
    'delete states the exact count and range and keeps the Bridge copy',
    (tester) async {
      final older = _now.subtract(const Duration(days: 40));
      final older2 = _now.subtract(const Duration(days: 31));
      final recent = _now.subtract(const Duration(hours: 1));
      final dao = _FakeDao(<StoredSample>[
        _sample(0, older),
        _sample(1, older2),
        _sample(2, recent),
      ]);
      controller = BridgeController(
        content: const _FixedContent(),
        sampleDao: dao,
      )..phase = ConnectionPhase.live;
      controller
        ..bridgeRecords = 24810
        ..bridgeCapacity = 338400
        ..bridgeOldestReadingAt = DateTime(2026, 10, 17, 8, 14)
        ..bridgeNewestReadingAt = DateTime(2026, 10, 25, 18, 30);

      await _pumpScreen(tester, controller);
      await tester.ensureVisible(find.text('Delete history from this phone…'));
      await tester.tap(find.text('Delete history from this phone…'));
      await tester.pumpAndSettle();

      expect(find.text('Delete history from this phone'), findsOneWidget);
      expect(
        find.text('2 readings · ${dateRangeLabel(older, older2)}'),
        findsOneWidget,
      );

      await tester.tap(find.text('Older than 30 days'));
      await tester.pumpAndSettle();

      expect(find.text('Delete history older than 30 days?'), findsOneWidget);
      expect(
        find.text('Date range: ${absoluteRangeLabel(older, older2)}'),
        findsOneWidget,
      );
      expect(find.text('2 readings will be deleted'), findsOneWidget);

      await tester.tap(find.text('Delete 2 readings'));
      await tester.pumpAndSettle();

      expect(dao.samples, hasLength(1));
      expect(controller.phoneRecords, 1);
      expect(controller.bridgeRecords, 24810);
      expect(find.text('24,810 of 338,400'), findsOneWidget);
    },
  );

  testWidgets('an empty range is named and cannot be deleted', (tester) async {
    final dao = _FakeDao(<StoredSample>[
      _sample(0, _now.subtract(const Duration(days: 40))),
    ]);
    controller = BridgeController(
      content: const _FixedContent(),
      sampleDao: dao,
    )..phase = ConnectionPhase.live;
    await _pumpScreen(tester, controller);

    await tester.ensureVisible(find.text('Delete history from this phone…'));
    await tester.tap(find.text('Delete history from this phone…'));
    await tester.pumpAndSettle();

    expect(find.text('No readings in this range'), findsOneWidget);
    final option = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Older than 90 days'),
    );
    expect(option.enabled, isFalse);

    await tester.tap(find.text('Older than 90 days'));
    await tester.pumpAndSettle();
    expect(find.text('Delete history older than 90 days?'), findsNothing);
    expect(dao.samples, hasLength(1));
  });

  testWidgets('clearing the Bridge never deletes phone history', (
    tester,
  ) async {
    final dao = _FakeDao(<StoredSample>[
      _sample(0, _now.subtract(const Duration(days: 2))),
      _sample(1, _now.subtract(const Duration(hours: 1))),
    ]);
    controller = BridgeController(
      content: const _FixedContent(),
      sampleDao: dao,
    )..phase = ConnectionPhase.live;
    controller
      ..bridgeRecords = 24810
      ..bridgeCapacity = 338400;

    await _pumpScreen(tester, controller);
    await tester.ensureVisible(find.text('Clear history on the Bridge…'));
    await tester.tap(find.text('Clear history on the Bridge…'));
    await tester.pumpAndSettle();

    expect(find.text('Clear history on the Bridge?'), findsOneWidget);
    expect(
      find.text('24,810 readings in history on the Bridge'),
      findsOneWidget,
    );
    expect(find.text('History on this phone is kept'), findsOneWidget);

    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();

    expect(controller.bridgeRecords, 0);
    expect(controller.phoneRecords, 2);
    expect(dao.samples, hasLength(2));
  });
}
