/// A22.1 — the preset library (design 13 §13.5.3).
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
/// Temperatures are tenths of °F throughout, the storage-canonical unit.
library;

import 'hazard.dart';

/// A single doneness level within a preset.
class Doneness {
  const Doneness({
    required this.id,
    required this.label,
    required this.targetF10,
    this.restOffsetF10 = 0,
  });

  final String id;
  final String label;

  /// Internal target, tenths °F.
  final int targetF10;

  /// Carry-over: pull this many tenths-°F early to land on target after rest.
  final int restOffsetF10;

  int get pullF10 => targetF10 - restOffsetF10;
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

  /// One line under the name in the picker.
  final String blurb;

  /// The default doneness: the last level for low-and-slow proteins whose only
  /// real answer is "probe-tender", the middle for steaks.
  Doneness get defaultDoneness =>
      hazard == HazardClass.wholeMuscleRedMeat && doneness.length >= 3
      ? doneness[doneness.length ~/ 2]
      : doneness.last;
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
      blurb: 'Low and slow until the collagen gives — probe-tender near 203°F',
      pitBandMinF10: 2250,
      pitBandMaxF10: 2750,
      doneness: [
        Doneness(id: 'sliceable', label: 'Sliceable', targetF10: 1950),
        Doneness(
          id: 'tender',
          label: 'Tender',
          targetF10: 2010,
          restOffsetF10: 50,
        ),
        Doneness(
          id: 'shred',
          label: 'Pitmaster shred',
          targetF10: 2030,
          restOffsetF10: 50,
        ),
      ],
    ),
    CookPreset(
      id: 'beef_ribeye',
      category: 'Beef',
      name: 'Ribeye steak',
      hazard: HazardClass.wholeMuscleRedMeat,
      blurb: 'A whole-muscle cut — cook it to the doneness you like',
      pitBandMinF10: 2000,
      pitBandMaxF10: 2500,
      doneness: [
        Doneness(id: 'rare', label: 'Rare', targetF10: 1250, restOffsetF10: 50),
        Doneness(
          id: 'medrare',
          label: 'Medium rare',
          targetF10: 1350,
          restOffsetF10: 50,
        ),
        Doneness(
          id: 'medium',
          label: 'Medium',
          targetF10: 1450,
          restOffsetF10: 50,
        ),
        Doneness(
          id: 'medwell',
          label: 'Medium well',
          targetF10: 1550,
          restOffsetF10: 50,
        ),
      ],
    ),
    CookPreset(
      id: 'beef_chuck',
      category: 'Beef',
      name: 'Chuck roast',
      hazard: HazardClass.wholeMuscleRedMeat,
      blurb: 'Braise-tender — treat it like a small brisket',
      pitBandMinF10: 2500,
      pitBandMaxF10: 2750,
      doneness: [
        Doneness(id: 'sliceable', label: 'Sliceable', targetF10: 1950),
        Doneness(
          id: 'shred',
          label: 'Shreddable',
          targetF10: 2050,
          restOffsetF10: 50,
        ),
      ],
    ),
    // ── Pork ──────────────────────────────────────────────────────────
    CookPreset(
      id: 'pork_butt',
      category: 'Pork',
      name: 'Pork shoulder',
      hazard: HazardClass.pork,
      blurb: 'Boston butt — pull it apart at 201°F',
      pitBandMinF10: 2250,
      pitBandMaxF10: 2750,
      doneness: [
        Doneness(
          id: 'sliceable',
          label: 'Sliceable',
          targetF10: 1850,
          restOffsetF10: 50,
        ),
        Doneness(
          id: 'pulled',
          label: 'Pulled',
          targetF10: 2010,
          restOffsetF10: 50,
        ),
      ],
    ),
    CookPreset(
      id: 'pork_ribs',
      category: 'Pork',
      name: 'Spare ribs',
      hazard: HazardClass.pork,
      blurb: 'Bend-test tender — bark set, meat pulled back from the bone',
      pitBandMinF10: 2250,
      pitBandMaxF10: 2750,
      doneness: [
        Doneness(
          id: 'tender',
          label: 'Bite-tender',
          targetF10: 1950,
          restOffsetF10: 0,
        ),
        Doneness(id: 'falloff', label: 'Fall-off-bone', targetF10: 2030),
      ],
    ),
    CookPreset(
      id: 'pork_loin',
      category: 'Pork',
      name: 'Pork loin',
      hazard: HazardClass.pork,
      blurb: 'A lean cut — pull at 145°F and rest for juicy slices',
      pitBandMinF10: 2500,
      pitBandMaxF10: 3000,
      doneness: [
        Doneness(
          id: 'juicy',
          label: 'Juicy (145°F + rest)',
          targetF10: 1450,
          restOffsetF10: 50,
        ),
        Doneness(id: 'well', label: 'Well done', targetF10: 1600),
      ],
    ),
    // ── Poultry ───────────────────────────────────────────────────────
    CookPreset(
      id: 'poultry_whole',
      category: 'Poultry',
      name: 'Whole turkey',
      hazard: HazardClass.poultry,
      blurb: 'Breast to 165°F — the safe minimum, and where it eats best',
      pitBandMinF10: 2750,
      pitBandMaxF10: 3250,
      doneness: [
        Doneness(
          id: 'done',
          label: 'Done (165°F)',
          targetF10: 1650,
          restOffsetF10: 40,
        ),
      ],
    ),
    CookPreset(
      id: 'poultry_breast',
      category: 'Poultry',
      name: 'Chicken breast',
      hazard: HazardClass.poultry,
      blurb: 'Pull at 165°F — juicy and safe',
      pitBandMinF10: 3250,
      pitBandMaxF10: 3750,
      doneness: [
        Doneness(
          id: 'done',
          label: 'Done (165°F)',
          targetF10: 1650,
          restOffsetF10: 20,
        ),
      ],
    ),
    CookPreset(
      id: 'poultry_thigh',
      category: 'Poultry',
      name: 'Chicken thighs',
      hazard: HazardClass.poultry,
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
      blurb: 'Flakes at 145°F — the safe minimum for fish',
      pitBandMinF10: 2250,
      pitBandMaxF10: 2750,
      doneness: [Doneness(id: 'done', label: 'Flaky (145°F)', targetF10: 1450)],
    ),
  ];

  /// The four category chips, in the order the sheet shows them.
  static const List<String> categories = ['Beef', 'Pork', 'Poultry', 'Fish'];

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
