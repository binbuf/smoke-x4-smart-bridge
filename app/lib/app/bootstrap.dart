import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

import '../data/ble/ble_client.dart';
import '../data/ble/flutter_blue_plus_ble_client.dart';
import '../data/db/app_database.dart';
import '../data/repository.dart';
import 'bridge_controller.dart';
import 'smoke_bridge_app.dart';

/// Opens persistence, creates the controller and starts the app.
///
/// [factory] and [databasePath] exist for host tests and review builds; they are
/// null in production. [bleClient] is the BLE seam: production passes a
/// platform-backed client in M2, tests pass the scripted fake.
Future<BridgeController> createBridgeController({
  DatabaseFactory? factory,
  String? databasePath,
  BridgeRepository? repository,
  BleClient? bleClient,
}) async {
  final data =
      repository ??
      SqliteBridgeRepository(
        await AppDatabase.open(factory: factory, databasePath: databasePath),
      );
  final controller = BridgeController(
    repository: data,
    bleClient: bleClient ?? FlutterBluePlusBleClient(),
    sampleDao: data is SqliteBridgeRepository ? data.dao : null,
  );
  await controller.initialize();
  // The recent History store fills from the durable archive's accepted batches.
  // A launch with no rows shows the empty state, never a fixture preview.
  controller.historyHasData = controller.phoneRecords > 0;
  return controller;
}

/// Production entrypoint.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await createBridgeController();
  // Load the saved Bridge and the last-known archive before the first frame, so
  // a returning user lands in the shell (never Setup) and offline values are
  // real stored readings. The bounded scan then runs in the foreground.
  await controller.prepareLaunch();
  runApp(SmokeBridgeApp(controller: controller));
  if (controller.hasSavedBridge) {
    unawaited(controller.connectSavedBridge());
  }
}
