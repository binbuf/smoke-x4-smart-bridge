import 'dart:async';
import 'dart:typed_data';

import 'package:smoke_bridge/data/ble/ble_client.dart';

import 'codecs.dart';
import 'fake_gatt_server.dart';

/// Scripted BLE central used by app tests.
///
/// It models everything the production `BleClient` must do, with no radio:
/// advertisements from a fixed script, connect/disconnect state, LE Secure
/// Connections bonding (including a wrong passkey), MTU negotiation, security
/// checks on reads/writes/subscriptions, and notification chunking at `MTU-3`.
///
/// GATT reads and writes are delegated to a [FakeGattServer], normally
/// [FakeBridge].
class FakeBleClient implements BleClient {
  FakeBleClient({
    required this.server,
    required List<BleDevice> advertisements,
    this.expectedPasskey,
    this.forcedBondFailure,
    this.scanInterval = const Duration(milliseconds: 1),
    this.connectDelay = const Duration(milliseconds: 5),
    this.bondDelay = const Duration(milliseconds: 5),
    this.maxMtu = bleMtuRequest,
    this.failConnect = false,
    this.connectFailuresRemaining = 0,
    this.permission = BlePermissionState.granted,
    this.permissionOnRequest,
    this.bluetoothOn = true,
    this.supported = true,
    this.androidSdk = 34,
    this.scanError,
    this.connectError,
    this.bondError,
    this.readError,
    this.writeError,
    this.notifyError,
    this.mtuError,
    this.removeBondError,
    BleDiagnostics? diagnostics,
  }) : _advertisements = List<BleDevice>.unmodifiable(advertisements),
       diagnostics =
           diagnostics ??
           BleDiagnostics(
             phoneModel: 'test-phone',
             androidVersion: 'Android 14 (SDK 34)',
             negotiatedMtu: bleMtuDefault,
           ) {
    server.setMtu(bleMtuDefault);
  }

  final FakeGattServer server;

  /// Advertisements emitted in order. A device must appear here before
  /// [connect] accepts it, so tests cannot accidentally connect to nothing.
  final List<BleDevice> _advertisements;

  /// Expected six-digit passkey. `null` means the fake accepts any passkey.
  final String? expectedPasskey;

  /// Optional scripted bond outcome other than [BleBondState.bonded].
  final BleBondState? forcedBondFailure;

  final Duration scanInterval;
  final Duration connectDelay;
  final Duration bondDelay;

  /// Highest MTU this fake peripheral supports.
  final int maxMtu;

  /// When true, [connect] reports [BleFailure.failed] without connecting.
  final bool failConnect;

  /// Number of scripted connection failures before [connect] succeeds.
  int connectFailuresRemaining;

  /// Every client call in order, for procedure-order assertions in tests.
  final List<String> operations = <String>[];

  final bool bluetoothOn;
  final bool supported;
  final int androidSdk;
  BlePermissionState permission;
  final BlePermissionState? permissionOnRequest;

  /// Scripted platform faults. A non-null value is thrown by the matching
  /// operation, which lets tests prove the named-state mapping.
  final BleException? scanError;
  final BleException? connectError;
  final BleException? bondError;
  BleException? readError;
  final BleException? writeError;
  final BleException? notifyError;
  final BleException? mtuError;
  final BleException? removeBondError;

  @override
  final BleDiagnostics diagnostics;

  final StreamController<BleConnectionState> _connectionController =
      StreamController<BleConnectionState>.broadcast();
  final StreamController<BleBondState> _bondController =
      StreamController<BleBondState>.broadcast();
  final Map<String, StreamController<Uint8List>> _notificationControllers =
      <String, StreamController<Uint8List>>{};
  final Map<String, StreamSubscription<Uint8List>> _serverSubscriptions =
      <String, StreamSubscription<Uint8List>>{};

  BleConnectionState _connectionState = BleConnectionState.disconnected;
  BleBondState _bondState = BleBondState.none;
  BleDevice? _connectedDevice;
  int? _negotiatedMtu;
  int linkRssi = -52;
  bool _scanning = false;
  bool _disposed = false;

  @override
  Future<BlePlatformStatus> platformStatus() async {
    return BlePlatformStatus(
      supported: supported,
      bluetoothOn: bluetoothOn,
      permission: permission,
      permissionKind: androidSdk >= 31
          ? BlePermissionKind.nearbyDevices
          : BlePermissionKind.location,
      androidSdk: androidSdk,
    );
  }

  @override
  Future<BlePermissionState> requestPermissions() async {
    final requested = permissionOnRequest;
    if (requested != null) permission = requested;
    return permission;
  }

