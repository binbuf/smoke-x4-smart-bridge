/// N0 foundations theme. The full token set (`SmokeTokens`, typography,
/// palettes) is N3; this is only enough to render the shell themed over the
/// three bundled fonts.
///
/// Surface and ink values come from `newui/NOTES.md` §8 and `styles.css`.
library;

import 'package:flutter/material.dart';

abstract final class SmokeTheme {
  static const Color background = Color(0xFF07090E);
  static const Color surface = Color(0xFF0F131D);
  static const Color ember = Color(0xFFD95926);
  static const Color textHi = Color(0xFFF8FAFC);
  static const Color textBody = Color(0xFFCBD5E1);

  static const String displayFont = 'Archivo';
  static const String textFont = 'Inter';
  static const String monoFont = 'JetBrainsMono';

  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    fontFamily: textFont,
    colorScheme: const ColorScheme.dark(
      primary: ember,
      surface: surface,
      onSurface: textHi,
    ),
    textTheme: const TextTheme(
      displaySmall: TextStyle(fontFamily: displayFont, color: textHi),
      bodyMedium: TextStyle(fontFamily: textFont, color: textBody),
    ),
  );
}
