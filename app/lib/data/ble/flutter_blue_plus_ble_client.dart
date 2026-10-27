import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart' as ph;

import 'ble_client.dart';
import 'ble_error_mapper.dart';

/// Production BLE client on `flutter_blue_plus`.
///
/// The rest of the app only sees [BleClient]: raw payloads, named states and
/// [BleException]. Every plugin exception is mapped here; no plugin type or
/// error string escapes this file.
class FlutterBluePlusBleClient implements BleClient {
  FlutterBluePlusBleClient({
    BleDiagnostics? diagnostics,
    this.scanTimeout = bleScanTimeout,
  }) : diagnostics = diagnostics ?? BleDiagnostics();

  @override
  final BleDiagnostics diagnostics;

  /// Default foreground scan window. Foreground-only by design: no background
  /// scan, foreground service or battery exemption.
  final Duration scanTimeout;

  final StreamController<BleConnectionState> _connectionController =
      StreamController<BleConnectionState>.broadcast();
  final StreamController<BleBondState> _bondController =
      StreamController<BleBondState>.broadcast();
  final Map<String, StreamController<Uint8List>> _notificationControllers =
      <String, StreamController<Uint8List>>{};
  final Map<String, StreamSubscription<List<int>>> _notificationSubscriptions =
      <String, StreamSubscription<List<int>>>{};
  final Map<String, _ScanSnapshot> _lastScanResults = <String, _ScanSnapshot>{};

  fbp.BluetoothDevice? _device;
  BleDevice? _connectedDevice;
  StreamSubscription<fbp.BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<fbp.BluetoothBondState>? _bondSubscription;
  StreamSubscription<List<fbp.ScanResult>>? _scanSubscription;
  Timer? _scanTimer;
  BleConnectionState _connectionState = BleConnectionState.disconnected;
  BleBondState _bondState = BleBondState.none;
  int? _negotiatedMtu;
  bool _disposed = false;
  _PhoneInfo? _phoneInfo;

  @override
  Future<BlePlatformStatus> platformStatus() async {
    final info = await _readPhoneInfo();
    diagnostics
      ..phoneModel = info.model
      ..androidVersion = info.androidVersion;

    bool supported;
    try {
      supported = await fbp.FlutterBluePlus.isSupported;
    } catch (_) {
      supported = false;
    }

    final permission = await _permissionStatus(info.sdkInt);
    final kind = _permissionKind(info.sdkInt);

    var bluetoothOn = false;
    if (supported) {
      try {
        final state = await fbp.FlutterBluePlus.adapterState.first.timeout(
          const Duration(seconds: 3),
        );
        bluetoothOn = state == fbp.BluetoothAdapterState.on;
      } catch (_) {
        bluetoothOn = false;
      }
    }

    final status = BlePlatformStatus(
      supported: supported,
      bluetoothOn: bluetoothOn,
      permission: permission,
      permissionKind: kind,
      androidSdk: info.sdkInt,
    );
    if (status.state != BleAppState.ready) {
      diagnostics.record(
        'platform state ${status.state.name}',
        level: BleLogLevel.warning,
      );
    }
    return status;
  }

  @override
  Future<BlePermissionState> requestPermissions() async {
    if (!Platform.isAndroid) return BlePermissionState.granted;
    final info = await _readPhoneInfo();
    final kind = _permissionKind(info.sdkInt);
    try {
      if (kind == BlePermissionKind.location) {
        return _fromPermissionStatus(
          await ph.Permission.locationWhenInUse.request(),
        );
      }
      final scan = await ph.Permission.bluetoothScan.request();
      final connect = await ph.Permission.bluetoothConnect.request();
      return _worstPermission(
        _fromPermissionStatus(scan),
        _fromPermissionStatus(connect),
      );
    } catch (_) {
      diagnostics.record(
        'permission request failed',
        level: BleLogLevel.error,
        failure: BleFailure.permissionDenied,
      );
      return BlePermissionState.denied;
    }
  }

