/// A22.1 — the cook-plan domain, and the food-safety gate (design 13 §13.5.3).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/plan/plan.dart';

CookPlan _plan(HazardClass hazard, int targetF10) => CookPlan(
  presetId: 'test',
  title: 'test',
  hazard: hazard,
  doneness: 'test',
  probes: [
    const PlanProbe(jack: 1, isPit: true, name: 'Pit'),
    PlanProbe(
      jack: 2,
      isPit: false,
      name: 'Food',
      targetF10: targetF10,
      pullF10: targetF10 - 50,
    ),
  ],
);

void main() {
  group('safety floors are enforced', () {
    test('poultry below 165 °F is refused', () {
      expect(() => _plan(HazardClass.poultry, 1600), throwsArgumentError);
    });

    test('poultry at exactly 165 °F is allowed', () {
      expect(() => _plan(HazardClass.poultry, 1650), returnsNormally);
    });

    test('ground below 160 °F is refused', () {
      expect(() => _plan(HazardClass.ground, 1550), throwsArgumentError);
    });

    test('pork below 145 °F is refused', () {
      expect(() => _plan(HazardClass.pork, 1400), throwsArgumentError);
    });

    test('fish below 145 °F is refused', () {
      expect(() => _plan(HazardClass.fish, 1440), throwsArgumentError);
    });
  });

  group('whole-muscle red meat has NO floor', () {
    test('a 125 °F rare steak constructs freely', () {
      expect(
        () => _plan(HazardClass.wholeMuscleRedMeat, 1250),
        returnsNormally,
        reason:
            'a rare ribeye is a preference on a surface-pasteurised cut, '
            'not an unsafe cook — the UI must not lecture about it',
      );
    });

    test('forClass returns null for whole-muscle red meat', () {
      expect(SafetyFloor.forClass(HazardClass.wholeMuscleRedMeat), isNull);
    });

    test('the pit probe is never floor-checked', () {
      // A pit target below any floor must still build — the pit is not food.
      expect(
        () => CookPlan(
          presetId: 't',
          title: 't',
          hazard: HazardClass.poultry,
          doneness: 't',
          probes: const [PlanProbe(jack: 1, isPit: true, name: 'Pit')],
          pitBandMinF10: 2750,
          pitBandMaxF10: 3250,
        ),
        returnsNormally,
      );
    });
  });

  group('the preset library is internally consistent', () {
    test('every preset builds a plan for every doneness without throwing', () {
      for (final preset in Presets.all) {
        for (final d in preset.doneness) {
          expect(
            () => CookPlan(
              presetId: preset.id,
              title: '${preset.name} — ${d.label}',
              hazard: preset.hazard,
              doneness: d.label,
              pitBandMinF10: preset.pitBandMinF10,
              pitBandMaxF10: preset.pitBandMaxF10,
              probes: [
                PlanProbe(jack: 1, isPit: true, name: 'Pit'),
                PlanProbe(
                  jack: 2,
                  isPit: false,
                  name: preset.name,
                  targetF10: d.targetF10,
                  pullF10: d.pullF10,
                ),
              ],
            ),
            returnsNormally,
            reason: '${preset.id} / ${d.id} must satisfy its own hazard floor',
          );
        }
      }
    });

    test('pull is never above target', () {
      for (final preset in Presets.all) {
        for (final d in preset.doneness) {
          expect(
            d.pullF10,
            lessThanOrEqualTo(d.targetF10),
            reason: '${preset.id}/${d.id}: you cannot pull hotter than target',
          );
        }
      }
    });

    test('every preset has a pit band with min below max', () {
      for (final preset in Presets.all) {
        expect(
          preset.pitBandMinF10,
          lessThan(preset.pitBandMaxF10),
          reason: preset.id,
        );
      }
    });

    test('categories cover every preset', () {
      for (final preset in Presets.all) {
        expect(
          Presets.categories,
          contains(preset.category),
          reason: preset.id,
        );
      }
    });

    test('byId round-trips', () {
      for (final preset in Presets.all) {
        expect(Presets.byId(preset.id)?.name, preset.name);
      }
      expect(Presets.byId('nope'), isNull);
    });
  });
}
