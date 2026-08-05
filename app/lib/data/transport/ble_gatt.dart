/// A6.1 — the GATT client seam (design 08 §8.1,
/// [ble-gatt](../../../../protocol/ble-gatt.md) §1–§5).
///
/// `flutter_blue_plus` is a platform plugin, so it hides behind a narrow
/// interface — exactly as `nsd` did for A7.2. Everything above this line
/// (BleTransport, the reassembler, the onboarding wizard) is then testable
/// against a Dart fake with no radio, no phone, and no board.
///
/// **The interface is deliberately smaller than the plugin.** Scan,
/// connect, bond, MTU, read, write, subscribe. Nothing about services or
/// descriptors leaks upward: characteristics are addressed by their 16-bit
/// slot in the bridge's base UUID, because that is the only vocabulary
/// [ble-gatt](../../../../protocol/ble-gatt.md) defines.
library;

import 'dart:typed_data';

/// Base UUID `7f9aXXXX-4c5b-4b0f-9a3d-1c2e3f405162` (ble-gatt §1).
String bridgeUuid(int slot) =>
    '7f9a${slot.toRadixString(16).padLeft(4, '0')}-4c5b-4b0f-9a3d-1c2e3f405162';

/// The eleven characteristics, by their `XXXX` slot.
class BridgeChar {
  static const deviceInfo = 0x0001;
  static const netStatus = 0x0002;
  static const wifiScanCtrl = 0x0003;
  static const wifiScanResult = 0x0004;
  static const wifiConfig = 0x0005;
  static const deviceControl = 0x0006;
  static const liveState = 0x0007;
  static const historyPreview = 0x0008;
  static const result = 0x0009;

  /// v1.1 — full history over BLE (ble-gatt §5.10–§5.11). Present only on a
  /// bridge whose `device_info.caps` b6 `history_full` is set; writing them
  /// on an older one gets no answer at all, which is why the flag gates
  /// them rather than a try/catch.
  static const historyCtrl = 0x000A;
  static const historyData = 0x000B;

  static const service = 0x0000;
}

/// Bluetooth SIG reserved test company ID, until a real one is assigned
/// (ble-gatt §2.2).
const bridgeCompanyId = 0xFFFF;

enum BleBondState { none, bonding, bonded, failed }

enum BleConnectionState { disconnected, connecting, connected }

/// One advertisement, before any connection exists.
class BleAdvertisement {
  const BleAdvertisement({
    required this.deviceId,
    this.name,
    this.manufacturerData,
    this.rssi = 0,
  });

  /// The platform's handle for the device (a MAC on Android).
  final String deviceId;
  final String? name;

  /// The bytes AFTER the 2-byte company id — the §2.3 status blob when the
  /// advertiser is one of ours. Null when the AD structure was absent.
  final Uint8List? manufacturerData;
  final int rssi;
}

/// ── Typed failures ───────────────────────────────────────────────────
///
/// Every one of these exists because its untyped version produces the same
/// user-visible bug report — "it just won't connect" — with no way to tell
/// the causes apart.

sealed class BleException implements Exception {
  const BleException(this.message);
  final String message;
  @override
  String toString() => '$runtimeType: $message';
}

/// The characteristic needs an encrypted (or authenticated) link and the
/// current one is not. The caller should bond, not retry.
class BleNotBondedException extends BleException {
  const BleNotBondedException([super.message = 'link security insufficient']);
}

/// We hold a bond the peer no longer does — the bridge was factory-reset
/// since we paired. The fix is to forget and re-pair, which is a different
/// action from "retry", and the app must say so (A6.4).
class BleRebondRequiredException extends BleException {
  const BleRebondRequiredException([
    super.message = 'the bridge no longer knows this phone',
  ]);
}

class BleConnectionLostException extends BleException {
  const BleConnectionLostException([super.message = 'connection dropped']);
}

class BleBondRejectedException extends BleException {
  const BleBondRejectedException([super.message = 'pairing was rejected']);
}

/// Misuse the platform would otherwise turn into platform-dependent luck
/// (the same discipline A14.1's binder applies).
class BleStateException extends BleException {
  const BleStateException(super.message);
}

/// ── The seam ─────────────────────────────────────────────────────────
abstract interface class BleGattClient {
  /// Advertisements matching the bridge's service UUID. Ends when
  /// [stopScan] is called or [timeout] elapses.
  Stream<BleAdvertisement> scan({Duration timeout});
  Future<void> stopScan();

  BleConnectionState get connectionState;
  Stream<BleConnectionState> get connectionStates;

  Future<void> connect(String deviceId);
  Future<void> disconnect();

  BleBondState get bondState;
  Stream<BleBondState> get bondStates;

  /// Drives the platform bond flow. On Android the passkey dialog is owned
  /// by the OS and appears over the app (see A6's epic flag), so this
  /// *observes* rather than prompts.
  Future<void> bond();

  /// Drops the OS-level bond for this device (A24.11). The stale-bond heal:
  /// a factory-reset bridge no longer holds our key, and Android will retry
  /// the dead key forever rather than show a new passkey dialog — the only
  /// way to pair fresh is to forget the old bond first. May throw where the
  /// platform refuses; callers fall back to sending the user to Bluetooth
  /// settings.
  Future<void> removeBond();

  /// Requests [mtu] and returns what was actually negotiated. Never
  /// throws for a refusal: 23 is a valid answer, and the whole payload
  /// design survives it (ble-gatt §4).
  Future<int> requestMtu(int mtu);
  int get mtu;

  /// A26 — the connected link's RSSI in dBm, read from the phone's own
  /// radio. This is the *phone ↔ bridge* hop and the only one the app can
  /// measure directly; nothing on the GATT contract carries it, because it
  /// is a property of the link rather than of the peer. Throws
  /// [BleStateException] when there is no connection to measure.
  Future<int> readRssi();

  Future<Uint8List> read(int slot);
  Future<void> write(int slot, Uint8List value);

  /// Raw notification chunks, exactly as they arrive. Reassembly is
  /// A6.3's job, one layer up, because the boundary is a property of the
  /// payload rather than of the link.
  Stream<Uint8List> subscribe(int slot);

  Future<void> dispose();
}