  @override
  Stream<BleDevice> scan({Duration timeout = bleScanTimeout}) {
    late StreamController<BleDevice> controller;
    var finished = false;

    Future<void> finish() async {
      if (finished) return;
      finished = true;
      _scanTimer?.cancel();
      _scanTimer = null;
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      try {
        await fbp.FlutterBluePlus.stopScan();
      } catch (_) {
        // A failed stop must never mask the scan result or its named error.
      }
      if (!controller.isClosed) await controller.close();
    }

    Future<void> start() async {
      try {
        final status = await platformStatus();
        if (!status.canScan) {
          throw exceptionForBleAppState(status.state);
        }
        _lastScanResults.clear();
        await fbp.FlutterBluePlus.startScan(
          // Scan unfiltered and filter in Dart. Android's platform service
          // filter can drop a connectable advertisement whose 128-bit UUID is
          // in the primary PDU while the local name is in the scan response.
          // The bridge contract still requires both (isCompatibleBridge).
          timeout: timeout,
          androidScanMode: fbp.AndroidScanMode.lowLatency,
        );
        _scanSubscription = fbp.FlutterBluePlus.onScanResults.listen(
          (results) {
            // The plugin re-emits the whole list. A device can appear first in
            // the primary advertisement and only gain its name/manufacturer
            // block when the scan response arrives, so emit an update rather
            // than dropping every later report for that address.
            for (final result in results) {
              final device = _toBleDevice(result);
              final previous = _lastScanResults[device.id];
              final next = _ScanSnapshot.of(device);
              if (previous == next) continue;
              _lastScanResults[device.id] = next;
              if (!controller.isClosed) controller.add(device);
            }
          },
          onError: (Object error, StackTrace stack) {
            final mapped = mapBlePlatformError(
              error,
              operation: BleOperation.scan,
            );
            diagnostics.record(
              'scan failed (${mapped.failure.name})',
              level: BleLogLevel.error,
              failure: mapped.failure,
            );
            if (!controller.isClosed) controller.addError(mapped);
            unawaited(finish());
          },
        );
        _scanTimer = Timer(timeout, () => unawaited(finish()));
      } catch (error) {
        final mapped = mapBlePlatformError(error, operation: BleOperation.scan);
        diagnostics.record(
          'scan start failed (${mapped.failure.name})',
          level: BleLogLevel.error,
          failure: mapped.failure,
        );
        if (!controller.isClosed) controller.addError(mapped);
        await finish();
      }
    }

    controller = StreamController<BleDevice>(
      onListen: () => unawaited(start()),
      onCancel: () => unawaited(finish()),
    );
    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    try {
      await fbp.FlutterBluePlus.stopScan();
    } catch (error) {
      diagnostics.record('stop scan failed', level: BleLogLevel.warning);
    }
  }

  @override
  BleConnectionState get connectionState => _connectionState;

  @override
  Stream<BleConnectionState> get connectionStates =>
      _connectionController.stream;

  @override
  BleDevice? get connectedDevice => _connectedDevice;

  @override
  Future<void> connect(
    BleDevice device, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    _checkNotDisposed();
    if (_connectionState == BleConnectionState.connected &&
        _connectedDevice?.id == device.id) {
      return;
    }
    final status = await platformStatus();
    if (!status.canScan) throw exceptionForBleAppState(status.state);

    await stopScan();
    _setConnection(BleConnectionState.connecting);
    try {
      await _connectOnce(device, timeout);
    } catch (error) {
      var mapped = mapBlePlatformError(error, operation: BleOperation.connect);
      // Android frequently reports GATT status 133 for the first attempt
      // immediately after a scan stops. One short, sequential retry is the
      // documented workaround and does not mask a real permission, bond, or
      // range failure (those map to other failures).
      if (mapped.failure == BleFailure.connectionFailed ||
          mapped.failure == BleFailure.failed) {
        diagnostics.record(
          'connect failed (${mapped.failure.name}); retrying once',
          level: BleLogLevel.warning,
          failure: mapped.failure,
        );
        await _dropConnection();
        await Future<void>.delayed(const Duration(milliseconds: 350));
        try {
          await _connectOnce(device, timeout);
          diagnostics.record('connected to ${device.id} (retry)');
          return;
        } catch (retryError) {
          mapped = mapBlePlatformError(
            retryError,
            operation: BleOperation.connect,
          );
        }
      }
      diagnostics.record(
        'connect failed (${mapped.failure.name})',
        level: BleLogLevel.error,
        failure: mapped.failure,
      );
      await _dropConnection();
      _setConnection(BleConnectionState.disconnected);
      throw mapped;
    }
  }

