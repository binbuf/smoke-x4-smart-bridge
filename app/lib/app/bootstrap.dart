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
  );
  await controller.initialize();
  // V0 has no durable archive yet: the recent History store fills from the
  // link's first sync. Until then History must show its empty state, never a
  // fixture preview.
  controller.historyHasData = controller.phoneRecords > 0;
  return controller;
}

/// Production entrypoint.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await createBridgeController();
  // Bridge identity persistence lands with the archive tasks. Until then a
  // launch has no saved Bridge, so start on the approved setup route instead
  // of showing simulated Live data.
  controller.beginSetup();
  runApp(SmokeBridgeApp(controller: controller));
}
