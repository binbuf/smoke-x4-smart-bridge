/// N3 exit gate — the component gallery in three theme combinations × both
/// densities.
///
/// The three combinations are dark, light and the daylight contrast profile
/// (layered on the dark palette, as `styles.css` does). `settle: false` because
/// the gallery deliberately renders a busy spinner and a loading state; the
/// description records structure and copy, not pixels.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';

import '../support/load_fonts.dart';
import 'golden.dart';

void main() {
  setUpAll(loadAppFonts);

  final combos = <String, (Brightness, SmokeProfile)>{
    'dark': (Brightness.dark, SmokeProfile.standard),
    'light': (Brightness.light, SmokeProfile.standard),
    'daylight': (Brightness.dark, SmokeProfile.daylight),
  };
  final densities = <String, SmokeDensity>{
    'compact': SmokeDensity.compact,
    'comfortable': SmokeDensity.comfortable,
  };

  for (final combo in combos.entries) {
    for (final density in densities.entries) {
      final name = 'design_gallery_${combo.key}_${density.key}';
      testWidgets('$name matches its committed golden', (tester) async {
        final (brightness, profile) = combo.value;
        await pumpForGolden(
          tester,
          MaterialApp(
            theme: SmokeThemeData.build(
              brightness: brightness,
              profile: profile,
              density: density.value,
            ),
            home: const DesignGallery(),
          ),
          settle: false,
        );
        expectGolden(tester, name);
      });
    }
  }
}
