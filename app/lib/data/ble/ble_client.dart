import 'dart:typed_data';

/// The single app-side BLE seam.
///
/// Production wraps `flutter_blue_plus`; tests use the scripted fake under
/// `test/support/`. Everything above this interface (setup, link procedures,
/// sync) works with byte payloads and never imports a radio plugin.
abstract interface class BleClient {
  /// Checks hardware support, the Android adapter and the runtime permission.
  ///
  /// The result is a named [BleAppState], never a plugin exception.
  Future<BlePlatformStatus> platformStatus();

  /// Adapter state changes while the app is running.
  ///
  /// The app is on Live when the user turns phone Bluetooth off; without this
  /// stream the GATT link can look `Connected` until the next watchdog read.
  /// Emits only the states that affect the link: [BleAppState.ready],
  /// [BleAppState.bluetoothOff], [BleAppState.permissionBlocked],
  /// [BleAppState.permissionNeeded] and [BleAppState.unsupportedPhone].
  Stream<BleAppState> get platformStates;

  /// Requests the permissions needed for this Android version and returns the
  /// resulting state. Android 12+ uses `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`;
  /// Android 11 and below uses location.
  Future<BlePermissionState> requestPermissions();

  /// Starts a scan and emits each advertisement once. The stream closes when
  /// the scan stops, either by [stopScan] or after [timeout].
  Stream<BleDevice> scan({Duration timeout = const Duration(seconds: 10)});

  /// Stops an in-flight scan. Safe to call when no scan is running.
  Future<void> stopScan();

  BleConnectionState get connectionState;
  Stream<BleConnectionState> get connectionStates;

  /// The currently connected device, or `null` when disconnected.
  BleDevice? get connectedDevice;

  Future<void> connect(
    BleDevice device, {
    Duration timeout = const Duration(seconds: 15),
  });

  Future<void> disconnect();

  BleBondState get bondState;
  Stream<BleBondState> get bondStates;

  /// Starts LE Secure Connections pairing. Passkey entry normally happens in an
  /// OS dialog; [passkey] exists so tests and scripted flows can supply it.
  Future<BleBondState> bond({String? passkey});

  /// Removes the OS bond, for the stale-bond recovery path.
  Future<void> removeBond();

  /// The negotiated ATT MTU, or `null` before connection/negotiation.
  int? get negotiatedMtu;

  /// Reads the current RSSI of the connected phone→Bridge link.
  Future<int> readRssi();

  /// Requests [mtu] and returns the negotiated value. A controller must treat a
  /// small result as a slow link, not an error.
  Future<int> requestMtu(int mtu);

  /// Reads the complete characteristic value, including the long-read fallback
  /// for `info` when the negotiated MTU cannot carry it in one ATT response.
  Future<Uint8List> read(String characteristicUuid);

  /// Writes the complete characteristic value, chunking queued writes when the
  /// value is larger than the negotiated MTU.
  Future<void> write(String characteristicUuid, Uint8List value);

  /// Notification payloads for [characteristicUuid], exactly as they arrive on
  /// the wire (already split at the negotiated MTU).
  ///
  /// Call [setNotify] to enable the CCCD first; the stream yields nothing until
  /// then.
  Stream<Uint8List> notifications(String characteristicUuid);

  /// Enables or disables notifications for [characteristicUuid]. The platform
  /// writes the CCCD at the characteristic's security level.
  Future<void> setNotify(String characteristicUuid, {required bool enabled});

  /// Debug-only diagnostics: phone model, Android version, negotiated MTU and
  /// the scan/connect/bond failure log. Never rendered as user copy.
  BleDiagnostics get diagnostics;

  /// Releases the platform resources. Idempotent.
  Future<void> dispose();
}

enum BleConnectionState { disconnected, connecting, connected, disconnecting }

/// Bonding covers more than a boolean so the setup flow can name a failed
/// attempt. `bonded` persists across a disconnect, like a platform bond.
enum BleBondState {
  none,
  bonding,
  bonded,
  wrongPasskey,
  timeout,
  bondStoreFull,
  failed;

  bool get isBonded => this == BleBondState.bonded;
}

