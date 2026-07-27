/// A minimal [AppEnv] for tests that need one installed rather than mocked.
///
/// `AppEnv.instance` is how the shell, the tabs and the settings pages reach
/// the database, the prefs and the export sink. Most widget tests get away
/// with no environment at all (every screen has a no-env branch, by design);
/// the ones that exercise *persistence* cannot, so they build one here.
///
/// Everything is in memory: `NativeDatabase.memory()`, [InMemoryBridgePrefs],
/// [InMemoryExportSink]. No plugin, no socket, no radio.
library;

import 'package:drift/native.dart';
import 'package:smoke_bridge/app/app_env.dart';
import 'package:smoke_bridge/data/local/database.dart';
import 'package:smoke_bridge/data/prefs/bridge_prefs.dart';
import 'package:smoke_bridge/features/sessions/export.dart';

AppEnv fakeEnv({BridgePrefs? prefs, AppDatabase? db}) => AppEnv(
  db: db ?? AppDatabase(NativeDatabase.memory()),
  prefs: prefs ?? InMemoryBridgePrefs(),
  exportSink: InMemoryExportSink(),
);
