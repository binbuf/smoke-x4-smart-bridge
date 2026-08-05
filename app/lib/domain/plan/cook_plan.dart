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

import '../entities/entities.dart' show ProbeRole;
import 'hazard.dart';

/// One jack's job in a guided cook.
class PlanProbe {
  PlanProbe({
    required this.jack,
    required this.isPit,
    required this.name,
    this.targetF10,
    this.pullF10,
    this.hazard,
    this.isIntact = true,
    this.doneness = '',
    ProbeRole? role,
  }) : role = role ?? (isPit ? ProbeRole.pit : ProbeRole.food);

  /// 1..4 — the physical jack. Colour and history follow this, not the role.
  final int jack;

  /// The pit/ambient channel. At most one per plan.
  final bool isPit;

  /// The full role. [isPit] is the two-state question the gauges ask; this is
  /// the four-state one the settings tree and `ambient_*` alarm rules need,
  /// and it is what a custom cook edits.
  final ProbeRole role;

  /// A human name — the cut for a food probe, "Pit" for the pit.
  final String name;

  /// The doneness target, tenths °F. Null for the pit (which uses [CookPlan]'s
  /// band instead) and for a probe being watched without a target.
  final int? targetF10;

  /// Pull-early temperature, tenths °F: `target − carryover`. Null when no
  /// target, or when the cut has no meaningful carry-over.
  final int? pullF10;

  /// Per-jack hazard override, for a custom cook running two proteins at once
  /// (chicken thighs on jack 2, a ribeye on jack 3). Null takes the plan's.
  final HazardClass? hazard;

  /// Whether this cut is intact whole-muscle. False forces the ground-meat
  /// floor on red meat — the tenderized/injected case (§D.4).
  final bool isIntact;

  /// The doneness label for this jack ('' takes the plan's).
  final String doneness;

  /// The carryover this jack is pulling early by, tenths °F. 0 when there is
  /// no target or no offset.
  int get carryoverF10 =>
      targetF10 == null || pullF10 == null ? 0 : targetF10! - pullF10!;

  Map<String, Object?> toJson() => {
    'jack': jack,
    'is_pit': isPit,
    'role': role.name,
    'name': name,
    if (targetF10 != null) 'target_f10': targetF10,
    if (pullF10 != null) 'pull_f10': pullF10,
    if (hazard != null) 'hazard': hazard!.name,
    if (!isIntact) 'is_intact': false,
    if (doneness.isNotEmpty) 'doneness': doneness,
  };

  static PlanProbe fromJson(Map<String, Object?> j) {
    final isPit = j['is_pit'] as bool? ?? false;
    final roleName = j['role'] as String?;
    return PlanProbe(
      jack: (j['jack'] as num?)?.toInt() ?? 0,
      isPit: isPit,
      role: roleName == null
          ? null
          : ProbeRole.values.where((r) => r.name == roleName).firstOrNull,
      name: j['name'] as String? ?? '',
      targetF10: (j['target_f10'] as num?)?.toInt(),
      pullF10: (j['pull_f10'] as num?)?.toInt(),
      hazard: switch (j['hazard'] as String?) {
        final String n => HazardClass.values
            .where((h) => h.name == n)
            .firstOrNull,
        _ => null,
      },
      isIntact: j['is_intact'] as bool? ?? true,
      doneness: j['doneness'] as String? ?? '',
    );
  }

