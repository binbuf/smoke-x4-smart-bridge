/// N1.3 — how current a reading is.
///
/// **Never present stale data as current (I4).** Past [stale] the widget must
/// *remove* derived values (trend, ETA, a projected range) rather than grey
/// them: a greyed ETA is still a number someone will act on. [showsDerived]
/// ([canShowDerived]) is the gate every derived readout passes through, and the
/// "stale removes ETA" invariant is pinned by a named test.
///
/// The ladder, from `components_research_notes.md` I4:
///   ≤ 45 s [live] · ≤ 90 s [aging] · ≤ 600 s [stale] · > 600 s [frozen]
/// plus [unknown] for "no reading at all", which is distinct from a reading
/// that has merely aged.
library;

/// The freshness ladder.
enum Freshness {
  /// ≤ 45 s. Full ink, everything shown.
  live,

  /// ≤ 90 s. Full ink; update age is stated.
  aging,

  /// ≤ 600 s. Dim, derived values removed.
  stale,

  /// > 600 s, or the bridge says the base went quiet. A `LAST` chip.
  frozen,

  /// No timestamped reading yet. Distinct from aged; absent is not zero.
  unknown;

  static const int liveMaxS = 45;
  static const int agingMaxS = 90;
  static const int staleMaxS = 600;

  /// The ladder from an age in seconds and the bridge's own base-lost flag.
  ///
  /// A null [ageS] is [unknown]; [baseLost] outranks the arithmetic because
  /// the phone may be hearing the bridge perfectly while the *base station*
  /// has stopped measuring.
  static Freshness fromAge(int? ageS, {bool baseLost = false}) {
    if (baseLost) {
      return Freshness.frozen;
    }
    if (ageS == null) {
      return Freshness.unknown;
    }
    if (ageS <= liveMaxS) {
      return Freshness.live;
    }
    if (ageS <= agingMaxS) {
      return Freshness.aging;
    }
    if (ageS <= staleMaxS) {
      return Freshness.stale;
    }
    return Freshness.frozen;
  }

  /// Whether a derived readout (trend, ETA, projection) may be shown at all.
  /// This is the I4 gate.
  bool get showsDerived => this == Freshness.live || this == Freshness.aging;

  /// Alias kept for the contract vocabulary in the task (`canShowDerived`).
  bool get canShowDerived => showsDerived;

  /// Whether the reading is dimmed and should not be read as current.
  bool get isDim => this == Freshness.stale || this == Freshness.frozen;

  /// Ink opacity for the reading, per the ladder.
  double get ink => switch (this) {
    Freshness.live || Freshness.aging => 1,
    Freshness.stale => 0.55,
    Freshness.frozen => 0.4,
    Freshness.unknown => 0.55,
  };

  String get label => switch (this) {
    Freshness.live => 'Live',
    Freshness.aging => 'Aging',
    Freshness.stale => 'Stale',
    Freshness.frozen => 'No signal',
    Freshness.unknown => 'No reading',
  };
}
