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

/// A6.5's lane, wired for real. It engages only after every HTTP lane has
/// failed — a bridge reachable over Wi-Fi must never be demoted to a
/// degraded transport just because a bonded BLE reconnect answered first.
Future<BleTransport?> _bleLane() async {
  final client = FlutterBlueGattClient();
  try {
    final transport = BleTransport(client);
    await transport.start();
    return transport;
  } on Object {
    await client.dispose();
    return null;
  }
}
