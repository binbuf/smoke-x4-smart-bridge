/// A22.1 — food-safety floors (design 13 §13.5.3, decision U3 in §13.9.1).
///
/// **This is a food-safety artefact, not a preferences list**, and the product
/// owner has decided it is *enforced*, not advised: a target below a protein's
/// floor is refused in [CookPlan]'s constructor, not warned about.
///
/// The floor exists only where the hazard is real — an intact cut's interior is
/// sterile and only its surface carries pathogens, so searing it to a safe
/// surface temperature makes any interior doneness safe. Ground, poultry, pork
/// and fish do not have that property.
///
/// **Whole-muscle red meat therefore has NO floor.** A 125 °F rare ribeye is a
/// doneness preference on a surface-pasteurised cut, and the UI must not lecture
/// about it. That distinction is *data* here ([HazardClass.wholeMuscleRedMeat]
/// → `floor == null`), never a special case in a widget.
///
/// Sources (cited so the table is auditable, per §13.5.3's reviewer gate):
///  * Poultry 165 °F — USDA FSIS, safe minimum internal temperature.
///  * Ground meats 160 °F — USDA FSIS (grinding distributes surface bacteria).
///  * Pork (and other whole cuts of beef/veal/lamb the user cooks as pork-like)
///    145 °F **with a 3-minute rest** — USDA FSIS 2011 revision.
///  * Fish & shellfish 145 °F — USDA FSIS.
///
/// The 3-minute rest is captured as [SafetyFloor.restMinutes] so the plan can
/// surface it; it is advice attached to the floor, not a second gate.
library;

/// The food-safety category a preset belongs to. Drives whether a floor exists.
enum HazardClass {
  /// Intact cuts of beef, veal, lamb, game — surface-pasteurised by searing.
  /// **No floor:** doneness runs rare→well as a preference.
  wholeMuscleRedMeat,

  /// Chicken, turkey, duck — 165 °F, no exceptions.
  poultry,

  /// Any ground meat — surface bacteria are mixed throughout.
  ground,

  /// Pork and pork-like whole cuts — 145 °F + a 3-minute rest.
  pork,

  /// Fish and shellfish — 145 °F.
  fish,
}

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
  static SafetyFloor? forClass(HazardClass hazard) => switch (hazard) {
    HazardClass.wholeMuscleRedMeat => null,
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
  };
}
