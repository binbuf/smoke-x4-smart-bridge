import 'dart:typed_data';

import 'package:smoke_bridge/data/ble/ble_client.dart';

/// The GATT peripheral side used by [FakeBleClient].
///
/// Production code never implements this: the real peripheral is the ESP32.
/// Keeping it separate lets the fake client model link state (scan, connect,
/// bond, MTU) independently of the fake bridge's characteristics and codecs.
abstract interface class FakeGattServer {
  /// Applies the negotiated ATT MTU so framed notifications fit.
  void setMtu(int mtu);

  /// Notification stream for one characteristic UUID.
  Stream<Uint8List> notificationsFor(String characteristicUuid);

  /// Returns the complete characteristic value (Read Blob already assembled).
  Future<Uint8List> read(String characteristicUuid);

  /// Handles one complete write. Throws [BleException] for a rejected value.
  Future<void> write(String characteristicUuid, Uint8List value);

  /// Called when the central disconnects, so in-flight streams can be dropped.
  Future<void> onDisconnected();
}