  PlanProbe copyWith({
    String? name,
    int? targetF10,
    int? pullF10,
    bool clearTarget = false,
    HazardClass? hazard,
    bool? isIntact,
    String? doneness,
    ProbeRole? role,
  }) => PlanProbe(
    jack: jack,
    isPit: role == null ? isPit : role == ProbeRole.pit,
    role: role ?? this.role,
    name: name ?? this.name,
    targetF10: clearTarget ? null : (targetF10 ?? this.targetF10),
    pullF10: clearTarget ? null : (pullF10 ?? this.pullF10),
    hazard: hazard ?? this.hazard,
    isIntact: isIntact ?? this.isIntact,
    doneness: doneness ?? this.doneness,
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
    this.safetyMode = SafetyMode.enthusiast,
  }) {
    // The gate runs **per jack**, not per plan: a custom cook can carry a
    // ribeye and chicken thighs at once, and one shared hazard would either
    // refuse the steak or wave the chicken through.
    for (final p in probes) {
      final t = p.targetF10;
      if (p.isPit || t == null) {
        continue;
      }
      final h = p.hazard ?? hazard;
      final floor = SafetyFloor.forClass(
        h,
        isIntact: p.isIntact,
        mode: safetyMode,
      );
      if (floor != null && t < floor.minF10) {
        throw ArgumentError.value(
          t,
          'probes[${p.jack}].targetF10',
          'below the ${h.name} safe minimum of ${floor.minF10 / 10}°F'
              '${floor.source == null ? '' : ' (${floor.source})'}',
        );
      }
    }
  }

  /// Which reading of "safe" this plan was built under (§D.4). Only ever
  /// relaxes intact whole-muscle red meat.
  final SafetyMode safetyMode;

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
  SafetyFloor? get floor =>
      SafetyFloor.forClass(hazard, isIntact: isIntact, mode: safetyMode);

  /// True while every food jack claims to be an intact cut. One needled steak
  /// on jack 3 makes the whole plan non-intact for advisory purposes.
  bool get isIntact => probes.every((p) => p.isPit || p.isIntact);

  /// Whether to show [intactCutAdvisory] — a red-meat plan the app is taking
  /// the user's word about.
  bool get needsIntactAdvisory => probes.any(
    (p) =>
        !p.isPit &&
        p.targetF10 != null &&
        SafetyFloor.needsIntactAdvisory(
          p.hazard ?? hazard,
          isIntact: p.isIntact,
        ),
  );

  /// The pit probe, if the plan names one.
  PlanProbe? get pit {
    for (final p in probes) {
      if (p.isPit) {
        return p;
      }
    }
    return null;
  }

  /// The primary food probe — the one the guided overlay heroes.
  PlanProbe? get primaryFood {
    for (final p in probes) {
      if (!p.isPit && p.targetF10 != null) {
        return p;
      }
    }
    for (final p in probes) {
      if (!p.isPit) {
        return p;
      }
    }
    return null;
  }

  /// True while no food jack carries a target — the "start now, target later"
  /// state (§D.3.2), which the reader surfaces as a persistent affordance
  /// rather than as an incomplete-looking cook.
  bool get hasNoTarget =>
      probes.where((p) => !p.isPit).every((p) => p.targetF10 == null);

  /// §D.4 — editing a **running** cook is allowed. Re-runs the gate, so a
  /// retarget that would be unsafe throws exactly like a fresh plan would.
  CookPlan copyWith({
    String? title,
    String? doneness,
    List<PlanProbe>? probes,
    int? pitBandMinF10,
    int? pitBandMaxF10,
    HazardClass? hazard,
    SafetyMode? safetyMode,
  }) {
    final next = CookPlan(
      presetId: presetId,
      title: title ?? this.title,
      hazard: hazard ?? this.hazard,
      doneness: doneness ?? this.doneness,
      probes: probes ?? this.probes,
      pitBandMinF10: pitBandMinF10 ?? this.pitBandMinF10,
      pitBandMaxF10: pitBandMaxF10 ?? this.pitBandMaxF10,
      safetyMode: safetyMode ?? this.safetyMode,
    );
    next.startedUnixMs = startedUnixMs;
    next.cookId = cookId;
    return next;
  }

  /// When the cook was started, so the header's elapsed clock survives a
  /// restart. Millis since epoch; 0 in a plan built before this field existed
  /// (which then simply falls back to the snapshot's own elapsed count).
  int startedUnixMs = 0;

  /// The `Cooks` row this plan projects, once it has one (§D.1). Null for a
  /// plan built in a sheet and not yet committed, and for plans restored from
  /// a build that predates the annotation table — in both cases the app falls
  /// back to prefs-only behaviour rather than failing.
  int? cookId;

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
    'safety_mode': safetyMode.name,
    if (cookId != null) 'cook_id': cookId,
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
        // A plan stored before modes existed was built under the old
        // "red meat has no floor" rule, which is the enthusiast reading —
        // restoring it as USDA-compliant would drop a valid medium-rare cook.
        safetyMode: SafetyMode.values
            .where((m) => m.name == j['safety_mode'])
            .firstOrNull ??
            SafetyMode.enthusiast,
      );
      plan.startedUnixMs = (j['started_unix_ms'] as num?)?.toInt() ?? 0;
      plan.cookId = (j['cook_id'] as num?)?.toInt();
      return plan;
    } on Object {
      return null;
    }
  }
}
