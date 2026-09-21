/// N1.5/N1.6/N1.7/N1.16 — food-safety floors, doneness ladders, carryover,
/// pull temperatures, and the `CookPlan` gate.
library;

import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

CookPreset _ribeye() => const CookPreset(
  id: 'beef_ribeye',
  category: 'Beef',
  name: 'Ribeye',
  hazard: HazardClass.wholeMuscleRedMeat,
  thickness: CutThickness.thin,
  pitBandMinF10: 2000,
  pitBandMaxF10: 2500,
  doneness: DonenessLadder.steak,
);

CookPreset _burger() => const CookPreset(
  id: 'beef_burger',
  category: 'Beef',
  name: 'Burger',
  hazard: HazardClass.ground,
  thickness: CutThickness.thin,
  pitBandMinF10: 3250,
  pitBandMaxF10: 3750,
  doneness: [Doneness(id: 'done', label: 'Done', targetF10: 1600)],
);

void main() {
  group('N1.5 hazard floors', () {
    test('unstated carries the 160 °F ground floor in both modes', () {
      for (final mode in SafetyMode.values) {
        final floor = SafetyFloor.forClass(HazardClass.unstated, mode: mode)!;
        expect(floor.minF10, 1600);
      }
    });

    test(
      'intact whole-muscle red meat has no floor only in enthusiast mode',
      () {
        expect(SafetyFloor.forClass(HazardClass.wholeMuscleRedMeat), isNull);
        final usda = SafetyFloor.forClass(
          HazardClass.wholeMuscleRedMeat,
          mode: SafetyMode.usdaCompliant,
        )!;
        expect(usda.minF10, 1450);
        expect(usda.restMinutes, 3);
      },
    );

    test('non-intact red meat takes the ground floor in both modes', () {
      for (final mode in SafetyMode.values) {
        final floor = SafetyFloor.forClass(
          HazardClass.wholeMuscleRedMeat,
          isIntact: false,
          mode: mode,
        )!;
        expect(floor.minF10, 1600);
      }
    });

    test('poultry, ground, pork, fish and egg floors', () {
      expect(SafetyFloor.forClass(HazardClass.poultry)!.minF10, 1650);
      expect(SafetyFloor.forClass(HazardClass.ground)!.minF10, 1600);
      expect(SafetyFloor.forClass(HazardClass.pork)!.minF10, 1450);
      expect(SafetyFloor.forClass(HazardClass.fish)!.minF10, 1450);
      expect(SafetyFloor.forClass(HazardClass.egg)!.minF10, 1600);
    });

    test('the intact advisory only applies to claimed-intact red meat', () {
      expect(
        SafetyFloor.needsIntactAdvisory(HazardClass.wholeMuscleRedMeat),
        isTrue,
      );
      expect(SafetyFloor.needsIntactAdvisory(HazardClass.poultry), isFalse);
      expect(
        SafetyFloor.needsIntactAdvisory(
          HazardClass.wholeMuscleRedMeat,
          isIntact: false,
        ),
        isFalse,
      );
    });
  });

  group('N1.6 doneness ladders', () {
    test('red meat defaults to medium rare', () {
      final preset = _ribeye();
      expect(preset.defaultDoneness.id, 'medrare');
      expect(preset.defaultDoneness.targetF10, 1350);
    });

    test('low-and-slow proteins default to their last level', () {
      expect(_burger().defaultDoneness.id, 'done');
    });
  });

  group('N1.7 carryover and pull temperature', () {
    test('poultry carryover is always zero, whatever the thickness', () {
      for (final thickness in CutThickness.values) {
        expect(
          carryoverFor(hazard: HazardClass.poultry, thickness: thickness),
          0,
        );
      }
    });

    test('carryover is by thickness, not doneness', () {
      expect(
        carryoverFor(
          hazard: HazardClass.wholeMuscleRedMeat,
          thickness: CutThickness.thin,
        ),
        20,
      );
      expect(
        carryoverFor(
          hazard: HazardClass.wholeMuscleRedMeat,
          thickness: CutThickness.thick,
        ),
        80,
      );
      expect(
        carryoverFor(
          hazard: HazardClass.wholeMuscleRedMeat,
          thickness: CutThickness.sousVide,
        ),
        0,
      );
    });

    test('pull temp is target minus carryover on floor-free cuts', () {
      expect(
        pullTempFor(
          targetF10: 1350,
          carryoverF10: 20,
          hazard: HazardClass.wholeMuscleRedMeat,
        ),
        1330,
      );
    });

    test('pull temp is clamped at the safety floor', () {
      // A 160 °F ground-beef target on a thick patty pulls at 160 °F, not 152.
      expect(
        pullTempFor(
          targetF10: 1600,
          carryoverF10: 80,
          hazard: HazardClass.ground,
        ),
        1600,
      );
    });

    test('rest time derives from carryover and honours the safety minimum', () {
      expect(restSecondsFor(carryoverF10: 0), 0);
      expect(restSecondsFor(carryoverF10: 20), 300);
      expect(restSecondsFor(carryoverF10: 50), 600);
      expect(restSecondsFor(carryoverF10: 80), 1200);
      expect(restSecondsFor(carryoverF10: 0, safetyRestS: 180), 180);
    });
  });

  group('N1.16 CookPlan is the safety gate (I12)', () {
    CookPlan burgerPlan({int targetF10 = 1600}) => CookPlan(
      presetId: 'beef_burger',
      title: 'Burgers',
      hazard: HazardClass.ground,
      doneness: 'Done',
      probes: [
        PlanProbe(
          jack: ProbeJack.one,
          isPit: false,
          name: 'Burger',
          targetF10: targetF10,
        ),
      ],
    );

    test('an unsafe target throws rather than warning', () {
      expect(() => burgerPlan(targetF10: 1400), throwsArgumentError);
    });

    test('an intact rare steak constructs freely in enthusiast mode', () {
      final plan = CookPlan(
        presetId: 'beef_ribeye',
        title: 'Ribeye',
        hazard: HazardClass.wholeMuscleRedMeat,
        doneness: 'Medium rare',
        probes: [
          PlanProbe(
            jack: ProbeJack.one,
            isPit: false,
            name: 'Ribeye',
            targetF10: 1350,
          ),
        ],
      );
      expect(plan.primaryFood!.targetF10, 1350);
    });

    test('fromJson re-runs the gate and drops a now-unsafe plan', () {
      final safe = burgerPlan();
      final restored = CookPlan.fromJson(safe.toJson());
      expect(restored, isNotNull);
      expect(restored!.probes.single.targetF10, 1600);

      // Hand-edit the stored JSON down to an unsafe target: the gate must run
      // on load, not only on construction.
      final json = safe.toJson();
      final probes = json['probes']! as List;
      (probes.single as Map<String, Object?>)['target_f10'] = 1400;
      expect(CookPlan.fromJson(json), isNull);
    });
  });
}
