import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/debug/demo_content.dart';
import 'package:smoke_bridge/features/settings/bridge_details.dart';
import 'package:smoke_bridge/features/settings/settings_views.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/theme/app_theme.dart';
import 'package:smoke_bridge/widgets/prototype_widgets.dart';

/// T50: the approved Settings root, its offline/read-only states and the
/// navigation into and out of Bridge details. Copy assertions are literal so a
/// later refactor cannot reintroduce the banned `Device log` / `Saved data`
/// labels or a second Bridge section.
Future<void> pumpSettings(
  WidgetTester tester,
  BridgeController controller,
) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  controller.tab = AppTab.settings;
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: AppShell(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('connected root has one Bridge header, storage, preferences and '
      'About', (tester) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await pumpSettings(tester, controller);

    expect(find.text('Bridge'), findsOneWidget);
    expect(find.byKey(const Key('settings.bridge.status')), findsOneWidget);
    expect(find.text('Backyard Bridge'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Battery 87%'), findsOneWidget);
    expect(find.text('Fair'), findsOneWidget);
    expect(find.textContaining('Updated'), findsWidgets);

    expect(find.text('History & storage'), findsOneWidget);
    expect(find.byKey(const Key('settings.history.logs')), findsOneWidget);
    expect(find.text('Storage'), findsOneWidget);

    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Temperature units'), findsOneWidget);
    expect(find.byKey(const Key('settings.units')), findsOneWidget);
    expect(find.text('Live change window'), findsOneWidget);
    expect(find.byKey(const Key('settings.tempChangeWindow')), findsOneWidget);
    expect(find.text('5 min'), findsOneWidget);
    expect(find.byKey(const Key('settings.appearance')), findsOneWidget);
    expect(find.text('System'), findsOneWidget);

    expect(find.text('About'), findsOneWidget);
    expect(find.text('About this app'), findsOneWidget);

    // One Bridge entry point only; no duplicate rows or save-all chrome.
    expect(find.text('Bridge details'), findsNothing);
    expect(find.text('Sync now'), findsNothing);
    expect(find.text('Reconnect'), findsNothing);
    expect(find.text('Disconnect'), findsNothing);
    expect(find.text('Save changes'), findsNothing);
    expect(find.textContaining('Device log'), findsNothing);
    expect(find.textContaining('Saved data'), findsNothing);
    expect(find.textContaining('recorded data'), findsNothing);
    expect(find.textContaining('local data'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Bridge status header opens Bridge details and back returns '
      'to the root', (tester) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await pumpSettings(tester, controller);

    await tester.tap(find.byKey(const Key('settings.bridge.status')));
    await tester.pumpAndSettle();

    expect(find.byType(BridgeDetailsScreen), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Smoke X4 pairing'), findsOneWidget);
    expect(find.text('Re-pair Smoke X4'), findsOneWidget);
    expect(find.byKey(const Key('bridge.name')), findsOneWidget);
    expect(find.byKey(const Key('bridge.timeout')), findsOneWidget);
    expect(find.byKey(const Key('bridge.billows')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(BridgeDetailsScreen), findsNothing);
    expect(find.byKey(const Key('settings.bridge.status')), findsOneWidget);
    expect(find.byKey(const Key('settings.units')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('units and the Live change window apply immediately', (
    tester,
  ) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await pumpSettings(tester, controller);

    await tester.tap(find.text('°C'));
    await tester.pumpAndSettle();
    expect(controller.units, Units.celsius);
    expect(controller.settingsView.units, Units.celsius);

    await tester.tap(find.byKey(const Key('settings.tempChangeWindow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.tempChangeWindow.15')));
    await tester.pumpAndSettle();
    expect(controller.tempChangeWindowMinutes, 15);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('15 min'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Appearance applies immediately and survives back navigation', (
    tester,
  ) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await pumpSettings(tester, controller);

    await tester.tap(find.byKey(const Key('settings.appearance')));
    await tester.pumpAndSettle();
    expect(find.byType(AppearanceScreen), findsOneWidget);
    expect(find.text('Match your phone'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(controller.themeModeLabel, 'Dark');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Dark'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline shows one global banner and keeps local preferences and '
      'history available', (tester) async {
    final controller = demoBridgeController()
      ..phase = ConnectionPhase.offline
      ..offlineCache = true;
    addTearDown(controller.dispose);
    await pumpSettings(tester, controller);

    expect(find.byKey(const Key('settings.offlineBanner')), findsOneWidget);
    expect(find.textContaining('Bridge disconnected'), findsOneWidget);
    expect(find.textContaining('last connected'), findsWidgets);
    expect(
      find.text('The Bridge screen will update when you reconnect.'),
      findsOneWidget,
    );

    // Units and the Live change window stay local-only and immediate.
    await tester.tap(find.text('°C'));
    await tester.pumpAndSettle();
    expect(controller.units, Units.celsius);

    await tester.tap(find.byKey(const Key('settings.tempChangeWindow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.tempChangeWindow.30')));
    await tester.pumpAndSettle();
    expect(controller.tempChangeWindowMinutes, 30);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Appearance is local only.
    await tester.ensureVisible(
      find.byKey(const Key('settings.appearance')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.appearance')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(controller.themeModeLabel, 'Light');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // History & storage remains one destination.
    await tester.ensureVisible(find.byKey(const Key('settings.history.logs')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings.history.logs')), findsOneWidget);

    // Bridge details is read-only offline: no sync/repair/editors.
    await tester.ensureVisible(find.byKey(const Key('settings.bridge.status')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.bridge.status')));
    await tester.pumpAndSettle();
    expect(find.text('Sync now'), findsNothing);
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(
      tester.widget<SettingsTile>(find.byKey(const Key('bridge.name'))).onTap,
      isNull,
    );
    expect(
      tester
          .widget<SettingsTile>(find.byKey(const Key('bridge.timeout')))
          .onTap,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('bridge.repair')))
          .onPressed,
      isNull,
    );
    expect(find.text('Forget this phone'), findsOneWidget);
    expect(find.textContaining('Connect to change'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only offline root names the missing cache and still offers '
      'History', (tester) async {
    final controller = demoBridgeController()
      ..phase = ConnectionPhase.offline
      ..offlineCache = false;
    addTearDown(controller.dispose);
    await pumpSettings(tester, controller);

    expect(find.byKey(const Key('settings.offlineBanner')), findsOneWidget);
    expect(
      find.textContaining('Bridge disconnected · nothing saved yet'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('settings.history.logs')), findsOneWidget);
    expect(find.byKey(const Key('settings.units')), findsOneWidget);
    expect(find.byKey(const Key('settings.appearance')), findsOneWidget);
    expect(find.text('Sync now'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