  @override
  Stream<BleDevice> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async* {
    final failure = scanError;
    if (failure != null) {
      diagnostics.record(
        'scan failed (${failure.failure.name})',
        level: BleLogLevel.error,
        failure: failure.failure,
      );
      throw failure;
    }
    final status = await platformStatus();
    if (!status.canScan) {
      throw exceptionForBleAppState(status.state);
    }
    await stopScan();
    _scanning = true;
    final deadline = DateTime.now().add(timeout);
    try {
      for (final device in _advertisements) {
        if (!_scanning || DateTime.now().isAfter(deadline)) break;
        await Future<void>.delayed(scanInterval);
        if (!_scanning) break;
        yield device;
      }
    } finally {
      _scanning = false;
    }
  }

  @override
  Future<void> stopScan() async {
    _scanning = false;
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
    operations.add('connect:${device.id}');
    if (connectFailuresRemaining > 0) {
      connectFailuresRemaining--;
      _setConnection(BleConnectionState.disconnected);
      throw const BleException(BleFailure.connectionFailed, 'connect failed');
    }
    final failure = connectError;
    if (failure != null) {
      diagnostics.record(
        'connect failed (${failure.failure.name})',
        level: BleLogLevel.error,
        failure: failure.failure,
      );
      throw failure;
    }
    if (_connectionState == BleConnectionState.connected &&
        _connectedDevice?.id == device.id) {
      return;
    }
    final status = await platformStatus();
    if (!status.canScan) {
      throw exceptionForBleAppState(status.state);
    }
    if (!_advertisements.any((item) => item.id == device.id)) {
      throw BleException(
        BleFailure.failed,
        'device ${device.id} is not in the scripted advertisement list',
      );
    }
    await stopScan();
    _setConnection(BleConnectionState.connecting);
    final started = DateTime.now();
    await Future<void>.delayed(connectDelay);
    if (failConnect || DateTime.now().difference(started) > timeout) {
      _setConnection(BleConnectionState.disconnected);
      throw const BleException(BleFailure.failed, 'connect failed');
    }
    _connectedDevice = device;
    _negotiatedMtu = bleMtuDefault;
    diagnostics
      ..negotiatedMtu = _negotiatedMtu
      ..record('connected to ${device.id}');
    server.setMtu(bleMtuDefault);
    _setConnection(BleConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    _checkNotDisposed();
    operations.add('disconnect');
    if (_connectionState == BleConnectionState.disconnected) return;
    _setConnection(BleConnectionState.disconnecting);
    for (final subscription in _serverSubscriptions.values) {
      await subscription.cancel();
    }
    _serverSubscriptions.clear();
    await server.onDisconnected();
    _connectedDevice = null;
    _negotiatedMtu = null;
    _setConnection(BleConnectionState.disconnected);
  }

  @override
  BleBondState get bondState => _bondState;

  @override
  Stream<BleBondState> get bondStates => _bondController.stream;

  @override
  Future<BleBondState> bond({String? passkey}) async {
    _checkConnected();
    operations.add('bond');
    if (_bondState == BleBondState.bonded) return _bondState;
    final failure = bondError;
    if (failure != null) {
      final state = switch (failure.failure) {
        BleFailure.promptTimeout => BleBondState.timeout,
        BleFailure.bondStoreFull => BleBondState.bondStoreFull,
        _ => BleBondState.failed,
      };
      _setBond(state);
      diagnostics.record(
        'bond failed (${failure.failure.name})',
        level: BleLogLevel.error,
        failure: failure.failure,
      );
      return state;
    }
    _setBond(BleBondState.bonding);
    await Future<void>.delayed(bondDelay);
    final forced = forcedBondFailure;
    if (forced != null && forced != BleBondState.bonded) {
      _setBond(forced);
      diagnostics.record(
        'bond failed (forced ${forced.name})',
        level: BleLogLevel.error,
      );
      return _bondState;
    }
    if (expectedPasskey != null &&
        _normalizePasskey(passkey) != _normalizePasskey(expectedPasskey)) {
      _setBond(BleBondState.wrongPasskey);
      diagnostics.record(
        'bond failed (wrong passkey)',
        level: BleLogLevel.error,
        failure: BleFailure.wrongPasskey,
      );
      return _bondState;
    }
    _setBond(BleBondState.bonded);
    diagnostics.record('bonded');
    return _bondState;
  }

  @override
  Future<void> removeBond() async {
    _checkConnected();
    final failure = removeBondError;
    if (failure != null) {
      diagnostics.record(
        'remove bond failed (${failure.failure.name})',
        level: BleLogLevel.error,
        failure: failure.failure,
      );
      throw failure;
    }
    _setBond(BleBondState.none);
    diagnostics.record('bond removed');
  }

  @override
  int? get negotiatedMtu => _negotiatedMtu;

  @override
  Future<int> readRssi() async {
    _checkConnected();
    operations.add('rssi');
    return linkRssi;
  }

  @override
  Future<int> requestMtu(int mtu) async {
    _checkConnected();
    operations.add('mtu:$mtu');
    final failure = mtuError;
    if (failure != null) {
      diagnostics.record(
        'MTU request failed (${failure.failure.name})',
        level: BleLogLevel.error,
        failure: failure.failure,
      );
      throw failure;
    }
    final requested = mtu < bleMtuDefault ? bleMtuDefault : mtu;
    _negotiatedMtu = requested > maxMtu ? maxMtu : requested;
    diagnostics
      ..negotiatedMtu = _negotiatedMtu
      ..record('MTU $_negotiatedMtu (requested $mtu)');
    server.setMtu(_negotiatedMtu!);
    return _negotiatedMtu!;
  }

  @override
  Future<Uint8List> read(String characteristicUuid) async {
    _checkConnected();
    operations.add('read:$characteristicUuid');
    final failure = readError;
    if (failure != null) {
      diagnostics.record(
        'read $characteristicUuid failed (${failure.failure.name})',
        level: BleLogLevel.error,
        failure: failure.failure,
      );
      throw failure;
    }
    final characteristic = _characteristic(characteristicUuid);
    if (!characteristic.properties.contains('read')) {
      throw BleException(
        BleFailure.unsupported,
        '${characteristic.name} is not readable',
      );
    }
    _requireSecurity(characteristic);
    return server.read(characteristic.uuid);
  }

  @override
  Future<void> write(String characteristicUuid, Uint8List value) async {
    _checkConnected();
    operations.add('write:$characteristicUuid');
    final failure = writeError;
    if (failure != null) {
      diagnostics.record(
        'write $characteristicUuid failed (${failure.failure.name})',
        level: BleLogLevel.error,
        failure: failure.failure,
      );
      throw failure;
    }
    final characteristic = _characteristic(characteristicUuid);
    if (!characteristic.properties.contains('write')) {
      throw BleException(
        BleFailure.unsupported,
        '${characteristic.name} is not writable',
      );
    }
    _requireSecurity(characteristic);
    await server.write(characteristic.uuid, value);
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
    operations.add('notify:$characteristicUuid:$enabled');
    final failure = notifyError;
    if (failure != null) {
      diagnostics.record(
        'subscribe $characteristicUuid failed (${failure.failure.name})',
        level: BleLogLevel.error,
        failure: failure.failure,
      );
      throw failure;
    }
    final characteristic = _characteristic(characteristicUuid);
    if (!characteristic.properties.contains('notify')) {
      throw BleException(
        BleFailure.unsupported,
        '${characteristic.name} does not notify',
      );
    }
    _requireSecurity(characteristic);
    final key = characteristic.uuid;
    if (!enabled) {
      await _serverSubscriptions.remove(key)?.cancel();
      return;
    }
    if (_serverSubscriptions.containsKey(key)) return;
    final controller = _notificationController(key);
    _serverSubscriptions[key] = server.notificationsFor(key).listen((payload) {
      for (final chunk in _chunks(payload)) {
        controller.add(chunk);
      }
    });
  }

  /// Emits a raw characteristic value through the client's MTU chunker. The
  /// fake bridge already sends framed sync data within the MTU, so this mainly
  /// exercises live/result reassembly.
  StreamController<Uint8List> _notificationController(String uuid) {
    return _notificationControllers.putIfAbsent(
      uuid.toLowerCase(),
      () => StreamController<Uint8List>.broadcast(),
    );
  }

  List<Uint8List> _chunks(Uint8List payload) {
    final maxChunk = (_negotiatedMtu ?? bleMtuDefault) - 3;
    if (payload.length <= maxChunk) return <Uint8List>[payload];
    return <Uint8List>[
      for (var offset = 0; offset < payload.length; offset += maxChunk)
        Uint8List.sublistView(
          payload,
          offset,
          offset + maxChunk > payload.length
              ? payload.length
              : offset + maxChunk,
        ),
    ];
  }

  BleCharacteristic _characteristic(String uuid) {
    final characteristic = bleCharacteristicByUuid(uuid);
    if (characteristic == null) {
      throw BleException(
        BleFailure.unknownCharacteristic,
        'unknown characteristic $uuid',
      );
    }
    return characteristic;
  }

  void _requireSecurity(BleCharacteristic characteristic) {
    if (characteristic.security == 'open') return;
    if (_bondState != BleBondState.bonded) {
      throw BleException(
        BleFailure.notBonded,
        '${characteristic.name} requires bonding',
      );
    }
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
    _connectionController.add(state);
  }

  void _setBond(BleBondState state) {
    if (_bondState == state) return;
    _bondState = state;
    _bondController.add(state);
  }

  String? _normalizePasskey(String? value) {
    if (value == null) return null;
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stopScan();
    for (final subscription in _serverSubscriptions.values) {
      await subscription.cancel();
    }
    _serverSubscriptions.clear();
    for (final controller in _notificationControllers.values) {
      await controller.close();
    }
    _notificationControllers.clear();
    await _connectionController.close();
    await _bondController.close();
  }
}
