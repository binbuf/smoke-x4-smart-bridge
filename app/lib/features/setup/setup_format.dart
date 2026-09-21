/// N9 — the catalog/setup flow's pure projections.
///
/// Search, category filtering, the style and doneness ladders, the summary
/// card's arithmetic, jack assignment and the long-item guard only: no Flutter,
/// no repository. Keeping it here lets the prototype's exact rules be tested
/// without a binding, and lets the widget stay a view over one immutable value.
///
/// Rules this file holds (`app.js` `overlaySetup`, `requestAdd`, `adoptCook`):
///
///  * **Search covers all foods at once** (name, category or blurb) and
///    **overrides the category chip** (N9.4/N9.5).
///  * **Red meat defaults to medium rare** — that lives in the N1 ladder and is
///    re-asserted here so the picker cannot drift (N9.8).
///  * **A jack is busy when a *different* food already sits on it** (N9.10).
///  * **The long-item guard fires when the new item would finish more than 15
///    minutes after everything else** (N9.14).
///  * **A custom food carries its own timeline and re-runs the safety gate**
///    (N9.17/N9.18, I12). The built-in catalog keeps the prototype's
///    reviewer-pinned rungs untouched.
library;

import '../../data/content/catalog.dart';
import '../../data/model/app_settings.dart';
import '../../data/model/cook_state.dart';
import '../../domain/domain.dart';
import '../timeline/timeline_format.dart';

/// The three ways to start a cook (NOTES §5).
enum SetupMode {
  newCook,
  existing,
  watch;

  /// The segmented chip label.
  String get label => switch (this) {
    SetupMode.newCook => 'Start a cook',
    SetupMode.existing => 'Already started',
    SetupMode.watch => 'Just watch',
  };

  /// The sheet title.
  String get sheetTitle => switch (this) {
    SetupMode.watch => 'Cook setup',
    _ => 'New cook',
  };

  /// The one-line sub copy under the title.
  String get sub => switch (this) {
    SetupMode.existing => 'Build a cook over data already collected',
    SetupMode.watch => 'Live numbers, no plan',
    SetupMode.newCook => 'Set up before, during, or after you light the fire',
  };

  /// The primary action's label.
  String get primaryLabel => switch (this) {
    SetupMode.newCook => 'Start cook',
    SetupMode.existing => 'Start & pull history',
    SetupMode.watch => 'Watch live temperatures',
  };
}

/// One food in the picker — a catalog cut or a user-defined custom food.
class SetupFood {
  const SetupFood({
    required this.id,
    required this.name,
    required this.category,
    required this.blurb,
    required this.glyph,
    required this.hazard,
    required this.thickness,
    required this.pitBandMinF10,
    required this.pitBandMaxF10,
    required this.doneness,
    required this.defaultDonenessId,
    required this.isCustom,
    this.customTimeline,
  });

  final String id;
  final String name;
  final String category;
  final String blurb;
  final String glyph;
  final HazardClass hazard;
  final CutThickness thickness;
  final int pitBandMinF10;
  final int pitBandMaxF10;
  final List<Doneness> doneness;
  final String defaultDonenessId;

  /// True for a user-defined food (the tile gets a "Custom" badge).
  final bool isCustom;

  /// A custom food's own expected timeline (N9.18).
  final CookTimeline? customTimeline;

  /// Carryover for this cut, tenths °F — the same rule the catalog uses.
  int get carryoverF10 => carryoverFor(hazard: hazard, thickness: thickness);

  /// The doneness the picker opens on.
  Doneness get defaultDoneness {
    for (final d in doneness) {
      if (d.id == defaultDonenessId) {
        return d;
      }
    }
    return doneness.first;
  }

  /// The rung with [id], or the default when [id] is unknown.
  Doneness donenessById(String? id) {
    if (id != null) {
      for (final d in doneness) {
        if (d.id == id) {
          return d;
        }
      }
    }
    return defaultDoneness;
  }

  /// Whether the picker should label this a red-meat cut.
  bool get isRedMeat => hazard == HazardClass.wholeMuscleRedMeat;

  /// The N1 preset shape (used for the styles lookup and the safety gate).
  CookPreset toPreset() => CookPreset(
    id: id,
    category: category,
    name: name,
    hazard: hazard,
    doneness: doneness,
    pitBandMinF10: pitBandMinF10,
    pitBandMaxF10: pitBandMaxF10,
    thickness: thickness,
    blurb: blurb,
  );
}

