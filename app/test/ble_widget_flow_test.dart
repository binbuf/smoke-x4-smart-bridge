import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/app/smoke_bridge_app.dart';
import 'package:smoke_bridge/data/ble/ble_client.dart';

import 'support/codecs.dart';
import 'support/fake_bridge_session.dart';

void main() {
  testWidgets(
    'fake BLE drives scan -> connect -> bond -> subscribe -> live -> offline',
    (tester) async {
      final session = FakeBridgeSession();
      addTearDown(session.dispose);

      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(SmokeBridgeApp(controller: session.controller));
      await tester.pumpAndSettle();

      // Scan: the scripted advertisement is a real bridge advertisement.
      // BLE futures run outside the widget fake clock, so use runAsync.
      final device = await tester.runAsync(session.scan);
      expect(device, isNotNull);
      expect(device!.name, 'SmokeX4-A4F2');
      expect(device.isSmokeBridge, isTrue);

      // Connect and bond: no radio, no OS prompt.
      await tester.runAsync(() => session.connect(device));
      expect(session.client.connectionState, BleConnectionState.connected);
      expect(await tester.runAsync(session.bond), BleBondState.bonded);

      // Subscribe to live and deliver one sample through the generated codec.
      await tester.runAsync(session.subscribeLive);
      await tester.runAsync(
        () => session.publishLiveSample(
          seq: 5000,
          tempsF10: const <int>[2250, 1652, tempDetached, 800],
          batteryPct: 87,
          rssiLora: -71,
          ageS: 4,
        ),
      );
      await tester.pumpAndSettle();

      expect(session.controller.phase, ConnectionPhase.live);
      expect(session.controller.liveView.probes[0].tempF, 225.0);
      expect(session.controller.liveView.probes[1].tempF, 165.2);
      expect(session.controller.liveView.probes[2].tempF, isNull);
      expect(session.controller.liveView.batteryPercent, 87);
      expect(session.controller.liveView.rssi, -71);
      expect(find.text('P1'), findsOneWidget);
      expect(find.textContaining('225.0', findRichText: true), findsWidgets);
      expect(find.textContaining('Bridge connected'), findsWidgets);

      // A disconnect from the fake moves the same UI to the offline state.
      await tester.runAsync(session.disconnect);
      await tester.pumpAndSettle();

      expect(session.controller.phase, ConnectionPhase.offline);
      expect(session.controller.liveView.isOffline, isTrue);
      expect(
        find.textContaining('Showing saved readings', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Bridge disconnected', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('225.0', findRichText: true),
        findsWidgets,
        reason: 'saved readings stay visible while offline',
      );
    },
  );
}
