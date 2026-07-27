/// Design tokens — surfaces, ink, geometry, elevation (design 14 §14.3–§14.4).
///
/// Six surfaces, four inks, two hairlines. Everything else in the app is a
/// composite of these; a widget that reaches for a raw `Color(0x…)` or a bare
/// number is a rejected review comment.
///
/// Carried as a [ThemeExtension] rather than as bare constants for one reason:
/// the **daylight profile** (§14.3.3) swaps ink and switches every glow off
/// without a single call site knowing it happened. Radii and the spacing scale
/// never vary by profile, so they stay `static const` — cheaper, and they can
/// be used in `const` constructors.
library;

import 'package:flutter/material.dart';

/// The token set for one screen profile. Read it with [SmokeTokensX.tokens].
@immutable
class SmokeTokens extends ThemeExtension<SmokeTokens> {
  const SmokeTokens({
    required this.bg,
    required this.surface,
    required this.card,
    required this.cardSubtle,
    required this.cardRaised,
    required this.well,
    required this.hairline,
    required this.hairlineStrong,
    required this.scrim,
    required this.textHi,
    required this.textBody,
    required this.textMuted,
    required this.chromeDim,
    required this.shadowCard,
    required this.glowsEnabled,
  });

  // ── Radii — four, and no fifth ──────────────────────────────────────
  /// [SmokeCard], sheet top, modal.
  static const double radiusCard = 20;

  /// Buttons, inputs, option cards, the compact probe card.
  static const double radiusControl = 14;

  /// Range chips, target pills, insight banners.
  static const double radiusChip = 8;

  /// Transport chip, nav indicator, stroke swatch.
  static const double radiusPill = 999;

  // ── Spacing — a 4 dp scale. A 6 or a 10 is a bug ────────────────────
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s7 = 32;

  // ── Surfaces ────────────────────────────────────────────────────────

  /// `scaffoldBackgroundColor`, and the space between cards.
  final Color bg;

  /// Shell chrome: system status bar, nav bar, sheet body.
  final Color surface;

  /// [SmokeCard] default — the surface most marks are drawn on, and therefore
  /// the surface the series palette is validated against (§14.6.2).
  final Color card;

  /// Insets: chip rows, segmented tracks, list wells, disabled fills.
  final Color cardSubtle;

  /// Pressed card, selected option card, nav indicator.
  ///
  /// Named `bg-card-hover` in `docs/ui/design-system.md:66`; "hover" has no
  /// meaning on a touch device, so the token is renamed and the provenance
  /// recorded (§14.3).
  final Color cardRaised;

  /// Deepest inset. **Mono readouts only** — passkey, AP password, device id,
  /// chart crosshair. Nothing else may sit on `well`.
  final Color well;

  // ── Lines ───────────────────────────────────────────────────────────

  /// 1 dp decorative border on cards and chips.
  final Color hairline;

  /// Dividers *inside* a card.
  final Color hairlineStrong;

  /// Sheet and modal backdrop. Pair with a 6σ blur.
  final Color scrim;

  // ── Ink ─────────────────────────────────────────────────────────────

  /// Numbers, titles, **and all banner and chip text** — the status hue is
  /// carried by the icon and the border, never by the words (§14.6.5).
  final Color textHi;

  /// Prose.
  final Color textBody;

  /// Labels, secondary values, axis ticks, timestamps.
  final Color textMuted;

  /// **Non-text only**: gap connectors, disabled fills, inactive rules.
  /// It does not clear 4.5:1 on any surface here, which is why it may not
  /// carry a word.
  final Color chromeDim;

  // ── Elevation ───────────────────────────────────────────────────────

  /// The one shadow. Null in the daylight profile.
  final BoxShadow? shadowCard;

  /// Whether [glow] and [glowTight] return anything. False in daylight.
  final bool glowsEnabled;

  /// Ambient bloom, 20% alpha. Permitted on exactly three things: an accent
  /// card's border, the gauge's current-value dot, and `MonoWell`. It is the
  /// only reason a `saveLayer` appears in this app.
  BoxShadow? glow(Color c) => glowsEnabled
      ? BoxShadow(color: c.withValues(alpha: 0.20), blurRadius: 24)
      : null;

  /// Tight bloom, 55% alpha — a dot that has to read as *lit*.
  BoxShadow? glowTight(Color c) => glowsEnabled
      ? BoxShadow(color: c.withValues(alpha: 0.55), blurRadius: 8)
      : null;

