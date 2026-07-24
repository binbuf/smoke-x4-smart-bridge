/// A10.2 — the probe palette (design 08 §8.7).
///
/// §8.7 refuses to fix hex values and fixes the *constraints* instead:
/// colourblind-safe, legible in direct sunlight **and** in a dark theme,
/// consistent across the app, the exports and the OLED's single bit of
/// ink, with roles carrying semantic weight. Those are requirements. What
/// follows is the palette that satisfies them and the measurements that
/// prove it — run, not reasoned about.
///
/// ## What was decided, and why
///
/// **Colour follows the probe, never its role.** Probe 1 is orange whether
/// the user calls it the pit or the point. Two reasons, both structural:
/// re-roling a probe mid-cook must not repaint the history behind it, and
/// the OLED — which is the same data with one bit of ink — can only
/// identify a probe by its number. Role carries its semantic weight
/// through *form* instead: the pit is the reference series (heaviest
/// stroke, the alarm band, the target line), food probes are the subjects.
///
/// **Identity does not rest on hue.** Each probe also owns a stroke
/// pattern — P1 solid, P2 dashed, P3 dotted, P4 dash-dot — which survives
/// a monochrome export, a photocopy, and the SSD1306. This is not a
/// decoration; it is the channel that makes the palette honest for the one
/// case the adjacent-pair gate does not cover (below).
///
/// **Yellow and red are excluded from the series set on purpose.** They
/// are the status hues (warning, critical); a series wearing one would
/// impersonate an alarm on a screen whose whole job is alarms.
///
/// ## The measurements
///
/// Validated against the app's own surfaces — dark `#0D0F12`, light
/// `#FDFBF8` — in both modes, on the *adjacent* pairlist the method
/// prescribes for line charts. Every check passes in both:
///
/// | mode  | worst adjacent CVD ΔE      | worst adjacent normal ΔE | contrast |
/// | ----- | -------------------------- | ------------------------ | -------- |
/// | light | 26.5 (protan) — blue↔green | 29.0                     | all ≥ 3:1 (3.10–8.28) |
/// | dark  | 26.0 (deutan) — violet↔orange | 27.0                  | all ≥ 3:1 (3.88–6.14) |
///
/// The order was not chosen by eye: all 24 orderings of the four hues were
/// run through the validator and this one maximises the minimum adjacent
/// separation across both modes (26.0). Among the tied orders it is also
/// the one whose opening slot is the ember hue — probe 1 is the pit on
/// essentially every X4, and the app's own accent already reads as fire.
///
/// **The honest caveat.** Probes attach sparsely: probe 1 and probe 3 can
/// be the only two lines on screen, so the *all-pairs* gate is arguably
/// the fair one here, and this set does not clear it (worst all-pairs
/// CVD ΔE 3.2 light for green↔orange, 1.9 dark for blue↔violet). Nothing
/// in the documented palette clears all-pairs at four slots *and* keeps
/// every slot above 3:1 on a near-white surface — the sunlight
/// requirement and the all-pairs floor are in direct conflict at four
/// series, and sunlight legibility is the stated requirement. The
/// resolution is the secondary encoding the method asks for in exactly
/// this situation, and we ship all three channels: per-probe **stroke
/// pattern**, a **legend**, and **direct labels** at each series' end.
/// Identity never rests on hue alone.
library;

import 'package:flutter/material.dart';

import '../domain/entities/entities.dart';

/// How a probe's series is drawn: a hue plus a colour-free stroke.
class ProbeStyle {
  const ProbeStyle({
    required this.probe,
    required this.color,
    required this.dashArray,
    required this.strokeWidth,
  });

  /// 1..4 — the physical jack. The identity this style belongs to.
  final int probe;
  final Color color;

  /// Null for a solid line. `[on, off, …]`, in logical pixels — the same
  /// language `fl_chart`, an SVG export, and the OLED all speak.
  final List<int>? dashArray;
  final double strokeWidth;

  /// A short, speakable name for the stroke — goldens and semantics read
  /// this, so a colour change is reviewable in text.
  String get strokeName => switch (dashArray) {
    null => 'solid',
    [8, 4] => 'dashed',
    [2, 5] => 'dotted',
    _ => 'dash-dot',
  };
}

/// The four probe slots, in fixed order, plus the chart's ink.
///
/// Slots are **never cycled**: there is no fifth probe, and if there ever
/// were it would not be a generated hue.
abstract final class ProbePalette {
  // Slot 1 — ember/orange. The pit's conventional jack.
  static const Color _orangeLight = Color(0xFFEB6834);
  static const Color _orangeDark = Color(0xFFD95926);
  // Slot 2 — violet.
  static const Color _violetLight = Color(0xFF4A3AA7);
  static const Color _violetDark = Color(0xFF9085E9);
  // Slot 3 — green (mode-invariant; it clears 3:1 on both surfaces).
  static const Color _green = Color(0xFF008300);
  // Slot 4 — blue.
  static const Color _blueLight = Color(0xFF2A78D6);
  static const Color _blueDark = Color(0xFF3987E5);

  /// P1 solid, P2 dashed, P3 dotted, P4 dash-dot. Ordered by how much
  /// ink they lay down, so the reference series is the strongest mark.
  static const List<List<int>?> strokes = [
    null,
    [8, 4],
    [2, 5],
    [10, 4, 2, 4],
  ];

  /// The style for [probe] (1..4) under [brightness]. [role] does not pick
  /// the hue — it only decides the weight, because the pit is the
  /// reference series and the food probes are the subjects.
  static ProbeStyle styleFor(
    int probe,
    Brightness brightness, {
    ProbeRole role = ProbeRole.unused,
  }) {
    final dark = brightness == Brightness.dark;
    final i = (probe - 1).clamp(0, 3);
    final color = switch (i) {
      0 => dark ? _orangeDark : _orangeLight,
      1 => dark ? _violetDark : _violetLight,
      2 => _green,
      _ => dark ? _blueDark : _blueLight,
    };
    return ProbeStyle(
      probe: probe,
      color: color,
      dashArray: strokes[i],
      strokeWidth: role == ProbeRole.pit ? 3 : 2,
    );
  }

  /// Chart chrome. Recessive by rule — the grid must never compete with
  /// the data, and at 3 a.m. in a dark yard neither must the axis.
  static Color grid(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF2C2C2A) : const Color(0xFFE1E0D9);

  static Color axisInk(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF898781) : const Color(0xFF898781);

  /// The gap connector: a dotted hint that time passed, drawn in chrome
  /// ink rather than in the series colour so it can never be mistaken for
  /// data (08 §8.7 — "a 30-minute dropout must look like a 30-minute
  /// dropout").
  static Color gapInk(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF4A4A47) : const Color(0xFFBFBEB8);
}

/// Status colours (09 §9.2 severities). Reserved: these are never used
/// for a series, and they never travel alone — every use is paired with an
/// icon and a word, because colour cannot carry "critical" by itself.
abstract final class AlarmPalette {
  static const Color info = Color(0xFF898781);
  static const Color warning = Color(0xFFFAB219);
  static const Color critical = Color(0xFFD03B3B);

  static Color of(AlarmSeverity s) => switch (s) {
    AlarmSeverity.info => info,
    AlarmSeverity.warning => warning,
    AlarmSeverity.critical => critical,
  };

  static IconData iconOf(AlarmSeverity s) => switch (s) {
    AlarmSeverity.info => Icons.info_outline,
    AlarmSeverity.warning => Icons.warning_amber_rounded,
    AlarmSeverity.critical => Icons.error_outline,
  };
}
