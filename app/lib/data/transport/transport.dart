/// Transport layer: `BridgeTransport` plus the Http/Ble/Mock implementations.
///
/// The UI never knows how it is talking to the bridge (design 08 §8.1).
/// The interface and implementations land with tasks A3.1–A3.3; the BLE
/// seam and transport with A6 (M3).
library;

export 'ble_gatt.dart';
export 'ble_transport.dart';
export 'bridge_transport.dart';
export 'connection_manager.dart';
export 'discovery.dart';
export 'http_transport.dart';
export 'mock_transport.dart';
