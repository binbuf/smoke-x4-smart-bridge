/// A19.4 — the status palette (design 14 §14.6.5).
///
/// Replaces `AlarmPalette` (`app/lib/app/palette.dart`), keeping `of` and
/// `iconOf` over `AlarmSeverity` so existing call sites migrate by import
/// change.
///
/// ## The separation rule (§14.6.1) — the reason there are two palettes
///
/// A **series hue** ([ProbePalette]) may only be drawn as a *mark*: a chart
/// stroke, a gauge arc, a ≤12 dp probe dot, a card's left rule, a stroke
/// swatch. It never fills a shape larger than 12 dp and never carries a word.
///
/// A **status hue** (this file) may only be drawn as *chrome*: a filled pill or
/// banner at 12–16% alpha with a 22–35% border, **always** containing an icon
/// and a word.
///
/// Consequence: a lit lime chart line and a "target reached" banner cannot be
/// confused, because one is a 2 dp line and the other is a bordered slab with
/// text in it. This is what lets the app be data-dense without being
/// ambiguous.
///
/// ## Two values moved from the old palette, both measured, not stylistic
///
/// **`critical` `#D03B3B` → `#F04444`.** At a 14% fill over `card` the old hue
/// left its own icon at 3.19:1 — 0.19 above the graphics floor, on the single
/// most important glyph in the app. `#F04444` measures 3.96:1 on its fill and
/// 4.55:1 on `card`. It converges with the prototype's `#EF4444` by coincidence,
/// not by copying it.
///
/// **`info` `#898781` → `#94A3B8`.** The old value is a warm grey and every
/// other neutral in the app is now on the slate ramp; carrying two neutral
/// ramps for one enum is indefensible. `info` is a neutral, not a semantic hue,
/// so it carries no validation debt.
///
/// **`warning` stays `#FAB219`.** A draft moved it to `#F5A524` to sit further
/// from ember; measured, `#FAB219` reads 9.28:1 on `card` and both sit ~20°
/// from ember, so the move bought nothing and a validated status hue is not
/// changed to match a mood board.
///
/// **Banner and chip text is `textHi`, never the status hue.** On each role's
/// 14% fill, `textHi` lands 12.6–14.1:1 while the hue lands 3.2–7.0 — and
/// `critical`, the one that matters most, is the worst. The hue is carried by
/// the icon and the border; the words are carried at 13:1. Trailing values use
/// `textBody`.
library;

import 'package:flutter/material.dart';

import '../domain/entities/entities.dart';
import 'series_palette.dart';

/// A status role and how it is drawn as chrome.
enum StatusRole { critical, warning, positive, info, pit }

abstract final class StatusPalette {
  static const Color critical = Color(0xFFF04444);
  static const Color warning = Color(0xFFFAB219);

  /// **Transport healthy only.** Never a probe state — a "target reached" is
  /// not drawn in this, it closes the gauge ring instead (§14.6.6).
  static const Color positive = Color(0xFF10B981);

  /// A neutral, for advisories and capability notices.
  static const Color info = Color(0xFF94A3B8);

  /// The accent: primary actions, the AP transport chip, the cook-header
  /// gradient, the passkey well. Same hue as series slot 1 — the app's fire.
  static Color get pit => ProbePalette.hue(1);

  /// Ink that sits on the ember fill — a near-black that reads at 3 a.m. and
  /// clears contrast on `pit`. Const so it stays usable inside `const` widgets.
  static const Color onPit = Color(0xFF0A0400);

  static Color hue(StatusRole r) => switch (r) {
    StatusRole.critical => critical,
    StatusRole.warning => warning,
    StatusRole.positive => positive,
    StatusRole.info => info,
    StatusRole.pit => pit,
  };

  /// The fill alpha for a role's chrome. `info` sits lower because it is
  /// advisory; `pit` and `critical` a touch higher because they lead.
  static Color fill(StatusRole r) {
    final a = switch (r) {
      StatusRole.info => 0.10,
      StatusRole.positive => 0.12,
      StatusRole.critical || StatusRole.warning => 0.14,
      StatusRole.pit => 0.15,
    };
    return hue(r).withValues(alpha: a);
  }

  /// The border alpha for a role's chrome.
  static Color border(StatusRole r) {
    final a = switch (r) {
      StatusRole.info => 0.22,
      StatusRole.positive => 0.30,
      StatusRole.critical || StatusRole.warning || StatusRole.pit => 0.35,
    };
    return hue(r).withValues(alpha: a);
  }

  // ── AlarmSeverity bridge — keeps A10.2 call sites compiling ───────────

  static StatusRole roleOf(AlarmSeverity s) => switch (s) {
    AlarmSeverity.info => StatusRole.info,
    AlarmSeverity.warning => StatusRole.warning,
    AlarmSeverity.critical => StatusRole.critical,
  };

  static Color of(AlarmSeverity s) => hue(roleOf(s));

  static IconData iconOf(AlarmSeverity s) => switch (s) {
    AlarmSeverity.info => Icons.info_outline,
    AlarmSeverity.warning => Icons.warning_amber_rounded,
    AlarmSeverity.critical => Icons.error_outline,
  };
}
