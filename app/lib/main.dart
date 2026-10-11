import 'package:flutter/material.dart';

import 'app/smoke_bridge_app.dart';
import 'data/local/drift_sample_cache.dart';
import 'data/local/open_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openAppDatabase();
  runApp(SmokeBridgeApp(cache: DriftSampleCache(db)));
}
