import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/data/db/app_database.dart';
import 'package:smoke_bridge/data/db/sample_dao.dart';
import 'package:smoke_bridge/domain/content.dart';
import 'package:smoke_bridge/features/live/live_screen.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
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
      HistoryWindow(start: _now.subtract(const Duration(hours: 1)), end: _now);

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
    final start = customStart ?? _now.subtract(const Duration(hours: 1));
    final end = customEnd ?? _now;
    return HistoryFixture(
      start: start,
      end: end,
      series: const <ChartSeries>[
        ChartSeries(0, <ChartPoint>[]),
        ChartSeries(1, <ChartPoint>[]),
        ChartSeries(2, <ChartPoint>[]),
        ChartSeries(3, <ChartPoint>[]),
      ],
      gapStart: start,
      gapEnd: start,
      gapReason: HistoryGapReason.noSignal,
      estimated: estimated,
      missingFromBridge: missingFromBridge,
    );
  }

  @override
  List<CookSession> cooks() => const <CookSession>[];
}

StoredSample _sample(DateTime time, int seq, {int? p1, int? p2}) {
  return StoredSample(
    bridgeId: 'AC:A7:04:38:82:76',
    generation: 1,
    seq: seq,
    unixS: time.millisecondsSinceEpoch ~/ 1000,
    recordedMs: time.millisecondsSinceEpoch,
    timeEstimated: 0,
    tempsF10: <int?>[p1, p2, null, null],
    flags: 0x1F,
  );
}

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late SampleDao dao;

  setUp(() async {
    database = await AppDatabase.openInMemory(factory: databaseFactoryFfi);
    dao = SqfliteSampleDao(database);
    await dao.saveBridge(
      const SavedBridge(
        id: 'AC:A7:04:38:82:76',
        name: 'SmokeX4-8276',
        lastSeenMs: 0,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'a cold launch with a durable archive backfills the Live sparklines',
    () async {
      await dao.insertSamples(<StoredSample>[
        for (var i = 0; i < 100; i++)
          _sample(
            _now.subtract(Duration(minutes: 50 - i ~/ 2)),
            i,
            p1: 2250 + i,
            p2: i.isEven ? 1650 : null,
          ),
      ]);
      final controller = BridgeController(
        content: const _FixedContent(),
        sampleDao: dao,
      );
      addTearDown(controller.dispose);

      await controller.prepareLaunch();

      final view = controller.liveView;
      expect(
        view.probes[0].lastHour.any((point) => point.valueF != null),
        isTrue,
        reason: 'P1 must use the durable archive, not an empty session buffer',
      );
      expect(
        view.probes[1].lastHour.any((point) => point.valueF != null),
        isTrue,
      );
      // A probe with no valid stored value keeps the approved empty treatment;
      // the archive has no rows for it.
      expect(
        view.probes[3].lastHour.any((point) => point.valueF != null),
        isFalse,
      );
    },
  );

  test(
    'a stale durable archive still backfills the last recorded hour',
    () async {
      final lastReading = _now.subtract(const Duration(hours: 6));
      await dao.insertSamples(<StoredSample>[
        for (var i = 0; i < 60; i++)
          _sample(
            lastReading.subtract(Duration(minutes: 30 - i ~/ 2)),
            i,
            p1: 2250 + i,
            p2: 1650,
          ),
      ]);
      final controller = BridgeController(
        content: const _FixedContent(),
        sampleDao: dao,
      );
      addTearDown(controller.dispose);

      await controller.prepareLaunch();

      expect(
        controller.liveView.probes[0].lastHour.any(
          (point) => point.valueF != null,
        ),
        isTrue,
        reason: 'the last recorded hour is better than a false empty state',
      );
    },
  );

  testWidgets('backfilled sparklines never show the No history yet copy', (
    tester,
  ) async {
    late BridgeController controller;
    await tester.runAsync(() async {
      await dao.insertSamples(<StoredSample>[
        for (var i = 0; i < 60; i++)
          _sample(
            _now.subtract(Duration(minutes: 30 - i ~/ 2)),
            i,
            p1: 2250 + i,
            p2: 1650,
          ),
      ]);
      controller = BridgeController(
        content: const _FixedContent(),
        sampleDao: dao,
      )..phase = ConnectionPhase.offline;
      await controller.prepareLaunch();
    });
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: LiveScreen(controller: controller)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.descendant(
        of: find.byKey(const Key('live.probe.1')),
        matching: find.text('No history yet'),
      ),
      findsNothing,
    );
  });

  test(
    'the offline saved-Bridge header uses the saved identity, never A4F2',
    () async {
      final controller = BridgeController(
        content: const _FixedContent(),
        sampleDao: dao,
      );
      addTearDown(controller.dispose);

      await controller.prepareLaunch();

      expect(controller.deviceId, '8276');
      expect(controller.deviceName, 'SmokeX4-8276');
      expect(controller.deviceId, isNot('A4F2'));
      expect(controller.settingsView.deviceId, '8276');
      expect(controller.bridgeDetailsView.deviceId, '8276');
      expect(controller.bridgeDetailsView.deviceName, 'SmokeX4-8276');
    },
  );

  testWidgets('the offline Settings header renders the saved id, not A4F2', (
    tester,
  ) async {
    late BridgeController controller;
    await tester.runAsync(() async {
      controller = BridgeController(
        content: const _FixedContent(),
        sampleDao: dao,
      );
      await controller.prepareLaunch();
      controller.tab = AppTab.settings;
    });
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: AppShell(controller: controller),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Bridge 8276'), findsOneWidget);
    expect(find.text('Bridge A4F2'), findsNothing);
  });
}
