/// Opening the real database (A4.1, design 08 §8.5).
///
/// Split out from `database.dart` so the schema and the DAOs stay
/// importable by host tests without dragging in a platform plugin — the
/// suite runs on `NativeDatabase.memory()` and never touches this file.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';

/// The on-device database, in the app's documents directory.
///
/// `NativeDatabase.createInBackground` puts every query on a background
/// isolate, which is what makes A4.2's promise true: 2,880 rows lands in
/// tens of milliseconds and never touches the UI frame budget.
Future<AppDatabase> openAppDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'smoke_bridge.sqlite'));
  return AppDatabase(NativeDatabase.createInBackground(file));
}