  /// The shipping profile (§14.3). A white screen outdoors is worse than a
  /// high-contrast dark one, so there is no light theme — see §14.3.3 for the
  /// daylight *contrast* profile that replaces it.
  static const SmokeTokens dark = SmokeTokens(
    bg: Color(0xFF07090E),
    surface: Color(0xFF0F131D),
    card: Color(0xFF161C2A),
    cardSubtle: Color(0xFF121824),
    cardRaised: Color(0xFF1E2638),
    well: Color(0xFF04060A),
    hairline: Color(0x14FFFFFF), // 8%
    hairlineStrong: Color(0x24FFFFFF), // 14%
    scrim: Color(0xB8000000), // 72%
    textHi: Color(0xFFF8FAFC),
    textBody: Color(0xFFCBD5E1),
    textMuted: Color(0xFF94A3B8),
    chromeDim: Color(0xFF64748B),
    shadowCard: BoxShadow(
      color: Color(0x8C000000), // 55%
      blurRadius: 30,
      offset: Offset(0, 10),
      spreadRadius: -10,
    ),
    glowsEnabled: true,
  );

  /// Direct sun. Same surfaces — the eye adapts to the field, not the page —
  /// but the ink ramp lifts and every glow goes off, because a bloom in
  /// sunlight is a smear (§14.3.3).
  static const SmokeTokens daylight = SmokeTokens(
    bg: Color(0xFF07090E),
    surface: Color(0xFF0F131D),
    card: Color(0xFF161C2A),
    cardSubtle: Color(0xFF121824),
    cardRaised: Color(0xFF1E2638),
    well: Color(0xFF04060A),
    hairline: Color(0x24FFFFFF), // 14% — thin lines vanish outdoors
    hairlineStrong: Color(0x38FFFFFF), // 22%
    scrim: Color(0xD9000000), // 85%
    textHi: Color(0xFFFFFFFF),
    textBody: Color(0xFFE2E8F0),
    textMuted: Color(0xFFCBD5E1),
    chromeDim: Color(0xFF94A3B8),
    shadowCard: null,
    glowsEnabled: false,
  );

  @override
  SmokeTokens copyWith({
    Color? bg,
    Color? surface,
    Color? card,
    Color? cardSubtle,
    Color? cardRaised,
    Color? well,
    Color? hairline,
    Color? hairlineStrong,
    Color? scrim,
    Color? textHi,
    Color? textBody,
    Color? textMuted,
    Color? chromeDim,
    BoxShadow? shadowCard,
    bool? glowsEnabled,
  }) {
    return SmokeTokens(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      cardSubtle: cardSubtle ?? this.cardSubtle,
      cardRaised: cardRaised ?? this.cardRaised,
      well: well ?? this.well,
      hairline: hairline ?? this.hairline,
      hairlineStrong: hairlineStrong ?? this.hairlineStrong,
      scrim: scrim ?? this.scrim,
      textHi: textHi ?? this.textHi,
      textBody: textBody ?? this.textBody,
      textMuted: textMuted ?? this.textMuted,
      chromeDim: chromeDim ?? this.chromeDim,
      shadowCard: shadowCard ?? this.shadowCard,
      glowsEnabled: glowsEnabled ?? this.glowsEnabled,
    );
  }

  @override
  SmokeTokens lerp(covariant SmokeTokens? other, double t) {
    if (other == null) {
      return this;
    }
    return SmokeTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardSubtle: Color.lerp(cardSubtle, other.cardSubtle, t)!,
      cardRaised: Color.lerp(cardRaised, other.cardRaised, t)!,
      well: Color.lerp(well, other.well, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairlineStrong: Color.lerp(hairlineStrong, other.hairlineStrong, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      textHi: Color.lerp(textHi, other.textHi, t)!,
      textBody: Color.lerp(textBody, other.textBody, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      chromeDim: Color.lerp(chromeDim, other.chromeDim, t)!,
      shadowCard: BoxShadow.lerp(shadowCard, other.shadowCard, t),
      // A bool cannot be interpolated; switch at the midpoint so a profile
      // change never renders a half-strength glow.
      glowsEnabled: t < 0.5 ? glowsEnabled : other.glowsEnabled,
    );
  }
}

/// `context.tokens` — the only sanctioned way to reach a surface or an ink.
extension SmokeTokensX on BuildContext {
  SmokeTokens get tokens =>
      Theme.of(this).extension<SmokeTokens>() ?? SmokeTokens.dark;
}
