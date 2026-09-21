/// N3.1–N3.6 — the token set, as one `ThemeExtension`.
///
/// This is `newui/styles.css` `:root` + `theme-light` + `profile-daylight`
/// translated to Flutter. Three axes, independent:
///
/// * [Brightness] — `dark` (default) or `light`, the palette swap.
/// * [SmokeProfile] — `standard` or `daylight`, a **contrast profile** layered
///   on either palette. Daylight is not a light theme: it lifts the ink,
///   thickens the hairlines and removes shadow and glow.
/// * [SmokeDensity] — `compact` or `comfortable`, which spacing step a surface
///   uses. It never changes the 4 dp scale itself.
///
/// Colour discipline (`styles.css` header, research notes §9.3): series hues
/// (p1–p4) are **marks only**; status hues are **chrome only** and always carry
/// an icon *and* a word; green means transport health only. Every tint is
/// derived from a token through [tint] — the Flutter spelling of the
/// prototype's `rgba(var(--x-rgb), a)` — so tints retint with the theme and no
/// screen ever hardcodes a colour.
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// A surface's layout density.
enum SmokeDensity {
  /// More at a glance (default). 16 dp page gutters, 16 dp card padding.
  compact,

  /// Roomier. 18 dp page gutters, 20 dp card padding.
  comfortable;

  /// Horizontal page gutter.
  double get pageGutter => this == SmokeDensity.compact ? 16 : 18;

  /// Inside a card.
  double get cardPadding => this == SmokeDensity.compact ? 16 : 20;

  /// Gap between cards in a grid / stack.
  double get gridGap => this == SmokeDensity.compact ? 10 : 12;
}

/// The contrast profile, orthogonal to [Brightness].
enum SmokeProfile {
  /// The normal palette.
  standard,

  /// High contrast for bright sun: lifted ink, thicker hairlines, no
  /// shadow/glow.
  daylight,
}

/// The 4 dp spacing scale. "A 6 or a 10 is a bug."
@immutable
class SmokeSpacing {
  const SmokeSpacing();

  final double s1 = 4;
  final double s2 = 8;
  final double s3 = 12;
  final double s4 = 16;
  final double s5 = 20;
  final double s6 = 24;
  final double s7 = 32;

  @override
  bool operator ==(Object other) => other is SmokeSpacing;

  @override
  int get hashCode => 17;
}

/// The four radii: card 20 / control 14 / chip 8 / pill 999.
@immutable
class SmokeRadii {
  const SmokeRadii();

  final double card = 20;
  final double control = 14;
  final double chip = 8;
  final double pill = 999;

  @override
  bool operator ==(Object other) => other is SmokeRadii;

  @override
  int get hashCode => 23;
}

/// The whole token set, carried on `ThemeData.extensions`.
///
/// Read it with [SmokeTokens.of]; build a themed tree with
/// `SmokeThemeData.build`. Fields map one-to-one onto the prototype's CSS
/// custom properties so a value can always be traced back to `styles.css`.
@immutable
class SmokeTokens extends ThemeExtension<SmokeTokens> {
  const SmokeTokens({
    required this.brightness,
    required this.profile,
    required this.density,
    required this.bg,
    required this.surface,
    required this.card,
    required this.cardSubtle,
    required this.cardRaised,
    required this.well,
    required this.pageBg,
    required this.hairline,
    required this.hairlineStrong,
    required this.scrim,
    required this.textHi,
    required this.textBody,
    required this.textMuted,
    required this.chromeDim,
    required this.p1,
    required this.p2,
    required this.p3,
    required this.p4,
    required this.critical,
    required this.warning,
    required this.positive,
    required this.info,
    required this.pit,
    required this.shadowCard,
    required this.glow,
    this.spacing = const SmokeSpacing(),
    this.radii = const SmokeRadii(),
  });

  final Brightness brightness;
  final SmokeProfile profile;
  final SmokeDensity density;

  // Surfaces (6 + the page wash).
  final Color bg;
  final Color surface;
  final Color card;
  final Color cardSubtle;
  final Color cardRaised;
  final Color well;
  final Color pageBg;

  // Lines.
  final Color hairline;
  final Color hairlineStrong;
  final Color scrim;

  // Ink (4). `chromeDim` is non-text only.
  final Color textHi;
  final Color textBody;
  final Color textMuted;
  final Color chromeDim;

  // Series — marks only, follows the jack, never the role.
  final Color p1;
  final Color p2;
  final Color p3;
  final Color p4;