/// Builds the picker list: the catalog first, then the user's custom foods.
List<SetupFood> setupFoods({
  required CatalogTable catalog,
  List<CustomFood> customs = const <CustomFood>[],
}) => <SetupFood>[
  for (final entry in catalog.entries)
    SetupFood(
      id: entry.id,
      name: entry.name,
      category: entry.category,
      blurb: entry.blurb,
      glyph: entry.glyph,
      hazard: entry.hazard,
      thickness: entry.thickness,
      pitBandMinF10: entry.pitBandMinF10,
      pitBandMaxF10: entry.pitBandMaxF10,
      doneness: entry.doneness,
      defaultDonenessId: entry.defaultDonenessId,
      isCustom: false,
    ),
  for (final food in customs)
    SetupFood(
      id: food.id,
      name: food.name,
      category: food.category,
      blurb: food.blurb,
      glyph: food.glyph,
      hazard: food.hazard,
      thickness: food.thickness,
      pitBandMinF10: food.pitBandMinF10 ?? 2250,
      pitBandMaxF10: food.pitBandMaxF10 ?? 2750,
      doneness: <Doneness>[
        Doneness(id: 'target', label: 'Target', targetF10: food.targetF10),
      ],
      defaultDonenessId: 'target',
      isCustom: true,
      customTimeline: food.timeline,
    ),
];

/// The foods matching [query] (all categories) or, with no query, [category].
///
/// A non-empty [query] **overrides** the category chip (N9.5).
List<SetupFood> searchSetupFoods(
  List<SetupFood> all, {
  String query = '',
  String? category,
}) {
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) {
    return <SetupFood>[
      for (final food in all)
        if (food.name.toLowerCase().contains(q) ||
            food.category.toLowerCase().contains(q) ||
            food.blurb.toLowerCase().contains(q))
          food,
    ];
  }
  if (category == null) {
    return List<SetupFood>.of(all);
  }
  return <SetupFood>[
    for (final food in all)
      if (food.category == category) food,
  ];
}

/// The food with [id], or null.
SetupFood? setupFoodById(List<SetupFood> all, String? id) {
  if (id == null) {
    return null;
  }
  for (final food in all) {
    if (food.id == id) {
      return food;
    }
  }
  return null;
}

/// The named styles for [food] — empty for a custom food.
List<CookStyle> setupStylesFor(CatalogTable catalog, SetupFood? food) =>
    food == null || food.isCustom
    ? const <CookStyle>[]
    : catalog.stylesFor(food.id);

/// The style with [id] within [styles], or null.
CookStyle? setupStyleById(List<CookStyle> styles, String? id) {
  if (id == null) {
    return null;
  }
  for (final style in styles) {
    if (style.id == id) {
      return style;
    }
  }
  return null;
}

/// The summary card's values, all resolved for one selected food.
class SetupSummary {
  const SetupSummary({
    required this.targetF10,
    required this.pullF10,
    required this.carryoverF10,
    required this.restMin,
    required this.totalMin,
  });

  /// The final, post-rest target, tenths °F.
  final int targetF10;

  /// The pull temperature, tenths °F — floor-clamped (I12).
  final int pullF10;

  /// How far early the pull is, tenths °F.
  final int carryoverF10;

  /// Expected rest, minutes.
  final int restMin;

  /// Expected cook range, pre-rest, or null when the cut has no timeline.
  final MinuteRange? totalMin;
}

/// Builds the summary for [food], [doneness] and an optional [style].
SetupSummary setupSummary({
  required SetupFood food,
  required Doneness doneness,
  CookStyle? style,
  CookTimeline? timeline,
}) {
  final target = style?.targetF10 ?? doneness.targetF10;
  final carryover = food.carryoverF10;
  final pull = pullTempFor(
    targetF10: target,
    carryoverF10: carryover,
    hazard: food.hazard,
  );
  return SetupSummary(
    targetF10: target,
    pullF10: pull,
    carryoverF10: target - pull,
    restMin: style?.restMin ?? timeline?.restMin ?? 0,
    totalMin: timeline?.totalMin,
  );
}

/// `60–120 min`, or `—`.
String expectedCookLabel(MinuteRange? totalMin) =>
    totalMin == null ? '—' : '${totalMin.min}–${totalMin.max} min';

/// The jacks a *different* food already occupies (N9.10).
Set<ProbeJack> busyJacks(CookState cook, String? selectedId) => <ProbeJack>{
  for (final item in cook.items)
    if (item.presetId != selectedId) item.jack,
};

/// Whether [jack] is taken by a different food.
bool jackIsBusy(CookState cook, ProbeJack jack, String? selectedId) =>
    busyJacks(cook, selectedId).contains(jack);

/// The jack chip's label: `Jack 4 · grate`, `(in use)` when busy (N9.10).
String jackLabel(ProbeJack jack, {required bool busy}) {
  final grate = jack == ProbeJack.four ? ' · grate' : '';
  return 'Jack ${jack.n}$grate${busy ? ' (in use)' : ''}';
}

/// The first jack not taken by a different food, else jack 1.
ProbeJack firstFreeJack(CookState cook, String? selectedId) {
  final busy = busyJacks(cook, selectedId);
  for (final jack in ProbeJack.values) {
    if (!busy.contains(jack)) {
      return jack;
    }
  }
  return ProbeJack.one;
}

