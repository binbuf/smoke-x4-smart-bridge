/// A22.1 — food-safety floors (design 13 §13.5.3, decision U3 in §13.9.1;
/// hardened per newapp §D.4).
///
/// **This is a food-safety artefact, not a preferences list**, and the product
/// owner has decided it is *enforced*, not advised: a target below a protein's
/// floor is refused in [CookPlan]'s constructor, not warned about.
///
/// The floor exists only where the hazard is real — an **intact** cut's
/// interior is sterile and only its surface carries pathogens, so searing it to
/// a safe surface temperature makes any interior doneness safe. Ground,
/// poultry, pork and fish do not have that property.
///
/// **The intact qualifier is load-bearing and used to be missing.** Mechanically
/// tenderized, blade-tenderized or injected ("needled") beef has had surface
/// bacteria driven into its centre, so it behaves like ground meat and takes the
/// 160 °F ground floor. A table that said "red meat has no floor" without asking
/// whether the cut was intact was quietly wrong for every supermarket
/// "tenderized" steak, which is why [isIntact] is a required input here rather
/// than a note in the UI.
///
/// **Two labelled modes**, because "safe" has two defensible readings and the
/// app should not pretend otherwise:
///
///  * [SafetyMode.usdaCompliant] — the letter of USDA FSIS: 145 °F plus a
///    3-minute rest for whole cuts of beef, pork, lamb and veal.
///  * [SafetyMode.enthusiast] — the pitmaster reading, valid **for intact
///    whole-muscle only**: a 130–135 °F medium-rare ribeye is a doneness
///    preference on a surface-pasteurised cut. It does not relax poultry,
///    ground, pork or fish by one degree.
///
/// **Saying nothing is not the same as saying "steak".** A custom cook that has
/// not named its protein takes [HazardClass.unstated], which carries the 160 °F
/// ground-meat floor. This is the same precautionary reasoning §D.4 applies to
/// tenderized and injected meat: where the app cannot know whether the hazard is
/// surface-only, it must assume it is not. The alternative — defaulting an
/// unnamed cut to whole-muscle red meat — let a 140 °F chicken target through,
/// because red meat is the one class with no floor.
///
/// Sources (cited so the table is auditable, per §13.5.3's reviewer gate):
///  * Poultry 165 °F — USDA FSIS, safe minimum internal temperature. USDA also
///    warns you *cannot* rely on carryover to bring an under-cooked bird up to
///    165 °F, which is why poultry carries a zero pull offset (see `presets`).
///  * Ground meats 160 °F — USDA FSIS (grinding distributes surface bacteria).
///  * Whole cuts of beef/pork/veal/lamb 145 °F **with a 3-minute rest** — USDA
///    FSIS 2011 revision.
///  * Fish & shellfish 145 °F — USDA FSIS.
///  * Egg dishes 160 °F — USDA FSIS. The sixth row of §D.4's table, and it used
///    to be missing here, which meant a custom quiche fell through to red meat
///    and got no floor at all.
///  * Intact-muscle sterility — USDA NAL, *"Examination of the Microbiological
///    Safety of Rare Steak"*: muscle is considered a sterile tissue, so the
///    hazard is surface-only.
///
/// The 3-minute rest is captured as [SafetyFloor.restMinutes] so the plan can
/// surface it; it is advice attached to the floor, not a second gate.
library;

/// The food-safety category a preset belongs to. Drives whether a floor exists.
enum HazardClass {
  /// Nobody has said what is on this probe. **Takes the 160 °F ground-meat
  /// floor**, in both modes — see the library comment. It is a real answer a
  /// user may choose ("I would rather not say"), not only an initial state, so
  /// it has to be as safe as the least safe thing it could be.
  unstated,

  /// Cuts of beef, veal, lamb, game. **Only floor-free while intact** — see
  /// [SafetyFloor.forClass]'s `isIntact`.
  wholeMuscleRedMeat,

  /// Chicken, turkey, duck — 165 °F, no exceptions, in either mode.
  poultry,

  /// Any ground meat — surface bacteria are mixed throughout.
  ground,

  /// Pork and pork-like whole cuts — 145 °F + a 3-minute rest.
  pork,

  /// Fish and shellfish — 145 °F.
  fish,

  /// Quiche, frittata, strata, casseroles bound with egg — 160 °F (§D.4).
  egg;

