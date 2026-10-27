import 'dart:convert';
import 'dart:typed_data';

import 'ble_client.dart';

/// The contract's `info` characteristic. Open, so setup can read identity and
/// `bonds_free` before asking Android to bond.
const String bleInfoCharacteristicUuid = '7f9b0001-4c5b-4b0f-9a3d-1c2e3f405162';

/// Protocol major this app understands. A different value means the Bridge
/// speaks a newer contract and the app must be updated (06 §6.8).
const int bridgeProtocolMajor = 1;

/// The subset of `info` setup needs. The full generated codec lands with the
/// packaged codec work; the field offsets here are pinned by
/// `test/setup_codec_test.dart` against `protocol/gen/records.dart`.
class BridgeInfo {
  const BridgeInfo({
    required this.protoMajor,
    required this.protoMinor,
    required this.deviceId,
    required this.firmware,
    required this.model,
    required this.bondsFree,
  });

  final int protoMajor;
  final int protoMinor;
  final String deviceId;
  final String firmware;
  final String model;
  final int bondsFree;

  bool get isCompatible => protoMajor == bridgeProtocolMajor;

  static BridgeInfo decode(Uint8List bytes) {
    if (bytes.length < 32) {
      throw const FormatException('truncated info');
    }
    return BridgeInfo(
      protoMajor: bytes[1],
      protoMinor: bytes[2],
      deviceId: _readString(bytes, 6, 4),
      firmware: _readString(bytes, 10, 12),
      model: _readString(bytes, 22, 8),
      bondsFree: bytes[30],
    );
  }

  static String _readString(Uint8List bytes, int offset, int length) {
    final end = offset + length;
    var stop = offset;
    while (stop < end && bytes[stop] != 0) {
      stop++;
    }
    return utf8.decode(bytes.sublist(offset, stop), allowMalformed: true);
  }
}

/// The scan-response fields setup previews in the results list. The
/// advertisement is optional decoration: a missing or malformed payload leaves
/// the device selectable with no preview.
class BridgeAdvertisement {
  const BridgeAdvertisement({
    required this.pitTempF10,
    required this.batteryPercent,
  });

  final int pitTempF10;
  final int batteryPercent;

  bool get hasReading => pitTempF10 != 0;

  /// `P4 225°F · 87%`, the approved preview shape.
  String get preview {
    final temp = pitTempF10 == 0 ? '—' : '${(pitTempF10 / 10).round()}°F';
    return 'P4 $temp · $batteryPercent%';
  }

  static BridgeAdvertisement? decode(BleDevice device) {
    final data = device.manufacturerData;
    if (data == null || data.length < 11) return null;
    // Two-byte company ID followed by the 9-byte adv_status payload.
    const offset = 2;
    final view = ByteData.sublistView(data);
    final pitTempF10 = view.getInt16(offset + 2, Endian.little);
    return BridgeAdvertisement(
      pitTempF10: pitTempF10,
      batteryPercent: data[offset + 4],
    );
  }
}

/// Signal words used only in scan results. Live keeps its own four-bar label.
String scanSignalWord(int? rssi) {
  if (rssi == null) return 'Weak';
  if (rssi >= -65) return 'Strong';
  if (rssi >= -75) return 'Good';
  return 'Weak';
}

/// The detail line for one scan row: preview when advertised, signal word and
/// dBm always.
String scanResultDetail(BleDevice device) {
  final pieces = <String>[];
  final advertisement = BridgeAdvertisement.decode(device);
  if (advertisement != null) pieces.add(advertisement.preview);
  pieces.add(scanSignalWord(device.rssi));
  pieces.add(device.rssi == null ? '— dBm' : '${device.rssi} dBm');
  return pieces.join(' · ');
}

/// A row in the setup results list. A SmokeX4-named advertisement without the
/// current contract service is shown as a protocol-mismatch row rather than
/// silently dropped (12 §12.3 C1).
class ScannedBridge {
  const ScannedBridge({required this.device, required this.requiresNewerApp});

  final BleDevice device;
  final bool requiresNewerApp;

  String get name => device.name;
  String get id => device.id;

  String get detail =>
      requiresNewerApp ? 'Requires a newer app' : scanResultDetail(device);
}

/// Turns a raw scan result into a display row, or `null` when it is not a
/// SmokeX4 bridge at all. Legacy `7f9a…` advertisements are kept so the user
/// sees why they cannot connect.
ScannedBridge? scannedBridgeFor(BleDevice device) {
  if (device.isCompatibleBridge) {
    return ScannedBridge(device: device, requiresNewerApp: false);
  }
  if (device.isSmokeBridge) {
    return ScannedBridge(device: device, requiresNewerApp: true);
  }
  return null;
}
