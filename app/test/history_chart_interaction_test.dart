import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/debug/demo_content.dart';
import 'package:smoke_bridge/debug/fixtures.dart';
import 'package:smoke_bridge/features/history/history_chart_panel.dart';
import 'package:smoke_bridge/theme/app_theme.dart';
import 'package:smoke_bridge/widgets/probe_chart.dart';

void main() {
  Future<void> pumpPanel(
    WidgetTester tester,
    BridgeController controller,
    HistoryChartPanel panel,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 390, child: panel),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('vertical drag on the chart scrolls the page', (tester) async {
    final controller = demoBridgeController()
      ..historyRange = HistoryRange.twentyFourHours;
    addTearDown(controller.dispose);
    final view = controller.historyViewFor();
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: SingleChildScrollView(
              child: SizedBox(width: 390, child: HistoryChartPanel(view: view)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final before = tester.state<ScrollableState>(scrollable).position.pixels;
    await tester.drag(find.byType(HistoryChart), const Offset(0, -160));
    await tester.pumpAndSettle();
    final after = tester.state<ScrollableState>(scrollable).position.pixels;

    expect(after, greaterThan(before));
  });

  testWidgets('the overview brush commits a custom window', (tester) async {
    final end = fixtureNow;
    final controller = demoBridgeController()
      ..historyRange = HistoryRange.custom
      ..historyCustomRange = DateTimeRange(
        start: end.subtract(const Duration(hours: 6)),
        end: end,
      );
    addTearDown(controller.dispose);

    DateTimeRange? committed;
    final requested = <DateTimeRange>[];
    final view = controller.historyViewFor();
    final panel = HistoryChartPanel(
      view: view,
      loadRange: (range) async {
        requested.add(range);
        return controller.content.history(
          HistoryRange.custom,
          empty: false,
          oneProbe: false,
          estimated: false,
          missingFromBridge: false,
          hasGap: true,
          customStart: range.start,
          customEnd: range.end,
        );
      },
      onRangeChanged: (range) => committed = range,
    );

    await pumpPanel(tester, controller, panel);
    expect(find.byKey(const Key('history.overview')), findsOneWidget);
    expect(
      requested.any(
        (range) =>
            range.start == view.entireHistoryRange.start &&
            range.end == view.entireHistoryRange.end,
      ),
      isTrue,
      reason: 'the overview prefetches the whole archive extent',
    );

    await tester.drag(
      find.byKey(const Key('history.overview')),
      const Offset(-90, 0),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(committed, isNotNull);
    expect(committed!.start.isBefore(view.fixture.start), isTrue);
    expect(
      committed!.end.difference(committed!.start),
      const Duration(hours: 6),
    );
  });
}
