import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/debug/demo_content.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/theme/app_theme.dart';
import 'package:smoke_bridge/widgets/prototype_widgets.dart';

/// T54 contract tests for the states added after T36: two independent radio
/// meters with durations, the amber Smoke X4 warning dialog, the probe Min/Max
/// range line and a signed change for every Live change window.
void main() {
  Future<void> pump(WidgetTester tester, BridgeController controller) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: AppShell(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inLink(String key, Finder matching) => find.descendant(
    of: find.byKey(Key(key)),
    matching: matching,
  );

  testWidgets('BLE and LoRa meters are separate and name their durations', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final controller = demoBridgeController()
      ..bleRssi = -58
      ..rssi = -71;
    addTearDown(controller.dispose);
    await pump(tester, controller);

    expect(find.byType(SignalBars), findsNWidgets(2));
    expect(
      inLink('status.appBridgeLink', find.text('2h 14m')),
      findsOneWidget,
    );
    expect(inLink('status.x4Link', find.text('2h 10m')), findsOneWidget);

    expect(
      find.bySemanticsLabel(RegExp('Bluetooth signal, -58 dBm')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('radio signal, -71 dBm')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('App to Bridge: 2h 14m')),
      findsWidgets,
    );
    expect(
      find.bySemanticsLabel(RegExp('Bridge to Smoke X4: 2h 10m')),
      findsWidgets,
    );
    handle.dispose();
  });

  testWidgets('probe tiles keep the Min/Max range line', (tester) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    await pump(tester, controller);

    final tile = find.byKey(const Key('live.probe.1'));
    final range = find.descendant(
      of: tile,
      matching: find.textContaining(RegExp(r'Min .+ Max ')),
    );
    expect(range, findsOneWidget);
    final text = tester.widget<Text>(range).data!;
    expect(text, contains('°F'));
  });

  for (final minutes in const [1, 5, 10, 15, 30, 60]) {
    testWidgets('Live change window $minutes min shows a signed change', (
      tester,
    ) async {
      final controller = demoBridgeController()
        ..tempChangeWindowMinutes = minutes;
      addTearDown(controller.dispose);
      await pump(tester, controller);

      final tile = find.byKey(const Key('live.probe.1'));
      expect(
        find.descendant(of: tile, matching: find.text('· ${minutes}m')),
        findsOneWidget,
      );

      final changed = tester
          .widgetList<Text>(
            find.descendant(of: tile, matching: find.byType(Text)),
          )
          .map((text) => text.data ?? '')
          .where((text) => RegExp(r'^[+±\-]\d+\.\d°F$').hasMatch(text))
          .toList();
      expect(
        changed,
        hasLength(1),
        reason: 'window $minutes must show one signed change, got $changed',
      );
    });
  }

  testWidgets('the amber X4 warning opens the approved dialog', (tester) async {
    final controller = demoBridgeController()
      ..phase = ConnectionPhase.live
      ..smokeXStatus = SmokeXStatus.pairedLive
      ..smokeXAgeOverride = const Duration(minutes: 4);
    addTearDown(controller.dispose);
    await pump(tester, controller);

    final warning = tester.widget<Icon>(
      find.byKey(const Key('live.smokeXWarning')),
    );
    expect(warning.icon, Icons.warning_amber_rounded);
    expect(
      warning.color,
      StatusColors.aging(tester.element(find.byKey(const Key('live.smokeXWarning')))),
    );

    await tester.tap(find.byKey(const Key('live.smokeXWarning')));
    await tester.pumpAndSettle();

    expect(find.text('No data from Smoke X4'), findsOneWidget);
    expect(
      find.text(
        'The Bridge is connected but isn’t receiving data from the Smoke X4. '
        'Put the Smoke X4 in SYNC mode and keep it in range of the Bridge.',
      ),
      findsOneWidget,
    );
    expect(find.text('Pairing steps'), findsOneWidget);
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byIcon(Icons.warning_amber_rounded),
      ),
    );
    expect(
      icon.color,
      StatusColors.aging(tester.element(find.byType(AlertDialog))),
    );
  });
}
