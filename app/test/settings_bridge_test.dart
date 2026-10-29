import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/debug/demo_content.dart';
import 'package:smoke_bridge/features/settings/bridge_details.dart';
import 'package:smoke_bridge/widgets/prototype_widgets.dart';

Future<void> _pumpDetails(
  WidgetTester tester,
  BridgeController controller,
) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(home: BridgeDetailsScreen(controller: controller)),
  );
  await tester.pumpAndSettle();
}

ListTile _actionTile(WidgetTester tester, String label) {
  return tester.widget<ListTile>(
    find.ancestor(of: find.text(label), matching: find.byType(ListTile)).first,
  );
}

void main() {
  testWidgets('Bridge screen timeout lists exactly the four approved values', (
    tester,
  ) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await _pumpDetails(tester, controller);

    await tester.tap(find.byKey(const Key('bridge.timeout')));
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    Finder inSheet(String text) =>
        find.descendant(of: sheet, matching: find.text(text));

    expect(inSheet('30 sec'), findsOneWidget);
    expect(inSheet('30 sec · screen turns off'), findsOneWidget);
    expect(inSheet('1 min'), findsOneWidget);
    expect(inSheet('1 min · screen turns off'), findsOneWidget);
    expect(inSheet('2 min'), findsOneWidget);
    expect(inSheet('2 min · screen turns off'), findsOneWidget);
    expect(inSheet('Never'), findsOneWidget);
    expect(inSheet('Screen stays on'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bridge.timeout.120')));
    await tester.pumpAndSettle();
    expect(controller.displayTimeoutSeconds, 120);
    expect(inSheet('Saved'), findsOneWidget);
  });

  testWidgets('Bridge name applies on Done and shows inline state', (
    tester,
  ) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await _pumpDetails(tester, controller);

    await tester.tap(find.byKey(const Key('bridge.name')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('bridge.name.field')),
      'Patio Bridge',
    );
    await tester.tap(find.byKey(const Key('bridge.name.done')));
    await tester.pumpAndSettle();

    expect(controller.deviceName, 'Patio Bridge');
    expect(find.text('Saved'), findsOneWidget);

    controller
      ..nameSaveState = SettingsSaveState.error
      ..nameSaveError = 'The Bridge refused this value. Check it and try again.';
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(
      find.text('The Bridge refused this value. Check it and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Couldn’t save'), findsNothing);
  });

  testWidgets('Smoke X4 has four named states and keeps the updated line', (
    tester,
  ) async {
    final controller = demoBridgeController()
      ..smokeXStatus = SmokeXStatus.pairedLive
      ..smokeXAgeOverride = const Duration(seconds: 12);
    addTearDown(controller.dispose);
    await _pumpDetails(tester, controller);
    expect(find.text('Receiving readings'), findsOneWidget);
    expect(find.text('Updated 12s ago'), findsOneWidget);

    controller.smokeXAgeOverride = const Duration(minutes: 4);
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('No readings for 4 min'), findsOneWidget);

    controller
      ..smokeXStatus = SmokeXStatus.pairedLost
      ..smokeXAgeOverride = const Duration(minutes: 14);
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Signal lost'), findsOneWidget);

    controller.smokeXStatus = SmokeXStatus.unpaired;
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Not paired'), findsOneWidget);
  });

  testWidgets('Technical details is collapsed and the log has one subtitle', (
    tester,
  ) async {
    final controller = demoBridgeController()
      ..syncState = SyncState.complete
      ..billowsSeenThisSession = true;
    addTearDown(controller.dispose);
    await _pumpDetails(tester, controller);

    expect(find.text('Technical details'), findsOneWidget);
    expect(find.text('Bridge ID'), findsNothing);

    await tester.ensureVisible(find.text('Technical details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Bridge ID'));
    await tester.pumpAndSettle();
    expect(find.text('Bridge ID'), findsOneWidget);
    expect(find.text('Firmware'), findsOneWidget);
    expect(find.text('Protocol'), findsOneWidget);
    expect(find.text('Signal'), findsWidgets);
    expect(find.text('MTU'), findsOneWidget);
    expect(find.text('Connected for'), findsOneWidget);
    expect(find.text('Last synced'), findsOneWidget);

    expect(find.text('Connection log'), findsOneWidget);
    expect(
      find.text('Bridge, Smoke X, and Billows events'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Connection log'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connection log'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('History synced'));
    await tester.pumpAndSettle();
    expect(find.text('Bridge connected'), findsOneWidget);
    expect(find.text('Smoke X paired'), findsOneWidget);
    expect(find.text('Billows detected'), findsOneWidget);
    expect(find.text('History synced'), findsOneWidget);
  });

  testWidgets('action rows have no chevrons and offline reasons are exact', (
    tester,
  ) async {
    final controller = demoBridgeController()
      ..phase = ConnectionPhase.offline
      ..offlineCache = true;
    addTearDown(controller.dispose);
    await _pumpDetails(tester, controller);

    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Power off the Bridge'),
          matching: find.byType(ListTile),
        ),
        matching: find.byIcon(Icons.chevron_right),
      ),
      findsNothing,
    );
    expect(_actionTile(tester, 'Power off the Bridge').onTap, isNull);
    expect(_actionTile(tester, 'Factory reset Bridge').onTap, isNull);
    expect(find.text('Connect to the Bridge first'), findsNWidgets(2));
    expect(_actionTile(tester, 'Forget this phone').onTap, isNotNull);

    // Disabled per-field reasons, one line each, no extra banner on the subview.
    expect(find.text('Connect to change this'), findsOneWidget);
    expect(
      tester.widget<SettingsTile>(find.byKey(const Key('bridge.name'))).onTap,
      isNull,
    );
    expect(
      tester.widget<SettingsTile>(find.byKey(const Key('bridge.timeout'))).onTap,
      isNull,
    );
  });
}