/// The per-item expected timeline: a custom timeline wins, then the catalog.
CookTimeline timelineForItem(CookItem item, CatalogTable catalog) =>
    item.timeline ?? catalog.timelineFor(item.presetId) ?? kFallbackTimeline;

/// How many minutes a new [food] would outlast the current cook, or null.
///
/// The guard fires only when a cook is already running with items and the new
/// item's expected finish is **more than 15 minutes** after everything else
/// (N9.14, `app.js` `requestAdd`).
int? longItemDelayMin({
  required CookState cook,
  required SetupFood food,
  required int nowMs,
  required CatalogTable catalog,
  CookTimeline? timeline,
}) {
  if (!cook.active || cook.items.isEmpty) {
    return null;
  }
  final newTimeline =
      timeline ?? food.customTimeline ?? catalog.timelineFor(food.id);
  final newMid = (newTimeline?.totalMin ?? kFallbackTimeline.totalMin).mid;

  var lastEndMs = 0;
  for (final item in cook.items) {
    final mid = timelineForItem(item, catalog).totalMin.mid;
    final end = item.addedAtMs + (mid * 60000).round();
    if (end > lastEndMs) {
      lastEndMs = end;
    }
  }
  final newFinishMs = nowMs + (newMid * 60000).round();
  final slack = newFinishMs - lastEndMs - 15 * 60000;
  if (slack <= 0) {
    return null;
  }
  return ((newFinishMs - lastEndMs) / 60000).round();
}

/// The safety refusal for a user-authored target, or null when it is safe.
///
/// **This is the I12 gate for custom foods** (N9.18). A custom target below its
/// hazard's floor is refused with the floor's own words; the reviewer-pinned
/// built-in rungs are not re-litigated here (the catalog owns that exception
/// set, and N1's `CookPlan` still refuses one if it is ever used as a plan).
String? customTargetRefusal({
  required HazardClass hazard,
  required int targetF10,
  CutThickness thickness = CutThickness.medium,
  bool isIntact = true,
  SafetyMode mode = SafetyMode.enthusiast,
}) {
  final floor = SafetyFloor.forClass(hazard, isIntact: isIntact, mode: mode);
  if (floor == null || targetF10 >= floor.minF10) {
    return null;
  }
  final degrees = (targetF10 / 10).round();
  final min = (floor.minF10 / 10).round();
  return '$degrees°F is below the $min°F safe minimum for '
      '${hazard.phrase}${floor.source == null ? '' : ' (${floor.source})'}.';
}

/// Builds a custom food from the form's raw values (N9.17/N9.18).
///
/// Temperatures arrive as whole °F from the form and are stored as tenths °F.
/// A zero [wrapF] means "never wrap"; a zero [spritzMin] means "never spritz".
CustomFood customFoodFromForm({
  required String id,
  required String name,
  required String category,
  required String glyph,
  required HazardClass hazard,
  required CutThickness thickness,
  required int pitLoF,
  required int pitHiF,
  required int targetF,
  required int restMin,
  required int totalLoMin,
  required int totalHiMin,
  required int wrapF,
  required int spritzMin,
}) {
  final timeline = CookTimeline(
    totalMin: MinuteRange(totalLoMin, totalHiMin),
    wrap: wrapF > 0
        ? WrapStep(
            tempF10: wrapF * 10,
            label: 'Wrap',
            note: 'Wrap at the set temperature.',
          )
        : null,
    spritzEveryMin: spritzMin > 0 ? spritzMin : null,
    restMin: restMin,
    phases: const <CookPhaseSpec>[
      CookPhaseSpec(id: 'on', label: 'On the smoker', note: 'Custom timeline.'),
      CookPhaseSpec(
        id: 'pull',
        label: 'Pull',
        note: 'At target, rest before serving.',
      ),
    ],
  );
  return CustomFood(
    id: id,
    name: name,
    category: category,
    glyph: glyph,
    hazard: hazard,
    thickness: thickness,
    pitBandMinF10: pitLoF * 10,
    pitBandMaxF10: pitHiF * 10,
    targetF10: targetF * 10,
    timeline: timeline,
  );
}

/// The glyph names the custom-food form offers (`app.js` `overlayCustomFood`).
const List<String> kCustomFoodGlyphs = <String>[
  'beef',
  'steak',
  'pork',
  'ribs',
  'poultry',
  'wholeBird',
  'fish',
  'shellfish',
  'game',
  'ground',
  'egg',
  'veg',
  'potato',
  'cheese',
  'bread',
  'fruit',
  'side',
];

/// The hazard options the custom-food form offers, in order.
const List<HazardClass> kCustomFoodHazards = <HazardClass>[
  HazardClass.wholeMuscleRedMeat,
  HazardClass.pork,
  HazardClass.poultry,
  HazardClass.ground,
  HazardClass.fish,
  HazardClass.egg,
  HazardClass.unstated,
];
