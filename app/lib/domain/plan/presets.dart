/// N1.6/N1.7 — donorness ladders, carryover and pull temperatures.
///
/// **Targets are post-rest finals.** The pull temperature is therefore
/// `target − carryover`, and carryover comes from the cut's *thickness*, not
/// from how done it is: a 1″ steak coasts a degree or two, a 4–6″ roast coasts
/// five to ten. That is a property of mass.
///
/// Two hard rules:
///  * **Poultry carryover is always zero** — USDA is explicit that you cannot
///    rely on carryover to bring an under-cooked bird up to 165 °F.
///  * **Carryover never crosses a safety floor** — `pullTempFor` clamps at the
///    enforced minimum, because "take it off early and let it coast" is the
///    promise USDA declines to make for pork and poultry.
///
/// Temperatures are tenths of °F throughout, the storage-canonical unit.
library;

import 'hazard.dart';

/// How much thermal mass the cut has — the only thing carryover depends on.
enum CutThickness {
  /// ~1″: steaks, chops, chicken pieces, fillets.
  thin,

  /// ~2–3″: thick-cut steaks, small roasts, tenderloin.
  medium,

  /// 4–6″: prime rib, brisket, shoulder, whole birds.
  thick,

  /// Sous-vide: already isothermal with the bath, so no carryover.
  sousVide;

  String get label => switch (this) {
    CutThickness.thin => 'Thin',
    CutThickness.medium => 'Medium',
    CutThickness.thick => 'Thick',
    CutThickness.sousVide => 'Sous vide',
  };

  String get blurb => switch (this) {
    CutThickness.thin =>
      'About an inch — a steak, a chop, a chicken piece, a fillet. It coasts a '
          'degree or two off the heat.',
    CutThickness.medium =>
      'Two to three inches — a thick-cut steak, a small roast, a tenderloin.',
    CutThickness.thick =>
      'Four inches or more — a prime rib, a brisket, a shoulder, a whole bird. '
          'It keeps climbing 5 to 10°F after it comes off.',
    CutThickness.sousVide =>
      'In a water bath. It is already the temperature of the bath, so there is '
          'no carryover to allow for.',
  };
}

/// Carryover for a cut, tenths °F.
///
/// **Poultry is always zero**, whatever the thickness. Shared by presets and
/// custom cooks so the two cannot disagree about how far a roast coasts.
int carryoverFor({
  required HazardClass hazard,
  required CutThickness thickness,
}) => switch (hazard) {
  HazardClass.poultry => 0,
  _ => switch (thickness) {
    CutThickness.thin => 20,
    CutThickness.medium => 50,
    CutThickness.thick => 80,
    CutThickness.sousVide => 0,
  },
};

/// The pull-early temperature for [targetF10], tenths °F — and **never below
/// the enforced safe minimum**.
///
/// The offset is clamped at the floor: a 160 °F ground-beef target on a thick
/// patty pulls at 160 °F, not 152 °F. Intact whole-muscle red meat in
/// enthusiast mode has no floor, so a medium-rare roast still comes off early.
int pullTempFor({
  required int targetF10,
  required int carryoverF10,
  required HazardClass hazard,
  bool isIntact = true,
  SafetyMode mode = SafetyMode.enthusiast,
}) {
  final pull = targetF10 - carryoverF10;
  final floor = SafetyFloor.forClass(hazard, isIntact: isIntact, mode: mode);
  if (floor != null && pull < floor.minF10) {
    // Clamp, never raise: a target already above the floor keeps its offset.
    return targetF10 < floor.minF10 ? targetF10 : floor.minF10;
  }
  return pull;
}

/// How long a cut with this much carryover should rest, in seconds.
///
/// Derived from carryover rather than a second thickness field. [safetyRestS]
/// is the USDA floor and is a **minimum**, never a maximum.
int restSecondsFor({required int carryoverF10, int safetyRestS = 0}) {
  final byMass = switch (carryoverF10) {
    <= 0 => 0,
    <= 20 => 5 * 60,
    <= 50 => 10 * 60,
    _ => 20 * 60,
  };
  return byMass > safetyRestS ? byMass : safetyRestS;
}

