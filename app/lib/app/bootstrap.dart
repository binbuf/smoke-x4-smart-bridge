/// App bootstrap (A1.2, extended by A9.5): guarded zone, global error
/// hooks, the runtime environment, ProviderScope.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/local/open_database.dart';
import '../data/prefs/bridge_prefs.dart';
import '../data/transport/ble_gatt_fbp.dart';
import '../data/transport/ble_transport.dart';
import '../data/transport/nsd_discovery.dart';
import '../features/sessions/export.dart';
import '../platform/notifications_plugin.dart';
import 'app.dart';
import 'app_env.dart';
import 'error_boundary.dart';

/// Start the app inside a guarded zone so no uncaught error — sync or
/// async — can escape without being logged and surfaced in the in-app
/// error boundary.
void bootstrap() {
  runZonedGuarded<void>(() async {
    // Must run in the same zone as runApp.
    WidgetsFlutterBinding.ensureInitialized();
    installGlobalErrorHooks();

    // The three things that must exist before a route can build: the
    // cache, the remembered bridge (A7.5), and somewhere to write an
    // export. Discovery and the BLE lane belong to the race, not to a
    // screen.
    AppEnv.instance = AppEnv(
      db: await openAppDatabase(),
      prefs: await SharedPrefsBridgePrefs.load(),
      exportSink: FileExportSink(await getApplicationDocumentsDirectory()),
      discovery: NsdDiscoverySource(),
      bleAttempt: _bleLane,
      // A13. Both are seams: everything that DECIDES anything about a
      // notification is pure and host-tested, and these two are the
      // plugin plumbing the bench proves.
      notifications: PluginNotificationSink(),
      foregroundService: PluginForegroundServiceHost(),
    );

    runApp(const ProviderScope(child: SmokeBridgeApp()));
  }, AppErrors.reportFatal);
}

/// A6.5's lane, wired for real (A25: it now *connects*).
///
/// It used to build a client, call `transport.start()` and hope: but `start()`
/// only SUBSCRIBES to characteristics, so with nothing connected it threw on
/// the first subscribe and the lane returned null every single time. That is
/// why the BLE lane never engaged on the bench (the long-open A6.7 defect) —
/// the lane had no device to dial, because the bonded address was never
/// remembered. Setup now records it, and this connects to it.
Future<BleTransport?> _bleLane() async {
  final deviceId = AppEnv.instance?.prefs.lastBleDeviceId;
  if (deviceId == null || deviceId.isEmpty) {
    return null; // never bonded on this phone — the scan belongs to setup
  }
  final client = FlutterBlueGattClient();
  try {
    await client.connect(deviceId);
    final transport = BleTransport(client);
    await transport.start();
    return transport;
  } on Object {
    await client.dispose();
    return null;
  }
}
