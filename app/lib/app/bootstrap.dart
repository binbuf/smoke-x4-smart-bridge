/// App bootstrap (A1.2): guarded zone, global error hooks, ProviderScope.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'error_boundary.dart';

/// Start the app inside a guarded zone so no uncaught error — sync or
/// async — can escape without being logged and surfaced in the in-app
/// error boundary.
void bootstrap() {
  runZonedGuarded<void>(
    () {
      // Must run in the same zone as runApp.
      WidgetsFlutterBinding.ensureInitialized();
      installGlobalErrorHooks();
      runApp(const ProviderScope(child: SmokeBridgeApp()));
    },
    AppErrors.reportFatal,
  );
}