  /// What a picker calls this. Kept beside the floor rather than in the sheet
  /// so the words and the citation cannot drift apart between screens.
  String get label => switch (this) {
    HazardClass.unstated => 'Not stated',
    HazardClass.wholeMuscleRedMeat => 'Beef, lamb or game',
    HazardClass.poultry => 'Poultry',
    HazardClass.ground => 'Ground meat',
    HazardClass.pork => 'Pork',
    HazardClass.fish => 'Fish or seafood',
    HazardClass.egg => 'Egg dish',
  };

  /// The class as it reads **inside a sentence** — "below the 165°F safe
  /// minimum for poultry". [label] is a chip; this is prose, and the refusal
  /// the gate throws is read by a person, not by a log.
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

/// Which reading of "safe" the user has chosen. Only ever relaxes **intact
/// whole-muscle red meat**; every other class is identical in both modes.
enum SafetyMode {
  /// The letter of USDA FSIS. 145 °F + 3-minute rest on whole red-meat cuts.
  usdaCompliant,

  /// Chef / enthusiast — intact whole-muscle only. Medium-rare is permitted.
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

/// The safety strip every screen showing a raw-meat target carries, as MEATER
/// does. Committed as a constant because it is a legal-adjacent string, not
/// copy someone should improvise per screen.
const String rawMeatAdvisory =
    'Consuming raw or undercooked meats, poultry, or seafood may increase '
    'your risk of foodborne illness.';

/// The warning a *red-meat* cut earns instead of a refusal (§D.4: copy, not a
/// throw). Shown wherever a whole-muscle target is set, because the app cannot
/// see the packet the meat came in.
const String intactCutAdvisory =
    'Whole-muscle only. If this cut was tenderized, blade-tenderized or '
    'injected, cook it to 160°F like ground meat — the needles carry surface '
    'bacteria inside.';

/// The safety strip, as the lines every screen must show, in order (§D.4, §J3).
///
/// This returns **strings, not a widget**, because the strip has to sit in
/// three different chromes — the setup sheet, the guided overlay on `/live`,
/// and `/cooks/:id` — and the one thing that must not vary between them is the
/// words. §D.4 asks for the strip to be *persistent*, as MEATER's is; a strip
/// that appears on the setup sheet and nowhere else is missing from every
/// screen anyone actually reads during a cook.
///
/// [intactRedMeat] adds the tenderized-cut caveat above the raw-meat line —
/// the one case where the app is trusting a fact about the meat it cannot
/// measure, and so the one case that earns a second sentence.
List<String> safetyStripFor({bool intactRedMeat = false}) => [
  if (intactRedMeat) intactCutAdvisory,
  rawMeatAdvisory,
];

/// A minimum safe internal temperature, in tenths of °F, with any rest advice.
class SafetyFloor {
  const SafetyFloor({required this.minF10, this.restMinutes = 0, this.source});

  /// The minimum safe internal temperature, tenths °F. Storage is canonical
  /// tenths °F (04 §4.2), so no conversion is needed to compare a target.
  final int minF10;

  /// Recommended post-cook rest, minutes. 0 where none applies.
  final int restMinutes;

  /// The citation, for the setup sheet and for review.
  final String? source;

  /// The floor for [hazard], or null where the hazard does not warrant one.
  ///
  /// [isIntact] only matters for [HazardClass.wholeMuscleRedMeat]: a cut that
  /// is **not** intact takes the ground-meat floor, full stop, in both modes.
  /// [mode] only relaxes an intact whole-muscle cut.
  static SafetyFloor? forClass(
    HazardClass hazard, {
    bool isIntact = true,
    SafetyMode mode = SafetyMode.enthusiast,
  }) => switch (hazard) {
    // Neither mode moves this one: a mode is a reading of a *known* hazard,
    // and there is no hazard known here to read either way.
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
          // Intact + enthusiast: the interior is sterile, so doneness runs
          // rare→well as a preference. The advisory is copy, not a gate.
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

  /// Whether a cut in this class should carry [intactCutAdvisory]. True only
  /// for red meat claimed intact — the one case where the app is trusting a
  /// fact about the meat that it cannot measure.
  static bool needsIntactAdvisory(HazardClass hazard, {bool isIntact = true}) =>
      hazard == HazardClass.wholeMuscleRedMeat && isIntact;
}
