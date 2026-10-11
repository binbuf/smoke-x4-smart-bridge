/// Builds the app's single (dark) [ThemeData] from the tokens.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildSmokeTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: SmokePalette.ember,
    brightness: Brightness.dark,
  ).copyWith(surface: SmokePalette.bg, primary: SmokePalette.ember);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: SmokePalette.bg,
    fontFamily: 'Inter',
    cardTheme: CardThemeData(
      color: SmokePalette.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SmokeRadius.card),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: SmokePalette.bg,
      foregroundColor: SmokePalette.textHi,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: SmokePalette.surface,
      indicatorColor: SmokePalette.ember.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? SmokePalette.textHi
              : SmokePalette.textMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? SmokePalette.ember
              : SmokePalette.textMuted,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SmokePalette.ember,
        foregroundColor: SmokePalette.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SmokeRadius.control),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: SmokeSpace.lg,
          vertical: SmokeSpace.md,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: SmokePalette.ember),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SmokePalette.textHi,
        side: const BorderSide(color: SmokePalette.hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SmokeRadius.control),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: SmokeSpace.lg,
          vertical: SmokeSpace.md,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? SmokePalette.ember.withValues(alpha: 0.18)
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? SmokePalette.textHi
              : SmokePalette.textMuted,
        ),
        side: const WidgetStatePropertyAll(
          BorderSide(color: SmokePalette.hairline),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: SmokePalette.hairline,
      thickness: 1,
      space: 1,
    ),
  );
}