/// Named failures the UI can branch on instead of matching plugin strings.
enum BleFailure {
  notConnected,
  notBonded,
  unknownCharacteristic,
  unsupported,
  invalidValue,
  notSubscribed,
  timeout,
  failed,
  permissionDenied,
  permissionBlocked,
  bluetoothOff,
  unsupportedPhone,
  scanFailed,
  noResults,
  wrongPasskey,
  promptTimeout,
  staleBond,
  bondStoreFull,
  connectionFailed,
  gattError,
}

/// The named states in 06 §6.8 / 13 §13.4. The client returns these enums; the
/// setup screen owns the approved copy and buttons.
enum BleAppState {
  ready,
  bluetoothOff,
  permissionNeeded,
  permissionBlocked,
  unsupportedPhone,
  noResults,
  pairingFailed,
  promptTimeout,
  staleBond,
  phoneListFull,
  connectionFailed,
  gattError,
  timeout,
}

/// The approved next action for a named state. Copy stays in the UI layer.
enum BleRecoveryAction {
  none,
  openBluetoothSettings,
  grantPermission,
  openAppSettings,
  retry,
  forgetAndRepair,
}

extension BleFailureAppState on BleFailure {
  BleAppState get appState {
    switch (this) {
      case BleFailure.permissionDenied:
        return BleAppState.permissionNeeded;
      case BleFailure.permissionBlocked:
        return BleAppState.permissionBlocked;
      case BleFailure.bluetoothOff:
        return BleAppState.bluetoothOff;
      case BleFailure.unsupportedPhone:
        return BleAppState.unsupportedPhone;
      case BleFailure.scanFailed:
      case BleFailure.noResults:
        return BleAppState.noResults;
      case BleFailure.wrongPasskey:
        return BleAppState.pairingFailed;
      case BleFailure.promptTimeout:
        return BleAppState.promptTimeout;
      case BleFailure.staleBond:
        return BleAppState.staleBond;
      case BleFailure.bondStoreFull:
        return BleAppState.phoneListFull;
      case BleFailure.timeout:
        return BleAppState.timeout;
      case BleFailure.notConnected:
      case BleFailure.connectionFailed:
      case BleFailure.failed:
        return BleAppState.connectionFailed;
      case BleFailure.notBonded:
        return BleAppState.pairingFailed;
      case BleFailure.unknownCharacteristic:
      case BleFailure.unsupported:
      case BleFailure.invalidValue:
      case BleFailure.notSubscribed:
      case BleFailure.gattError:
        return BleAppState.gattError;
    }
  }
}

extension BleAppStateRecovery on BleAppState {
  BleRecoveryAction get recoveryAction {
    switch (this) {
      case BleAppState.ready:
        return BleRecoveryAction.none;
      case BleAppState.bluetoothOff:
        return BleRecoveryAction.openBluetoothSettings;
      case BleAppState.permissionNeeded:
        return BleRecoveryAction.grantPermission;
      case BleAppState.permissionBlocked:
        return BleRecoveryAction.openAppSettings;
      case BleAppState.unsupportedPhone:
        return BleRecoveryAction.none;
      case BleAppState.noResults:
      case BleAppState.pairingFailed:
      case BleAppState.promptTimeout:
      case BleAppState.phoneListFull:
      case BleAppState.connectionFailed:
      case BleAppState.gattError:
      case BleAppState.timeout:
        return BleRecoveryAction.retry;
      case BleAppState.staleBond:
        return BleRecoveryAction.forgetAndRepair;
    }
  }
}

class BleException implements Exception {
  const BleException(this.failure, [this.message = '']);

  final BleFailure failure;

  /// Debug-only detail. Screens must render [failure]'s named state, never this
  /// string.
  final String message;

  BleAppState get appState => failure.appState;

  BleRecoveryAction get recoveryAction => appState.recoveryAction;

  @override
  String toString() {
    final suffix = message.isEmpty ? '' : ': $message';
    return 'BleException(${failure.name})$suffix';
  }
}

/// Permission state as the app needs to explain it, not the plugin's enum.
enum BlePermissionState { notDetermined, granted, denied, permanentlyDenied }

