/// N9 — the setup flow's pure projections.
///
/// Pins the exit gate's data rules without a binding: search across all foods
/// (name/category/blurb) with the category override, the red-meat medium-rare
/// default, the summary arithmetic, jack assignment, the long-item guard and
/// the custom-food safety gate (I12).
library;

import 'package:smoke_bridge/data/content/catalog.dart';
import 'package:smoke_bridge/data/model/app_settings.dart';
import 'package:smoke_bridge/data/model/cook_state.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/setup/setup.dart';
import 'package:test/test.dart';

void main() {
  final foods = setupFoods(catalog: kCatalogTable);

  group('catalog search (N9.4/N9.5)', () {
    test('finds a cut by name', () {
      final results = searchSetupFoods(foods, query: 'brisket');
      expect(results, isNotEmpty);
      expect(results.map((f) => f.name), contains('Texas Brisket'));
    });

    test('finds a cut by category', () {
      final results = searchSetupFoods(foods, query: 'desserts');
      expect(results, isNotEmpty);
      expect(results.every((f) => f.category == 'Desserts'), isTrue);
    });

    test('finds a cut by blurb', () {
      // The brisket blurb: "Low and slow until the collagen gives."
      final results = searchSetupFoods(foods, query: 'collagen');
      expect(results.map((f) => f.id), contains('beef_brisket'));
    });

    test('search overrides the category chip', () {
      final results = searchSetupFoods(
        foods,
        query: 'brisket',
        category: 'Seafood',
      );
      expect(results.map((f) => f.id), contains('beef_brisket'));
    });

    test('no query filters by category', () {
      final results = setupFoods(
        catalog: kCatalogTable,
      ).where((f) => f.category == 'Beef');
      final filtered = searchSetupFoods(foods, category: 'Beef');
      expect(filtered.length, results.length);
      expect(filtered.every((f) => f.category == 'Beef'), isTrue);
    });

    test('searching all 139 foods is possible', () {
      // Every catalog entry is reachable from the picker.
      expect(foods.where((f) => !f.isCustom), hasLength(139));
    });
  });

  group('defaults and styles (N9.7/N9.8)', () {
    test('red meat opens on medium rare', () {
      final ribeye = setupFoodById(foods, 'beef_ribeye')!;
      expect(ribeye.isRedMeat, isTrue);
      expect(ribeye.defaultDoneness.id, 'medrare');
      expect(ribeye.defaultDoneness.targetF10, 1350);
    });

    test('brisket carries at least two preparation styles', () {
      final brisket = setupFoodById(foods, 'beef_brisket')!;
      final styles = setupStylesFor(kCatalogTable, brisket);
      expect(styles.length, greaterThanOrEqualTo(2));
      expect(styles.map((s) => s.region), contains('Texas'));
    });

    test('a custom food has no styles', () {
      const custom = CustomFood(
        id: 'custom_x',
        name: 'X',
        category: 'Misc',
        hazard: HazardClass.unstated,
        targetF10: 1800,
      );
      final all = setupFoods(
        catalog: kCatalogTable,
        customs: const <CustomFood>[custom],
      );
      final food = setupFoodById(all, 'custom_x')!;
      expect(food.isCustom, isTrue);
      expect(setupStylesFor(kCatalogTable, food), isEmpty);
      expect(food.defaultDoneness.targetF10, 1800);
    });
  });

  group('summary card (N9.9)', () {
    test('brisket target, carryover, rest and range', () {
      final brisket = setupFoodById(foods, 'beef_brisket')!;
      final doneness = brisket.defaultDoneness; // tender, 201 °F
      final timeline = kCatalogTable.timelineFor(brisket.id);
      final summary = setupSummary(
        food: brisket,
        doneness: doneness,
        timeline: timeline,
      );
      expect(summary.targetF10, 2010);
      // Thick whole-muscle red meat coasts 8 °F, no floor in enthusiast mode.
      expect(summary.carryoverF10, 80);
      expect(summary.pullF10, 1930);
      expect(summary.restMin, 60);
      expect(summary.totalMin, const MinuteRange(600, 840));
      expect(expectedCookLabel(summary.totalMin), '600–840 min');
    });

    test('a style target and rest win over the default rung', () {
      final brisket = setupFoodById(foods, 'beef_brisket')!;
      final styles = setupStylesFor(kCatalogTable, brisket);
      final competition = setupStyleById(styles, 'competition')!;
      final summary = setupSummary(
        food: brisket,
        doneness: brisket.defaultDoneness,
        style: competition,
        timeline: kCatalogTable.timelineFor(brisket.id),
      );
      expect(summary.targetF10, 2030);
      expect(summary.restMin, 90);
    });
  });

  group('jack assignment (N9.10)', () {
    final cook = CookState(
      active: true,
      items: const <CookItem>[
        CookItem(presetId: 'beef_brisket', jack: ProbeJack.one, addedAtMs: 0),
        CookItem(presetId: 'pork_ribs', jack: ProbeJack.two, addedAtMs: 0),
      ],
    );

    test('a jack is busy only for a different food', () {
      expect(jackIsBusy(cook, ProbeJack.one, 'beef_brisket'), isFalse);
      expect(jackIsBusy(cook, ProbeJack.two, 'beef_brisket'), isTrue);
      expect(jackIsBusy(cook, ProbeJack.three, 'beef_brisket'), isFalse);
    });

    test('labels carry the grate tag and the busy reason', () {
      expect(jackLabel(ProbeJack.four, busy: false), 'Jack 4 · grate');
      expect(jackLabel(ProbeJack.two, busy: true), 'Jack 2 (in use)');
    });

    test('firstFreeJack skips the occupied jacks', () {
      // A fresh selection sees both occupied jacks; jack 3 is free.
      expect(firstFreeJack(cook, null), ProbeJack.three);
      // Re-picking the food already on jack 1 may reuse jack 1.
      expect(firstFreeJack(cook, 'beef_brisket'), ProbeJack.one);
    });
  });

  group('long-item guard (N9.14)', () {
    final cook = CookState(
      active: true,
      startedAtMs: 0,
      items: const <CookItem>[
        CookItem(
          presetId: 'pork_sausage',
          jack: ProbeJack.two,
          addedAtMs: 0,
          timeline: CookTimeline(totalMin: MinuteRange(10, 20)),
        ),
      ],
    );

    test('a long add is flagged with the computed delay', () {
      final brisket = setupFoodById(foods, 'beef_brisket')!;
      final delay = longItemDelayMin(
        cook: cook,
        food: brisket,
        nowMs: 0,
        catalog: kCatalogTable,
      );
      // Existing ends at minute 15 (mid of 10–20); the new mid is 720.
      expect(delay, 705);
    });

    test('a comparable add is not flagged', () {
      // Existing brisket ends around minute 720; the sausage's mid is close.
      final brisketCook = CookState(
        active: true,
        startedAtMs: 0,
        items: const <CookItem>[
          CookItem(
            presetId: 'beef_brisket',
            jack: ProbeJack.one,
            addedAtMs: 0,
            timeline: CookTimeline(totalMin: MinuteRange(600, 840)),
          ),
        ],
      );
      final sausage = setupFoodById(foods, 'pork_sausage')!;
      final delay = longItemDelayMin(
        cook: brisketCook,
        food: sausage,
        nowMs: 0,
        catalog: kCatalogTable,
      );
      expect(delay, isNull);
    });

    test('no guard when nothing is on the grill', () {
      final brisket = setupFoodById(foods, 'beef_brisket')!;
      final delay = longItemDelayMin(
        cook: const CookState(),
        food: brisket,
        nowMs: 0,
        catalog: kCatalogTable,
      );
      expect(delay, isNull);
    });
  });

  group('custom food (N9.17/N9.18)', () {
    test('a below-floor custom target is refused (I12)', () {
      final refusal = customTargetRefusal(
        hazard: HazardClass.ground,
        targetF10: 1350,
      );
      expect(refusal, isNotNull);
      expect(refusal, contains('160°F'));

      expect(
        customTargetRefusal(hazard: HazardClass.poultry, targetF10: 1650),
        isNull,
      );
      // Intact whole-muscle red meat has no floor in enthusiast mode.
      expect(
        customTargetRefusal(
          hazard: HazardClass.wholeMuscleRedMeat,
          targetF10: 1350,
        ),
        isNull,
      );
    });

    test('the form builds the food with its own timeline', () {
      final food = customFoodFromForm(
        id: 'custom_1',
        name: 'Smoked Lamb Ribs',
        category: 'Lamb',
        glyph: 'ribs',
        hazard: HazardClass.wholeMuscleRedMeat,
        thickness: CutThickness.thin,
        pitLoF: 225,
        pitHiF: 275,
        targetF: 145,
        restMin: 10,
        totalLoMin: 90,
        totalHiMin: 150,
        wrapF: 165,
        spritzMin: 30,
      );
      expect(food.id, 'custom_1');
      expect(food.targetF10, 1450);
      expect(food.pitBandMinF10, 2250);
      expect(food.pitBandMaxF10, 2750);
      expect(food.timeline!.totalMin, const MinuteRange(90, 150));
      expect(food.timeline!.wrap!.tempF10, 1650);
      expect(food.timeline!.spritzEveryMin, 30);
      expect(food.timeline!.restMin, 10);
      expect(food.timeline!.phases.map((p) => p.id), ['on', 'pull']);
    });

    test('a zero wrap and spritz mean never', () {
      final food = customFoodFromForm(
        id: 'custom_2',
        name: 'Cold Plate',
        category: 'Sides',
        glyph: 'side',
        hazard: HazardClass.unstated,
        thickness: CutThickness.medium,
        pitLoF: 225,
        pitHiF: 275,
        targetF: 40,
        restMin: 0,
        totalLoMin: 5,
        totalHiMin: 10,
        wrapF: 0,
        spritzMin: 0,
      );
      expect(food.timeline!.wrap, isNull);
      expect(food.timeline!.spritzEveryMin, isNull);
    });
  });
}
