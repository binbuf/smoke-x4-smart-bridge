import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/ble/ble_client.dart';
import 'package:smoke_bridge/data/ble/ble_error_mapper.dart';

import 'support/codecs.dart';
import 'support/fake_ble_client.dart';
import 'support/fake_bridge.dart';

const String _service = '7f9b0000-4c5b-4b0f-9a3d-1c2e3f405162';

BleDevice _bridge({
  String id = 'fake-A4F2',
  String name = 'SmokeX4-A4F2',
  String service = _service,
}) {
  return BleDevice(
    id: id,
    name: name,
    rssi: -60,
    serviceUuids: <String>[service],
  );
}

FakeBleClient _fake({
  BlePermissionState permission = BlePermissionState.granted,
  bool bluetoothOn = true,
  bool supported = true,
  BleException? scanError,
  BleException? connectError,
  BleException? bondError,
  BleException? readError,
  BleException? writeError,
  BleException? notifyError,
  BleException? mtuError,
  BleException? removeBondError,
  BlePermissionState? permissionOnRequest,
}) {
  final bridge = FakeBridge();
  return FakeBleClient(
    server: bridge,
    advertisements: <BleDevice>[bridge.advertisement()],
    expectedPasskey: '418302',
    permission: permission,
    permissionOnRequest: permissionOnRequest,
    bluetoothOn: bluetoothOn,
    supported: supported,
    scanError: scanError,
    connectError: connectError,
    bondError: bondError,
    readError: readError,
    writeError: writeError,
    notifyError: notifyError,
    mtuError: mtuError,
    removeBondError: removeBondError,
  );
}