  /// Best-effort teardown after a partially successful connect (for example,
  /// GATT discovery failed). Leaving the OS link up would occupy the bridge's
  /// single connection slot and make the next attempt fail.
  Future<void> _dropConnection() async {
    try {
      await _device?.disconnect();
    } catch (_) {
      // Best effort only; the state reset below is what the app relies on.
    }
    await _cleanupLink();
  }

  Future<void> _connectOnce(BleDevice device, Duration timeout) async {
    final target = fbp.BluetoothDevice.fromId(device.id);
    await target.connect(timeout: timeout, mtu: null);
    _device = target;
    _connectedDevice = device;
    _negotiatedMtu = bleDefaultMtu;
    diagnostics.negotiatedMtu = _negotiatedMtu;
    _connectionSubscription = target.connectionState.listen((state) {
      if (state == fbp.BluetoothConnectionState.connected) {
        _setConnection(BleConnectionState.connected);
      } else if (state == fbp.BluetoothConnectionState.disconnected) {
        _onLinkLost();
      }
    });
    _bondSubscription = target.bondState.listen(_applyBondState);
    // The stream's first value is the OS bond state, but it is delivered
    // asynchronously. Wait for it before returning so a reconnect with a stored
    // bond never races into the "bond first" path (which has no prompt surface
    // outside setup).
    try {
      final initialBond = await target.bondState.first.timeout(
        const Duration(seconds: 3),
      );
      _applyBondState(initialBond);
    } catch (_) {
      // An OS that cannot report the bond state is treated as not bonded; the
      // procedure then takes the explicit bond path once.
    }
    await target.discoverServices();
    _setConnection(BleConnectionState.connected);
    diagnostics.record('connected to ${device.id}');
  }

  @override
  Future<void> disconnect() async {
    if (_connectionState == BleConnectionState.disconnected) return;
    _setConnection(BleConnectionState.disconnecting);
    try {
      await _device?.disconnect();
    } catch (error) {
      final mapped = mapBlePlatformError(
        error,
        operation: BleOperation.disconnect,
      );
      diagnostics.record(
        'disconnect failed (${mapped.failure.name})',
        level: BleLogLevel.warning,
        failure: mapped.failure,
      );
    } finally {
      await _cleanupLink();
      _setConnection(BleConnectionState.disconnected);
    }
  }

  @override
  BleBondState get bondState => _bondState;

  @override
  Stream<BleBondState> get bondStates => _bondController.stream;

  @override
  Future<BleBondState> bond({String? passkey}) async {
    _checkConnected();
    if (_bondState == BleBondState.bonded) return _bondState;
    _setBond(BleBondState.bonding);
    try {
      final pin = passkey == null ? null : _passkeyBytes(passkey);
      await _device!.createBond(timeout: 90, pin: pin);
      _setBond(BleBondState.bonded);
      diagnostics.record('bonded');
      return _bondState;
    } catch (error) {
      final mapped = mapBlePlatformError(error, operation: BleOperation.bond);
      final state = switch (mapped.failure) {
        BleFailure.promptTimeout => BleBondState.timeout,
        BleFailure.bondStoreFull => BleBondState.bondStoreFull,
        BleFailure.timeout => BleBondState.timeout,
        _ => BleBondState.failed,
      };
      _setBond(state);
      diagnostics.record(
        'bond failed (${mapped.failure.name})',
        level: BleLogLevel.error,
        failure: mapped.failure,
      );
      return state;
    }
  }

  @override
  Future<void> removeBond() async {
    _checkConnected();
    try {
      await _device!.removeBond();
      _setBond(BleBondState.none);
      diagnostics.record('bond removed');
    } catch (error) {
      final mapped = mapBlePlatformError(
        error,
        operation: BleOperation.removeBond,
      );
      diagnostics.record(
        'remove bond failed (${mapped.failure.name})',
        level: BleLogLevel.error,
        failure: mapped.failure,
      );
      throw mapped;
    }
  }

  @override
  int? get negotiatedMtu => _negotiatedMtu;

