import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/app/smoke_bridge_app.dart';
import 'package:smoke_bridge/data/ble/ble_client.dart';
import 'package:smoke_bridge/domain/content.dart';
import 'package:smoke_bridge/features/setup/setup_screen.dart';
import 'package:smoke_bridge/theme/app_theme.dart';

import 'support/fake_ble_client.dart';
import 'support/fake_bridge.dart';

class _Harness {
  _Harness({
    FakeBridge? bridge,
    List<BleDevice>? advertisements,
    String? expectedPasskey,
    BleBondState? forcedBondFailure,
    BleException? connectError,
    BlePermissionState permission = BlePermissionState.granted,
    BlePermissionState? permissionOnRequest,
    bool bluetoothOn = true,
    bool supported = true,
    Duration scanInterval = const Duration(milliseconds: 1),
  }) : bridge = bridge ?? FakeBridge() {
    client = FakeBleClient(
      server: this.bridge,
      advertisements:
          advertisements ?? <BleDevice>[this.bridge.advertisement()],
      expectedPasskey: expectedPasskey,
      forcedBondFailure: forcedBondFailure,
      connectError: connectError,
      permission: permission,
      permissionOnRequest: permissionOnRequest,
      bluetoothOn: bluetoothOn,
      supported: supported,
      scanInterval: scanInterval,
    );
    controller = BridgeController(bleClient: client, content: _EmptyContent())
      ..beginSetup();
    controller
      ..hasSavedData = true
      ..savedDataEmpty = false
      ..phoneRecords = 8241
      ..savedDataRange = 'Oct 19 – Oct 26'
      ..savedDataSize = '1.8 MB';
  }

  final FakeBridge bridge;
  late final FakeBleClient client;
  late final BridgeController controller;

  Future<void> dispose() async {
    await client.dispose();
    controller.dispose();
    await bridge.dispose();
  }
}

Future<void> _pumpSetup(WidgetTester tester, _Harness harness) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: SetupScreen(controller: harness.controller),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _findBridge(WidgetTester tester) async {
  await tester.tap(find.text('Find bridge'));
  await tester.pumpAndSettle();
}