void main() {
  group('contract constants and selection', () {
    test('production constants match the generated BLE contract', () {
      expect(bleContractServiceUuid, bleServiceUuid);
      expect(bleClientLocalNamePrefix, bleLocalNamePrefix);
      expect(bleRequestedMtu, bleMtuRequest);
      expect(bleDefaultMtu, bleMtuDefault);
    });

    test('remembered bridge wins by device ID, then by name', () {
      final first = _bridge(id: 'AA:01', name: 'SmokeX4-0001');
      final second = _bridge(id: 'AA:02', name: 'SmokeX4-0002');

      expect(
        selectPreferredBridge(<BleDevice>[
          first,
          second,
        ], rememberedDeviceId: 'aa:02')?.id,
        second.id,
      );
      expect(
        selectPreferredBridge(
          <BleDevice>[first, second],
          rememberedDeviceId: 'missing',
          rememberedName: 'SmokeX4-0001',
        )?.id,
        first.id,
      );
      expect(
        selectPreferredBridge(
          <BleDevice>[first, second],
          rememberedDeviceId: 'missing',
          rememberedName: 'missing',
        ),
        isNull,
        reason: 'must never auto-select an arbitrary first result',
      );
    });

    test('a legacy service UUID is never treated as compatible', () {
      final legacy = _bridge(
        id: 'LEGACY',
        name: 'SmokeX4-OLD1',
        service: '7f9a0000-4c5b-4b0f-9a3d-1c2e3f405162',
      );
      expect(legacy.isSmokeBridge, isTrue);
      expect(legacy.hasContractService, isFalse);
      expect(legacy.isCompatibleBridge, isFalse);
      expect(selectPreferredBridge(<BleDevice>[legacy]), isNull);
      expect(
        orderBridgesForDisplay(<BleDevice>[
          legacy,
        ], rememberedName: 'SmokeX4-OLD1'),
        isEmpty,
      );
    });

    test('the remembered bridge is first in the display order', () {
      final first = _bridge(id: 'AA:01', name: 'SmokeX4-0001');
      final second = _bridge(id: 'AA:02', name: 'SmokeX4-0002');
      expect(
        orderBridgesForDisplay(<BleDevice>[
          first,
          second,
        ], rememberedDeviceId: second.id).map((device) => device.id),
        <String>[second.id, first.id],
      );
    });
  });

  group('named state mapping', () {
    test('every BleFailure maps to a named app state', () {
      const expected = <BleFailure, BleAppState>{
        BleFailure.notConnected: BleAppState.connectionFailed,
        BleFailure.notBonded: BleAppState.pairingFailed,
        BleFailure.unknownCharacteristic: BleAppState.gattError,
        BleFailure.unsupported: BleAppState.gattError,
        BleFailure.invalidValue: BleAppState.gattError,
        BleFailure.notSubscribed: BleAppState.gattError,
        BleFailure.timeout: BleAppState.timeout,
        BleFailure.failed: BleAppState.connectionFailed,
        BleFailure.permissionDenied: BleAppState.permissionNeeded,
        BleFailure.permissionBlocked: BleAppState.permissionBlocked,
        BleFailure.bluetoothOff: BleAppState.bluetoothOff,
        BleFailure.unsupportedPhone: BleAppState.unsupportedPhone,
        BleFailure.scanFailed: BleAppState.noResults,
        BleFailure.noResults: BleAppState.noResults,
        BleFailure.wrongPasskey: BleAppState.pairingFailed,
        BleFailure.promptTimeout: BleAppState.promptTimeout,
        BleFailure.staleBond: BleAppState.staleBond,
        BleFailure.bondStoreFull: BleAppState.phoneListFull,
        BleFailure.connectionFailed: BleAppState.connectionFailed,
        BleFailure.gattError: BleAppState.gattError,
      };

      expect(expected.keys.toSet(), BleFailure.values.toSet());
      for (final entry in expected.entries) {
        expect(entry.key.appState, entry.value, reason: entry.key.name);
        final exception = BleException(entry.key);
        expect(exception.appState, entry.value);
        expect(exception.recoveryAction, entry.value.recoveryAction);
      }
    });

    test('every named state has the approved recovery action', () {
      const expected = <BleAppState, BleRecoveryAction>{
        BleAppState.ready: BleRecoveryAction.none,
        BleAppState.bluetoothOff: BleRecoveryAction.openBluetoothSettings,
        BleAppState.permissionNeeded: BleRecoveryAction.grantPermission,
        BleAppState.permissionBlocked: BleRecoveryAction.openAppSettings,
        BleAppState.unsupportedPhone: BleRecoveryAction.none,
        BleAppState.noResults: BleRecoveryAction.retry,
        BleAppState.pairingFailed: BleRecoveryAction.retry,
        BleAppState.promptTimeout: BleRecoveryAction.retry,
        BleAppState.staleBond: BleRecoveryAction.forgetAndRepair,
        BleAppState.phoneListFull: BleRecoveryAction.retry,
        BleAppState.connectionFailed: BleRecoveryAction.retry,
        BleAppState.gattError: BleRecoveryAction.retry,
        BleAppState.timeout: BleRecoveryAction.retry,
      };
      expect(expected.keys.toSet(), BleAppState.values.toSet());
      for (final entry in expected.entries) {
        expect(entry.key.recoveryAction, entry.value, reason: entry.key.name);
      }
    });

    test('a denied permission is permission-needed, blocked is distinct', () {
      const denied = BlePlatformStatus(
        supported: true,
        bluetoothOn: true,
        permission: BlePermissionState.denied,
        permissionKind: BlePermissionKind.nearbyDevices,
        androidSdk: 34,
      );
      const blocked = BlePlatformStatus(
        supported: true,
        bluetoothOn: true,
        permission: BlePermissionState.permanentlyDenied,
        permissionKind: BlePermissionKind.nearbyDevices,
        androidSdk: 34,
      );
      expect(denied.state, BleAppState.permissionNeeded);
      expect(denied.state.recoveryAction, BleRecoveryAction.grantPermission);
      expect(blocked.state, BleAppState.permissionBlocked);
      expect(blocked.state.recoveryAction, BleRecoveryAction.openAppSettings);
    });

    test('platform snapshot prefers unsupported, then Bluetooth off', () {
      const unsupported = BlePlatformStatus(
        supported: false,
        bluetoothOn: true,
        permission: BlePermissionState.granted,
        permissionKind: BlePermissionKind.nearbyDevices,
      );
      const off = BlePlatformStatus(
        supported: true,
        bluetoothOn: false,
        permission: BlePermissionState.granted,
        permissionKind: BlePermissionKind.nearbyDevices,
      );
      const oldAndroid = BlePlatformStatus(
        supported: true,
        bluetoothOn: true,
        permission: BlePermissionState.granted,
        permissionKind: BlePermissionKind.location,
        androidSdk: 30,
      );
      expect(unsupported.state, BleAppState.unsupportedPhone);
      expect(off.state, BleAppState.bluetoothOff);
      expect(off.state.recoveryAction, BleRecoveryAction.openBluetoothSettings);
      expect(oldAndroid.requiresLocationPermission, isTrue);
      expect(oldAndroid.canScan, isTrue);
    });
  });

  group('plugin exception injection', () {
    BleException map(
      Object error, {
      BleOperation operation = BleOperation.read,
    }) => mapBlePlatformError(error, operation: operation);

    test('adapter off and unsupported phone map to named states', () {
      expect(
        map(
          FlutterBluePlusException(
            ErrorPlatform.android,
            'startScan',
            FbpErrorCode.adapterIsOff.index,
            'adapter is off',
          ),
          operation: BleOperation.scan,
        ).appState,
        BleAppState.bluetoothOff,
      );
      expect(
        map(
          FlutterBluePlusException(
            ErrorPlatform.fbp,
            'requestMtu',
            FbpErrorCode.androidOnly.index,
            'android-only',
          ),
          operation: BleOperation.mtu,
        ).appState,
        BleAppState.unsupportedPhone,
      );
    });

    test('timeouts distinguish a pairing prompt from a GATT timeout', () {
      final gatt = map(
        FlutterBluePlusException(
          ErrorPlatform.fbp,
          'readCharacteristic',
          FbpErrorCode.timeout.index,
          'timeout',
        ),
      );
      expect(gatt.failure, BleFailure.timeout);
      expect(gatt.appState, BleAppState.timeout);

      final prompt = map(
        FlutterBluePlusException(
          ErrorPlatform.fbp,
          'createBond',
          FbpErrorCode.timeout.index,
          'timeout',
        ),
        operation: BleOperation.bond,
      );
      expect(prompt.failure, BleFailure.promptTimeout);
      expect(prompt.appState, BleAppState.promptTimeout);

      expect(
        map(TimeoutException('slow'), operation: BleOperation.bond).appState,
        BleAppState.promptTimeout,
      );
      expect(map(TimeoutException('slow')).appState, BleAppState.timeout);
    });

    test('bond and bond-removal failures are named', () {
      final wrong = map(
        FlutterBluePlusException(
          ErrorPlatform.fbp,
          'createBond',
          FbpErrorCode.createBondFailed.hashCode,
          'Failed to create bond',
        ),
        operation: BleOperation.bond,
      );
      expect(wrong.failure, BleFailure.wrongPasskey);
      expect(wrong.appState, BleAppState.pairingFailed);

      final stale = map(
        FlutterBluePlusException(
          ErrorPlatform.fbp,
          'removeBond',
          FbpErrorCode.removeBondFailed.hashCode,
          'Failed to remove bond',
        ),
        operation: BleOperation.removeBond,
      );
      expect(stale.failure, BleFailure.staleBond);
      expect(stale.appState, BleAppState.staleBond);
    });

    test('GATT status codes map to security, timeout and GATT states', () {
      BleException gatt(int code, {BleOperation op = BleOperation.read}) => map(
        FlutterBluePlusException(
          ErrorPlatform.android,
          'readCharacteristic',
          code,
          'status $code',
        ),
        operation: op,
      );

      expect(gatt(5).failure, BleFailure.notBonded);
      expect(gatt(15).appState, BleAppState.pairingFailed);
      expect(gatt(8).appState, BleAppState.timeout);
      expect(gatt(133).appState, BleAppState.gattError);
      expect(
        gatt(133, op: BleOperation.connect).appState,
        BleAppState.connectionFailed,
      );
      expect(gatt(19).appState, BleAppState.connectionFailed);
    });

    test('missing GATT objects and disconnected devices are named', () {
      expect(
        map(
          FlutterBluePlusException(
            ErrorPlatform.fbp,
            'readCharacteristic',
            FbpErrorCode.characteristicNotFound.index,
            'not found',
          ),
        ).appState,
        BleAppState.gattError,
      );
      expect(
        map(
          FlutterBluePlusException(
            ErrorPlatform.fbp,
            'readCharacteristic',
            FbpErrorCode.deviceIsDisconnected.index,
            'disconnected',
          ),
        ).appState,
        BleAppState.connectionFailed,
      );
    });

    test('platform channel failures never leak the raw error', () {
      final permission = map(
        PlatformException(code: 'permission_denied', message: 'raw plugin'),
        operation: BleOperation.permission,
      );
      expect(permission.appState, BleAppState.permissionNeeded);
      expect(permission.message, isNot(contains('raw plugin')));

      expect(
        map(
          PlatformException(code: 'bluetooth_off'),
          operation: BleOperation.scan,
        ).appState,
        BleAppState.bluetoothOff,
      );
      expect(
        map(
          const FormatException('bad'),
          operation: BleOperation.write,
        ).appState,
        BleAppState.gattError,
      );
    });

    test('unexpected scan failures fall back to no-results', () {
      expect(
        map(StateError('radio'), operation: BleOperation.scan).appState,
        BleAppState.noResults,
      );
    });

    test('the mapper preserves an existing typed exception', () {
      const original = BleException(BleFailure.notBonded, 'security');
      expect(map(original, operation: BleOperation.read), same(original));
    });
  });

  group('fake fault injection', () {
    test('FakeBleClient still satisfies the production interface', () {
      final BleClient client = _fake();
      expect(client, isA<FakeBleClient>());
      addTearDown(client.dispose);
    });

    test('permission, Bluetooth and support states are named', () async {
      final denied = _fake(permission: BlePermissionState.denied);
      addTearDown(denied.dispose);
      expect(
        (await denied.platformStatus()).state,
        BleAppState.permissionNeeded,
      );
      await expectLater(
        denied.scan(),
        emitsError(
          isA<BleException>().having(
            (error) => error.appState,
            'appState',
            BleAppState.permissionNeeded,
          ),
        ),
      );

      final blocked = _fake(
        permission: BlePermissionState.denied,
        permissionOnRequest: BlePermissionState.permanentlyDenied,
      );
      addTearDown(blocked.dispose);
      expect(
        await blocked.requestPermissions(),
        BlePermissionState.permanentlyDenied,
      );
      expect(
        (await blocked.platformStatus()).state,
        BleAppState.permissionBlocked,
      );

      final off = _fake(bluetoothOn: false);
      addTearDown(off.dispose);
      expect((await off.platformStatus()).state, BleAppState.bluetoothOff);

      final unsupported = _fake(supported: false);
      addTearDown(unsupported.dispose);
      expect(
        (await unsupported.platformStatus()).state,
        BleAppState.unsupportedPhone,
      );
    });

    test('scan failure carries the named no-results mapping', () async {
      final client = _fake(
        scanError: const BleException(BleFailure.scanFailed, 'radio'),
      );
      addTearDown(client.dispose);
      await expectLater(
        client.scan(),
        emitsError(
          isA<BleException>().having(
            (error) => error.appState,
            'appState',
            BleAppState.noResults,
          ),
        ),
      );
      expect(client.diagnostics.entries.single.failure, BleFailure.scanFailed);
    });

    test('connect, MTU, read, write and subscribe faults stay typed', () async {
      final connect = _fake(
        connectError: const BleException(
          BleFailure.connectionFailed,
          'refused',
        ),
      );
      addTearDown(connect.dispose);
      await expectLater(
        connect.connect(_bridge()),
        throwsA(
          isA<BleException>().having(
            (error) => error.appState,
            'appState',
            BleAppState.connectionFailed,
          ),
        ),
      );

      final client = _fake(
        mtuError: const BleException(BleFailure.gattError, 'mtu'),
        readError: const BleException(BleFailure.notBonded, 'security'),
        writeError: const BleException(BleFailure.gattError, 'write'),
        notifyError: const BleException(BleFailure.unsupported, 'notify'),
      );
      addTearDown(client.dispose);
      await client.connect(_bridge());
      expect(client.connectionState, BleConnectionState.connected);

      await expectLater(
        client.requestMtu(bleRequestedMtu),
        throwsA(
          isA<BleException>().having(
            (error) => error.appState,
            'appState',
            BleAppState.gattError,
          ),
        ),
      );
      await expectLater(
        client.read(bleUuid('info')),
        throwsA(
          isA<BleException>().having(
            (error) => error.appState,
            'appState',
            BleAppState.pairingFailed,
          ),
        ),
      );
      await expectLater(
        client.write(bleUuid('config'), Uint8List(1)),
        throwsA(
          isA<BleException>().having(
            (error) => error.appState,
            'appState',
            BleAppState.gattError,
          ),
        ),
      );
      await expectLater(
        client.setNotify(bleUuid('live'), enabled: true),
        throwsA(
          isA<BleException>().having(
            (error) => error.appState,
            'appState',
            BleAppState.gattError,
          ),
        ),
      );
    });

    test(
      'bond failure states are named and removeBond clears the bond',
      () async {
        final timeout = _fake(
          bondError: const BleException(BleFailure.promptTimeout, 'no prompt'),
        );
        addTearDown(timeout.dispose);
        await timeout.connect(_bridge());
        expect(await timeout.bond(), BleBondState.timeout);
        expect(
          timeout.diagnostics.entries.last.failure,
          BleFailure.promptTimeout,
        );

        final full = _fake(
          bondError: const BleException(BleFailure.bondStoreFull, 'full'),
        );
        addTearDown(full.dispose);
        await full.connect(_bridge());
        expect(await full.bond(), BleBondState.bondStoreFull);

        final normal = _fake();
        addTearDown(normal.dispose);
        await normal.connect(_bridge());
        expect(await normal.bond(passkey: '418302'), BleBondState.bonded);
        await normal.removeBond();
        expect(normal.bondState, BleBondState.none);
      },
    );

    test('negotiated MTU is recorded and visible in diagnostics', () async {
      final client = _fake();
      addTearDown(client.dispose);
      await client.connect(_bridge());
      expect(client.diagnostics.negotiatedMtu, bleDefaultMtu);

      final negotiated = await client.requestMtu(bleRequestedMtu);
      expect(negotiated, bleRequestedMtu);
      expect(client.negotiatedMtu, bleRequestedMtu);
      expect(client.diagnostics.negotiatedMtu, bleRequestedMtu);
      expect(client.diagnostics.summary, contains('MTU 247'));
      expect(client.diagnostics.phoneModel, 'test-phone');
      expect(client.diagnostics.androidVersion, contains('Android 14'));
      expect(
        client.diagnostics.entries.any(
          (entry) => entry.message.contains('MTU 247'),
        ),
        isTrue,
      );
    });
  });
}