  @override
  Future<int> readRssi() async {
    _checkConnected();
    try {
      return await _device!.readRssi();
    } catch (error) {
      final mapped = mapBlePlatformError(error, operation: BleOperation.read);
      diagnostics.record(
        'read RSSI failed (${mapped.failure.name})',
        level: BleLogLevel.warning,
        failure: mapped.failure,
      );
      throw mapped;
    }
  }

  @override
  Future<int> requestMtu(int mtu) async {
    _checkConnected();
    try {
      final negotiated = await _device!.requestMtu(mtu);
      _negotiatedMtu = negotiated;
      diagnostics
        ..negotiatedMtu = negotiated
        ..record('MTU $negotiated (requested $mtu)');
      return negotiated;
    } catch (error) {
      final mapped = mapBlePlatformError(error, operation: BleOperation.mtu);
      diagnostics.record(
        'MTU request failed (${mapped.failure.name})',
        level: _bleLevelFor(mapped.failure),
        failure: mapped.failure,
      );
      throw mapped;
    }
  }

  @override
  Future<Uint8List> read(String characteristicUuid) async {
    _checkConnected();
    try {
      final characteristic = _characteristic(characteristicUuid);
      var value = await characteristic.read();

      // `flutter_blue_plus` has no Read Blob offset API. Android may truncate a
      // long attribute at MTU-1, which is exactly `info` at the default MTU.
      // Detect that boundary, negotiate the contract MTU, and re-read once; the
      // bridge's longest fixed payload (80 B) fits at MTU 247.
      final mtu = _negotiatedMtu;
      if (mtu != null && mtu < bleRequestedMtu && value.length >= mtu - 1) {
        diagnostics.record('long read retry at MTU $bleRequestedMtu');
        await requestMtu(bleRequestedMtu);
        final second = await characteristic.read();
        if (second.length > value.length) value = second;
      }
      return Uint8List.fromList(value);
    } catch (error) {
      final mapped = mapBlePlatformError(error, operation: BleOperation.read);
      diagnostics.record(
        'read $characteristicUuid failed (${mapped.failure.name})',
        level: BleLogLevel.error,
        failure: mapped.failure,
      );
      throw mapped;
    }
  }

  @override
  Future<void> write(String characteristicUuid, Uint8List value) async {
    _checkConnected();
    try {
      final characteristic = _characteristic(characteristicUuid);
      final mtu = _negotiatedMtu ?? bleDefaultMtu;
      await characteristic.write(value, allowLongWrite: value.length > mtu - 3);
    } catch (error) {
      final mapped = mapBlePlatformError(error, operation: BleOperation.write);
      diagnostics.record(
        'write $characteristicUuid failed (${mapped.failure.name})',
        level: BleLogLevel.error,
        failure: mapped.failure,
      );
      throw mapped;
    }
  }

  @override
  Stream<Uint8List> notifications(String characteristicUuid) {
    return _notificationController(characteristicUuid).stream;
  }

  @override
  Future<void> setNotify(
    String characteristicUuid, {
    required bool enabled,
  }) async {
    _checkConnected();
    final key = characteristicUuid.toLowerCase();
    try {
      final characteristic = _characteristic(characteristicUuid);
      await characteristic.setNotifyValue(enabled);
      if (enabled) {
        final controller = _notificationController(key);
        await _notificationSubscriptions[key]?.cancel();
        _notificationSubscriptions[key] = characteristic.onValueReceived.listen(
          (value) {
            if (!controller.isClosed) {
              controller.add(Uint8List.fromList(value));
            }
          },
          onError: (Object error, StackTrace stack) {
            final mapped = mapBlePlatformError(
              error,
              operation: BleOperation.subscribe,
            );
            diagnostics.record(
              'notification $characteristicUuid failed '
              '(${mapped.failure.name})',
              level: BleLogLevel.error,
              failure: mapped.failure,
            );
            if (!controller.isClosed) controller.addError(mapped);
          },
        );
        diagnostics.record('subscribed $characteristicUuid');
      } else {
        await _notificationSubscriptions.remove(key)?.cancel();
        diagnostics.record('unsubscribed $characteristicUuid');
      }
    } catch (error) {
      final mapped = mapBlePlatformError(
        error,
        operation: BleOperation.subscribe,
      );
      diagnostics.record(
        'subscribe $characteristicUuid failed (${mapped.failure.name})',
        level: BleLogLevel.error,
        failure: mapped.failure,
      );
      throw mapped;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      await fbp.FlutterBluePlus.stopScan();
    } catch (_) {
      // Best effort on shutdown.
    }
    await _cleanupLink();
    for (final controller in _notificationControllers.values) {
      await controller.close();
    }
    _notificationControllers.clear();
    await _connectionController.close();
    await _bondController.close();
  }

