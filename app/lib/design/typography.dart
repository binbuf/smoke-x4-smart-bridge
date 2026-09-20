/// The type scale (design 14 §14.5).
///
/// Three families, bundled as assets — **no `google_fonts`, no network
/// fetch**. The prototype's `<link>` to `fonts.googleapis.com`
/// (`docs/ui/index.html:10`) is not portable to an app that must render on a
/// phone joined to the bridge's own AP with no internet at all
/// (`bindProcessToNetwork` removes `NET_CAPABILITY_INTERNET` by design,
/// design 05 §5.8.1), and a golden that depends on a font download is a
/// golden that fails in CI.
///
/// Until `assets/fonts/` is populated (M8 A19.2) these families resolve to the
/// platform default. Sizes, weights, tracking and figure style are correct
/// regardless, so layout work can proceed; **goldens must not be pinned before
/// the assets land.**
library;

import 'package:flutter/material.dart';

/// Font family names, matching the `fonts:` block in `pubspec.yaml`.
abstract final class SmokeFonts {
  /// Variable, `wdth 100..125`, `wght 400..800`. Display and every temperature.
  static const String display = 'Archivo';

  /// Variable, `opsz`, `wght`. All prose and labels.
  static const String text = 'Inter';

  /// Variable, `wght`. Anything the user might read aloud or type in.
  static const String mono = 'JetBrainsMono';

  /// The width axis for temperatures.
  ///
  /// The hero number is *width*-constrained — it shares a 208 dp card row with
  /// an 84 dp gauge — and a width axis buys optical size at ten feet without
  /// buying line height, which is what principle 1
  /// (`docs/ui/design-system.md:8`) actually asks for. **[I]** — a design
  /// judgement, not a measurement. It is settled by a held-phone read at 3 m
  /// against a `wdth 100` control; until that test runs, 100 is the fallback
  /// and this constant is the single place to change it.
  static const List<FontVariation> tempWidth = [FontVariation('wdth', 112)];
}

const List<FontFeature> _tnum = [FontFeature.tabularFigures()];

/// The fourteen named styles. There is no fifteenth: a size that is not here
/// is a design question, not a widget's decision.
///
/// Colour is **not** baked in — every style inherits, and the call site picks
/// an ink from [SmokeTokens]. That is what lets the daylight profile lift the
/// whole ramp without touching this file.
abstract final class SmokeType {
  /// Pit and primary-food hero number. Fixed at 96 — never `FittedBox`ed
  /// (§14.5.1): a glyph that changes height as a probe crosses 99 → 100 °F
  /// reads as the layout breaking, not as a temperature rising.
  static const TextStyle heroTemp = TextStyle(
    fontFamily: SmokeFonts.display,
    fontVariations: SmokeFonts.tempWidth,
    fontSize: 96,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -3.0,
    fontFeatures: _tnum,
  );

  /// The `°F` sitting on the hero baseline.
  static const TextStyle heroUnit = TextStyle(
    fontFamily: SmokeFonts.display,
    fontSize: 30,
    height: 1.0,
    fontWeight: FontWeight.w600,
  );

  /// Instrument-mode rows, stat heroes.
  static const TextStyle bigTemp = TextStyle(
    fontFamily: SmokeFonts.display,
    fontVariations: SmokeFonts.tempWidth,
    fontSize: 56,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.6,
    fontFeatures: _tnum,
  );

  /// The compact probe card.
  static const TextStyle midTemp = TextStyle(
    fontFamily: SmokeFonts.display,
    fontSize: 34,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.0,
    fontFeatures: _tnum,
  );

  /// Screen titles, cook name.
  static const TextStyle displayL = TextStyle(
    fontFamily: SmokeFonts.display,
    fontSize: 26,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );

  /// Card titles, sheet headers.
  static const TextStyle displayS = TextStyle(
    fontFamily: SmokeFonts.display,
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  /// List rows, settings rows.
  static const TextStyle title = TextStyle(
    fontFamily: SmokeFonts.text,
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w700,
  );

  /// Prose.
  static const TextStyle body = TextStyle(
    fontFamily: SmokeFonts.text,
    fontSize: 16,
    height: 1.45,
  );

  /// Secondary prose, banner text.
  static const TextStyle bodySm = TextStyle(
    fontFamily: SmokeFonts.text,
    fontSize: 14,
    height: 1.4,
  );

  /// Probe name, eyebrow, chip. Rendered uppercase by the call site — the
  /// tracking assumes it.
  static const TextStyle label = TextStyle(
    fontFamily: SmokeFonts.text,
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.6,
  );

  /// Axis ticks, timestamps.
  static const TextStyle labelSm = TextStyle(
    fontFamily: SmokeFonts.text,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );

  /// Ids, addresses, chart crosshair.
  static const TextStyle mono = TextStyle(
    fontFamily: SmokeFonts.mono,
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    fontFeatures: _tnum,
  );

  /// The elapsed-cook badge.
  static const TextStyle monoBig = TextStyle(
    fontFamily: SmokeFonts.mono,
    fontSize: 22,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.0,
    fontFeatures: _tnum,
  );

  /// The BLE passkey and the AP password — the two strings a user copies off
  /// one screen and types into another, so they get the widest tracking in the
  /// app and the deepest surface under them (`SmokeTokens.well`).
  static const TextStyle monoKey = TextStyle(
    fontFamily: SmokeFonts.mono,
    fontSize: 34,
    height: 1.1,
    fontWeight: FontWeight.w800,
    letterSpacing: 12.0,
    fontFeatures: _tnum,
  );

  /// A temperature is laid out at its declared size and no other (§14.5.1) —
  /// so it is rendered with the user's text scaler **switched off**, and the
  /// scaler is answered by [SmokeTextScale] reflowing the layout around it
  /// instead. Wrap only the number; everything else on the card still scales.
  ///
  /// This is what makes "never scale a temperature" and "honour text scale"
  /// both true at once: the glyph height is constant between frames and
  /// between two cards side by side, and a person at 200% text still gets
  /// bigger *labels*, a bigger banner and a layout that has made room for
  /// them.
  static Widget unscaled({required Widget child}) =>
      MediaQuery.withNoTextScaling(child: child);

  /// The Material mapping, so widgets that have not migrated yet inherit
  /// something correct rather than a Material default (§14.5).
  static TextTheme textTheme(Color body_, Color display_) => TextTheme(
    displayLarge: heroTemp,
    displayMedium: midTemp,
    displaySmall: displayL,
    headlineMedium: displayL,
    headlineSmall: displayS,
    titleLarge: displayS,
    titleMedium: title,
    bodyLarge: body,
    bodyMedium: bodySm,
    labelLarge: title,
    labelMedium: label,
    labelSmall: labelSm,
  ).apply(bodyColor: body_, displayColor: display_);
}
