/// A19.1 — the app theme (design 14 §14.3.2).
///
/// **Dark-only ships** (decision U4, 13 §13.9.1). A white screen in a dark yard
/// at 3 a.m. is worse than a high-contrast dark one, and a second `Brightness`
/// is a v1.1 project with its own token pass and its own golden set. The
/// daylight *contrast profile* ([SmokeTokens.daylight]) covers reading the same
/// screens in direct sun without a second theme — same surfaces, lifted ink,
/// glows off.
///
/// So both `theme:` and `darkTheme:` on the `MaterialApp` are set to [dark]:
/// OS-light system chrome can then never leak a white bar behind the app.
///
/// The `ColorScheme` maps deliberately (§14.3.2): `surface` → `card`, because
/// `card` is the surface `SmokeCard` and the chart are actually drawn on, and
/// the series palette is validated against it. `scaffoldBackgroundColor` is the
/// deeper `bg` — the space between cards.
///
/// The touch-target work is carried forward from the previous theme
/// (`app/lib/app/theme.dart`): `Size(64, 52)` minimums, padded tap targets,
/// tall list rows — it may be a cold or greasy finger.
library;

import 'package:flutter/material.dart';

import 'series_palette.dart';
import 'status_palette.dart';
import 'tokens.dart';
import 'typography.dart';

abstract final class SmokeTheme {
  /// The shipping theme.
  static ThemeData get dark => _build(SmokeTokens.dark);

  /// The direct-sun contrast profile. Same surfaces, lifted ink, no glows.
  static ThemeData get daylight => _build(SmokeTokens.daylight);

  static ThemeData _build(SmokeTokens t) {
    final scheme = ColorScheme.dark(
      primary: StatusPalette.pit,
      onPrimary: const Color(0xFF0A0400),
      secondary: ProbePalette.hue(2),
      error: StatusPalette.critical,
      onError: t.textHi,
      // `card` is the surface most content sits on and the one the palette is
      // validated against — not the deeper `bg`.
      surface: t.card,
      onSurface: t.textHi,
      surfaceContainerLowest: t.bg,
      surfaceContainerLow: t.surface,
      surfaceContainer: t.card,
      surfaceContainerHigh: t.cardRaised,
      outline: t.hairline,
    );

    const minTouch = Size(64, 52);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.bg,
      textTheme: SmokeType.textTheme(t.textBody, t.textHi),
      extensions: [t],
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: t.surface,
        foregroundColor: t.textHi,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: SmokeType.displayS.copyWith(color: t.textHi),
      ),
      dividerTheme: DividerThemeData(color: t.hairlineStrong, thickness: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: minTouch),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(minimumSize: minTouch),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: minTouch),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: minTouch),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
      ),
      // ── the settings tree, brought into the design system (newapp §F) ──
      //
      // §F names the settings pages as "the largest visual inconsistency in
      // the app": four files, ~76 Material-default rows, and not one reference
      // to a token. The fix is not to hand-restyle seventy-six widgets — it is
      // to say what a row IS, once, here. That is what a ThemeExtension-driven
      // design system is for, and it means the daylight profile reaches those
      // pages for free rather than needing a second pass.
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 14,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        titleTextStyle: SmokeType.title.copyWith(color: t.textHi),
        // Prose under a title is `textBody`; a *value* under a title is the
        // same ink, because a settings row's subtitle is usually the value and
        // muting it would make the answer quieter than the question.
        subtitleTextStyle: SmokeType.bodySm.copyWith(color: t.textBody),
        iconColor: t.textMuted,
        selectedTileColor: t.cardRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
        ),
      ),
      switchTheme: SwitchThemeData(
        // The track is chrome, so it takes a status hue at chrome strength;
        // `pit` rather than `positive`, because green is transport health and
        // a page of green switches would compete with the one chip that means
        // "connected" (§14.6).
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? t.chromeDim
              : states.contains(WidgetState.selected)
              ? StatusPalette.pit
              : t.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? StatusPalette.fill(StatusRole.pit)
              : t.cardSubtle,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? StatusPalette.border(StatusRole.pit)
              : t.hairlineStrong,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(SmokeType.labelSm),
          side: WidgetStatePropertyAll(BorderSide(color: t.hairlineStrong)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? t.cardRaised
                : t.cardSubtle,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? t.chromeDim
                : t.textHi,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SmokeTokens.radiusChip),
            ),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.cardSubtle,
        // A form field is an inset, so it gets the control radius and a
        // hairline — never Material's default underline, which reads as a
        // different app on the same screen.
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
          borderSide: BorderSide(color: t.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
          borderSide: BorderSide(color: t.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
          borderSide: BorderSide(color: StatusPalette.pit),
        ),
        labelStyle: SmokeType.bodySm.copyWith(color: t.textMuted),
        helperStyle: SmokeType.labelSm.copyWith(color: t.textMuted),
        helperMaxLines: 3,
        hintStyle: SmokeType.bodySm.copyWith(color: t.chromeDim),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SmokeTokens.radiusCard),
        ),
        titleTextStyle: SmokeType.displayS.copyWith(color: t.textHi),
        contentTextStyle: SmokeType.body.copyWith(color: t.textBody),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: t.scrim,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SmokeTokens.radiusCard),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.cardSubtle,
        side: BorderSide(color: t.hairlineStrong),
        labelStyle: SmokeType.bodySm.copyWith(color: t.textHi),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SmokeTokens.radiusChip),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: t.cardRaised,
        contentTextStyle: SmokeType.body.copyWith(color: t.textHi),
      ),
    );
  }
}
