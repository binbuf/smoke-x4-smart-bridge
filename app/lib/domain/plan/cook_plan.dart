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
}