  Future<void> _cleanupLink() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _bondSubscription?.cancel();
    _bondSubscription = null;
    for (final subscription in _notificationSubscriptions.values) {
      await subscription.cancel();
    }
    _notificationSubscriptions.clear();
    _device = null;
    _connectedDevice = null;
    _negotiatedMtu = null;
    diagnostics.negotiatedMtu = null;
  }

  void _onLinkLost() {
    _setConnection(BleConnectionState.disconnected);
    _connectedDevice = null;
    _negotiatedMtu = null;
    diagnostics
      ..negotiatedMtu = null
      ..record('link lost', level: BleLogLevel.warning);
  }

  fbp.BluetoothCharacteristic _characteristic(String uuid) {
    final target = uuid.toLowerCase();
    for (final service in _device!.servicesList) {
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid.str.toLowerCase() == target) {
          return characteristic;
        }
      }
    }
    throw const BleException(
      BleFailure.unknownCharacteristic,
      'contract characteristic not found',
    );
  }

  StreamController<Uint8List> _notificationController(String uuid) {
    return _notificationControllers.putIfAbsent(
      uuid.toLowerCase(),
      () => StreamController<Uint8List>.broadcast(),
    );
  }

  void _checkConnected() {
    _checkNotDisposed();
    if (_connectionState != BleConnectionState.connected) {
      throw const BleException(BleFailure.notConnected);
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw const BleException(BleFailure.failed, 'client disposed');
    }
  }

  void _setConnection(BleConnectionState state) {
    if (_connectionState == state) return;
    _connectionState = state;
    if (!_connectionController.isClosed) _connectionController.add(state);
  }

  void _setBond(BleBondState state) {
    if (_bondState == state) return;
    _bondState = state;
    if (!_bondController.isClosed) _bondController.add(state);
  }

  void _applyBondState(fbp.BluetoothBondState state) {
    switch (state) {
      case fbp.BluetoothBondState.bonded:
        _setBond(BleBondState.bonded);
      case fbp.BluetoothBondState.bonding:
        _setBond(BleBondState.bonding);
      case fbp.BluetoothBondState.none:
        // A just-finished attempt keeps its named failure so the UI does not
        // lose "wrong code" as the OS settles back to none.
        if (_bondState != BleBondState.failed &&
            _bondState != BleBondState.wrongPasskey) {
          _setBond(BleBondState.none);
        }
    }
  }

  BleDevice _toBleDevice(fbp.ScanResult result) {
    final data = result.advertisementData;
    Uint8List? manufacturerData;
    if (data.manufacturerData.isNotEmpty) {
      final entry = data.manufacturerData.entries.first;
      manufacturerData = Uint8List.fromList(<int>[
        entry.key & 0xFF,
        (entry.key >> 8) & 0xFF,
        ...entry.value,
      ]);
    }
    return BleDevice(
      id: result.device.remoteId.str,
      name: data.advName.isNotEmpty ? data.advName : result.device.platformName,
      rssi: result.rssi,
      manufacturerData: manufacturerData,
      serviceUuids: <String>[
        for (final uuid in data.serviceUuids) uuid.str.toLowerCase(),
      ],
    );
  }

  Uint8List _passkeyBytes(String passkey) {
    final digits = passkey.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return Uint8List(0);
    return Uint8List.fromList(
      digits.split('').map(int.parse).toList(growable: false),
    );
  }

  Future<_PhoneInfo> _readPhoneInfo() async {
    final cached = _phoneInfo;
    if (cached != null) return cached;
    try {
      final map = await const MethodChannel('smoke_bridge/device_info')
          .invokeMapMethod<String, Object?>('get');
      final sdk = (map?['sdkInt'] as num?)?.toInt();
      final release = map?['release']?.toString() ?? 'unknown';
      final model = map?['model']?.toString() ?? 'unknown';
      return _phoneInfo = _PhoneInfo(
        model: model,
        androidVersion: 'Android $release (SDK ${sdk ?? '?'})',
        sdkInt: sdk,
      );
    } catch (_) {
      final version = Platform.operatingSystemVersion;
      final match = RegExp(r'API (\d+)').firstMatch(version);
      return _phoneInfo = _PhoneInfo(
        model: Platform.localHostname,
        androidVersion: version,
        sdkInt: match == null ? null : int.tryParse(match.group(1)!),
      );
    }
  }

  Future<BlePermissionState> _permissionStatus(int? sdk) async {
    if (!Platform.isAndroid) return BlePermissionState.granted;
    try {
      if (_permissionKind(sdk) == BlePermissionKind.location) {
        return _fromPermissionStatus(
          await ph.Permission.locationWhenInUse.status,
        );
      }
      final scan = await ph.Permission.bluetoothScan.status;
      final connect = await ph.Permission.bluetoothConnect.status;
      return _worstPermission(
        _fromPermissionStatus(scan),
        _fromPermissionStatus(connect),
      );
    } catch (_) {
      return BlePermissionState.notDetermined;
    }
  }

  BlePermissionKind _permissionKind(int? sdk) {
    final effective = sdk ?? 31;
    return effective >= 31
        ? BlePermissionKind.nearbyDevices
        : BlePermissionKind.location;
  }
}

