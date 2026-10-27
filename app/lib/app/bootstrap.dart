import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db/app_database.dart';
import '../data/repository.dart';
import 'bridge_controller.dart';
import 'smoke_bridge_app.dart';

/// Opens persistence, creates the controller and starts the app.
///
/// [factory] and [databasePath] exist for host tests and review builds; they are
/// null in production.
Future<BridgeController> createBridgeController({
  DatabaseFactory? factory,
  String? databasePath,
  BridgeRepository? repository,
}) async {
  final data =
      repository ??
      SqliteBridgeRepository(
        await AppDatabase.open(factory: factory, databasePath: databasePath),
      );
  final controller = BridgeController(repository: data);
  await controller.initialize();
  return controller;
}

/// Production entrypoint.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await createBridgeController();
  runApp(SmokeBridgeApp(controller: controller));
}