  // Status — chrome only.
  final Color critical;
  final Color warning;
  final Color positive;
  final Color info;
  final Color pit;

  /// One elevation. Empty under the daylight profile.
  final List<BoxShadow> shadowCard;

  /// 1 in the dark standard profile, 0 otherwise (no glow in daylight/light).
  final double glow;

  final SmokeSpacing spacing;
  final SmokeRadii radii;

  /// The series hue for a jack (1–4). A **mark**, never a status.
  Color series(int jack) => switch (jack) {
    1 => p1,
    2 => p2,
    3 => p3,
    _ => p4,
  };

  /// The Flutter spelling of `rgba(var(--x-rgb), a)`.
  ///
  /// Every tint in the system goes through here so it retints with the theme.
  Color tint(Color base, double alpha) => base.withValues(alpha: alpha);

  /// A status tinted fill (12–16 %).
  Color statusFill(Color status, {double alpha = 0.14}) => tint(status, alpha);

  /// A status tinted border (22–35 %).
  Color statusBorder(Color status, {double alpha = 0.32}) =>
      tint(status, alpha);

  static SmokeTokens of(BuildContext context) =>
      Theme.of(context).extension<SmokeTokens>() ?? SmokeTokens.dark();

  /// The dark palette from `styles.css` `:root`.
  factory SmokeTokens.dark({
    SmokeProfile profile = SmokeProfile.standard,
    SmokeDensity density = SmokeDensity.compact,
  }) {
    final daylight = profile == SmokeProfile.daylight;
    return SmokeTokens(
      brightness: Brightness.dark,
      profile: profile,
      density: density,
      bg: const Color(0xFF07090E),
      surface: const Color(0xFF0F131D),
      card: const Color(0xFF161C2A),
      cardSubtle: const Color(0xFF121824),
      cardRaised: const Color(0xFF1E2638),
      well: const Color(0xFF04060A),
      pageBg: const Color(0xFF05070B),
      hairline: daylight ? const Color(0x2EFFFFFF) : const Color(0x14FFFFFF),
      hairlineStrong: daylight
          ? const Color(0x4DFFFFFF)
          : const Color(0x24FFFFFF),
      scrim: const Color(0xB8000000),
      textHi: daylight ? const Color(0xFFFFFFFF) : const Color(0xFFF8FAFC),
      textBody: daylight ? const Color(0xFFE6EBF2) : const Color(0xFFCBD5E1),
      textMuted: daylight ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8),
      chromeDim: daylight ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      p1: const Color(0xFFD95926),
      p2: const Color(0xFF9085E9),
      p3: const Color(0xFF008300),
      p4: const Color(0xFF3987E5),
      critical: const Color(0xFFF04444),
      warning: const Color(0xFFFAB219),
      positive: const Color(0xFF10B981),
      info: const Color(0xFF94A3B8),
      pit: const Color(0xFFD95926),
      shadowCard: daylight
          ? const <BoxShadow>[]
          : const <BoxShadow>[
              BoxShadow(
                color: Color(0x8C000000),
                blurRadius: 30,
                offset: Offset(0, 10),
                spreadRadius: -10,
              ),
            ],
      glow: daylight ? 0 : 1,
    );
  }

  /// The light palette from `styles.css` `body.theme-light`, with weightier
  /// series hues so they stay legible on white.
  factory SmokeTokens.light({
    SmokeProfile profile = SmokeProfile.standard,
    SmokeDensity density = SmokeDensity.compact,
  }) {
    final daylight = profile == SmokeProfile.daylight;
    return SmokeTokens(
      brightness: Brightness.light,
      profile: profile,
      density: density,
      bg: const Color(0xFFF5F6F9),
      surface: const Color(0xFFFFFFFF),
      card: const Color(0xFFFFFFFF),
      cardSubtle: const Color(0xFFF1F3F7),
      cardRaised: const Color(0xFFFFFFFF),
      well: const Color(0xFFE9EDF3),
      pageBg: const Color(0xFFE7EAF0),
      hairline: daylight ? const Color(0x2E000000) : const Color(0x1A0F172A),
      hairlineStrong: daylight
          ? const Color(0x4D000000)
          : const Color(0x2E0F172A),
      scrim: const Color(0x6B0F172A),
      textHi: daylight ? const Color(0xFF000000) : const Color(0xFF0B1220),
      textBody: daylight ? const Color(0xFF1E293B) : const Color(0xFF334155),
      textMuted: daylight ? const Color(0xFF475569) : const Color(0xFF64748B),
      chromeDim: daylight ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
      p1: const Color(0xFFC2410C),
      p2: const Color(0xFF6D5BD0),
      p3: const Color(0xFF0F7A0F),
      p4: const Color(0xFF2563EB),
      critical: const Color(0xFFDC2626),
      warning: const Color(0xFFB45309),
      positive: const Color(0xFF059669),
      info: const Color(0xFF64748B),
      pit: const Color(0xFFC2410C),
      shadowCard: daylight
          ? const <BoxShadow>[]
          : const <BoxShadow>[
              BoxShadow(
                color: Color(0x38101729),
                blurRadius: 24,
                offset: Offset(0, 8),
                spreadRadius: -12,
              ),
            ],
      glow: 0,
    );
  }

  @override
  SmokeTokens copyWith({
    Brightness? brightness,
    SmokeProfile? profile,
    SmokeDensity? density,
    Color? bg,
    Color? surface,
    Color? card,
    Color? cardSubtle,
    Color? cardRaised,
    Color? well,
    Color? pageBg,
    Color? hairline,
    Color? hairlineStrong,
    Color? scrim,
    Color? textHi,
    Color? textBody,
    Color? textMuted,
    Color? chromeDim,
    Color? p1,
    Color? p2,
    Color? p3,
    Color? p4,
    Color? critical,
    Color? warning,
    Color? positive,
    Color? info,
    Color? pit,
    List<BoxShadow>? shadowCard,
    double? glow,
    SmokeSpacing? spacing,
    SmokeRadii? radii,
  }) {
    return SmokeTokens(
      brightness: brightness ?? this.brightness,
      profile: profile ?? this.profile,
      density: density ?? this.density,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      cardSubtle: cardSubtle ?? this.cardSubtle,
      cardRaised: cardRaised ?? this.cardRaised,
      well: well ?? this.well,
      pageBg: pageBg ?? this.pageBg,
      hairline: hairline ?? this.hairline,
      hairlineStrong: hairlineStrong ?? this.hairlineStrong,
      scrim: scrim ?? this.scrim,
      textHi: textHi ?? this.textHi,
      textBody: textBody ?? this.textBody,
      textMuted: textMuted ?? this.textMuted,
      chromeDim: chromeDim ?? this.chromeDim,
      p1: p1 ?? this.p1,
      p2: p2 ?? this.p2,
      p3: p3 ?? this.p3,
      p4: p4 ?? this.p4,
      critical: critical ?? this.critical,
      warning: warning ?? this.warning,
      positive: positive ?? this.positive,
      info: info ?? this.info,
      pit: pit ?? this.pit,
      shadowCard: shadowCard ?? this.shadowCard,
      glow: glow ?? this.glow,
      spacing: spacing ?? this.spacing,
      radii: radii ?? this.radii,
    );
  }

  @override
  SmokeTokens lerp(covariant SmokeTokens? other, double t) {
    if (other == null) {
      return this;
    }
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return SmokeTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      profile: t < 0.5 ? profile : other.profile,
      density: t < 0.5 ? density : other.density,
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      card: c(card, other.card),
      cardSubtle: c(cardSubtle, other.cardSubtle),
      cardRaised: c(cardRaised, other.cardRaised),
      well: c(well, other.well),
      pageBg: c(pageBg, other.pageBg),
      hairline: c(hairline, other.hairline),
      hairlineStrong: c(hairlineStrong, other.hairlineStrong),
      scrim: c(scrim, other.scrim),
      textHi: c(textHi, other.textHi),
      textBody: c(textBody, other.textBody),
      textMuted: c(textMuted, other.textMuted),
      chromeDim: c(chromeDim, other.chromeDim),
      p1: c(p1, other.p1),
      p2: c(p2, other.p2),
      p3: c(p3, other.p3),
      p4: c(p4, other.p4),
      critical: c(critical, other.critical),
      warning: c(warning, other.warning),
      positive: c(positive, other.positive),
      info: c(info, other.info),
      pit: c(pit, other.pit),
      shadowCard: t < 0.5 ? shadowCard : other.shadowCard,
      glow: lerpDouble(glow, other.glow, t) ?? glow,
      spacing: t < 0.5 ? spacing : other.spacing,
      radii: t < 0.5 ? radii : other.radii,
    );
  }
}
