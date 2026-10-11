/// N15.9 — opening the real on-device database.
///
/// Split out from `app_database.dart` so the schema and [DriftSampleCache] stay
/// importable by host tests (which run on `NativeDatabase.memory()`) without
/// dragging in `path_provider`.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

/// The on-device database in the app's documents directory.
///
/// `createInBackground` puts every query on its own isolate, so a 24-hour
/// cook's 2,880 rows land off the UI thread (N15.9).
Future<AppDatabase> openAppDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'smoke_bridge.sqlite'));
  return AppDatabase(NativeDatabase.createInBackground(file));
}
