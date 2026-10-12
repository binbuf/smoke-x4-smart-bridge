/// Screen-level widget tests: the three tabs render their honest states from a
/// real controller over an in-memory cache, and the connection sheet opens.
///
/// No radio is dialled: the prefs hold no remembered bridge, so bootstrap stays
/// disconnected and every assertion is about presentation, not the link.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/app/bridge_scope.dart';
import 'package:smoke_bridge/data/ble/ble_transport.dart';
import 'package:smoke_bridge/data/local/app_database.dart';
import 'package:smoke_bridge/data/local/drift_sample_cache.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/common/unit_toggle.dart';
import 'package:smoke_bridge/features/graph/graph_screen.dart';
import 'package:smoke_bridge/features/history/history_screen.dart';
import 'package:smoke_bridge/features/live/live_screen.dart';
import 'package:smoke_bridge/features/settings/settings_screen.dart';

import '../support/fake_peripheral.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftSampleCache cache;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    cache = DriftSampleCache(db);
  });

  tearDown(() async {
    await db.close();
  });

  Widget host(BridgeController controller, Widget child) => BridgeScope(
    controller: controller,
    child: MaterialApp(theme: buildSmokeTheme(), home: child),
  );

  Future<BleTransport> openFake(FakePeripheral fake) async {
    await fake.connect('AA:BB:CC:DD:AA:BB');
    await fake.bond();
    await fake.requestMtu(247);
    final transport = BleTransport(fake);
    await transport.start();
    return transport;
  }

  /// Boots the controller over a fake and waits for the link, on the real event
  /// loop (a fake clock would stall the radio-free fake).
  Future<void> connect(WidgetTester tester, BridgeController controller) async {
    await tester.runAsync(() async {
      await controller.bootstrap();
      final end = DateTime.now().add(const Duration(seconds: 3));
      while (!controller.connected && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
  }

  Future<void> seedSession() async {
    await cache.upsertSessions('A4F2', const [
      SessionInfo(
        id: 0x1A,
        name: 'Brisket',
        startedUnixMs: 1774051200000,
        endedUnixMs: 1774054800000,
        samplePeriodS: 30,
        sampleCount: 3,
        numProbes: 4,
        closed: true,
        pinned: false,
      ),
    ]);
    await cache.upsertSamples('A4F2', 0x1A, const [
      Sample(t: 0, tempsF10: [2000, 1600, null, 900]),
      Sample(t: 30, tempsF10: [2010, 1601, null, 901]),
      Sample(t: 60, tempsF10: [2020, 1602, null, 902]),
    ]);
  }

  testWidgets('Live, no link and no cook, offers exactly the connect action', (
    tester,
  ) async {
    final controller = BridgeController(cache);
    await controller.bootstrap();

    await tester.pumpWidget(host(controller, const LiveScreen()));
    await tester.pump();

    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Find my bridge'), findsOneWidget);
    expect(find.text('Cook clock'), findsNothing);

    controller.dispose();
  });

  testWidgets('a running cook stays visible with no link', (tester) async {
    SharedPreferences.setMockInitialValues({
      'cook_started_unix_ms':
          DateTime.now().millisecondsSinceEpoch - 65000, // 1:05
    });
    final controller = BridgeController(cache);
    await controller.bootstrap();

    await tester.pumpWidget(host(controller, const LiveScreen()));
    // The cook ticker repaints once a second, so never pumpAndSettle here.
    await tester.pump();

    expect(find.text('Cook clock'), findsOneWidget);
    expect(find.text('Not started'), findsNothing);
    // The card reads as running, not merely present.
    expect(find.text('Restart clock'), findsOneWidget);
    // And it is explicit that the clock does not create a History entry.
    expect(find.textContaining('records continuously'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('History lists a cached session and opens its detail', (
    tester,
  ) async {
    await seedSession();
    final controller = BridgeController(cache);
    await controller.bootstrap();

    await tester.pumpWidget(host(controller, const HistoryScreen()));
    await tester.pump();

    expect(find.text('Brisket'), findsOneWidget);
    expect(find.textContaining('3 readings'), findsOneWidget);

    await tester.tap(find.text('Brisket'));
    await tester.pumpAndSettle();

    expect(find.text('Statistics'), findsOneWidget);
    expect(find.text('Still recording'), findsNothing);

    controller.dispose();
  });

  testWidgets('Graph shows the session picker, chart legend and metadata', (
    tester,
  ) async {
    await seedSession();
    final controller = BridgeController(cache);
    await controller.bootstrap();

    await tester.pumpWidget(host(controller, const GraphScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Brisket · closed'), findsOneWidget);
    expect(find.text('Probe 1'), findsOneWidget);
    // Probe 3 is detached throughout, so it never earns a legend entry.
    expect(find.text('Probe 3'), findsNothing);
    expect(find.textContaining('Session #26'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('the status chip opens the connection sheet', (tester) async {
    final controller = BridgeController(cache);
    await controller.bootstrap();

    await tester.pumpWidget(host(controller, const LiveScreen()));
    await tester.pump();

    await tester.tap(find.text('Offline'));
    await tester.pumpAndSettle();

    expect(find.text('Connection'), findsOneWidget);
    // The tab's own empty state and the sheet both say "Not connected".
    expect(find.text('Not connected'), findsWidgets);
    expect(find.text('Find my bridge'), findsWidgets);

    controller.dispose();
  });

  testWidgets('Live shows only the jacks the bridge actually has', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'last_bridge_device_id': 'AA:BB:CC:DD:AA:BB',
    });
    final fake = FakePeripheral(state: FakeBridgeState(probes: 2));
    Future<BleTransport> open() async {
      await fake.connect('AA:BB:CC:DD:AA:BB');
      await fake.bond();
      await fake.requestMtu(247);
      final transport = BleTransport(fake);
      await transport.start();
      return transport;
    }

    final controller = BridgeController(cache, openTransport: open);
    // bootstrap dials asynchronously; runAsync uses the real event loop so the
    // link actually comes up (a fake clock would stall the radio-free fake).
    await tester.runAsync(() async {
      await controller.bootstrap();
      final end = DateTime.now().add(const Duration(seconds: 3));
      while (!controller.connected && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(controller.connected, isTrue, reason: 'link did not come up');

    await tester.pumpWidget(host(controller, const LiveScreen()));
    await tester.pump();

    expect(find.text('Probe 1'), findsOneWidget);
    expect(find.text('Probe 2'), findsOneWidget);
    expect(find.text('Probe 3'), findsNothing);
    expect(find.text('Probe 4'), findsNothing);

    controller.dispose();
  });

  testWidgets('a factory-fresh install is walked through setup', (
    tester,
  ) async {
    final controller = BridgeController(cache);
    await controller.bootstrap();

    await tester.pumpWidget(host(controller, const LiveScreen()));
    await tester.pump();

    expect(find.text('Set up your bridge'), findsOneWidget);
    expect(find.text('Find the bridge'), findsOneWidget);
    expect(find.text('Pair it'), findsOneWidget);
    expect(find.text('Connect your Smoke X4'), findsOneWidget);
    expect(find.text('Find my bridge'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('a paired bridge shows the Smoke X4 and LoRa signal', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'last_bridge_device_id': 'AA:BB:CC:DD:AA:BB',
    });
    final fake = FakePeripheral(state: FakeBridgeState());
    final controller = BridgeController(
      cache,
      openTransport: () => openFake(fake),
    );
    await connect(tester, controller);
    expect(controller.connected, isTrue, reason: 'link did not come up');

    await tester.pumpWidget(host(controller, const LiveScreen()));
    await tester.pump();

    expect(find.text('Smoke X4 paired'), findsOneWidget);
    expect(find.textContaining('LoRa'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('an unpaired bridge offers the pair action', (tester) async {
    SharedPreferences.setMockInitialValues({
      'last_bridge_device_id': 'AA:BB:CC:DD:AA:BB',
    });
    final fake = FakePeripheral(state: FakeBridgeState(paired: false));
    final controller = BridgeController(
      cache,
      openTransport: () => openFake(fake),
    );
    await connect(tester, controller);
    expect(controller.connected, isTrue, reason: 'link did not come up');

    await tester.pumpWidget(host(controller, const LiveScreen()));
    await tester.pump();

    expect(find.text('No Smoke X4 paired'), findsOneWidget);
    expect(find.text('Pair with Smoke X4'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('the unit control is on every tab and can change the unit', (
    tester,
  ) async {
    await seedSession();
    final controller = BridgeController(cache);
    await controller.bootstrap();
    addTearDown(controller.dispose);

    for (final screen in const [LiveScreen(), GraphScreen(), HistoryScreen()]) {
      await tester.pumpWidget(host(controller, screen));
      await tester.pumpAndSettle();
      expect(
        find.byType(UnitToggle),
        findsOneWidget,
        reason: '${screen.runtimeType} must expose the unit control',
      );
    }

    // Switch it from the Graph, away from the default.
    await tester.pumpWidget(host(controller, const GraphScreen()));
    await tester.pumpAndSettle();
    expect(controller.unit, TempUnit.fahrenheit);

    await tester.tap(find.byType(UnitToggle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Celsius'));
    await tester.pumpAndSettle();

    expect(controller.unit, TempUnit.celsius);
  });

  testWidgets('Settings exposes the bridge lifecycle controls', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'last_bridge_device_id': 'AA:BB:CC:DD:AA:BB',
    });
    final fake = FakePeripheral(state: FakeBridgeState());
    final controller = BridgeController(
      cache,
      openTransport: () => openFake(fake),
    );
    await connect(tester, controller);
    expect(controller.connected, isTrue, reason: 'link did not come up');

    await tester.pumpWidget(host(controller, const SettingsScreen()));
    await tester.pump();

    // Identity and telemetry.
    expect(find.text('A4F2'), findsOneWidget);
    expect(find.text('heltec-v3'), findsOneWidget);
    // Link verbs.
    expect(find.text('Disconnect'), findsOneWidget);
    // Smoke X4 pair/unpair.
    expect(find.text('Unpair Smoke X4'), findsOneWidget);
    // Device actions.
    expect(find.text('Identify (flash screen)'), findsOneWidget);
    expect(find.text('Reboot bridge'), findsOneWidget);
    expect(find.text('Power off'), findsOneWidget);
    expect(find.text('Factory reset'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('Settings shows stats and the probe editor on an admin bridge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'last_bridge_device_id': 'AA:BB:CC:DD:AA:BB',
    });
    final fake = FakePeripheral(state: FakeBridgeState(admin: true));
    final controller = BridgeController(
      cache,
      openTransport: () => openFake(fake),
    );
    await connect(tester, controller);
    expect(controller.connected, isTrue, reason: 'link did not come up');

    await tester.pumpWidget(host(controller, const SettingsScreen()));
    await tester.pump();

    expect(find.text('BRIDGE STATS'), findsOneWidget);
    expect(find.text('BRIDGE PREFERENCES'), findsOneWidget);
    expect(find.text('Edit probes'), findsOneWidget);

    controller.dispose();
  });
}
