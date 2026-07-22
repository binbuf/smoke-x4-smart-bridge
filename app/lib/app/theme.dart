/// App theming — DARK-FIRST (design 08 §8.7).
///
/// This app is read from four feet away, in a dark yard, at 3 a.m., possibly
/// through a screen door. That constraint lives in the theme from the first
/// commit:
///
///  * dark theme is the default; a light theme exists for daytime use;
///  * large type, with dedicated huge styles for the two headline
///    temperature slots (pit + primary food probe);
///  * high contrast (near-black surfaces, near-white text, ember accent);
///  * generous touch targets ([MaterialTapTargetSize.padded], standard
///    visual density, tall buttons and list tiles).
library;

import 'package:flutter/material.dart';

/// The project theme set. Access [dark] (the default), [light], and the
/// headline temperature text styles.
abstract final class SmokeTheme {
  /// Ember orange — the seed for both schemes.
  static const Color seed = Color(0xFFFF6B35);

  /// The default theme. Dark-first is a product requirement, not a style
  /// preference (design 08 §8.7).
  static ThemeData get dark {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ).copyWith(
          // Push contrast beyond the Material defaults: near-black surface,
          // near-white foreground, for legibility outdoors at night.
          surface: const Color(0xFF0D0F12),
          onSurface: const Color(0xFFF2F3F5),
        );
    return _base(scheme);
  }

  /// The light theme, for reading the same screens in daylight.
  static ThemeData get light {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ).copyWith(
          surface: const Color(0xFFFDFBF8),
          onSurface: const Color(0xFF17181A),
        );
    return _base(scheme);
  }

  /// Style for the two headline temperature slots on the dashboard.
  ///
  /// Huge, heavy, and tabular — the digits must not jitter sideways as the
  /// value ticks, and must be readable at arm's length and beyond. Also
  /// exposed as `textTheme.displayLarge`.
  static const TextStyle headlineTemp = TextStyle(
    fontSize: 88,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -2.0,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Secondary temperature readouts (remaining probes, targets).
  static const TextStyle secondaryTemp = TextStyle(
    fontSize: 40,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.0,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static ThemeData _base(ColorScheme scheme) {
    // Body/label sizes are bumped one step over the Material defaults —
    // "large type" applies to everything, not only the headline numbers.
    final textTheme = ThemeData(brightness: scheme.brightness).textTheme
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
        .copyWith(
          displayLarge: headlineTemp,
          displayMedium: secondaryTemp,
          bodyLarge: const TextStyle(fontSize: 18, height: 1.4),
          bodyMedium: const TextStyle(fontSize: 16, height: 1.4),
          labelLarge: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        );

    // Generous minimum for anything tappable — well past the 48 dp Material
    // minimum, because it may be hit with cold or greasy fingers.
    const minTouchTarget = Size(64, 52);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      // Never let a platform default compact the hit areas.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: minTouchTarget),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(minimumSize: minTouchTarget),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: minTouchTarget),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: minTouchTarget),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 14,
        contentPadding: EdgeInsets.symmetric(horizontal: 20),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: textTheme.bodyLarge,
      ),
    );
  }
}
