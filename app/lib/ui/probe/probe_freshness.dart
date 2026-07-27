/// A19.6 — how fresh a reading is, as far as a probe widget must know
/// (design 14 §14.7, 13 §13.6.1).
///
/// The shell's truth model (W5) owns the real `Freshness` and the clocks behind
/// it. The `ui/` layer must not depend on the shell, so it takes this small
/// mirror: enough for a card to obey the rendering ladder (dim at stale, remove
/// derived values, drop to a `LAST` chip at frozen) without knowing where the
/// number came from.
library;

/// The rendering-ladder levels (13 §13.6.1). A value never outlives its source:
/// derived readouts are *removed*, not greyed, from [stale] down.
enum ProbeFreshness {
  /// ≤ 45 s. Full ink, animating pulse, everything shown.
  live,

  /// ≤ 90 s. Full ink, pulse static, "updated 1m ago".
  aging,

  /// ≤ 10 min. 55% ink, derived values removed, amber hairline.
  stale,

  /// > 10 min (the firmware's `base_lost_s`). 40% ink, a `LAST` chip.
  frozen,

  /// No reading yet. Dashed, "no reading yet".
  unknown;

  bool get showsDerived => this == live || this == aging;
  bool get isDim => this == stale || this == frozen;

  double get ink => switch (this) {
    live || aging => 1.0,
    stale => 0.55,
    frozen => 0.40,
    unknown => 0.55,
  };
}