/// Which runtime permission Android requires for this version.
enum BlePermissionKind { nearbyDevices, location }

/// A complete platform snapshot: hardware, adapter and permission.
class BlePlatformStatus {
  const BlePlatformStatus({
    required this.supported,
    required this.bluetoothOn,
    required this.permission,
    required this.permissionKind,
    this.androidSdk,
  });

  final bool supported;
  final bool bluetoothOn;
  final BlePermissionState permission;
  final BlePermissionKind permissionKind;
  final int? androidSdk;

  BleAppState get state {
    if (!supported) return BleAppState.unsupportedPhone;
    if (!bluetoothOn) return BleAppState.bluetoothOff;
    switch (permission) {
      case BlePermissionState.granted:
        return BleAppState.ready;
      case BlePermissionState.notDetermined:
      case BlePermissionState.denied:
        return BleAppState.permissionNeeded;
      case BlePermissionState.permanentlyDenied:
        return BleAppState.permissionBlocked;
    }
  }

  bool get canScan => state == BleAppState.ready;

  /// Android 12+ must not request location. Android 11 and below needs it for
  /// scanning, which the primer explains.
  bool get requiresLocationPermission =>
      permissionKind == BlePermissionKind.location;
}

/// One advertisement seen during a scan.
///
/// [manufacturerData] is the raw manufacturer-specific data from the scan
/// response, including the two-byte company ID when present. Callers decode it
/// with the generated `AdvStatus` codec; the advertisement is optional
/// decoration, so scan must work when it is absent or malformed.
class BleDevice {
  const BleDevice({
    required this.id,
    required this.name,
    this.rssi,
    this.manufacturerData,
    this.serviceUuids = const <String>[],
  });

  final String id;
  final String name;
  final int? rssi;
  final Uint8List? manufacturerData;
  final List<String> serviceUuids;

  /// Whether this looks like a bridge advertisement. Scan responses are
  /// optional, so the name prefix is enough here; compatibility checks must
  /// also require [hasContractService].
  bool get isSmokeBridge =>
      name.toUpperCase().startsWith(bleClientLocalNamePrefix.toUpperCase());

  /// The bridge's own service UUID. A legacy `7f9a…` device is not compatible.
  bool get hasContractService => serviceUuids.any(
    (uuid) => uuid.toLowerCase() == bleContractServiceUuid.toLowerCase(),
  );

  /// A device the app may select and connect to. Both the contract service UUID
  /// and the local-name prefix are required; the service UUID alone keeps a
  /// legacy device from being mistaken for a compatible one.
  bool get isCompatibleBridge => hasContractService && isSmokeBridge;

  @override
  String toString() => 'BleDevice($id, $name, rssi=$rssi)';
}

/// Must match `bleServiceUuid` in the generated contract; a test asserts this.
const String bleContractServiceUuid = '7f9b0000-4c5b-4b0f-9a3d-1c2e3f405162';

/// Must match `bleClientLocalNamePrefix` in the generated contract.
const String bleClientLocalNamePrefix = 'SmokeX4-';

/// Contract request; every fixed payload works at the default MTU too.
const int bleRequestedMtu = 247;

/// ATT default MTU before negotiation.
const int bleDefaultMtu = 23;

/// Scanning is foreground-only and stops after this window.
const Duration bleScanTimeout = Duration(seconds: 10);

/// Picks the remembered bridge by device ID first, then by name. Returns `null`
/// when the remembered bridge did not advertise; it never falls back to the
/// first arbitrary result.
BleDevice? selectPreferredBridge(
  Iterable<BleDevice> devices, {
  String? rememberedDeviceId,
  String? rememberedName,
}) {
  final candidates = devices.where((device) => device.isCompatibleBridge);
  final id = rememberedDeviceId?.trim();
  if (id != null && id.isNotEmpty) {
    for (final device in candidates) {
      if (device.id.toLowerCase() == id.toLowerCase()) return device;
    }
  }
  final name = rememberedName?.trim();
  if (name != null && name.isNotEmpty) {
    for (final device in candidates) {
      if (device.name.toLowerCase() == name.toLowerCase()) return device;
    }
  }
  return null;
}

