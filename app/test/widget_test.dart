import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/features/setup/setup_screen.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/main.dart';
import 'package:smoke_bridge/prototype/prototype_controller.dart';
import 'package:smoke_bridge/prototype/scenario_lab.dart';
import 'package:smoke_bridge/theme/app_theme.dart';
import 'package:smoke_bridge/widgets/probe_sparkline.dart';

Widget shell(PrototypeController controller) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    home: AppShell(controller: controller),
  );
}

Future<void> pumpShell(
  WidgetTester tester,
  PrototypeController controller,
) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(shell(controller));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('launches into Live with four numbered probes', (tester) async {
    final controller = PrototypeController();
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
    final controller = PrototypeController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Connected · 4s'), findsOneWidget);
    expect(find.text('updated 4s ago · bridge 87% · -71 dBm'), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('PREFERENCES'), findsOneWidget);
    expect(find.text('BRIDGE'), findsOneWidget);
    expect(find.text('HISTORY & STORAGE'), findsOneWidget);
    expect(find.text('ABOUT'), findsOneWidget);
    expect(find.text('ACTIONS'), findsNothing);
    expect(find.text('Probe names & roles'), findsNothing);

    await tester.ensureVisible(find.widgetWithText(ListTile, 'About'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'About'));
    await tester.pumpAndSettle();
    expect(find.text('Smoke X4 Smart Bridge'), findsOneWidget);

    await tester.longPress(find.text('Smoke X4 Smart Bridge'));
    await tester.pumpAndSettle();
    expect(find.text('Scenario lab'), findsOneWidget);
  });

  testWidgets('first-run setup advances without simulation buttons', (
    tester,
  ) async {
    final controller = PrototypeController();
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

    expect(find.text('Connect your bridge'), findsOneWidget);
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

    await tester.tap(find.text('Start monitoring'));
    await tester.pump();
    expect(controller.phase, ConnectionPhase.live);
    expect(controller.tab, AppTab.live);
  });

  testWidgets('bottom navigation reaches History and Settings', (tester) async {
    final controller = PrototypeController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Summary'), findsOneWidget);
    await tester.tap(find.text('7D'));
    await tester.pumpAndSettle();
    expect(find.text('Days'), findsOneWidget);
    expect(find.text('Graph'), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Temperature units'), findsOneWidget);
  });

  testWidgets('units apply immediately and reach History', (tester) async {
    final controller = PrototypeController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    await tester.tap(find.text('Settings'));
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

  testWidgets('History filters and summary respond to a probe tile', (
    tester,
  ) async {
    final controller = PrototypeController();
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
    final controller = PrototypeController()
      ..probePresence = ProbePresence.detachedP3;
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('—'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.textContaining('0.0 °F'), findsNothing);
  });

  testWidgets('offline history stays usable and is labelled', (tester) async {
    final controller = PrototypeController()
      ..tab = AppTab.history
      ..phase = ConnectionPhase.offline
      ..offlineCache = true;
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.text('Showing last saved readings'), findsOneWidget);
    expect(find.text('Last sync 2 h ago'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
  });

  testWidgets('scenario lab still opens', (tester) async {
    final controller = PrototypeController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ScenarioLabScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Scenario lab'), findsOneWidget);
    expect(find.text('No devices required'), findsOneWidget);
  });

  testWidgets('prototype entrypoint boots', (tester) async {
    await tester.pumpWidget(const PrototypeApp());
    await tester.pumpAndSettle();
    expect(find.text('P1'), findsOneWidget);
  });
}
