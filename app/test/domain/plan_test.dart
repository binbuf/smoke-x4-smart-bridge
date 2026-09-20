/// A22.1 — the cook-plan domain, and the food-safety gate (design 13 §13.5.3),
/// hardened per newapp §D.4 with the intact-cut flag and the two labelled modes.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/plan/plan.dart';

CookPlan _plan(
  HazardClass hazard,
  int targetF10, {
  bool isIntact = true,
  SafetyMode mode = SafetyMode.enthusiast,
}) => CookPlan(
  presetId: 'test',
  title: 'test',
  hazard: hazard,
  doneness: 'test',
  safetyMode: mode,
  probes: [
    PlanProbe(jack: 1, isPit: true, name: 'Pit'),
    PlanProbe(
      jack: 2,
      isPit: false,
      name: 'Food',
      targetF10: targetF10,
      pullF10: targetF10 - 50,
      isIntact: isIntact,
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

    test('neither mode relaxes poultry, ground, pork or fish', () {
      for (final mode in SafetyMode.values) {
        expect(
          () => _plan(HazardClass.poultry, 1600, mode: mode),
          throwsArgumentError,
          reason: '${mode.name} must not move the 165 °F poultry floor',
        );
        expect(
          () => _plan(HazardClass.ground, 1550, mode: mode),
          throwsArgumentError,
        );
        expect(
          () => _plan(HazardClass.pork, 1400, mode: mode),
          throwsArgumentError,
        );
        expect(
          () => _plan(HazardClass.fish, 1440, mode: mode),
          throwsArgumentError,
        );
      }
    });
  });

  group('§D.4 — the table covers every class the app can name', () {
    test('only intact red meat in enthusiast mode is floor-free', () {
      // The guard for the next class somebody adds: a member with no case and
      // no citation is a protein that silently inherits "no floor".
      for (final h in HazardClass.values) {
        final floor = SafetyFloor.forClass(h, mode: SafetyMode.enthusiast);
        if (h == HazardClass.wholeMuscleRedMeat) {
          expect(floor, isNull, reason: 'an intact cut is surface-only');
          continue;
        }
        expect(floor, isNotNull, reason: '${h.name} must carry a floor');
        expect(
          floor!.source,
          isNotNull,
          reason: '${h.name} must cite where its floor comes from',
        );
      }
    });

    test('every class has words for a chip and for a sentence', () {
      for (final h in HazardClass.values) {
        expect(h.label, isNotEmpty, reason: h.name);
        expect(h.phrase, isNotEmpty, reason: h.name);
      }
    });

    test('egg dishes take the 160 °F floor', () {
      // §D.4's sixth row. Without it a custom quiche fell through to red meat,
      // which is the one class with no floor at all.
      final floor = SafetyFloor.forClass(HazardClass.egg);
      expect(floor?.minF10, 1600);
      expect(floor?.source, contains('USDA FSIS'));
      expect(() => _plan(HazardClass.egg, 1550), throwsArgumentError);
      expect(() => _plan(HazardClass.egg, 1600), returnsNormally);
    });

    test('nothing stated takes the 160 °F ground-meat floor', () {
      // The precautionary default §D.4 applies to tenderized meat, applied to
      // the case where the app has not been told what the meat *is*.
      final floor = SafetyFloor.forClass(HazardClass.unstated);
      expect(floor?.minF10, 1600);
      expect(() => _plan(HazardClass.unstated, 1400), throwsArgumentError);
      expect(() => _plan(HazardClass.unstated, 1600), returnsNormally);
    });

    test('neither mode moves the egg or the unstated floor', () {
      for (final mode in SafetyMode.values) {
        expect(
          () => _plan(HazardClass.egg, 1550, mode: mode),
          throwsArgumentError,
          reason: '${mode.name} must not move the 160 °F egg floor',
        );
        expect(
          () => _plan(HazardClass.unstated, 1550, mode: mode),
          throwsArgumentError,
          reason: '${mode.name} is a reading of a known hazard; there is none',
        );
      }
    });

    test('an unstated jack cannot inherit a permissive plan hazard', () {
      // The shape of the bug this closes: a red-meat plan with chicken on
      // jack 3. The jack states its own class, so the plan's does not apply.
      expect(
        () => CookPlan(
          presetId: 'custom',
          title: 'mixed',
          hazard: HazardClass.wholeMuscleRedMeat,
          doneness: '',
          probes: [
            PlanProbe(jack: 1, isPit: true, name: 'Pit'),
            PlanProbe(
              jack: 2,
              isPit: false,
              name: 'Something',
              targetF10: 1400,
              hazard: HazardClass.unstated,
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('the refusal names both temperatures and the protein', () {
      // The message is read on the setup sheet by a tired person, so it has to
      // stand on its own without a status code or an enum name.
      try {
        _plan(HazardClass.poultry, 1400);
        fail('the gate should have refused');
      } on ArgumentError catch (e) {
        final message = e.message.toString();
        expect(message, contains('140°F'));
        expect(message, contains('165°F'));
        expect(message, contains('poultry'));
        expect(message, contains('USDA FSIS'));
      }
    });
  });

  group('§D.4 — carryover never crosses a floor', () {
    test('carryoverF10For is the one table both paths read', () {
      for (final t in CutThickness.values) {
        expect(
          carryoverF10For(hazard: HazardClass.poultry, thickness: t),
          0,
          reason:
              'USDA is explicit that carryover cannot be relied on to bring '
              'an under-cooked bird up to 165 °F, at any thickness',
        );
      }
      expect(
        carryoverF10For(
          hazard: HazardClass.wholeMuscleRedMeat,
          thickness: CutThickness.thin,
        ),
        20,
      );
      expect(
        carryoverF10For(
          hazard: HazardClass.wholeMuscleRedMeat,
          thickness: CutThickness.thick,
        ),
        80,
      );
      expect(
        carryoverF10For(
          hazard: HazardClass.wholeMuscleRedMeat,
          thickness: CutThickness.sousVide,
        ),
        0,
        reason: 'ThermoWorks: sous vide has no carryover at all',
      );
      // The preset table and the custom path must not be able to disagree.
      final roast = Presets.byId('beef_prime_rib')!;
      expect(
        roast.carryoverF10,
        carryoverF10For(hazard: roast.hazard, thickness: roast.thickness),
      );
    });

    test('an intact roast still comes off 8 °F early', () {
      expect(
        safePullF10(
          targetF10: 1350,
          carryoverF10: 80,
          hazard: HazardClass.wholeMuscleRedMeat,
        ),
        1270,
        reason: 'no floor to cross, so the measured carryover stands',
      );
    });

    test('ground beef at 160 °F comes off at 160 °F, not 152 °F', () {
      expect(
        safePullF10(
          targetF10: 1600,
          carryoverF10: 80,
          hazard: HazardClass.ground,
        ),
        1600,
        reason:
            '"take it off early and let it coast up" is exactly the promise '
            'USDA declines to make about a floor',
      );
    });

    test('an unstated cut cannot be pulled below 160 °F either', () {
      expect(
        safePullF10(
          targetF10: 1700,
          carryoverF10: 80,
          hazard: HazardClass.unstated,
        ),
        1620,
      );
      expect(
        safePullF10(
          targetF10: 1650,
          carryoverF10: 80,
          hazard: HazardClass.unstated,
        ),
        1600,
      );
    });

    test('USDA-compliant mode holds red meat at 145 °F on the way off', () {
      expect(
        safePullF10(
          targetF10: 1450,
          carryoverF10: 80,
          hazard: HazardClass.wholeMuscleRedMeat,
          mode: SafetyMode.usdaCompliant,
        ),
        1450,
        reason:
            'FSIS says 145 °F "before removing meat from the heat source" — '
            'the 3-minute rest is after that, not instead of it',
      );
    });

    test('a tenderized cut is clamped like the ground meat it behaves as', () {
      expect(
        safePullF10(
          targetF10: 1600,
          carryoverF10: 80,
          hazard: HazardClass.wholeMuscleRedMeat,
          isIntact: false,
        ),
        1600,
      );
    });

    test('pull is never above target, even below a floor', () {
      // A target under its floor is refused by the gate, but the sheet renders
      // a pull temperature before the gate runs, and "pull at 165, target 140"
      // is nonsense on the way to a refusal.
      expect(
        safePullF10(
          targetF10: 1400,
          carryoverF10: 50,
          hazard: HazardClass.poultry,
        ),
        1400,
      );
    });

    test('every preset pulls at or above its own floor', () {
      for (final preset in Presets.all) {
        for (final mode in SafetyMode.values) {
          for (final d in preset.doneness) {
            final pull = preset.pullF10For(d, mode: mode);
            final floor = SafetyFloor.forClass(
              preset.hazard,
              isIntact: preset.isIntact,
              mode: mode,
            );
            expect(
              pull,
              lessThanOrEqualTo(d.targetF10),
              reason: '${preset.id}/${d.id}',
            );
            if (floor != null && d.targetF10 >= floor.minF10) {
              expect(
                pull,
                greaterThanOrEqualTo(floor.minF10),
                reason:
                    '${preset.id}/${d.id} in ${mode.name}: a preset may not '
                    'talk anyone into taking food off below its minimum',
              );
            }
          }
        }
      }
    });
  });

  group('§D.4 — the safety strip is one list of words', () {
    test('the raw-meat line is always there, and always last', () {
      expect(safetyStripFor(), [rawMeatAdvisory]);
      expect(safetyStripFor(intactRedMeat: true).last, rawMeatAdvisory);
    });

    test('an intact red-meat cook adds the tenderized-cut caveat', () {
      expect(safetyStripFor(intactRedMeat: true), [
        intactCutAdvisory,
        rawMeatAdvisory,
      ]);
      final plan = _plan(HazardClass.wholeMuscleRedMeat, 1350);
      expect(plan.safetyStripLines, [intactCutAdvisory, rawMeatAdvisory]);
    });

    test('a poultry cook carries the raw-meat line alone', () {
      // The intact caveat is about a fact the app is trusting the user for.
      // There is no such fact on a chicken, so the second sentence would be
      // noise on the one screen that must stay readable at 3 a.m.
      expect(_plan(HazardClass.poultry, 1650).safetyStripLines, [
        rawMeatAdvisory,
      ]);
    });
  });

  group('intact whole-muscle red meat has NO floor', () {
    test('a 125 °F rare steak constructs freely', () {
      expect(
        () => _plan(HazardClass.wholeMuscleRedMeat, 1250),
        returnsNormally,
        reason:
            'a rare ribeye is a preference on a surface-pasteurised cut, '
            'not an unsafe cook — the UI must not lecture about it',
      );
    });

    test('forClass returns null for intact red meat in enthusiast mode', () {
      expect(
        SafetyFloor.forClass(
          HazardClass.wholeMuscleRedMeat,
          mode: SafetyMode.enthusiast,
        ),
        isNull,
      );
    });

    test('the pit probe is never floor-checked', () {
      // A pit target below any floor must still build — the pit is not food.
      expect(
        () => CookPlan(
          presetId: 't',
          title: 't',
          hazard: HazardClass.poultry,
          doneness: 't',
          probes: [PlanProbe(jack: 1, isPit: true, name: 'Pit')],
          pitBandMinF10: 2750,
          pitBandMaxF10: 3250,
        ),
        returnsNormally,
      );
    });
  });

  group('§D.4 — the intact-cut flag is the load-bearing qualifier', () {
    test('tenderized red meat takes the 160 °F ground floor', () {
      expect(
        () => _plan(HazardClass.wholeMuscleRedMeat, 1350, isIntact: false),
        throwsArgumentError,
        reason:
            'blade-tenderized or injected beef carries surface bacteria into '
            'the centre, so it behaves like ground meat',
      );
    });

    test('tenderized red meat at 160 °F is allowed', () {
      expect(
        () => _plan(HazardClass.wholeMuscleRedMeat, 1600, isIntact: false),
        returnsNormally,
      );
    });

    test('neither mode waives the non-intact floor', () {
      for (final mode in SafetyMode.values) {
        expect(
          () => _plan(
            HazardClass.wholeMuscleRedMeat,
            1350,
            isIntact: false,
            mode: mode,
          ),
          throwsArgumentError,
          reason: '${mode.name} must not let a needled steak run medium-rare',
        );
      }
    });

    test('forClass gives non-intact red meat the ground floor', () {
      final floor = SafetyFloor.forClass(
        HazardClass.wholeMuscleRedMeat,
        isIntact: false,
      );
      expect(floor?.minF10, 1600);
    });

    test('the advisory is copy for intact red meat, not a refusal', () {
      expect(
        SafetyFloor.needsIntactAdvisory(HazardClass.wholeMuscleRedMeat),
        isTrue,
      );
      expect(SafetyFloor.needsIntactAdvisory(HazardClass.poultry), isFalse);
      expect(
        _plan(HazardClass.wholeMuscleRedMeat, 1350).needsIntactAdvisory,
        isTrue,
      );
    });
  });

  group('§D.4 — USDA-compliant mode', () {
    test('refuses medium-rare red meat', () {
      expect(
        () => _plan(
          HazardClass.wholeMuscleRedMeat,
          1350,
          mode: SafetyMode.usdaCompliant,
        ),
        throwsArgumentError,
      );
    });

    test('allows 145 °F, and carries the 3-minute rest', () {
      expect(
        () => _plan(
          HazardClass.wholeMuscleRedMeat,
          1450,
          mode: SafetyMode.usdaCompliant,
        ),
        returnsNormally,
      );
      final floor = SafetyFloor.forClass(
        HazardClass.wholeMuscleRedMeat,
        mode: SafetyMode.usdaCompliant,
      );
      expect(floor?.minF10, 1450);
      expect(floor?.restMinutes, 3);
    });
  });

  group('§D.4 — the gate runs per jack, not per plan', () {
    test('a mixed cook refuses only the jack that is unsafe', () {
      expect(
        () => CookPlan(
          presetId: 'custom',
          title: 'mixed',
          hazard: HazardClass.wholeMuscleRedMeat,
          doneness: '',
          probes: [
            PlanProbe(jack: 1, isPit: true, name: 'Pit'),
            // A medium-rare ribeye under the plan's own hazard: fine.
            PlanProbe(jack: 2, isPit: false, name: 'Ribeye', targetF10: 1350),
            // Chicken on jack 3, below its own floor: refused, even though the
            // plan-level hazard would have waved it through.
            PlanProbe(
              jack: 3,
              isPit: false,
              name: 'Thighs',
              targetF10: 1600,
              hazard: HazardClass.poultry,
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('the same mixed cook builds once the chicken is safe', () {
      expect(
        () => CookPlan(
          presetId: 'custom',
          title: 'mixed',
          hazard: HazardClass.wholeMuscleRedMeat,
          doneness: '',
          probes: [
            PlanProbe(jack: 1, isPit: true, name: 'Pit'),
            PlanProbe(jack: 2, isPit: false, name: 'Ribeye', targetF10: 1350),
            PlanProbe(
              jack: 3,
              isPit: false,
              name: 'Thighs',
              targetF10: 1650,
              hazard: HazardClass.poultry,
            ),
          ],
        ),
        returnsNormally,
      );
    });
  });

  group('§D.3 — a cook with no target is a valid cook', () {
    test('every food jack targetless builds, and says so', () {
      final plan = CookPlan(
        presetId: 'custom',
        title: 'Cook',
        hazard: HazardClass.poultry,
        doneness: '',
        probes: [
          PlanProbe(jack: 1, isPit: true, name: 'Pit'),
          PlanProbe(jack: 2, isPit: false, name: ''),
        ],
      );
      expect(plan.hasNoTarget, isTrue);
      expect(plan.primaryFood?.jack, 2);
    });

    test('a retarget on a running cook re-runs the gate', () {
      final plan = _plan(HazardClass.poultry, 1650);
      expect(
        () => plan.copyWith(
          probes: [
            PlanProbe(jack: 1, isPit: true, name: 'Pit'),
            PlanProbe(jack: 2, isPit: false, name: 'Food', targetF10: 1400),
          ],
        ),
        throwsArgumentError,
        reason: 'editing a running cook must not be a way around the gate',
      );
    });

    test('copyWith preserves the start time and the cook id', () {
      final plan = _plan(HazardClass.poultry, 1650)
        ..startedUnixMs = 1234
        ..cookId = 7;
      final next = plan.copyWith(title: 'renamed');
      expect(next.title, 'renamed');
      expect(next.startedUnixMs, 1234);
      expect(next.cookId, 7);
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
                  pullF10: preset.pullF10For(d),
                  isIntact: preset.isIntact,
                ),
              ],
            ),
            returnsNormally,
            reason: '${preset.id} / ${d.id} must satisfy its own hazard floor',
          );
        }
      }
    });

    test('every preset is safe in USDA-compliant mode too, or is red meat', () {
      // The point of the mode is that it is *stricter*; the only presets it may
      // refuse are whole-muscle red-meat donenesses below 145 °F, which is
      // exactly what choosing that mode means.
      for (final preset in Presets.all) {
        if (preset.hazard == HazardClass.wholeMuscleRedMeat) {
          continue;
        }
        for (final d in preset.doneness) {
          expect(
            () => CookPlan(
              presetId: preset.id,
              title: preset.name,
              hazard: preset.hazard,
              doneness: d.label,
              safetyMode: SafetyMode.usdaCompliant,
              probes: [
                PlanProbe(
                  jack: 2,
                  isPit: false,
                  name: preset.name,
                  targetF10: d.targetF10,
                ),
              ],
            ),
            returnsNormally,
            reason: '${preset.id}/${d.id}',
          );
        }
      }
    });

    test('pull is never above target', () {
      for (final preset in Presets.all) {
        for (final d in preset.doneness) {
          expect(
            preset.pullF10For(d),
            lessThanOrEqualTo(d.targetF10),
            reason: '${preset.id}/${d.id}: you cannot pull hotter than target',
          );
        }
      }
    });

    test('§D.4 — poultry carries zero carryover, whatever its thickness', () {
      for (final preset in Presets.all) {
        if (preset.hazard != HazardClass.poultry) {
          continue;
        }
        expect(
          preset.carryoverF10,
          0,
          reason:
              '${preset.id}: USDA is explicit that carryover cannot be relied '
              'on to bring an under-cooked bird up to 165 °F, so the app must '
              'verify poultry by sensor and never pull it early',
        );
        for (final d in preset.doneness) {
          expect(preset.pullF10For(d), d.targetF10, reason: preset.id);
        }
      }
    });

    test('§D.4 — a 1 inch steak coasts a couple of degrees, not five', () {
      final ribeye = Presets.byId('beef_ribeye')!;
      expect(ribeye.thickness, CutThickness.thin);
      expect(ribeye.carryoverF10, lessThanOrEqualTo(30));
    });

    test('§D.4 — a thick roast coasts 5–10 °F', () {
      final roast = Presets.byId('beef_prime_rib')!;
      expect(roast.thickness, CutThickness.thick);
      expect(roast.carryoverF10, inInclusiveRange(50, 100));
    });

    test('§D.4 — targets are post-rest finals on the MEATER ladder', () {
      // Do not double-count: the ladder is what the meat ENDS at.
      expect(DonenessLadder.rare.targetF10, 1250);
      expect(DonenessLadder.mediumRare.targetF10, 1350);
      expect(DonenessLadder.medium.targetF10, 1450);
      expect(DonenessLadder.mediumWell.targetF10, 1550);
      expect(DonenessLadder.wellDone.targetF10, 1650);
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

    test('§D.4 — the library has a preset for every hazard class it gates', () {
      // Eggs were the missing row: no preset meant no path to the class, and
      // no path to the class meant a custom quiche was gated as steak.
      final covered = {for (final p in Presets.all) p.hazard};
      for (final h in HazardClass.values) {
        if (h == HazardClass.unstated) {
          continue; // not a thing you can cook — it is the absence of an answer
        }
        expect(
          covered,
          contains(h),
          reason: '${h.name} has a floor but nothing in the picker reaches it',
        );
      }
    });

    test('§D.4 — the egg presets sit on the 160 °F floor', () {
      final eggs = Presets.all.where((p) => p.hazard == HazardClass.egg);
      expect(eggs, isNotEmpty);
      for (final p in eggs) {
        for (final d in p.doneness) {
          expect(d.targetF10, greaterThanOrEqualTo(1600), reason: p.id);
          expect(
            p.pullF10For(d),
            greaterThanOrEqualTo(1600),
            reason: '${p.id}: a custard may not be pulled under 160 °F either',
          );
        }
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

  group('the plan round-trips through JSON', () {
    test('mode, intact flag, per-jack hazard and cook id all survive', () {
      final plan = CookPlan(
        presetId: 'custom',
        title: 'mixed',
        hazard: HazardClass.wholeMuscleRedMeat,
        doneness: 'medium rare',
        safetyMode: SafetyMode.usdaCompliant,
        probes: [
          PlanProbe(jack: 1, isPit: true, name: 'Pit'),
          // Non-intact, so 160 °F is the floor — the round trip has to carry
          // that flag or the restored plan would be gated differently.
          PlanProbe(
            jack: 2,
            isPit: false,
            name: 'Ribeye',
            targetF10: 1600,
            pullF10: 1580,
            isIntact: false,
            hazard: HazardClass.wholeMuscleRedMeat,
            doneness: 'medium',
          ),
        ],
      )..cookId = 12;

      final back = CookPlan.fromJson(plan.toJson())!;
      expect(back.safetyMode, SafetyMode.usdaCompliant);
      expect(back.cookId, 12);
      final food = back.probes.firstWhere((p) => p.jack == 2);
      expect(food.isIntact, isFalse);
      expect(food.hazard, HazardClass.wholeMuscleRedMeat);
      expect(food.doneness, 'medium');
      expect(food.pullF10, 1580);
    });

    test('a plan stored before modes existed restores as enthusiast', () {
      final legacy = <String, Object?>{
        'preset_id': 'beef_ribeye',
        'title': 'Ribeye',
        'hazard': 'wholeMuscleRedMeat',
        'doneness': 'Medium rare',
        'probes': [
          {'jack': 2, 'is_pit': false, 'name': 'Ribeye', 'target_f10': 1350},
        ],
        'started_unix_ms': 99,
      };
      final back = CookPlan.fromJson(legacy)!;
      expect(
        back.safetyMode,
        SafetyMode.enthusiast,
        reason:
            'it was built under the old "red meat has no floor" rule; '
            'restoring it as USDA-compliant would silently drop a valid cook',
      );
      expect(back.probes.single.targetF10, 1350);
    });

    test('a stored plan that would now be refused is dropped, not thrown', () {
      final unsafe = <String, Object?>{
        'preset_id': 'x',
        'title': 'x',
        'hazard': 'poultry',
        'doneness': '',
        'probes': [
          {'jack': 2, 'is_pit': false, 'name': 'Chicken', 'target_f10': 1400},
        ],
      };
      expect(CookPlan.fromJson(unsafe), isNull);
    });
  });
}
