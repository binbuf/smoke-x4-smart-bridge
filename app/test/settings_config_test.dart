import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/data/ble/ble_client.dart';
import 'package:smoke_bridge/data/ble/bridge_link.dart';
import 'package:smoke_bridge/data/ble/bridge_protocol.dart';

import 'support/codecs.dart' as gen;
import 'support/fake_ble_client.dart';
import 'support/fake_bridge.dart';

/// T51: every Settings field is a read-modify-write of the whole 80-byte
/// `config`, and the UI state branches on the Bridge's refusal status.
void main() {
  late FakeBridge bridge;
  late FakeBleClient client;
  late BridgeController controller;
  late BridgeLink link;

  setUp(() async {
    bridge = FakeBridge();
    client = FakeBleClient(
      server: bridge,
      advertisements: <BleDevice>[bridge.advertisement()],
      expectedPasskey: '418302',
      connectDelay: Duration.zero,
      bondDelay: Duration.zero,
      scanInterval: Duration.zero,
    );
    final device = bridge.advertisement();
    await client.connect(device);
    await client.bond(passkey: '418302');
    controller = BridgeController(bleClient: client)
      ..hasSavedBridge = true
      ..phase = ConnectionPhase.offline;
    link = controller.ensureLink(
      nowUtc: () => DateTime.now().toUtc(),
      wait: (_) async {},
      schedule: (_, _) => _NoopTimer(),
      sink: const NullBridgeSyncSink(),
    );
    controller.phase = ConnectionPhase.live;
    await link.completeFirstConnect(device);
  });

  tearDown(() async {
    await link.dispose();
    controller.dispose();
    await client.dispose();
    await bridge.dispose();
  });

  test('config adopts the Bridge values on connect', () {
    expect(controller.deviceName, 'Backyard Bridge');
    expect(controller.displayTimeoutSeconds, 60);
    expect(controller.units, Units.fahrenheit);
  });

  test('units write the whole struct and read it back', () async {
    controller.setUnits(Units.celsius);
    // The local change is immediate.
    expect(controller.units, Units.celsius);
    await _settle(() => controller.unitsSaveState == SettingsSaveState.saved);

    expect(bridge.config.units, 0);
    // Untouched fields survive the read-modify-write.
    expect(bridge.config.deviceName, 'Backyard Bridge');
    expect(bridge.config.displayTimeoutS, 60);
    expect(bridge.config.reserved0.every((byte) => byte == 0), isTrue);
    expect(controller.unitsSaveState, SettingsSaveState.saved);
  });

  test('Bridge name saves on Done without touching other fields', () async {
    await controller.setDeviceName('Patio Bridge');

    expect(controller.nameSaveState, SettingsSaveState.saved);
    expect(controller.deviceName, 'Patio Bridge');
    expect(bridge.config.deviceName, 'Patio Bridge');
    expect(bridge.config.units, 1);
    expect(bridge.config.displayTimeoutS, 60);
  });

  test('Bridge name is validated at 15 UTF-8 bytes', () async {
    await controller.setDeviceName('123456789012345');
    expect(controller.nameSaveState, SettingsSaveState.saved);
    expect(bridge.config.deviceName, '123456789012345');

    await controller.setDeviceName('1234567890123456');
    expect(controller.nameSaveState, SettingsSaveState.error);
    expect(controller.nameSaveError, contains('15 characters'));
    expect(bridge.config.deviceName, '123456789012345');

    await controller.setDeviceName('   ');
    expect(controller.nameSaveState, SettingsSaveState.error);
  });

  test('screen timeout accepts only the four approved values', () async {
    await controller.setDisplayTimeout(120);
    expect(controller.timeoutSaveState, SettingsSaveState.saved);
    expect(controller.displayTimeoutSeconds, 120);
    expect(bridge.config.displayTimeoutS, 120);

    await controller.setDisplayTimeout(45);
    expect(controller.timeoutSaveState, SettingsSaveState.error);
    expect(controller.displayTimeoutSeconds, 120);
    expect(bridge.config.displayTimeoutS, 120);
  });

  test('a bridge refusal is named and never claims success', () async {
    bridge.forcedConfigAttStatus = 1; // invalid
    await controller.setDisplayTimeout(30);

    expect(controller.timeoutSaveState, SettingsSaveState.error);
    expect(controller.timeoutSaveError, contains('refused'));
    expect(controller.displayTimeoutSeconds, 60);
    expect(bridge.config.displayTimeoutS, 60);

    bridge.forcedConfigAttStatus = 2; // unsupported
    await controller.setDeviceName('New name');
    expect(controller.nameSaveState, SettingsSaveState.error);
    expect(controller.nameSaveError, contains('doesn’t support'));
    expect(controller.deviceName, 'Backyard Bridge');
    expect(bridge.config.deviceName, 'Backyard Bridge');
  });

  test('re-pair sends unpair_smoke_x and branches on the result', () async {
    final status = await controller.startRePair();
    expect(status, BridgeConfigStatus.ok);
    expect(bridge.controlWrites.last.op, gen.ControlOp.unpairSmokeX.wire);
    expect(controller.smokeXStatus, SmokeXStatus.unpaired);
  });

  test('re-pair failure keeps the pairing and returns the status', () async {
    bridge.forcedControlStatus = gen.ResultStatus.unsupported;
    final status = await controller.startRePair();
    expect(status, BridgeConfigStatus.unsupported);
    expect(controller.smokeXStatus, isNot(SmokeXStatus.unpaired));
  });

  test('Appearance is persisted and applied on the next launch', () async {
    controller.setThemeMode(ThemeMode.dark);
    for (var attempt = 0; attempt < 100; attempt++) {
      final stored = await controller.repository.preferences.read(
        BridgeController.themePreferenceKey,
      );
      if (stored == 'dark') break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final relaunched = BridgeController(repository: controller.repository);
    addTearDown(relaunched.dispose);
    await relaunched.loadLocalPreferences();
    expect(relaunched.themeMode, ThemeMode.dark);
    expect(relaunched.themeModeLabel, 'Dark');
  });
}

Future<void> _settle(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('state did not settle');
}

class _NoopTimer implements BridgeLinkTimer {
  @override
  void cancel() {}
}
