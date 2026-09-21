/// N1.5 — food-safety floors.
///
/// **This is a food-safety artefact, not a preferences list.** A target below a
/// protein's floor is *refused* (see `CookPlan`'s constructor), not warned
/// about.
///
/// The floor exists only where the hazard is real: an **intact** whole-muscle
/// cut's interior is sterile, so searing its surface makes any interior
/// doneness safe. Ground, poultry, pork, fish and egg do not have that
/// property. Mechanically tenderized or injected beef has had surface bacteria
/// driven inside, so it behaves like ground meat — which is why [isIntact] is a
/// required input rather than a note in the UI.
///
/// **Two labelled readings of "safe":** [SafetyMode.usdaCompliant] follows USDA
/// FSIS to the letter; [SafetyMode.enthusiast] permits rare/medium-rare on
/// *intact whole-muscle only* and relaxes nothing else.
///
/// Saying nothing is not the same as saying "steak": an unnamed protein is
/// [HazardClass.unstated] and carries the 160 °F ground floor, because the one
/// class with no floor is the one class that must not be a default.
///
/// Sources: USDA FSIS — poultry 165 °F, ground 160 °F, whole cuts 145 °F + 3 min
/// rest (2011), fish 145 °F, egg dishes 160 °F.
library;

/// The food-safety category a preset belongs to. Drives whether a floor exists.
enum HazardClass {
  /// Nobody has said what is on this probe. Takes the 160 °F ground floor in
  /// both modes — a real answer, not only an initial state.
  unstated,

  /// Beef, veal, lamb, game. Only floor-free while intact.
  wholeMuscleRedMeat,

  /// Chicken, turkey, duck — 165 °F, no exceptions.
  poultry,

  /// Any ground meat — surface bacteria are mixed through.
  ground,

  /// Pork and pork-like whole cuts — 145 °F + 3-minute rest.
  pork,

  /// Fish and shellfish — 145 °F.
  fish,

  /// Quiche, frittata, strata — 160 °F.
  egg;

  String get label => switch (this) {
    HazardClass.unstated => 'Not stated',
    HazardClass.wholeMuscleRedMeat => 'Beef, lamb or game',
    HazardClass.poultry => 'Poultry',
    HazardClass.ground => 'Ground meat',
    HazardClass.pork => 'Pork',
    HazardClass.fish => 'Fish or seafood',
    HazardClass.egg => 'Egg dish',
  };

  /// The class as it reads inside a sentence, for the refusal copy.
  String get phrase => switch (this) {
    HazardClass.unstated => 'a probe with nothing stated about it',
    HazardClass.wholeMuscleRedMeat => 'beef, lamb or game',
    HazardClass.poultry => 'poultry',
    HazardClass.ground => 'ground meat',
    HazardClass.pork => 'pork',
    HazardClass.fish => 'fish and seafood',
    HazardClass.egg => 'egg dishes',
  };
}

/// Which reading of "safe" the user has chosen.
enum SafetyMode {
  /// The letter of USDA FSIS: 145 °F + 3-minute rest on whole red-meat cuts.
  usdaCompliant,

  /// Chef reading, valid for intact whole-muscle only.
  enthusiast;

  String get label => switch (this) {
    SafetyMode.usdaCompliant => 'USDA compliant',
    SafetyMode.enthusiast => 'Chef — intact whole-muscle only',
  };

  String get blurb => switch (this) {
    SafetyMode.usdaCompliant =>
      'Whole cuts of beef, pork, lamb and veal finish at 145°F with a '
          '3-minute rest, as USDA FSIS specifies.',
    SafetyMode.enthusiast =>
      'Rare and medium-rare are allowed on intact whole-muscle cuts, whose '
          'interior is sterile. Poultry, ground, pork and fish are unchanged.',
  };
}

/// The safety strip every screen showing a raw-meat target carries.
const String rawMeatAdvisory =
    'Consuming raw or undercooked meats, poultry, or seafood may increase '
    'your risk of foodborne illness.';

/// The warning a red-meat cut earns instead of a refusal.
const String intactCutAdvisory =
    'Whole-muscle only. If this cut was tenderized, blade-tenderized or '
    'injected, cook it to 160°F like ground meat — the needles carry surface '
    'bacteria inside.';

/// The lines every safety strip shows, in order. The words are the contract,
/// not the widget.
List<String> safetyStripFor({bool intactRedMeat = false}) => [
  if (intactRedMeat) intactCutAdvisory,
  rawMeatAdvisory,
];

/// A minimum safe internal temperature, tenths °F, with any rest advice.
class SafetyFloor {
  const SafetyFloor({required this.minF10, this.restMinutes = 0, this.source});

  /// The minimum safe internal temperature, tenths °F.
  final int minF10;

  /// Recommended post-cook rest, minutes. 0 where none applies.
  final int restMinutes;

  /// The citation, for the setup sheet and for review.
  final String? source;

  /// The floor for [hazard], or null where the hazard does not warrant one.
  ///
  /// [isIntact] only matters for [HazardClass.wholeMuscleRedMeat]: a cut that
  /// is not intact takes the ground-meat floor in both modes. [mode] only
  /// relaxes an intact whole-muscle cut.
  static SafetyFloor? forClass(
    HazardClass hazard, {
    bool isIntact = true,
    SafetyMode mode = SafetyMode.enthusiast,
  }) => switch (hazard) {
    HazardClass.unstated => const SafetyFloor(
      minF10: 1600,
      source:
          'Nothing stated for this probe, so the app applies the 160 °F '
          'ground-meat floor (USDA FSIS — ground meats) until you say what '
          'it is',
    ),
    HazardClass.wholeMuscleRedMeat when !isIntact => const SafetyFloor(
      minF10: 1600,
      source:
          'USDA FSIS — tenderized or injected beef is treated as ground meat: '
          'the needles carry surface bacteria into the centre',
    ),
    HazardClass.wholeMuscleRedMeat =>
      mode == SafetyMode.usdaCompliant
          ? const SafetyFloor(
              minF10: 1450,
              restMinutes: 3,
              source:
                  'USDA FSIS 2011 — whole cuts of beef, pork, veal and lamb, '
                  '145 °F + 3-minute rest',
            )
          : null,
    HazardClass.poultry => const SafetyFloor(
      minF10: 1650,
      source: 'USDA FSIS — poultry safe minimum internal temperature',
    ),
    HazardClass.ground => const SafetyFloor(
      minF10: 1600,
      source: 'USDA FSIS — ground meats',
    ),
    HazardClass.pork => const SafetyFloor(
      minF10: 1450,
      restMinutes: 3,
      source: 'USDA FSIS 2011 — pork and whole cuts, 145 °F + 3-minute rest',
    ),
    HazardClass.fish => const SafetyFloor(
      minF10: 1450,
      source: 'USDA FSIS — fish & shellfish',
    ),
    HazardClass.egg => const SafetyFloor(
      minF10: 1600,
      source: 'USDA FSIS — egg dishes',
    ),
  };

  /// Whether a cut in this class should carry [intactCutAdvisory].
  static bool needsIntactAdvisory(HazardClass hazard, {bool isIntact = true}) =>
      hazard == HazardClass.wholeMuscleRedMeat && isIntact;
}
