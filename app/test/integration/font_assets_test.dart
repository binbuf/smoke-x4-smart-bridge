/// N0.5 — the three fonts are bundled assets and their OFL licences are both
/// shipped and registered with `LicenseRegistry`. This is what fails if a font
/// or its licence stops shipping.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/font_licences.dart';

void main() {
  const fonts = <String, String>{
    'Archivo': 'assets/fonts/Archivo[wdth,wght].ttf',
    'Inter': 'assets/fonts/Inter[opsz,wght].ttf',
    'JetBrainsMono': 'assets/fonts/JetBrainsMono[wght].ttf',
  };
  const licences = <String>[
    'assets/fonts/OFL-Archivo.txt',
    'assets/fonts/OFL-Inter.txt',
    'assets/fonts/OFL-JetBrainsMono.txt',
  ];

  test('every bundled font and licence is on disk', () {
    for (final path in <String>[...fonts.values, ...licences]) {
      expect(File(path).existsSync(), isTrue, reason: 'missing asset $path');
    }
  });

  testWidgets('the licences load from the asset bundle and are registered', (
    tester,
  ) async {
    registerFontLicences();

    for (final path in licences) {
      final text = await rootBundle.loadString(path);
      expect(text, contains('SIL OPEN FONT LICENSE'));
    }

    final packages = (await LicenseRegistry.licenses.toList())
        .expand((entry) => entry.packages)
        .toSet();
    expect(packages, containsAll(fonts.keys));
  });
}
