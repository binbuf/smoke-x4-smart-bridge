/// N1.16 — the guided cook, and the food-safety gate.
///
/// The plan's presence is the whole switch from instrument mode to guided mode.
/// It is app-tier: it never reaches the Smoke X base, so its targets are
/// advisory and drive the app's own gauges and alarms.
///
/// **The constructor is the gate (I12).** A food jack whose target is below its
/// protein's [SafetyFloor] throws [ArgumentError] — a refusal, not a warning.
/// [CookPlan.fromJson] builds through the same constructor, so a stored plan
/// that would now be refused is dropped rather than restored.
library;

import '../entities/probe.dart';
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
  final ProbeJack jack;

  /// The pit/ambient channel. At most one per plan.
  final bool isPit;

  /// The full role — what a custom cook edits.
  final ProbeRole role;

  /// A human name — the cut for a food probe, "Pit" for the pit.
  final String name;

  /// Doneness target, tenths °F. Null for the pit or an untargeted probe.
  final int? targetF10;

  /// Pull-early temperature, tenths °F. Null when no target/no offset.
  final int? pullF10;

  /// Per-jack hazard override for a mixed cook. Null takes the plan's.
  final HazardClass? hazard;

  /// False forces the ground-meat floor on red meat.
  final bool isIntact;

  /// The doneness label for this jack ('' takes the plan's).
  final String doneness;

  /// The carryover this jack is pulling early by, tenths °F.
  int get carryoverF10 =>
      targetF10 == null || pullF10 == null ? 0 : targetF10! - pullF10!;

  Map<String, Object?> toJson() => {
    'jack': jack.n,
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
      jack: ProbeJack.fromN((j['jack'] as num?)?.toInt() ?? 0) ?? ProbeJack.one,
      isPit: isPit,
      role: roleName == null
          ? null
          : ProbeRole.values.where((r) => r.name == roleName).firstOrNull,
      name: j['name'] as String? ?? '',
      targetF10: (j['target_f10'] as num?)?.toInt(),
      pullF10: (j['pull_f10'] as num?)?.toInt(),
      hazard: switch (j['hazard'] as String?) {
        final String n =>
          HazardClass.values.where((h) => h.name == n).firstOrNull,
        _ => null,
      },
      isIntact: j['is_intact'] as bool? ?? true,
      doneness: j['doneness'] as String? ?? '',
    );
  }
}

/// A guided cook: what is being cooked, to what doneness, and how jacks map.
///
/// **The constructor is a food-safety gate.** The gate runs **per jack**, not
/// per plan: a custom cook can carry a ribeye and chicken thighs at once, and
/// one shared hazard would either refuse the steak or wave the chicken through.
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
          'probes[${p.jack.n}].targetF10',
          '${(t / 10).round()}°F is below the '
              '${(floor.minF10 / 10).round()}°F safe minimum for ${h.phrase}'
              '${floor.source == null ? '' : ' (${floor.source})'}.',
        );
      }
    }
  }

  final SafetyMode safetyMode;

  /// Stable id of the preset this plan came from, or `custom`.
  final String presetId;
  final String title;
  final HazardClass hazard;
  final String doneness;
  final List<PlanProbe> probes;

  /// Pit target band, tenths °F. Null renders the pit gauge in sweep mode.
  final int? pitBandMinF10;
  final int? pitBandMaxF10;

  /// When the cook was started. Millis since epoch; 0 when not yet started.
  int startedUnixMs = 0;

  /// Rest advice for this plan's protein, if any.
  SafetyFloor? get floor =>
      SafetyFloor.forClass(hazard, isIntact: isIntact, mode: safetyMode);

  /// True while every food jack claims to be intact.
  bool get isIntact => probes.every((p) => p.isPit || p.isIntact);

  /// Whether to show the tenderized-cut caveat.
  bool get needsIntactAdvisory => probes.any(
    (p) =>
        !p.isPit &&
        p.targetF10 != null &&
        SafetyFloor.needsIntactAdvisory(
          p.hazard ?? hazard,
          isIntact: p.isIntact,
        ),
  );

  /// The safety strip, ready to render.
  List<String> get safetyStripLines =>
      safetyStripFor(intactRedMeat: needsIntactAdvisory);

  PlanProbe? get pit {
    for (final p in probes) {
      if (p.isPit) {
        return p;
      }
    }
    return null;
  }

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

  /// True while no food jack carries a target — "start now, target later".
  bool get hasNoTarget =>
      probes.where((p) => !p.isPit).every((p) => p.targetF10 == null);

  /// Re-runs the gate, so an unsafe retarget throws exactly like a fresh plan.
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
    return next;
  }

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
  };

  /// Rebuilds a plan from [toJson], **running the same gate**. Returns null
  /// rather than throwing on anything malformed or now-unsafe: a plan that
  /// cannot be read is a cook that shows in instrument mode, not a crash.
  static CookPlan? fromJson(Map<String, Object?> j) {
    try {
      final hazardName = j['hazard'] as String?;
      final hazard = HazardClass.values.firstWhere(
        (h) => h.name == hazardName,
        orElse: () => HazardClass.unstated,
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
            if (p is Map) PlanProbe.fromJson(p.cast<String, Object?>()),
        ],
        pitBandMinF10: (j['pit_band_min_f10'] as num?)?.toInt(),
        pitBandMaxF10: (j['pit_band_max_f10'] as num?)?.toInt(),
        safetyMode:
            SafetyMode.values
                .where((m) => m.name == j['safety_mode'])
                .firstOrNull ??
            SafetyMode.enthusiast,
      );
      plan.startedUnixMs = (j['started_unix_ms'] as num?)?.toInt() ?? 0;
      return plan;
    } on Object {
      return null;
    }
  }
}
