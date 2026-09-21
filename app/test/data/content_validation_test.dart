/// N2.12 — content validation.
///
/// The reviewer-owned tables must stay internally consistent: every cut has a
/// timeline, every style points at a real preset, and no target dips below the
/// food-safety floor the app enforces at selection time.
///
/// **Documented exception.** The prototype catalog deliberately carries a small
/// set of raw / rosé / cold-serve rungs below their class floor (sashimi tuna,
/// rosé duck, warmed ham, cold sides). Reproducing the prototype's exact
/// numbers is a must-not-regress, so this test *pins the exact exception set*
/// rather than pretending it does not exist: a new unsafe rung fails the test,
/// and `CookPlan` still refuses one if a user selects it. `unstated` catalog
/// entries are non-meat content (vegetables, sides, desserts); N1's unstated
/// floor is about unknown *meat*, so it is not applied to declared non-meat.
library;

import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

/// Catalog rungs intentionally below their class floor.
const Map<String, Set<String>> pinnedCatalogBelowFloor = {
  'pork_ham': {'warm'},
  'poultry_duck': {'rose'},
  'poultry_duck_breast': {'rose', 'classic'},
  'fish_salmon': {'moist'},
  'fish_tuna': {'rare'},
  'fish_lobster': {'done'},
  'fish_crab': {'warm'},
  'game_rabbit': {'done'},
};

/// Style variants intentionally below their class floor.
const Map<String, Set<String>> pinnedStyleBelowFloor = {
  'beef_burger': {'tallow'},
  'pork_ham': {'honey_baked', 'dr_pepper'},
  'poultry_duck': {'tea_smoked', 'orange'},
  'poultry_duck_breast': {'pan_roast', 'honey_soy'},
  'fish_tuna': {'sesame_seared', 'teriyaki'},
  'fish_lobster': {'garlic_butter', 'cajun'},
  'fish_crab': {'garlic_butter', 'cajun'},
  'game_rabbit': {'hunter', 'bacon_wrapped'},
};

bool _isProteinFloor(HazardClass hazard) => switch (hazard) {
  HazardClass.poultry ||
  HazardClass.ground ||
  HazardClass.pork ||
  HazardClass.fish ||
  HazardClass.egg => true,
  HazardClass.unstated || HazardClass.wholeMuscleRedMeat => false,
};

void main() {
  final table = kCatalogTable;

  group('catalog shape', () {
    test('139 cuts across the 10 categories', () {
      expect(table.entries.length, 139);
      expect(table.categories, hasLength(10));
      for (final category in table.categories) {
        expect(
          table.entries.where((e) => e.category == category),
          isNotEmpty,
          reason: category,
        );
      }
      // Every entry's category is one of the declared categories.
      for (final entry in table.entries) {
        expect(table.categories, contains(entry.category), reason: entry.id);
      }
    });

    test('every catalog id has a timeline', () {
      expect(table.missingTimelines, isEmpty);
      expect(table.timelines.length, table.entries.length);
      for (final entry in table.entries) {
        expect(table.timelineFor(entry.id), isNotNull, reason: entry.id);
      }
    });

    test('every cut has styles and every style maps to a real preset', () {
      for (final entry in table.entries) {
        expect(table.stylesFor(entry.id), isNotEmpty, reason: entry.id);
      }
      expect(table.styledCutCount, table.entries.length);
      for (final key in table.styles.keys) {
        expect(table.byId(key), isNotNull, reason: key);
      }
    });

    test('the style table holds 331 named variants', () {
      expect(table.styleCount, 331);
    });

    test('every entry default doneness is on its own ladder', () {
      for (final entry in table.entries) {
        expect(
          entry.donenessById(entry.defaultDonenessId),
          isNotNull,
          reason: '${entry.id} default ${entry.defaultDonenessId}',
        );
      }
    });
  });

  group('food safety', () {
    test('catalog targets are at or above their protein floor, except pinned '
        'raw/rosé/cold rungs', () {
      final violations = <String, Set<String>>{};
      for (final entry in table.entries) {
        if (!_isProteinFloor(entry.hazard)) {
          continue;
        }
        final floor = SafetyFloor.forClass(entry.hazard);
        if (floor == null) {
          continue;
        }
        final below = {
          for (final d in entry.doneness)
            if (d.targetF10 < floor.minF10) d.id,
        };
        if (below.isNotEmpty) {
          violations[entry.id] = below;
        }
      }
      expect(violations, pinnedCatalogBelowFloor);
    });

    test('style targets are at or above their protein floor, except pinned '
        'raw/rosé/cold variants', () {
      final violations = <String, Set<String>>{};
      for (final entry in table.entries) {
        if (!_isProteinFloor(entry.hazard)) {
          continue;
        }
        final floor = SafetyFloor.forClass(entry.hazard);
        if (floor == null) {
          continue;
        }
        final below = {
          for (final style in table.stylesFor(entry.id))
            if (style.targetF10 != null && style.targetF10! < floor.minF10)
              style.id,
        };
        if (below.isNotEmpty) {
          violations[entry.id] = below;
        }
      }
      expect(violations, pinnedStyleBelowFloor);
    });

    test('the safe pull never rises above the target', () {
      for (final entry in table.entries) {
        for (final d in entry.doneness) {
          final pull = pullTempFor(
            targetF10: d.targetF10,
            carryoverF10: entry.carryoverF10,
            hazard: entry.hazard,
          );
          expect(pull, lessThanOrEqualTo(d.targetF10), reason: entry.id);
        }
      }
    });
  });
}
