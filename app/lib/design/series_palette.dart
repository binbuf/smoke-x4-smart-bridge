/// A19.3 — the series palette (design 14 §14.6.2).
///
/// Ported from `app/lib/app/palette.dart` (A10.2) **with the four dark hues
/// unchanged**. An earlier draft retuned them on the theory that they were
/// validated against `#0D0F12` and the shipping background is now `#07090E`.
/// Measured, that argument inverts: contrast is the *only* background-dependent
/// term in the validation, and moving the surface darker lifted every slot's
/// contrast (§14.6.2). Adjacent CVD ΔE and adjacent normal ΔE are pair
/// comparisons between two series hues and do not move when the surface moves.
/// So the surface change alone invalidated nothing, and the hues move here
/// byte-for-byte.
///
/// ## What was decided, and why (carried from A10.2, still true)
///
/// **Colour follows the probe, never its role.** Probe 1 is orange whether
/// the user calls it the pit or the point. Re-roling a probe mid-cook must not
/// repaint the history behind it, and the OLED can only identify a probe by its
/// number. Role carries its weight through *form*: the pit is the reference
/// series (heaviest stroke, the alarm band, the target line).
///
/// **Identity does not rest on hue.** Each probe owns a stroke pattern — P1
/// solid, P2 dashed, P3 dotted, P4 dash-dot — which survives a monochrome
/// export, a photocopy, and the SSD1306.
///
/// **Yellow and red are excluded from the series set on purpose.** They are the
/// status hues; a series wearing one would impersonate an alarm.
///
/// ## Measurements
///
/// The dark hues, on the surface each is actually drawn on. The `card` column
/// is new (§14.6.2); it is the surface `SmokeCard` and therefore the chart
/// uses, so it is the one the validator now checks against:
///
/// | slot     | hue       | on `bg #07090E` | on `card #161C2A` |
/// | -------- | --------- | --------------- | ----------------- |
/// | P1 ember | `#D95926` | 5.13            | 4.38              |
/// | P2 violet| `#9085E9` | 6.37            | 5.45              |
/// | P3 green | `#008300` | 4.03            | 3.44              |
/// | P4 blue  | `#3987E5` | 5.47            | 4.68              |
///
/// All ≥ 3:1 on both. The ordering (all 24 permutations run through the
/// validator) maximises the minimum adjacent CVD ΔE at 26.0 dark, with ember
/// pinned to slot 1. The **light** values below are retained as the export /
/// print palette — CSV plots and share images render on paper-white, not on
/// the app's obsidian — and are not used in-app.
///
/// ## Standing obligation on any future retune (§14.6.3)
///
/// 1. No hue ships that has not been through the validator
///    (`app/test/design/series_palette_cvd_test.dart`), run against `card`,
///    on the adjacent pairlist, plus the status hues.
/// 2. Paste the measured table here; a hue whose measurements are not beside
///    it is not reviewable.
/// 3. The floor is the current dark adjacent-CVD ΔE of 26.0. If a pair drops
///    below it: permute the four slots (ember pinned → 6 orderings) first, then
///    re-step lightness, and only then change a family.
/// 4. Never lower the floor — the same rule the repo applies to the heap gate.
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

  /// A short, speakable name for the stroke — goldens and semantics read this,
  /// so a colour change is reviewable in text.
  String get strokeName => switch (dashArray) {
    null => 'solid',
    [8, 4] => 'dashed',
    [2, 5] => 'dotted',
    _ => 'dash-dot',
  };
}

/// The four probe slots, in fixed order, plus the chart's ink.
///
/// Slots are **never cycled**: there is no fifth probe, and if there ever were
/// it would not be a generated hue.
abstract final class ProbePalette {
  // Slot 1 — ember/orange. The pit's conventional jack.
  static const Color _orangeLight = Color(0xFFEB6834);
  static const Color _orangeDark = Color(0xFFD95926);
  // Slot 2 — violet.
  static const Color _violetLight = Color(0xFF4A3AA7);
  static const Color _violetDark = Color(0xFF9085E9);
  // Slot 3 — green (mode-invariant; clears 3:1 on both surfaces).
  static const Color _green = Color(0xFF008300);
  // Slot 4 — blue.
  static const Color _blueLight = Color(0xFF2A78D6);
  static const Color _blueDark = Color(0xFF3987E5);

  /// The dark hues in slot order, for the validator and for direct reads.
  static const List<Color> dark = [_orangeDark, _violetDark, _green, _blueDark];

  /// P1 solid, P2 dashed, P3 dotted, P4 dash-dot. Ordered by ink laid down, so
  /// the reference series is the strongest mark.
  static const List<List<int>?> strokes = [
    null,
    [8, 4],
    [2, 5],
    [10, 4, 2, 4],
  ];

  /// The hue for [probe] (1..4), dark surface. The mark colour, nothing else.
  static Color hue(int probe) => dark[(probe - 1).clamp(0, 3)];

  /// The **only** sanctioned fill of a series hue: the pit band sector and the
  /// gauge track. A series hue may otherwise appear only as a mark — a stroke,
  /// an arc, a ≤12 dp dot, a card's left rule — never as a filled shape and
  /// never carrying a word (the separation rule, [StatusPalette]).
  static Color tint(Color c) => c.withValues(alpha: 0.16);

  /// The style for [probe] (1..4) under [brightness]. [role] does not pick the
  /// hue — it only decides the weight, because the pit is the reference series.
  static ProbeStyle styleFor(
    int probe,
    Brightness brightness, {
    ProbeRole role = ProbeRole.unused,
  }) {
    final isDark = brightness == Brightness.dark;
    final i = (probe - 1).clamp(0, 3);
    final color = switch (i) {
      0 => isDark ? _orangeDark : _orangeLight,
      1 => isDark ? _violetDark : _violetLight,
      2 => _green,
      _ => isDark ? _blueDark : _blueLight,
    };
    return ProbeStyle(
      probe: probe,
      color: color,
      dashArray: strokes[i],
      strokeWidth: role == ProbeRole.pit ? 3 : 2,
    );
  }

  /// Chart chrome. Recessive by rule — the grid must never compete with the
  /// data, and at 3 a.m. in a dark yard neither must the axis.
  static Color grid(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF2C2C2A) : const Color(0xFFE1E0D9);

  static Color axisInk(Brightness b) => const Color(0xFF898781);

  /// The gap connector: a dotted hint that time passed, drawn in chrome ink
  /// rather than in the series colour so it can never be mistaken for data
  /// ("a 30-minute dropout must look like a 30-minute dropout").
  static Color gapInk(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF4A4A47) : const Color(0xFFBFBEB8);
}