BleLogLevel _bleLevelFor(BleFailure failure) {
  switch (failure) {
    case BleFailure.permissionDenied:
    case BleFailure.permissionBlocked:
    case BleFailure.bluetoothOff:
    case BleFailure.unsupportedPhone:
      return BleLogLevel.warning;
    default:
      return BleLogLevel.error;
  }
}

BlePermissionState _fromPermissionStatus(ph.PermissionStatus status) {
  switch (status) {
    case ph.PermissionStatus.granted:
    case ph.PermissionStatus.limited:
    case ph.PermissionStatus.provisional:
      return BlePermissionState.granted;
    case ph.PermissionStatus.denied:
      return BlePermissionState.denied;
    case ph.PermissionStatus.permanentlyDenied:
    case ph.PermissionStatus.restricted:
      return BlePermissionState.permanentlyDenied;
  }
}

BlePermissionState _worstPermission(
  BlePermissionState a,
  BlePermissionState b,
) {
  if (a == BlePermissionState.permanentlyDenied ||
      b == BlePermissionState.permanentlyDenied) {
    return BlePermissionState.permanentlyDenied;
  }
  if (a == BlePermissionState.denied || b == BlePermissionState.denied) {
    return BlePermissionState.denied;
  }
  if (a == BlePermissionState.notDetermined ||
      b == BlePermissionState.notDetermined) {
    return BlePermissionState.notDetermined;
  }
  return BlePermissionState.granted;
}

/// The fields a later scan report may improve on. RSSI is deliberately not
/// included: it changes constantly, and the results list only needs identity,
/// name, service UUIDs and the manufacturer preview.
class _ScanSnapshot {
  const _ScanSnapshot({
    required this.name,
    required this.serviceUuids,
    required this.manufacturerData,
  });

  factory _ScanSnapshot.of(BleDevice device) {
    return _ScanSnapshot(
      name: device.name,
      serviceUuids: device.serviceUuids.join(','),
      manufacturerData: device.manufacturerData == null
          ? ''
          : device.manufacturerData!.join(','),
    );
  }

  final String name;
  final String serviceUuids;
  final String manufacturerData;

  @override
  bool operator ==(Object other) =>
      other is _ScanSnapshot &&
      other.name == name &&
      other.serviceUuids == serviceUuids &&
      other.manufacturerData == manufacturerData;

  @override
  int get hashCode => Object.hash(name, serviceUuids, manufacturerData);
}

class _PhoneInfo {
  const _PhoneInfo({
    required this.model,
    required this.androidVersion,
    required this.sdkInt,
  });

  final String model;
  final String androidVersion;
  final int? sdkInt;
}
