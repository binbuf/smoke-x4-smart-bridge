import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/features/history/history_full_screen.dart';
import 'package:smoke_bridge/features/setup/setup_screen.dart';
import 'package:smoke_bridge/features/settings/bridge_details.dart';
import 'package:smoke_bridge/features/settings/settings_details.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/debug/demo_content.dart';
import 'package:smoke_bridge/app/smoke_bridge_app.dart';
import 'package:smoke_bridge/debug/scenario_lab.dart';
import 'package:smoke_bridge/theme/app_theme.dart';
import 'package:smoke_bridge/widgets/probe_sparkline.dart';

Widget shell(BridgeController controller) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    home: AppShell(controller: controller),
  );
}

Future<void> pumpShell(WidgetTester tester, BridgeController controller) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(shell(controller));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('launches into Live with four numbered probes', (tester) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('P1'), findsOneWidget);
    expect(find.text('P4'), findsOneWidget);
    expect(find.byType(ProbeSparkline), findsNWidgets(4));
    expect(find.text('Billows'), findsOneWidget);
    expect(find.text('Brisket'), findsNothing);
    expect(find.text('FOOD'), findsNothing);
    expect(find.text('GRATE'), findsNothing);
    expect(find.text('Open graph'), findsNothing);
    expect(find.text('Last hour'), findsNothing);
  });

  testWidgets('healthy connection is quiet and the lab is in About', (
    tester,
  ) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.byKey(const Key('status.connection')), findsOneWidget);
    expect(find.text('App'), findsOneWidget);
    expect(find.text('Connected · 4s'), findsNothing);
    expect(find.text('Bridge connected · 2h 14m'), findsOneWidget);
    expect(find.text('Fair'), findsOneWidget);
    expect(find.textContaining('Last data 12s ago'), findsNothing);
    expect(find.text('updated 4s ago · bridge 87% · -71 dBm'), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Bridge'), findsOneWidget);
    expect(find.text('History & storage'), findsOneWidget);
    expect(find.text('About'), findsWidgets);
    expect(find.text('ACTIONS'), findsNothing);
    expect(find.text('Storage'), findsOneWidget);
    expect(find.byKey(const Key('settings.history.logs')), findsOneWidget);
    expect(find.text('Smoke X4'), findsNothing);
    expect(find.text('Updated 4s ago'), findsOneWidget);
    expect(find.textContaining('Connected for'), findsNothing);
    expect(find.text('Fair'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Preferences')).dy,
      greaterThan(tester.getTopLeft(find.text('History & storage')).dy),
    );
    expect(find.text('Probe names & roles'), findsNothing);

    await tester.ensureVisible(find.widgetWithText(ListTile, 'About this app'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'About this app'));
    await tester.pumpAndSettle();
    expect(find.text('Smoke X4 Smart Bridge'), findsOneWidget);

    await tester.longPress(find.text('Smoke X4 Smart Bridge'));
    await tester.pumpAndSettle();
    expect(find.text('Experimental lab'), findsOneWidget);
  });

  testWidgets('first-run setup advances without simulation buttons', (
    tester,
  ) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: SetupScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect your Bridge'), findsOneWidget);
    await tester.tap(find.text('Find bridge'));
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(find.text('Nearby bridges'), findsOneWidget);
    expect(find.text('Simulate scan results'), findsNothing);

    await tester.tap(find.text('SmokeX4-A4F2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pair'));
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Loading history'), findsOneWidget);

    await tester.tap(find.text('View live readings'));
    await tester.pump();
    expect(controller.phase, ConnectionPhase.live);
    expect(controller.tab, AppTab.live);
  });

  testWidgets('bottom navigation reaches History and Settings', (tester) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Summary'), findsOneWidget);
    await tester.tap(find.byKey(const Key('history.range.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history.range.2d')));
    await tester.pumpAndSettle();
    expect(controller.historyRange, HistoryRange.twoDays);
    expect(find.text('Cooks'), findsWidgets);
    expect(find.text('Days'), findsNothing);
    expect(find.text('Graph'), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Temperature units'));
    expect(find.text('Temperature units'), findsOneWidget);
  });

  testWidgets('units apply immediately and reach History', (tester) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('°C'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('°C'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Live'));
    await tester.pumpAndSettle();
    expect(find.textContaining('°C'), findsWidgets);
    expect(find.textContaining('°F'), findsNothing);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.textContaining('°C'), findsWidgets);
  });

  testWidgets('History layout fits a 320 px phone', (tester) async {
    final controller = demoBridgeController()..tab = AppTab.history;
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(960, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(shell(controller));
    await tester.pumpAndSettle();

    expect(find.text('Summary'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bridge name dialog saves without crashing', (tester) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.bridge.status')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('bridge.name')));
    await tester.tap(find.byKey(const Key('bridge.name')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Patio Bridge');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(controller.deviceName, 'Patio Bridge');
    expect(tester.takeException(), isNull);
  });

  testWidgets('History filters and summary respond to a probe tile', (
    tester,
  ) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('P1'));
    await tester.pumpAndSettle();
    expect(find.text('Summary'), findsOneWidget);
    expect(controller.historyProbe, 1);
    expect(controller.historyRange, HistoryRange.oneHour);
    expect(find.text('History'), findsWidgets);
  });

  testWidgets('a detached probe is never shown as zero', (tester) async {
    final controller = demoBridgeController()
      ..probePresence = ProbePresence.detachedP3;
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('—'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.textContaining('0.0 °F'), findsNothing);
  });

  testWidgets('offline history stays usable and is labelled', (tester) async {
    final controller = demoBridgeController()
      ..tab = AppTab.history
      ..phase = ConnectionPhase.offline
      ..offlineCache = true;
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Showing saved readings'), findsOneWidget);
    expect(find.text('Last reading 2 hr ago'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
  });

  testWidgets('Live separates the BLE link from Smoke X4 telemetry', (
    tester,
  ) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.byKey(const Key('status.connection')), findsOneWidget);
    expect(find.text('App'), findsOneWidget);
    expect(find.text('Bridge'), findsWidgets);
    expect(find.text('Smoke X4'), findsWidgets);
    expect(find.text('This phone'), findsNothing);
    expect(find.text('Connected'), findsNothing);
    expect(find.text('Receiving'), findsNothing);
    expect(find.textContaining('Connected for'), findsNothing);
    expect(find.text('Bridge connected · 2h 14m'), findsOneWidget);
    expect(find.text('Receiving readings · updated 12s ago'), findsOneWidget);
    expect(find.text('Fair'), findsOneWidget);
  });

  testWidgets('Live distinguishes stale X4 telemetry from a connected Bridge', (
    tester,
  ) async {
    final controller = demoBridgeController()
      ..phase = ConnectionPhase.stale
      ..smokeXStatus = SmokeXStatus.pairedLive;
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    final connection = find.byKey(const Key('status.connection'));
    expect(
      find.descendant(
        of: connection,
        matching: find.text('Bridge connected · 2h 14m'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: connection,
        matching: find.text('No readings for 4 min'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Live names a lost Smoke X4 signal', (tester) async {
    final controller = demoBridgeController()
      ..smokeXStatus = SmokeXStatus.pairedLost;
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Smoke X4 signal lost · 14 min ago'), findsOneWidget);
  });

  testWidgets('Billows only appears when detected and loss is explained', (
    tester,
  ) async {
    final controller = demoBridgeController()
      ..billowsAttachment = BillowsAttachment.unknown
      ..billowsSeenThisSession = false;
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.byKey(const Key('live.billows')), findsNothing);
    expect(find.text('Billows not detected'), findsNothing);

    controller
      ..billowsAttachment = BillowsAttachment.detached
      ..billowsSeenThisSession = true
      ..notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live.billows')), findsNothing);
    expect(find.text('Billows not detected'), findsOneWidget);

    controller
      ..billowsAttachment = BillowsAttachment.attached
      ..notifyListeners();
    await tester.pumpAndSettle();
    final billows = find.byKey(const Key('live.billows'));
    expect(billows, findsOneWidget);
    expect(find.text('Billows not detected'), findsNothing);
    expect(find.text('Set temp'), findsOneWidget);
    expect(find.text('12s ago'), findsOneWidget);
    expect(find.textContaining('Read-only'), findsNothing);
    expect(find.text('Set target'), findsNothing);
    expect(find.text('Monitor only'), findsNothing);
    expect(
      find.descendant(of: billows, matching: find.text('Connected')),
      findsNothing,
    );
  });

  testWidgets('offline Live greys the chain and hides the signal', (
    tester,
  ) async {
    final controller = demoBridgeController()
      ..phase = ConnectionPhase.offline
      ..offlineCache = true;
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(
      find.textContaining('Bridge disconnected · last connected 2 hr ago'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Showing saved readings · last reading 2 hr ago'),
      findsOneWidget,
    );
    expect(find.text('Not connected'), findsNothing);
    expect(find.text('Fair'), findsNothing);
    expect(find.text('Offline'), findsNothing);
  });

  testWidgets('Summary shows latest, min and max without deltas', (
    tester,
  ) async {
    final controller = demoBridgeController()..tab = AppTab.history;
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    final summary = find.byKey(const Key('history.summary'));
    expect(summary, findsOneWidget);
    expect(
      find.descendant(of: summary, matching: find.text('Latest')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Min')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Max')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.textContaining('+')),
      findsNothing,
    );
  });

  testWidgets('Summary sorts since the detected cook started', (tester) async {
    final controller = demoBridgeController()..tab = AppTab.history;
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Probe order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Since cook start'));
    await tester.pumpAndSettle();

    expect(controller.historySort, HistorySort.sinceCookStart);
    expect(find.text('Since cook start'), findsOneWidget);
    expect(find.textContaining('Cook started 9h 20m ago'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
  });

  testWidgets('full-screen chart is a separate view in either orientation', (
    tester,
  ) async {
    final controller = demoBridgeController()..tab = AppTab.history;
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.ensureVisible(find.byTooltip('Full-screen chart'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Full-screen chart'));
    await tester.pumpAndSettle();

    expect(find.byType(HistoryFullScreenScreen), findsOneWidget);
    expect(find.text('Summary'), findsNothing);
    expect(find.text('Cooks'), findsNothing);
    expect(find.byTooltip('Close full-screen chart'), findsOneWidget);

    tester.view.physicalSize = const Size(2532, 1170);
    await tester.pumpAndSettle();
    expect(find.byType(HistoryFullScreenScreen), findsOneWidget);
    expect(find.byTooltip('Close full-screen chart'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Cooks opens a historical view without changing the current view',
    (tester) async {
      final controller = demoBridgeController()..tab = AppTab.history;
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);

      await tester.ensureVisible(find.byKey(const Key('history.cooks.open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('history.cooks.open')));
      await tester.pumpAndSettle();
      final sheet = find.byType(DraggableScrollableSheet);
      expect(sheet, findsOneWidget);
      final yesterday = find.descendant(
        of: sheet,
        matching: find.text('Yesterday'),
      );
      expect(yesterday, findsOneWidget);
      await tester.ensureVisible(yesterday);
      await tester.tap(yesterday);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pastCook.history')), findsOneWidget);
      expect(find.text('Cook'), findsOneWidget);
      expect(find.text('Recorded history'), findsOneWidget);
      expect(controller.historyRange, HistoryRange.twentyFourHours);
      expect(controller.historyCustomRange, isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history.chart')), findsOneWidget);
      expect(controller.historyRange, HistoryRange.twentyFourHours);
    },
  );

  testWidgets('custom range starts with all saved history', (tester) async {
    final controller = demoBridgeController()..tab = AppTab.history;
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.byKey(const Key('history.range.menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history.range.2d')), findsOneWidget);
    expect(find.byKey(const Key('history.range.custom')), findsOneWidget);
    expect(find.text('7D'), findsNothing);
    expect(find.text('ALL'), findsNothing);

    await tester.tap(find.byKey(const Key('history.range.custom')));
    await tester.pumpAndSettle();
    expect(find.text('Custom range'), findsOneWidget);
    expect(controller.historyRange, HistoryRange.custom);
    expect(controller.historyCustomRange, controller.entireHistoryRange);
    expect(find.text('All saved history'), findsOneWidget);
  });

  testWidgets('Bridge details keeps one sync and one repair path', (
    tester,
  ) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: BridgeDetailsScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bridge.connectionLog')), findsOneWidget);
    expect(find.text('Re-pair Smoke X4'), findsOneWidget);
    expect(find.byKey(const Key('bridge.name')), findsOneWidget);
    expect(find.byKey(const Key('bridge.timeout')), findsOneWidget);
    expect(find.byKey(const Key('bridge.billows')), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
  });

  testWidgets('Billows loss is added to the connection log', (tester) async {
    final controller = demoBridgeController()
      ..billowsAttachment = BillowsAttachment.detached
      ..billowsSeenThisSession = true;
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Billows not detected'), findsOneWidget);
    expect(
      controller.billowsLog.any((event) => event.title == 'Billows lost'),
      isTrue,
    );

    await tester.ensureVisible(find.text('View connection log'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View connection log'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('billows.connectionLog')));
    await tester.pumpAndSettle();
    expect(find.text('Billows lost'), findsOneWidget);
  });

  testWidgets('Billows settings is status-only and mirrors set temp', (
    tester,
  ) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: BillowsSettingsScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Billows status'), findsOneWidget);
    expect(find.text('Set temp'), findsOneWidget);
    expect(find.text('Smoke X4 (channel 4)'), findsOneWidget);
    expect(find.text('Monitor only'), findsNothing);
    expect(find.text('Control'), findsNothing);
    expect(find.text('Set target'), findsNothing);
    expect(find.byKey(const Key('billows.connectionLog')), findsOneWidget);
  });

  testWidgets('experimental lab opens from the app-bar menu', (tester) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.byKey(const Key('nav.experimental')));
    await tester.pumpAndSettle();
    expect(find.text('Experimental lab'), findsOneWidget);
    await tester.tap(find.text('Experimental lab'));
    await tester.pumpAndSettle();
    expect(find.text('Experimental lab'), findsOneWidget);
    expect(find.text('No devices required'), findsOneWidget);
  });

  testWidgets('experimental lab still opens', (tester) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ScenarioLabScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Experimental lab'), findsOneWidget);
    expect(find.text('No devices required'), findsOneWidget);
  });

  testWidgets('production entrypoint boots into Live', (tester) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(SmokeBridgeApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('P1'), findsOneWidget);
  });
}
