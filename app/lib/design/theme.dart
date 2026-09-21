/// N3.1–N3.8 — the theme entry point.
///
/// [SmokeThemeData] turns the [SmokeTokens] palette + [SmokeMotion] tokens into
/// a `ThemeData` for a brightness, contrast profile and density. The three
/// theme axes (theme mode, contrast profile, density) are applied at the app
/// root; screens read the resolved values from `Theme.of(context)` and never
/// carry their own.
///
/// [SmokeTheme] keeps the N0 font and dark-palette constants that the shell and
/// the dev panel already reference, so N3 is additive rather than a rename.
library;

import 'package:flutter/material.dart';

import 'motion.dart';
import 'text.dart';
import 'tokens.dart';

export 'motion.dart';
export 'text.dart';
export 'tokens.dart';

/// Builds the app's `ThemeData` from the token set.
abstract final class SmokeThemeData {
  const SmokeThemeData._();

  /// The dark theme (the default).
  static ThemeData dark({
    SmokeProfile profile = SmokeProfile.standard,
    SmokeDensity density = SmokeDensity.compact,
    bool reducedMotion = false,
  }) => build(
    brightness: Brightness.dark,
    profile: profile,
    density: density,
    reducedMotion: reducedMotion,
  );

  /// The light theme.
  static ThemeData light({
    SmokeProfile profile = SmokeProfile.standard,
    SmokeDensity density = SmokeDensity.compact,
    bool reducedMotion = false,
  }) => build(
    brightness: Brightness.light,
    profile: profile,
    density: density,
    reducedMotion: reducedMotion,
  );

  /// The general builder.
  static ThemeData build({
    required Brightness brightness,
    SmokeProfile profile = SmokeProfile.standard,
    SmokeDensity density = SmokeDensity.compact,
    bool reducedMotion = false,
  }) {
    final tokens = brightness == Brightness.light
        ? SmokeTokens.light(profile: profile, density: density)
        : SmokeTokens.dark(profile: profile, density: density);
    final motion = SmokeMotion(reducedMotion: reducedMotion);
    final scheme = brightness == Brightness.light
        ? ColorScheme.light(
            primary: tokens.pit,
            onPrimary: const Color(0xFF0A0400),
            secondary: tokens.info,
            onSecondary: tokens.textHi,
            surface: tokens.surface,
            onSurface: tokens.textHi,
            error: tokens.critical,
            onError: tokens.textHi,
            outline: tokens.hairlineStrong,
          )
        : ColorScheme.dark(
            primary: tokens.pit,
            onPrimary: const Color(0xFF0A0400),
            secondary: tokens.info,
            onSecondary: tokens.textHi,
            surface: tokens.surface,
            onSurface: tokens.textHi,
            error: tokens.critical,
            onError: tokens.textHi,
            outline: tokens.hairlineStrong,
          );

    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.bg,
      canvasColor: tokens.bg,
      fontFamily: SmokeText.textFont,
      dividerColor: tokens.hairline,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[tokens, motion],
      textTheme: TextTheme(
        displayLarge: SmokeText.heroTemp.copyWith(color: tokens.textHi),
        displayMedium: SmokeText.tempXl.copyWith(color: tokens.textHi),
        titleLarge: SmokeText.title.copyWith(color: tokens.textHi),
        titleMedium: SmokeText.cardTitle.copyWith(color: tokens.textHi),
        bodyLarge: SmokeText.body.copyWith(color: tokens.textBody),
        bodyMedium: SmokeText.body.copyWith(color: tokens.textBody),
        bodySmall: SmokeText.sub.copyWith(color: tokens.textMuted),
        labelLarge: SmokeText.label.copyWith(color: tokens.textBody),
        labelSmall: SmokeText.labelSm.copyWith(color: tokens.textMuted),
      ),
    );
  }
}

/// The N0 façade: fonts and the dark palette constants the shell and dev panel
/// already reference. New code reads [SmokeTokens] from the theme instead.
abstract final class SmokeTheme {
  const SmokeTheme._();

  static const String displayFont = SmokeText.displayFont;
  static const String textFont = SmokeText.textFont;
  static const String monoFont = SmokeText.monoFont;

  // Dark-palette aliases (styles.css :root).
  static const Color background = Color(0xFF07090E);
  static const Color surface = Color(0xFF0F131D);
  static const Color card = Color(0xFF161C2A);
  static const Color cardRaised = Color(0xFF1E2638);
  static const Color ember = Color(0xFFD95926);
  static const Color textHi = Color(0xFFF8FAFC);
  static const Color textBody = Color(0xFFCBD5E1);

  /// The dark theme with the standard profile (the shell default).
  static ThemeData get dark => SmokeThemeData.dark();
}
