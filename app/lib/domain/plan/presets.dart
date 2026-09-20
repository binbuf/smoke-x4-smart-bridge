/// A22.1 — the preset library (design 13 §13.5.3; carryover per newapp §D.4).
///
/// The starter set of proteins and doneness levels the cook-setup sheet offers.
/// Targets and rest offsets overlap the prototype's modal where they meet
/// (`docs/ui/index.html`: brisket 203/198, ribeye 135/130, pork butt 201/196,
/// turkey 165/161) and are extended sensibly beyond it.
///
/// **This table needs a named reviewer before it ships** — it is food-safety
/// data, and 13 §13.5.3 records that assignment as open. Every doneness here
/// runs through [CookPlan]'s constructor, so a value below a hazard floor is a
/// build-time failure, not a runtime surprise (see `plan_test.dart`).
///
/// **Targets are post-rest finals, and carryover is not double-counted.** The
/// doneness ladder follows MEATER's published convention (rare 125 °F,
/// medium-rare 135, medium 145, medium-well 155, well 165) which is stated as
/// the temperature the meat *ends at*. The pull temperature is therefore
/// `target − carryover`, and carryover comes from the cut's thickness
/// ([CutThickness]) rather than being guessed per doneness — AmazingRibs
/// measures a 1″ steak gaining "a degree or two" against a 4–6″ prime rib
/// gaining 5–10 °F, which is a property of the mass, not of how done it is.
///
/// **Carryover never crosses a safety floor.** `target − carryover` is clamped
/// at the enforced minimum ([safePullF10]), because "take it off early and let
/// it coast up" is precisely the promise USDA declines to make about poultry,
/// and its pork and whole-cut wording is 145 °F *before* the meat leaves the
/// heat. The offset is a doneness convenience on cuts that have no floor, not a
/// way under one that does.
///
/// Temperatures are tenths of °F throughout, the storage-canonical unit.
library;

import 'hazard.dart';

/// How much thermal mass the cut has, which is the only thing carryover
/// actually depends on. Poultry overrides this to zero — see [carryoverF10].
enum CutThickness {
  /// ~1″: steaks, chops, chicken pieces, fillets.
  thin,

  /// ~2–3″: thick-cut steaks, small roasts, tenderloin.
  medium,

  /// 4–6″: prime rib, brisket, pork shoulder, whole birds.
  thick,

  /// Sous-vide. ThermoWorks is explicit: there is **no** carryover, because
  /// the food is already isothermal with the bath.
  sousVide;

  /// The chip's word. Thickness is the honest question to ask a custom cook —
  /// §D.4 derives carryover from mass, not from doneness — so the picker asks
  /// about the cut, never "how many degrees would you like to pull early?".
  String get label => switch (this) {
    CutThickness.thin => 'Thin',
    CutThickness.medium => 'Medium',
    CutThickness.thick => 'Thick',
    CutThickness.sousVide => 'Sous vide',
  };

