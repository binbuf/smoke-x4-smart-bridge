import 'dart:typed_data';

/// The single app-side BLE seam.
///
/// Production wraps `flutter_blue_plus`; tests use the scripted fake under
/// `test/support/`. Everything above this interface (setup, link procedures,
/// sync) works with byte payloads and never imports a radio plugin.
abstract interface class BleClient {
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

  /// The negotiated ATT MTU, or `null` before connection/negotiation.
  int? get negotiatedMtu;

  /// Requests [mtu] and returns the negotiated value. A controller must treat a
  /// small result as a slow link, not an error.
  Future<int> requestMtu(int mtu);

  /// Reads the complete characteristic value, reassembling Read Blob responses
  /// when needed.
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

  /// Enables or disables notifications for [characteristicUuid].
  Future<void> setNotify(String characteristicUuid, {required bool enabled});

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
}

class BleException implements Exception {
  const BleException(this.failure, [this.message = '']);

  final BleFailure failure;
  final String message;

  @override
  String toString() {
    final suffix = message.isEmpty ? '' : ': $message';
    return 'BleException(${failure.name})$suffix';
  }
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
  /// optional, so the name prefix is enough here; the production scan layer may
  /// additionally match `bleServiceUuid` from the generated contract.
  bool get isSmokeBridge =>
      name.toUpperCase().startsWith(_smokeBridgeLocalNamePrefix.toUpperCase());

  @override
  String toString() => 'BleDevice($id, $name, rssi=$rssi)';
}

/// Must match `bleLocalNamePrefix` in the generated contract; a test asserts
/// the two stay equal.
const String _smokeBridgeLocalNamePrefix = 'SmokeX4-';

/// Convenience for callers that only need the bonded/not-bonded answer.
extension BleBondStateX on BleBondState {
  bool get canReadEncrypted => isBonded;
}
