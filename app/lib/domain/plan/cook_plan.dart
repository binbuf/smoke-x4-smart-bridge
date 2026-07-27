/// A22.1 — the cook plan (design 13 §13.3.1, §13.5.3).
///
/// A plan is what turns instrument mode into guided mode. Its presence — a
/// single nullable on the cook snapshot — is the whole switch: with a plan, a
/// probe wears a [target] and a pull tick; without one, it wears a sparkline.
///
/// The plan is app-tier. It never reaches the Smoke X base — the bridge
/// transmits exactly one packet per pairing (02 §2.5), so app targets are
/// advisory and drive the app's own alarms and the gauge, not the base's
/// beeper. Nothing here is written to the device except the probe roles/names,
/// which the bridge does persist.
library;

import 'hazard.dart';

/// One jack's job in a guided cook.
class PlanProbe {
  const PlanProbe({
    required this.jack,
    required this.isPit,
    required this.name,
    this.targetF10,
    this.pullF10,
  });

  /// 1..4 — the physical jack. Colour and history follow this, not the role.
  final int jack;

  /// The pit/ambient channel. At most one per plan.
  final bool isPit;

  /// A human name — the cut for a food probe, "Pit" for the pit.
  final String name;

  /// The doneness target, tenths °F. Null for the pit (which uses [CookPlan]'s
  /// band instead) and for a probe being watched without a target.
  final int? targetF10;

  /// Pull-early temperature, tenths °F: `target − restOffset`. Null when no
  /// target, or when the cut has no meaningful carry-over.
  final int? pullF10;

  Map<String, Object?> toJson() => {
    'jack': jack,
    'is_pit': isPit,
    'name': name,
    if (targetF10 != null) 'target_f10': targetF10,
    if (pullF10 != null) 'pull_f10': pullF10,
  };

  static PlanProbe fromJson(Map<String, Object?> j) => PlanProbe(
    jack: (j['jack'] as num?)?.toInt() ?? 0,
    isPit: j['is_pit'] as bool? ?? false,
    name: j['name'] as String? ?? '',
    targetF10: (j['target_f10'] as num?)?.toInt(),
    pullF10: (j['pull_f10'] as num?)?.toInt(),
  );
}

/// A guided cook: what is being cooked, to what doneness, and how the jacks map.
///
/// **The constructor is a food-safety gate.** A food probe's [PlanProbe.targetF10]
/// below its protein's [SafetyFloor] throws [ArgumentError] — the refusal the
/// owner asked for (U3). Whole-muscle red meat has no floor, so a rare steak
/// constructs freely.
class CookPlan {
  CookPlan({
    required this.presetId,
    required this.title,
    required this.hazard,
    required this.doneness,
    required this.probes,
    this.pitBandMinF10,
    this.pitBandMaxF10,
  }) {
    final floor = SafetyFloor.forClass(hazard);
    if (floor != null) {
      for (final p in probes) {
        final t = p.targetF10;
        if (!p.isPit && t != null && t < floor.minF10) {
          throw ArgumentError.value(
            t,
            'probes[${p.jack}].targetF10',
            'below the ${hazard.name} safe minimum of ${floor.minF10 / 10}°F'
                '${floor.source == null ? '' : ' (${floor.source})'}',
          );
        }
      }
    }
  }

  /// Stable id of the preset this plan came from, or `custom`.
  final String presetId;

  /// What the header says: "Texas brisket", "Ribeye — medium rare".
  final String title;

  final HazardClass hazard;

  /// The chosen doneness label ("medium rare", "pitmaster shred").
  final String doneness;

  /// The four jacks (or fewer), in jack order.
  final List<PlanProbe> probes;

  /// The pit target band, tenths °F. Null renders the pit gauge in sweep mode.
  final int? pitBandMinF10;
  final int? pitBandMaxF10;

  /// The rest advice for this plan's protein, if any (surfaced in the sheet).
  SafetyFloor? get floor => SafetyFloor.forClass(hazard);

  /// The pit probe, if the plan names one.
  PlanProbe? get pit {
    for (final p in probes) {
      if (p.isPit) {
        return p;
      }
    }
    return null;
  }

  /// When the cook was started, so the header's elapsed clock survives a
  /// restart. Millis since epoch; 0 in a plan built before this field existed
  /// (which then simply falls back to the snapshot's own elapsed count).
  int startedUnixMs = 0;

  // ── persistence (13 §13.3.1) ────────────────────────────────────────
  //
  // A guided cook is the app's central promise and it used to live in one
  // `CookPlan? _plan` field on a State object: an OS kill at hour nine of an
  // eighteen-hour brisket dropped the user silently back into instrument
  // mode, targets and gauges and name gone, with no way to tell that had
  // happened. The plan is small and flat, so it round-trips through prefs
  // rather than earning a drift table.

  Map<String, Object?> toJson() => {
    'preset_id': presetId,
    'title': title,
    'hazard': hazard.name,
    'doneness': doneness,
    'probes': [for (final p in probes) p.toJson()],
    if (pitBandMinF10 != null) 'pit_band_min_f10': pitBandMinF10,
    if (pitBandMaxF10 != null) 'pit_band_max_f10': pitBandMaxF10,
    'started_unix_ms': startedUnixMs,
  };

  /// Rebuilds a plan from [toJson]. Returns null rather than throwing on
  /// anything malformed — a plan that cannot be read is a cook that shows in
  /// instrument mode, which is a degradation; a throw here is a launch that
  /// never renders, which is a bug report.
  ///
  /// Note this runs the same food-safety gate the constructor does, so a
  /// stored plan that would now be refused (a floor that moved between
  /// releases) is dropped rather than restored.
  static CookPlan? fromJson(Map<String, Object?> j) {
    try {
      final hazardName = j['hazard'] as String?;
      final hazard = HazardClass.values.firstWhere(
        (h) => h.name == hazardName,
        orElse: () => HazardClass.wholeMuscleRedMeat,
      );
      final raw = j['probes'];
      if (raw is! List) {
        return null;
      }
      final plan = CookPlan(
        presetId: j['preset_id'] as String? ?? 'custom',
        title: j['title'] as String? ?? '',
        hazard: hazard,
        doneness: j['doneness'] as String? ?? '',
        probes: [
          for (final p in raw)
            if (p is Map<String, Object?>) PlanProbe.fromJson(p),
        ],
        pitBandMinF10: (j['pit_band_min_f10'] as num?)?.toInt(),
        pitBandMaxF10: (j['pit_band_max_f10'] as num?)?.toInt(),
      );
      plan.startedUnixMs = (j['started_unix_ms'] as num?)?.toInt() ?? 0;
      return plan;
    } on Object {
      return null;
    }
  }
}
