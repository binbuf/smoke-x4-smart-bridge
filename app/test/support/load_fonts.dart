/// Loads the app's bundled fonts into the test renderer so widget tests measure
/// the metrics that actually ship (design 14 §14.5). Without this, text falls
/// back to a wider test font and a layout that fits on-device reports a false
/// overflow. Call [loadAppFonts] in `setUpAll`.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

bool _loaded = false;

Future<void> loadAppFonts() async {
  if (_loaded) {
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  const fonts = <String, String>{
    'Archivo': 'assets/fonts/Archivo[wdth,wght].ttf',
    'Inter': 'assets/fonts/Inter[opsz,wght].ttf',
    'JetBrainsMono': 'assets/fonts/JetBrainsMono[wght].ttf',
  };
  for (final entry in fonts.entries) {
    final bytes = await File(entry.value).readAsBytes();
    final loader = FontLoader(entry.key)
      ..addFont(Future.value(bytes.buffer.asByteData()));
    await loader.load();
  }
  _loaded = true;
}