Future<void> _selectBridge(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('fresh phone starts on Connect your Bridge with saved history', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await _pumpSetup(tester, harness);

    expect(find.text('Set up'), findsOneWidget);
    expect(find.text('Connect your Bridge'), findsOneWidget);
    expect(
      find.text(
        'Power it on. Press PRG to wake the screen. If the Bridge is off, hold PRG for 1.5 seconds to turn it on.',
      ),
      findsOneWidget,
    );
    expect(find.text('Find bridge'), findsOneWidget);
    expect(find.text('History on this phone'), findsOneWidget);
    expect(find.textContaining('8,241 readings'), findsOneWidget);
    expect(find.textContaining('Oct 19 – Oct 26'), findsOneWidget);
    expect(find.text('View history on this phone'), findsOneWidget);
    expect(find.text('Simulate scan results'), findsNothing);
    expect(find.text('Simulate'), findsNothing);
  });

  testWidgets('permission primer only appears when permission is not granted', (
    tester,
  ) async {
    final granted = _Harness();
    addTearDown(granted.dispose);
    await _pumpSetup(tester, granted);
    await _findBridge(tester);
    expect(find.text('Nearby bridges'), findsOneWidget);
    expect(find.text('Allow Bluetooth to find your Bridge'), findsNothing);

    final denied = _Harness(permission: BlePermissionState.denied);
    addTearDown(denied.dispose);
    await _pumpSetup(tester, denied);
    await _findBridge(tester);
    expect(find.text('Allow Bluetooth to find your Bridge'), findsOneWidget);
    expect(
      find.textContaining('Android 12 and newer use Nearby devices'),
      findsOneWidget,
    );
    expect(find.textContaining('Android 11 and older'), findsOneWidget);
    expect(
      find.textContaining('only needed to find your Bridge'),
      findsOneWidget,
    );
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.text('Looking for your Bridge…'), findsNothing);
  });

  testWidgets('permission denied and blocked are reachable', (tester) async {
    final denied = _Harness(
      permission: BlePermissionState.denied,
      permissionOnRequest: BlePermissionState.denied,
    );
    addTearDown(denied.dispose);
    await _pumpSetup(tester, denied);
    await _findBridge(tester);
    await tester.scrollUntilVisible(
      find.text('Continue'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Bluetooth permission needed'), findsOneWidget);
    expect(
      find.text(
        'The app needs Nearby devices permission to scan for the Bridge.',
      ),
      findsOneWidget,
    );
    expect(find.text('Grant permission'), findsOneWidget);
    expect(find.text('Open app settings'), findsOneWidget);

    final blocked = _Harness(
      permission: BlePermissionState.permanentlyDenied,
      permissionOnRequest: BlePermissionState.permanentlyDenied,
    );
    addTearDown(blocked.dispose);
    await _pumpSetup(tester, blocked);
    await _findBridge(tester);
    expect(find.text('Bluetooth permission is blocked'), findsOneWidget);
    expect(
      find.text(
        'Enable Nearby devices permission in Android settings, then come back.',
      ),
      findsOneWidget,
    );
    expect(find.text('Open app settings'), findsOneWidget);
  });

  testWidgets('Bluetooth off keeps the recording message and checks again', (
    tester,
  ) async {
    final harness = _Harness(bluetoothOn: false);
    addTearDown(harness.dispose);
    await _pumpSetup(tester, harness);
    await _findBridge(tester);

    expect(find.text('Bluetooth is off'), findsOneWidget);
    expect(
      find.text(
        'Turn Bluetooth on so the app can find your Bridge. The Bridge keeps recording while you do.',
      ),
      findsOneWidget,
    );
    expect(find.text('Open Bluetooth settings'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);

    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(find.text('Bluetooth is off'), findsOneWidget);
  });

  testWidgets(
    'unsupported phone never scans and keeps saved history reachable',
    (tester) async {
      final harness = _Harness(supported: false);
      addTearDown(harness.dispose);
      await _pumpSetup(tester, harness);
      await _findBridge(tester);

      expect(
        find.text('This phone doesn’t support Bluetooth LE'),
        findsOneWidget,
      );
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('View history on this phone'), findsOneWidget);
      expect(find.text('Learn more'), findsOneWidget);
      expect(find.text('Looking for your Bridge…'), findsNothing);
      expect(harness.client.diagnostics.entries, isEmpty);

      await tester.tap(find.text('View history on this phone'));
      await tester.pumpAndSettle();
      expect(find.text('History on this phone'), findsWidgets);
      expect(find.text('Readings'), findsOneWidget);
      expect(find.text('Date range'), findsOneWidget);
      expect(find.text('Storage used'), findsOneWidget);
      expect(find.text('Delete history from this phone…'), findsOneWidget);
    },
  );

  testWidgets('scanning can be cancelled and no results offers saved history', (
    tester,
  ) async {
    final scanning = _Harness(scanInterval: const Duration(seconds: 5));
    addTearDown(scanning.dispose);
    await _pumpSetup(tester, scanning);
    await tester.tap(find.text('Find bridge'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Looking for your Bridge…'), findsOneWidget);
    expect(
      find.text(
        'Scanning stops after 10 seconds. We’ll check your last Bridge first.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Connect your Bridge'), findsOneWidget);

    final empty = _Harness(
      advertisements: const <BleDevice>[
        BleDevice(id: 'other', name: 'OtherDevice', rssi: -40),
      ],
    );
    addTearDown(empty.dispose);
    await _pumpSetup(tester, empty);
    await _findBridge(tester);
    expect(find.text('No Bridge found'), findsOneWidget);
    expect(
      find.text(
        'Make sure it’s on and within about 10 meters (30 feet). If it’s off, hold PRG for 1.5 seconds to turn it on.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Open Bluetooth settings'), findsOneWidget);
    expect(find.text('View history on this phone'), findsOneWidget);
  });

  testWidgets('results prefer the remembered bridge and show scan preview', (
    tester,
  ) async {
    final rememberedBridge = FakeBridge();
    final otherBridge = FakeBridge(deviceId: 'B91C');
    final remembered = rememberedBridge.advertisement(pitTempF10: 2250);
    final other = otherBridge.advertisement(pitTempF10: 1800, battery: 64);
    final replacement = _Harness(
      advertisements: <BleDevice>[other, remembered],
    );
    addTearDown(replacement.dispose);
    addTearDown(rememberedBridge.dispose);
    addTearDown(otherBridge.dispose);
    replacement.controller.rememberedBridgeId = remembered.id;

    await _pumpSetup(tester, replacement);
    await _findBridge(tester);

    expect(find.text('Nearby bridges'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('SmokeX4-A4F2')).dy,
      lessThan(tester.getTopLeft(find.text('SmokeX4-B91C')).dy),
    );
    expect(find.text('Last used'), findsOneWidget);
    expect(find.textContaining('P4 225°F · 87%'), findsOneWidget);
    expect(find.textContaining('Strong'), findsWidgets);
    expect(find.textContaining('-60 dBm'), findsWidgets);
    expect(
      find.textContaining('P4 225°F · 87% · Strong · -60 dBm'),
      findsOneWidget,
    );
  });

  testWidgets('a remembered bridge is matched by name when the ID changed', (
    tester,
  ) async {
    final bridge = FakeBridge();
    final advertisement = bridge.advertisement();
    final harness = _Harness(advertisements: <BleDevice>[advertisement]);
    addTearDown(harness.dispose);
    addTearDown(bridge.dispose);
    harness.controller.rememberedBridgeName = 'smokex4-a4f2';

    await _pumpSetup(tester, harness);
    await _findBridge(tester);

    expect(find.text('Last used'), findsOneWidget);
    expect(find.text('SmokeX4-A4F2'), findsOneWidget);
  });

  testWidgets('protocol-mismatch row opens the update explanation', (
    tester,
  ) async {
    final legacy = BleDevice(
      id: 'fake-legacy',
      name: 'SmokeX4-LEGACY',
      rssi: -80,
      serviceUuids: const <String>['7f9a0000-4c5b-4b0f-9a3d-1c2e3f405162'],
    );
    final harness = _Harness(advertisements: <BleDevice>[legacy]);
    addTearDown(harness.dispose);
    await _pumpSetup(tester, harness);
    await _findBridge(tester);

    expect(find.text('Requires a newer app'), findsOneWidget);
    await tester.tap(find.text('SmokeX4-LEGACY'));
    await tester.pumpAndSettle();

    expect(find.text('Update the app to use this Bridge'), findsOneWidget);
    expect(find.text('Update app'), findsOneWidget);
    expect(find.text('View history on this phone'), findsOneWidget);
    expect(find.text('Learn more'), findsOneWidget);
    expect(
      find.textContaining('The Bridge hasn’t been changed'),
      findsOneWidget,
    );
  });

  testWidgets('select reads info and stops on a protocol-major mismatch', (
    tester,
  ) async {
    final bridge = FakeBridge(protoMajor: 2);
    final harness = _Harness(bridge: bridge);
    addTearDown(harness.dispose);
    await _pumpSetup(tester, harness);
    await _findBridge(tester);
    await _selectBridge(tester, 'SmokeX4-A4F2');

    expect(find.text('Update the app to use this Bridge'), findsOneWidget);
    expect(harness.client.bondState, BleBondState.none);
    expect(find.text('Pair with the Bridge'), findsNothing);
  });

  testWidgets(
    'the passkey block is shown before the OS bond, with only the example code',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await _pumpSetup(tester, harness);
      await _findBridge(tester);
      await _selectBridge(tester, 'SmokeX4-A4F2');

      expect(find.text('Pair with the Bridge'), findsOneWidget);
      expect(
        find.text(
          'Enter the 6-digit code shown on the Bridge screen in the Android prompt.',
        ),
        findsOneWidget,
      );
      expect(find.text('Look at the Bridge screen'), findsOneWidget);
      expect(find.text('418 302'), findsOneWidget);
      expect(
        find.text(
          'Example: the code appears on the Bridge screen. Only the Bridge screen shows the real code.',
        ),
        findsOneWidget,
      );
      expect(find.text('Pair'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(harness.client.bondState, BleBondState.none);
    },
  );

  testWidgets('pairing reaches first sync and lands on Live', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(SmokeBridgeApp(controller: harness.controller));
    await tester.pumpAndSettle();

    await _findBridge(tester);
    await _selectBridge(tester, 'SmokeX4-A4F2');
    await tester.tap(find.text('Pair'));
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('Pairing…'), findsOneWidget);
    expect(find.text('Connecting to the Bridge'), findsOneWidget);
    expect(find.text('Checking the code'), findsOneWidget);
    expect(find.text('Syncing recent history'), findsOneWidget);
    expect(find.textContaining('GATT'), findsNothing);
    expect(find.textContaining('secure characteristics'), findsNothing);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Loading history'), findsOneWidget);
    expect(
      find.text(
        'Your latest readings are ready. Older readings will load in the background.',
      ),
      findsOneWidget,
    );
    expect(find.text('Time set'), findsOneWidget);
    expect(find.text('Loading recent readings'), findsOneWidget);
    expect(find.text('Loading older readings'), findsOneWidget);
    expect(find.text('Live view ready'), findsOneWidget);
    expect(find.textContaining('last 15 minutes'), findsOneWidget);
    expect(find.textContaining('last 24 hours'), findsNothing);
    expect(find.text('Loading the last 24 hours'), findsNothing);

    await tester.tap(find.text('View live readings'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Set up'), findsNothing);
    expect(harness.controller.phase, ConnectionPhase.live);
    expect(harness.controller.tab, AppTab.live);
    expect(
      harness.controller.rememberedBridgeId,
      harness.bridge.advertisement().id,
    );
    expect(harness.controller.rememberedBridgeName, 'SmokeX4-A4F2');
  });

  testWidgets('a wrong code retries, then explains how to remove the pairing', (
    tester,
  ) async {
    final harness = _Harness(expectedPasskey: '418302');
    addTearDown(harness.dispose);
    await _pumpSetup(tester, harness);
    await _findBridge(tester);
    await _selectBridge(tester, 'SmokeX4-A4F2');

    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();
    expect(find.text('The code didn’t match'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Open Android settings'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('The code didn’t match'), findsOneWidget);
    expect(
      find.text(
        'Remove this Bridge’s pairing in Android settings, then try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Open Android settings'), findsOneWidget);
  });

  testWidgets('prompt timeout names the notification shade', (tester) async {
    final harness = _Harness(forcedBondFailure: BleBondState.timeout);
    addTearDown(harness.dispose);
    await _pumpSetup(tester, harness);
    await _findBridge(tester);
    await _selectBridge(tester, 'SmokeX4-A4F2');
    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();

    expect(find.text('No prompt appeared'), findsOneWidget);
    expect(
      find.text(
        'Open your notifications and look for the Android pairing request, then try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Open Bluetooth settings'), findsOneWidget);
  });

  testWidgets('a stale bond offers forget and re-pair', (tester) async {
    final harness = _Harness(
      connectError: const BleException(BleFailure.staleBond),
    );
    addTearDown(harness.dispose);
    await _pumpSetup(tester, harness);
    await _findBridge(tester);
    await _selectBridge(tester, 'SmokeX4-A4F2');

    expect(find.text('This phone’s pairing is out of date'), findsOneWidget);
    expect(find.textContaining('The Bridge was reset'), findsOneWidget);
    expect(find.text('Forget and re-pair'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('a full bond store is reported before the OS bond starts', (
    tester,
  ) async {
    final harness = _Harness(bridge: FakeBridge(bondsFree: 0));
    addTearDown(harness.dispose);
    await _pumpSetup(tester, harness);
    await _findBridge(tester);
    await _selectBridge(tester, 'SmokeX4-A4F2');

    expect(
      find.text('This Bridge already has 4 phones paired'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Open the app on a phone that’s already paired and choose Forget this phone. If none is available, the Bridge needs a USB reset.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(harness.client.bondState, BleBondState.none);
  });

  testWidgets(
    'orphaned history survives forget and is never deleted automatically',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.controller.forgetPhone();
      await _pumpSetup(tester, harness);

      expect(find.text('Connect your Bridge'), findsOneWidget);
      expect(find.text('History on this phone'), findsOneWidget);
      await tester.tap(find.text('View history on this phone'));
      await tester.pumpAndSettle();

      expect(find.text('History on this phone'), findsWidgets);
      expect(find.text('8,241'), findsOneWidget);
      expect(find.text('Oct 19 – Oct 26'), findsOneWidget);
      expect(find.text('1.8 MB'), findsOneWidget);
      expect(find.text('Delete history from this phone…'), findsOneWidget);
      expect(harness.controller.phoneRecords, 8241);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Connect your Bridge'), findsOneWidget);
    },
  );
}

class _EmptyContent implements BridgeContent {
  @override
  List<double?> probeTemps = const <double?>[null, null, null, null];

  @override
  DateTime get now => DateTime(2026, 10, 26, 12);

  @override
  HistoryWindow get historyWindow =>
      HistoryWindow(start: now.subtract(const Duration(hours: 1)), end: now);

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
    final start = customStart ?? historyWindow.start;
    final end = customEnd ?? historyWindow.end;
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