/// Display order: remembered bridge first, then the rest in scan order.
List<BleDevice> orderBridgesForDisplay(
  Iterable<BleDevice> devices, {
  String? rememberedDeviceId,
  String? rememberedName,
}) {
  final all = devices.where((device) => device.isCompatibleBridge).toList();
  final preferred = selectPreferredBridge(
    all,
    rememberedDeviceId: rememberedDeviceId,
    rememberedName: rememberedName,
  );
  if (preferred == null) return all;
  return <BleDevice>[
    preferred,
    ...all.where((device) => device.id != preferred.id),
  ];
}

/// Convenience for callers that only need the bonded/not-bonded answer.
extension BleBondStateX on BleBondState {
  bool get canReadEncrypted => isBonded;
}

enum BleLogLevel { info, warning, error }

class BleLogEntry {
  const BleLogEntry({
    required this.time,
    required this.level,
    required this.message,
    this.failure,
  });

  final DateTime time;
  final BleLogLevel level;
  final String message;
  final BleFailure? failure;
}

/// Debug-only BLE diagnostics.
///
/// Kept in the client so scan/connect/bond failures and the negotiated MTU stay
/// available to Bridge details diagnostics. The log is bounded; it is never
/// rendered as user copy and never contains raw platform error strings in UI
/// state.
class BleDiagnostics {
  BleDiagnostics({
    this.phoneModel = 'unknown',
    this.androidVersion = 'unknown',
    this.negotiatedMtu,
    this.maxEntries = 200,
  });

  String phoneModel;
  String androidVersion;
  int? negotiatedMtu;
  final int maxEntries;
  final List<BleLogEntry> _entries = <BleLogEntry>[];

  List<BleLogEntry> get entries => List<BleLogEntry>.unmodifiable(_entries);

  void record(
    String message, {
    BleLogLevel level = BleLogLevel.info,
    BleFailure? failure,
  }) {
    _entries.add(
      BleLogEntry(
        time: DateTime.now(),
        level: level,
        message: message,
        failure: failure,
      ),
    );
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  void clear() {
    _entries.clear();
    negotiatedMtu = null;
  }

  /// One-line summary for the diagnostics screen; contains no user copy.
  String get summary =>
      '${phoneModel.isEmpty ? 'unknown' : phoneModel} · '
      '${androidVersion.isEmpty ? 'unknown' : androidVersion} · '
      'MTU ${negotiatedMtu ?? '—'} · ${_entries.length} events';
}

/// A blocked platform state as the typed failure the client throws when an
/// operation is attempted.
BleException exceptionForBleAppState(BleAppState state) {
  switch (state) {
    case BleAppState.ready:
      return const BleException(BleFailure.failed, 'platform is ready');
    case BleAppState.bluetoothOff:
      return const BleException(BleFailure.bluetoothOff, 'Bluetooth is off');
    case BleAppState.permissionNeeded:
      return const BleException(
        BleFailure.permissionDenied,
        'permission is required',
      );
    case BleAppState.permissionBlocked:
      return const BleException(
        BleFailure.permissionBlocked,
        'permission is blocked',
      );
    case BleAppState.unsupportedPhone:
      return const BleException(
        BleFailure.unsupportedPhone,
        'BLE is unsupported',
      );
    case BleAppState.noResults:
      return const BleException(BleFailure.noResults, 'no bridge found');
    case BleAppState.pairingFailed:
      return const BleException(BleFailure.wrongPasskey, 'pairing failed');
    case BleAppState.promptTimeout:
      return const BleException(BleFailure.promptTimeout, 'prompt timed out');
    case BleAppState.staleBond:
      return const BleException(BleFailure.staleBond, 'bond is stale');
    case BleAppState.phoneListFull:
      return const BleException(BleFailure.bondStoreFull, 'bond store is full');
    case BleAppState.connectionFailed:
      return const BleException(
        BleFailure.connectionFailed,
        'connection failed',
      );
    case BleAppState.gattError:
      return const BleException(BleFailure.gattError, 'GATT operation failed');
    case BleAppState.timeout:
      return const BleException(BleFailure.timeout, 'operation timed out');
  }
}
