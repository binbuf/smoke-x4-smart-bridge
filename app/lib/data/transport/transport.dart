/// N15 — the real-bridge transport barrel.
///
/// Pure Dart (no Flutter): the connection, session, sync and cache layers are
/// all in the `dart test test/data` gate. Screens never import this library;
/// they read `BridgeRepository` (the N2 seam).
library;

export 'ble_gatt.dart';
export 'ble_transport.dart';
export 'bridge_session.dart';
export 'bridge_transport.dart';
export 'connection_manager.dart';
export 'connection_supervisor.dart';
export 'http_transport.dart';
export 'mock_transport.dart';
export 'sample_cache.dart';
export 'sync_engine.dart';
