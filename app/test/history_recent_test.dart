import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/data/ble/ble_client.dart';
import 'package:smoke_bridge/data/ble/bridge_link.dart';
import 'package:smoke_bridge/domain/content.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/theme/app_theme.dart';
import 'package:smoke_bridge/widgets/probe_chart.dart';
import 'package:smoke_bridge/widgets/prototype_widgets.dart';

import 'support/fake_ble_client.dart';
import 'support/fake_bridge.dart';
import 'support/recent_history.dart';

final DateTime _now = DateTime.utc(2026, 10, 27, 12);

Widget _shell(BridgeController controller) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    home: AppShell(controller: controller),
  );
}

Future<void> _pump(WidgetTester tester, BridgeController controller) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_shell(controller));
  await tester.pumpAndSettle();
}

class _FixedContent implements BridgeContent {
  _FixedContent(this.now);

  @override
  final DateTime now;

  @override
  List<double?> get probeTemps => const <double?>[160.0, 150.0, null, 220.0];

  @override
  HistoryWindow get historyWindow =>
      HistoryWindow(start: now.subtract(const Duration(hours: 1)), end: now);

  @override
  int get bridgeRecords => 30;

  @override
  int get bridgeCapacity => 1000;

  @override
  int get phoneRecords => 30;

  @override
  String get savedDataRange => '—';

  @override
  String get savedDataSize => '0 B';

  @override
  List<ChartPoint> sparkline(int probe, {required bool hasData}) =>
      const <ChartPoint>[];

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
    return HistoryFixture(
      start: now,
      end: now,
      series: const <ChartSeries>[
        ChartSeries(0, <ChartPoint>[]),
        ChartSeries(1, <ChartPoint>[]),
        ChartSeries(2, <ChartPoint>[]),
        ChartSeries(3, <ChartPoint>[]),
      ],
      gapStart: now,
      gapEnd: now,
      gapReason: HistoryGapReason.noSignal,
      estimated: estimated,
      missingFromBridge: missingFromBridge,
    );
  }

  @override
  List<CookSession> cooks() => const <CookSession>[];
}

class _SyncedSession {
  _SyncedSession() {
    bridge = FakeBridge(
      seq: 200,
      initialRecords: buildThirtyRecentRecords(_now),
    );
    client = FakeBleClient(
      server: bridge,
      advertisements: <BleDevice>[bridge.advertisement()],
      connectDelay: Duration.zero,
      bondDelay: Duration.zero,
      scanInterval: Duration.zero,
    );
    controller = BridgeController(
      bleClient: client,
      content: _FixedContent(_now),
    )..hasSavedBridge = true;
    link = controller.ensureLink(
      nowUtc: () => _now,
      bondPrompt: () async => true,
    );
    device = bridge.advertisement();
  }

  late final FakeBridge bridge;
  late final FakeBleClient client;
  late final BridgeController controller;
  late final BridgeLink link;
  late final BleDevice device;

  Future<void> sync() async {
    await link.connectAndSecure(device);
    await Future<void>.delayed(Duration.zero);
    controller.tab = AppTab.history;
    controller.notifyListeners();
  }
}

void main() {
  testWidgets(
    'a fake sync of 30 readings draws the full History shell with a gap',
    (tester) async {
      final session = _SyncedSession();
      addTearDown(session.controller.dispose);
      await tester.runAsync(session.sync);

      final fixture = session.controller.recentHistory.fixture(
        range: HistoryRange.oneHour,
      );
      expect(fixture.series, hasLength(4));
      expect(historySeriesSegments(fixture.series[0]), hasLength(2));
      expect(historySeriesSegments(fixture.series[1]), hasLength(2));
      expect(historySeriesSegments(fixture.series[3]), hasLength(2));
      expect(
        historySeriesSegments(fixture.series[2]),
        isEmpty,
        reason: 'P3 is detached for the whole sync',
      );

      await _pump(tester, session.controller);

      expect(find.byKey(const Key('history.filters')), findsOneWidget);
      expect(find.byKey(const Key('history.chart')), findsOneWidget);
      expect(find.byKey(const Key('history.summary')), findsOneWidget);
      expect(find.byKey(const Key('history.cooks')), findsOneWidget);
      expect(find.text('Cooks'), findsOneWidget);
      expect(
        find.text('Grouped automatically from your readings'),
        findsOneWidget,
      );
      expect(find.text('Latest'), findsOneWidget);
      expect(find.text('Min'), findsOneWidget);
      expect(find.text('Max'), findsOneWidget);
      expect(find.text('No data'), findsOneWidget);

      // The chart is the real multi-series surface, not a placeholder.
      expect(find.byType(HistoryChart), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);

      // Range/probe shared with Live survive a tab switch.
      session.controller
        ..setHistoryProbe(2)
        ..setHistoryRange(HistoryRange.sixHours);
      await tester.tap(find.text('Live'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(session.controller.historyProbe, 2);
      expect(session.controller.historyRange, HistoryRange.sixHours);

      await session.link.dispose();
    },
  );

  testWidgets('reset icon appears only while a filter is active', (
    tester,
  ) async {
    final session = _SyncedSession();
    addTearDown(session.controller.dispose);
    await tester.runAsync(session.sync);
    await _pump(tester, session.controller);

    expect(find.byKey(const Key('history.filters.reset')), findsNothing);

    await tester.tap(find.byKey(const Key('history.range.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history.range.6h')));
    await tester.pumpAndSettle();

    expect(session.controller.historyRange, HistoryRange.sixHours);
    expect(find.byKey(const Key('history.filters.reset')), findsOneWidget);

    await tester.tap(find.byKey(const Key('history.filters.reset')));
    await tester.pumpAndSettle();

    expect(session.controller.historyRange, HistoryRange.twentyFourHours);
    expect(find.byKey(const Key('history.filters.reset')), findsNothing);

    await session.link.dispose();
  });

  testWidgets('History shows an honest empty state with no chart', (
    tester,
  ) async {
    final controller = BridgeController()
      ..hasSavedBridge = true
      ..historyHasData = false
      ..tab = AppTab.history;
    addTearDown(controller.dispose);

    await _pump(tester, controller);

    expect(find.text('No readings yet'), findsOneWidget);
    expect(find.byType(HistoryChart), findsNothing);
    expect(find.byKey(const Key('history.cooks')), findsNothing);
    expect(find.byKey(const Key('history.summary')), findsOneWidget);
  });

  testWidgets('offline with saved readings keeps the chart and labels it', (
    tester,
  ) async {
    final session = _SyncedSession();
    addTearDown(session.controller.dispose);
    await tester.runAsync(session.sync);
    await _pump(tester, session.controller);

    session.controller
      ..phase = ConnectionPhase.offline
      ..offlineCache = true
      ..notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('Showing saved readings'), findsOneWidget);
    expect(find.byType(HistoryChart), findsOneWidget);

    await session.link.dispose();
  });

  testWidgets('offline without cache never presents saved readings as current', (
    tester,
  ) async {
    final session = _SyncedSession();
    addTearDown(session.controller.dispose);
    await tester.runAsync(session.sync);
    await _pump(tester, session.controller);

    session.controller
      ..phase = ConnectionPhase.offline
      ..offlineCache = false
      ..notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('No readings yet'), findsOneWidget);
    expect(find.byType(HistoryChart), findsNothing);
    expect(session.controller.recentHistory.hasRecords, isTrue);

    await session.link.dispose();
  });
}