/// A single doneness level within a preset. [targetF10] is the **final,
/// post-rest** temperature; the pull temperature is derived, never stored twice.
class Doneness {
  const Doneness({
    required this.id,
    required this.label,
    required this.targetF10,
    this.restOffsetF10,
  });

  final String id;
  final String label;

  /// Internal target, tenths °F — where the meat ends up after resting.
  final int targetF10;

  /// Carryover override, tenths °F. Null means "use the cut's thickness".
  final int? restOffsetF10;
}

/// The doneness ladder for whole-muscle red meat, as MEATER publishes it —
/// final (post-rest) temperatures.
abstract final class DonenessLadder {
  static const Doneness rare = Doneness(
    id: 'rare',
    label: 'Rare',
    targetF10: 1250,
  );
  static const Doneness mediumRare = Doneness(
    id: 'medrare',
    label: 'Medium rare',
    targetF10: 1350,
  );
  static const Doneness medium = Doneness(
    id: 'medium',
    label: 'Medium',
    targetF10: 1450,
  );
  static const Doneness mediumWell = Doneness(
    id: 'medwell',
    label: 'Medium well',
    targetF10: 1550,
  );
  static const Doneness wellDone = Doneness(
    id: 'well',
    label: 'Well done',
    targetF10: 1650,
  );

  static const List<Doneness> steak = [
    rare,
    mediumRare,
    medium,
    mediumWell,
    wellDone,
  ];
}

/// A protein cut with its doneness options and a recommended pit band.
class CookPreset {
  const CookPreset({
    required this.id,
    required this.category,
    required this.name,
    required this.hazard,
    required this.doneness,
    required this.pitBandMinF10,
    required this.pitBandMaxF10,
    this.thickness = CutThickness.medium,
    this.isIntact = true,
    this.blurb = '',
  });

  final String id;

  /// "Beef" · "Pork" · "Poultry" · "Fish" … — the chip a user taps first.
  final String category;
  final String name;
  final HazardClass hazard;
  final List<Doneness> doneness;

  /// Recommended pit target band, tenths °F.
  final int pitBandMinF10;
  final int pitBandMaxF10;

  /// Drives carryover. Not a doneness property.
  final CutThickness thickness;

  /// Whether this cut is intact whole-muscle. False forces the ground floor on
  /// red meat.
  final bool isIntact;

  /// One line under the name in the picker.
  final String blurb;

  /// Carryover for this cut, tenths °F.
  int get carryoverF10 => carryoverFor(hazard: hazard, thickness: thickness);

  /// The default doneness. **Red meat defaults to medium rare** per the brief;
  /// low-and-slow proteins default to their last (probe-tender) level.
  Doneness get defaultDoneness {
    if (hazard == HazardClass.wholeMuscleRedMeat) {
      for (final d in doneness) {
        if (d.id == DonenessLadder.mediumRare.id) {
          return d;
        }
      }
    }
    if (doneness.length >= 3 && hazard == HazardClass.wholeMuscleRedMeat) {
      return doneness[doneness.length ~/ 2];
    }
    return doneness.last;
  }

  /// Pull temperature for [d] on this cut, tenths °F, floor-clamped.
  int pullF10For(Doneness d, {SafetyMode mode = SafetyMode.enthusiast}) =>
      pullTempFor(
        targetF10: d.targetF10,
        carryoverF10: d.restOffsetF10 ?? carryoverF10,
        hazard: hazard,
        isIntact: isIntact,
        mode: mode,
      );

  /// The doneness whose [Doneness.id] is [id], or null.
  Doneness? donenessById(String id) {
    for (final d in doneness) {
      if (d.id == id) {
        return d;
      }
    }
    return null;
  }
}
