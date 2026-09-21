/// N0.7 — app bootstrap: bindings, bundled-font licences, and the
/// `ProviderScope` every later provider hangs off.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'font_licences.dart';
import 'smoke_app.dart';

void bootstrap() {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicences();
  runApp(const ProviderScope(child: SmokeApp()));
}