  /// The sentence under the chips, naming a real cut so the choice is
  /// answerable by looking at the food rather than by guessing a number.
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

/// Carryover for a cut, tenths °F — the one place thickness becomes a number.
///
/// Shared by [CookPreset.carryoverF10] and by the custom-cook path in the setup
/// sheet. A preset and a hand-built cook that disagreed about how far a 4″ roast
/// coasts would be a drift nobody notices until a roast comes out grey.
///
/// **Poultry is always zero**, whatever the thickness: USDA is explicit that you
/// cannot rely on carryover to bring an under-cooked bird up to 165 °F, so the
/// app verifies poultry by sensor and never predicts it upward.
int carryoverF10For({
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
/// Carryover says "take it off early and let it coast up". Where a hard floor
/// exists, that is exactly the promise USDA says you may not make: FSIS's pork
/// and whole-cut wording is 145 °F *"before removing meat from the heat
/// source"*, and its poultry guidance is that carryover cannot be relied on to
/// finish an under-cooked bird. So the offset is clamped at the floor: a
/// 160 °F ground-beef target on a thick patty pulls at 160 °F, not 152 °F.
///
/// Intact whole-muscle red meat in enthusiast mode has no floor, so nothing is
/// clamped there — a medium-rare roast still comes off 8 °F early, which is the
/// case carryover was measured for (AmazingRibs, ThermoWorks).
int safePullF10({
  required int targetF10,
  required int carryoverF10,
  required HazardClass hazard,
  bool isIntact = true,
  SafetyMode mode = SafetyMode.enthusiast,
}) {
  final pull = targetF10 - carryoverF10;
  final floor = SafetyFloor.forClass(hazard, isIntact: isIntact, mode: mode);
  if (floor != null && pull < floor.minF10) {
    // Clamp, never raise: a target already above the floor keeps its offset,
    // and one at the floor simply loses it.
    return targetF10 < floor.minF10 ? targetF10 : floor.minF10;
  }
  return pull;
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

  /// Carry-over override, tenths °F. Null means "use the cut's thickness",
  /// which is the right answer for every preset here; the override exists so a
  /// custom cook can say something the thickness table cannot.
  final int? restOffsetF10;

  // There is deliberately no `pullF10Against` here any more. It computed
  // `target − carryover` with no knowledge of the hazard, which is exactly the
  // subtraction that can hand someone an under-cooked bird; the derivation
  // lives in [safePullF10], where the floor is in scope.
}

/// The doneness ladder for whole-muscle red meat, as MEATER publishes it —
/// final (post-rest) temperatures. Kept as one named table so a preset that
/// wants "the usual four" cannot drift a degree away from a preset that wants
/// "the usual five".
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

  /// "Beef" · "Pork" · "Poultry" · "Fish" — the chip a user taps first.
  final String category;
  final String name;
  final HazardClass hazard;
  final List<Doneness> doneness;

  /// Recommended pit target band, tenths °F.
  final int pitBandMinF10;
  final int pitBandMaxF10;

  /// Drives carryover (§D.4). Not a doneness property — a thick roast coasts
  /// whether you want it rare or well.
  final CutThickness thickness;

  /// Whether this cut is whole-muscle and un-needled. Only consulted for
  /// [HazardClass.wholeMuscleRedMeat]; false forces the 160 °F ground floor.
  /// Presets ship `true` and the cook sheet lets the user say otherwise,
  /// because only the person holding the packet knows.
  final bool isIntact;

  /// One line under the name in the picker.
  final String blurb;

  /// Carryover for this cut, tenths °F. Delegates so a preset and a custom cook
  /// cannot disagree — see [carryoverF10For], which also explains why poultry
  /// is always zero.
  int get carryoverF10 =>
      carryoverF10For(hazard: hazard, thickness: thickness);

  /// The default doneness: the last level for low-and-slow proteins whose only
  /// real answer is "probe-tender", the middle for steaks.
  Doneness get defaultDoneness =>
      hazard == HazardClass.wholeMuscleRedMeat && doneness.length >= 3
      ? doneness[doneness.length ~/ 2]
      : doneness.last;

  /// Pull temperature for [d] on this cut, tenths °F, floor-clamped — a preset
  /// may not talk the user into taking ground beef off at 152 °F either.
  int pullF10For(Doneness d, {SafetyMode mode = SafetyMode.enthusiast}) =>
      safePullF10(
        targetF10: d.targetF10,
        carryoverF10: d.restOffsetF10 ?? carryoverF10,
        hazard: hazard,
        isIntact: isIntact,
        mode: mode,
      );
}

/// The v1.0 library. Ordered by category, then by how common the cut is.
abstract final class Presets {
  static const List<CookPreset> all = [
    // ── Beef ──────────────────────────────────────────────────────────
    CookPreset(
      id: 'beef_brisket',
      category: 'Beef',
      name: 'Texas brisket',
      hazard: HazardClass.wholeMuscleRedMeat,
      thickness: CutThickness.thick,
      blurb: 'Low and slow until the collagen gives — probe-tender near 203°F',
      pitBandMinF10: 2250,
      pitBandMaxF10: 2750,
      doneness: [
        Doneness(id: 'sliceable', label: 'Sliceable', targetF10: 1950),
        Doneness(id: 'tender', label: 'Tender', targetF10: 2010),
        Doneness(id: 'shred', label: 'Pitmaster shred', targetF10: 2030),
      ],
    ),
    CookPreset(
      id: 'beef_ribeye',
      category: 'Beef',
      name: 'Ribeye steak',
      hazard: HazardClass.wholeMuscleRedMeat,
      // A 1″ steak coasts a degree or two, not five — the old 5 °F offset was
      // pulling a medium-rare steak at 130 °F on a promise it never kept.
      thickness: CutThickness.thin,
      blurb: 'A whole-muscle cut — cook it to the doneness you like',
      pitBandMinF10: 2000,
      pitBandMaxF10: 2500,
      doneness: DonenessLadder.steak,
    ),
    CookPreset(
      id: 'beef_prime_rib',
      category: 'Beef',
      name: 'Prime rib roast',
      hazard: HazardClass.wholeMuscleRedMeat,
      // 4–6″ of mass: AmazingRibs measures 5–10 °F of coast, and more from a
      // hot pit. This is the cut carryover was written for.
      thickness: CutThickness.thick,
      blurb: 'Thick roast — it keeps climbing off the heat, so it comes out '
          'early',
      pitBandMinF10: 2250,
      pitBandMaxF10: 2750,
      doneness: DonenessLadder.steak,
    ),
    CookPreset(
      id: 'beef_chuck',
      category: 'Beef',
      name: 'Chuck roast',
      hazard: HazardClass.wholeMuscleRedMeat,
      thickness: CutThickness.thick,
      blurb: 'Braise-tender — treat it like a small brisket',
      pitBandMinF10: 2500,
      pitBandMaxF10: 2750,
      doneness: [
        Doneness(id: 'sliceable', label: 'Sliceable', targetF10: 1950),
        Doneness(id: 'shred', label: 'Shreddable', targetF10: 2050),
      ],
    ),
    CookPreset(
      id: 'beef_burger',
      category: 'Beef',
      name: 'Burgers',
      // Ground, so the floor is real and the sheet cannot be talked out of it.
      hazard: HazardClass.ground,
      thickness: CutThickness.thin,
      blurb: 'Ground beef finishes at 160°F — grinding mixes surface bacteria '
          'right through',
      pitBandMinF10: 3250,
      pitBandMaxF10: 3750,
      doneness: [Doneness(id: 'done', label: 'Done (160°F)', targetF10: 1600)],
    ),
    // ── Pork ──────────────────────────────────────────────────────────
    CookPreset(
      id: 'pork_butt',
      category: 'Pork',
      name: 'Pork shoulder',
      hazard: HazardClass.pork,
      thickness: CutThickness.thick,
      blurb: 'Boston butt — pull it apart at 201°F',
      pitBandMinF10: 2250,
      pitBandMaxF10: 2750,
      doneness: [
        Doneness(id: 'sliceable', label: 'Sliceable', targetF10: 1850),
        Doneness(id: 'pulled', label: 'Pulled', targetF10: 2010),
      ],
    ),
    CookPreset(
      id: 'pork_ribs',
      category: 'Pork',
      name: 'Spare ribs',
      hazard: HazardClass.pork,
      thickness: CutThickness.thin,
      blurb: 'Bend-test tender — bark set, meat pulled back from the bone',
      pitBandMinF10: 2250,
      pitBandMaxF10: 2750,
      doneness: [
        Doneness(id: 'tender', label: 'Bite-tender', targetF10: 1950),
        Doneness(id: 'falloff', label: 'Fall-off-bone', targetF10: 2030),
      ],
    ),
    CookPreset(
      id: 'pork_loin',
      category: 'Pork',
      name: 'Pork loin',
      hazard: HazardClass.pork,
      thickness: CutThickness.medium,
      blurb: 'A lean cut — pull at 145°F and rest for juicy slices',
      pitBandMinF10: 2500,
      pitBandMaxF10: 3000,
      doneness: [
        Doneness(id: 'juicy', label: 'Juicy (145°F + rest)', targetF10: 1450),
        Doneness(id: 'well', label: 'Well done', targetF10: 1600),
      ],
    ),
    // ── Poultry ───────────────────────────────────────────────────────
    CookPreset(
      id: 'poultry_whole',
      category: 'Poultry',
      name: 'Whole turkey',
      hazard: HazardClass.poultry,
      // Thick, but poultry carryover is zero by rule: 165 °F is verified by
      // the probe, never predicted up to.
      thickness: CutThickness.thick,
      blurb: 'Breast to 165°F — the safe minimum, and where it eats best',
      pitBandMinF10: 2750,
      pitBandMaxF10: 3250,
      doneness: [Doneness(id: 'done', label: 'Done (165°F)', targetF10: 1650)],
    ),
    CookPreset(
      id: 'poultry_breast',
      category: 'Poultry',
      name: 'Chicken breast',
      hazard: HazardClass.poultry,
      thickness: CutThickness.thin,
      blurb: 'Pull at 165°F — juicy and safe',
      pitBandMinF10: 3250,
      pitBandMaxF10: 3750,
      doneness: [Doneness(id: 'done', label: 'Done (165°F)', targetF10: 1650)],
    ),
    CookPreset(
      id: 'poultry_thigh',
      category: 'Poultry',
      name: 'Chicken thighs',
      hazard: HazardClass.poultry,
      thickness: CutThickness.thin,
      blurb: 'Dark meat is best past the minimum — 175–185°F renders it silky',
      pitBandMinF10: 3250,
      pitBandMaxF10: 3750,
      doneness: [
        Doneness(id: 'safe', label: 'Safe (165°F)', targetF10: 1650),
        Doneness(id: 'silky', label: 'Silky (180°F)', targetF10: 1800),
      ],
    ),
    // ── Fish ──────────────────────────────────────────────────────────
    CookPreset(
      id: 'fish_salmon',
      category: 'Fish',
      name: 'Salmon fillet',
      hazard: HazardClass.fish,
      thickness: CutThickness.thin,
      blurb: 'Flakes at 145°F — the safe minimum for fish',
      pitBandMinF10: 2250,
      pitBandMaxF10: 2750,
      doneness: [Doneness(id: 'done', label: 'Flaky (145°F)', targetF10: 1450)],
    ),
    // ── Eggs ──────────────────────────────────────────────────────────
    //
    // §D.4's sixth row, and the reason it is here: without an egg preset and an
    // egg hazard class, a custom quiche had nothing to be but red meat, and red
    // meat is the one class with no floor. A 130 °F quiche built freely.
    CookPreset(
      id: 'egg_bake',
      category: 'Eggs',
      name: 'Quiche or egg bake',
      hazard: HazardClass.egg,
      thickness: CutThickness.medium,
      blurb: 'Custard set through at 160°F — USDA’s minimum for egg dishes',
      pitBandMinF10: 3250,
      pitBandMaxF10: 3750,
      doneness: [Doneness(id: 'set', label: 'Set (160°F)', targetF10: 1600)],
    ),
    CookPreset(
      id: 'egg_casserole',
      category: 'Eggs',
      name: 'Breakfast casserole',
      hazard: HazardClass.egg,
      thickness: CutThickness.thick,
      blurb: 'A deep bake — same 160°F, read at the centre',
      pitBandMinF10: 3000,
      pitBandMaxF10: 3500,
      doneness: [Doneness(id: 'set', label: 'Set (160°F)', targetF10: 1600)],
    ),
  ];

  /// The category chips, in the order the sheet shows them.
  static const List<String> categories = [
    'Beef',
    'Pork',
    'Poultry',
    'Fish',
    'Eggs',
  ];

  static List<CookPreset> inCategory(String c) =>
      all.where((p) => p.category == c).toList(growable: false);

  static CookPreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) {
        return p;
      }
    }
    return null;
  }
}
