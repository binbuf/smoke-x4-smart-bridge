/// The cook-setup sheet, and the food-safety gate it is the front door to
/// (newapp §D.4, risk §J3).
///
/// This file exists because the sheet had none, and the gap it left was not
/// cosmetic: "Something else" cleared the preset, nothing on the sheet could
/// name a protein, and the fallback class was whole-muscle red meat — the one
/// class with no floor. A custom cook of chicken thighs at 140 °F built and
/// started without a word. So the properties pinned here are the ones that
/// stop that, and each names the class of cook it protects:
///
///  * a targeted probe must say what is on it before the cook can start;
///  * whatever it says, including "not stated", carries a floor except the one
///    case §D.4 exempts — an intact whole-muscle cut in enthusiast mode;
///  * the pull offset can never take food off the heat below that floor;
///  * the refusal is copy on the sheet, not an exception the user must read.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/entities/entities.dart' show ProbeRole;
import 'package:smoke_bridge/domain/plan/plan.dart';
import 'package:smoke_bridge/features/cook/cook_setup_sheet.dart';
import 'package:smoke_bridge/ui/ui.dart';

void main() {
  late Future<CookPlan?> pending;

  Widget host({CookPlan? initial, bool celsius = false}) => MaterialApp(
    theme: SmokeTheme.dark,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => pending = showCookSetupSheet(
              context,
              celsius: celsius,
              initial: initial,
              probeNames: const {1: 'Pit', 2: 'Probe 2'},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  /// A view tall enough that the whole sheet lays out — the sheet is a
  /// ListView, and a control that has not been built cannot be tapped.
  Future<void> open(
    WidgetTester tester, {
    CookPlan? initial,
    bool celsius = false,
    Size size = const Size(1000, 5000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(initial: initial, celsius: celsius));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<void> chooseCustom(WidgetTester tester) =>
      tapKey(tester, 'cook-setup-custom');

  /// Scoped to the category track: "Poultry" and "Pork" are also hazard-chip
  /// labels, three jacks over.
  Future<void> chooseCategory(WidgetTester tester, String category) async {
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedChips<String>),
        matching: find.text(category),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> setHazard(WidgetTester tester, int jack, HazardClass h) =>
      tapKey(tester, 'hazard-$jack-${h.name}');

  Future<void> setTarget(WidgetTester tester, int jack, String value) async {
    await tester.enterText(find.byKey(Key('target-$jack')), value);
    await tester.pumpAndSettle();
  }

  Future<void> setThickness(
    WidgetTester tester,
    int jack,
    CutThickness thickness,
  ) async {
    await tester.tap(
      find.descendant(
        of: find.byKey(Key('jack-$jack')),
        matching: find.text(thickness.label),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('cook-setup-start')));
    await tester.pumpAndSettle();
  }

  bool startEnabled(WidgetTester tester) =>
      tester
          .widget<PrimaryAction>(find.byKey(const Key('cook-setup-start')))
          .onPressed !=
      null;

  PlanProbe probe(CookPlan plan, int jack) =>
      plan.probes.firstWhere((p) => p.jack == jack);

  group('§D.4 — a custom cook is subject to the gate', () {
    testWidgets('every food jack asks what is on it; the pit jack does not', (
      tester,
    ) async {
      await open(tester);
      await chooseCustom(tester);
      for (final jack in [2, 3, 4]) {
        for (final h in HazardClass.values) {
          expect(
            find.byKey(Key('hazard-$jack-${h.name}')),
            findsOneWidget,
            reason: 'jack $jack must be able to say it is ${h.name}',
          );
        }
      }
      expect(
        find.byKey(Key('hazard-1-${HazardClass.poultry.name}')),
        findsNothing,
        reason: 'jack 1 is the pit — a pit has no doneness and no hazard',
      );
    });

    testWidgets('the cook cannot start until a targeted probe says what it is', (
      tester,
    ) async {
      await open(tester);
      await chooseCustom(tester);
      await setTarget(tester, 2, '140');

      expect(startEnabled(tester), isFalse);
      // §16.7: not merely disabled — disabled with its reason on screen, and
      // the reason names the jack.
      expect(find.byKey(const Key('cook-setup-blocked')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('cook-setup-blocked')))
            .data,
        contains('Probe 2'),
      );

      await setHazard(tester, 2, HazardClass.poultry);
      expect(startEnabled(tester), isTrue);
      expect(find.byKey(const Key('cook-setup-blocked')), findsNothing);
    });

    testWidgets('a probe with no target needs no answer (§D.3 still holds)', (
      tester,
    ) async {
      await open(tester);
      await chooseCustom(tester);
      expect(
        startEnabled(tester),
        isTrue,
        reason:
            'a cook with no targets is a valid cook — the gate has nothing to '
            'refuse, so there is nothing to ask about yet',
      );
      await start(tester);
      final plan = await pending;
      expect(plan, isNotNull);
      expect(plan!.hasNoTarget, isTrue);
    });

    testWidgets('chicken thighs at 140°F are refused, on the sheet', (
      tester,
    ) async {
      await open(tester);
      await chooseCustom(tester);
      await setHazard(tester, 2, HazardClass.poultry);
      await setTarget(tester, 2, '140');
      await start(tester);

      // Copy over error: the sheet stays open with the reason on it.
      expect(find.text('Set up a cook'), findsOneWidget);
      expect(find.byKey(const Key('cook-setup-refusal')), findsOneWidget);
      final banner = tester.widget<InsightBanner>(
        find.byKey(const Key('cook-setup-refusal')),
      );
      expect(banner.label, contains('165°F'));
      expect(banner.label, contains('poultry'));
    });

    testWidgets('the same cook builds at 165°F and states poultry per jack', (
      tester,
    ) async {
      await open(tester);
      await chooseCustom(tester);
      await setHazard(tester, 2, HazardClass.poultry);
      await setTarget(tester, 2, '165');
      await start(tester);

      final plan = (await pending)!;
      expect(probe(plan, 2).hazard, HazardClass.poultry);
      expect(probe(plan, 2).targetF10, 1650);
      expect(
        probe(plan, 2).pullF10,
        1650,
        reason:
            'USDA: carryover cannot be relied on to bring an under-cooked '
            'bird up to 165 °F, so it is read, not predicted',
      );
    });

    testWidgets('"not stated" is an answer, and it costs the 160°F floor', (
      tester,
    ) async {
      await open(tester);
      await chooseCustom(tester);
      await setHazard(tester, 2, HazardClass.unstated);
      await setTarget(tester, 2, '140');
      await start(tester);

      expect(find.byKey(const Key('cook-setup-refusal')), findsOneWidget);
      expect(
        tester
            .widget<InsightBanner>(find.byKey(const Key('cook-setup-refusal')))
            .label,
        contains('160°F'),
      );

      await setTarget(tester, 2, '160');
      await start(tester);
      final plan = (await pending)!;
      expect(probe(plan, 2).hazard, HazardClass.unstated);
      expect(
        plan.hazard,
        HazardClass.unstated,
        reason:
            'the plan-level fallback used to be red meat, which is the one '
            'class with no floor — a later retarget would inherit it',
      );
    });

    testWidgets('an egg dish is reachable, and floors at 160°F', (
      tester,
    ) async {
      await open(tester);
      await chooseCustom(tester);
      await setHazard(tester, 2, HazardClass.egg);
      await setTarget(tester, 2, '150');
      await start(tester);
      expect(find.byKey(const Key('cook-setup-refusal')), findsOneWidget);

      await setTarget(tester, 2, '160');
      await start(tester);
      expect(probe((await pending)!, 2).hazard, HazardClass.egg);
    });

    testWidgets('the floor line names the minimum and cites it', (
      tester,
    ) async {
      await open(tester);
      await chooseCustom(tester);
      expect(
        tester.widget<Text>(find.byKey(const Key('floor-2'))).data,
        contains('Pick one'),
      );
      await setHazard(tester, 2, HazardClass.pork);
      final line = tester.widget<Text>(find.byKey(const Key('floor-2'))).data!;
      expect(line, contains('145°'));
      expect(line, contains('USDA FSIS'));
      expect(line, contains('3 minutes'), reason: 'the rest is part of the rule');
    });

    testWidgets('starting blank does not hand a later retarget red meat', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Start one now, decide later'));
      await tester.pumpAndSettle();
      final plan = (await pending)!;
      expect(plan.hazard, HazardClass.unstated);
    });

    testWidgets('a saved cook with no target still has to answer', (
      tester,
    ) async {
      // The shape a pre-existing blank cook comes back in: a red-meat plan
      // hazard, a food jack, and nothing that was ever gated. It must not
      // arrive pre-answered as the one class with no floor.
      await open(
        tester,
        initial: CookPlan(
          presetId: 'custom',
          title: 'Cook',
          hazard: HazardClass.wholeMuscleRedMeat,
          doneness: '',
          probes: [
            PlanProbe(jack: 1, isPit: true, name: 'Pit'),
            PlanProbe(jack: 2, isPit: false, role: ProbeRole.food, name: ''),
          ],
        ),
      );
      await setTarget(tester, 2, '140');
      expect(startEnabled(tester), isFalse);
      expect(find.byKey(const Key('cook-setup-blocked')), findsOneWidget);
    });
  });

  group('§D.4 — the intact split and the two labelled modes', () {
    testWidgets('an intact whole-muscle cut runs medium-rare', (tester) async {
      await open(tester);
      await chooseCustom(tester);
      await setHazard(tester, 2, HazardClass.wholeMuscleRedMeat);
      await setTarget(tester, 2, '135');
      expect(
        tester.widget<Text>(find.byKey(const Key('floor-2'))).data,
        contains('No fixed minimum'),
      );
      await start(tester);
      final plan = (await pending)!;
      expect(probe(plan, 2).targetF10, 1350);
      expect(probe(plan, 2).isIntact, isTrue);
    });

    testWidgets('turning intact off refuses the very same target', (
      tester,
    ) async {
      await open(tester);
      await chooseCustom(tester);
      await setHazard(tester, 2, HazardClass.wholeMuscleRedMeat);
      await setTarget(tester, 2, '135');
      await tapKey(tester, 'intact-2');
      expect(
        tester.widget<Text>(find.byKey(const Key('floor-2'))).data,
        contains('160°'),
      );
      await start(tester);
      expect(
        find.byKey(const Key('cook-setup-refusal')),
        findsOneWidget,
        reason:
            'a needled steak carries surface bacteria into the centre, so it '
            'takes the ground-meat floor',
      );
    });

    testWidgets('USDA-compliant mode refuses medium-rare and allows 145°F', (
      tester,
    ) async {
      await open(tester);
      await chooseCustom(tester);
      await setHazard(tester, 2, HazardClass.wholeMuscleRedMeat);
      await setTarget(tester, 2, '135');
      await tester.tap(find.text(SafetyMode.usdaCompliant.label));
      await tester.pumpAndSettle();
      await start(tester);
      expect(find.byKey(const Key('cook-setup-refusal')), findsOneWidget);

      await setTarget(tester, 2, '145');
      await start(tester);
      final plan = (await pending)!;
      expect(plan.safetyMode, SafetyMode.usdaCompliant);
      expect(probe(plan, 2).targetF10, 1450);
    });

    testWidgets('the mode picker is absent where it would change nothing', (
      tester,
    ) async {
      await open(tester);
      await chooseCustom(tester);
      await setHazard(tester, 2, HazardClass.poultry);
      expect(
        find.text(SafetyMode.usdaCompliant.label),
        findsNothing,
        reason:
            'both modes are identical on poultry, and a control that cannot '
            'change an outcome is a dead control',
      );
      await setHazard(tester, 2, HazardClass.wholeMuscleRedMeat);
      expect(find.text(SafetyMode.usdaCompliant.label), findsOneWidget);
    });
  });

  group('§D.4 — the pull offset, asked as cut thickness', () {
    testWidgets('a thick roast comes off 8°F early', (tester) async {
      await open(tester);
      await chooseCustom(tester);
      await setHazard(tester, 2, HazardClass.wholeMuscleRedMeat);
      await setTarget(tester, 2, '135');
      await setThickness(tester, 2, CutThickness.thick);
      await start(tester);
      final p = probe((await pending)!, 2);
      expect(p.pullF10, 1270);
      expect(
        p.carryoverF10,
        80,
        reason:
            'AmazingRibs measures 5–10 °F of coast on a 4–6″ roast, and the '
            'four-phase progression needs a real rest to count down',
      );
    });

    testWidgets('the default thin cut coasts a degree or two', (tester) async {
      await open(tester);
      await chooseCustom(tester);
      await setHazard(tester, 2, HazardClass.wholeMuscleRedMeat);
      await setTarget(tester, 2, '135');
      await start(tester);
      expect(probe((await pending)!, 2).pullF10, 1330);
    });

    testWidgets('sous vide has no carryover to allow for', (tester) async {
      await open(tester);
      await chooseCustom(tester);
      await setHazard(tester, 2, HazardClass.wholeMuscleRedMeat);
      await setTarget(tester, 2, '135');
      await setThickness(tester, 2, CutThickness.sousVide);
      await start(tester);
      expect(probe((await pending)!, 2).pullF10, 1350);
    });

    testWidgets('poultry has no thickness control, and says why', (
      tester,
    ) async {
      await open(tester);
      await chooseCustom(tester);
      await setHazard(tester, 2, HazardClass.poultry);
      expect(
        find.descendant(
          of: find.byKey(const Key('jack-2')),
          matching: find.text(CutThickness.sousVide.label),
        ),
        findsNothing,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('carryover-2'))).data,
        contains('does not come off early'),
      );
    });

    testWidgets('an offset can never cross a floor', (tester) async {
      await open(tester);
      await chooseCustom(tester);
      await setHazard(tester, 2, HazardClass.ground);
      await setTarget(tester, 2, '160');
      await setThickness(tester, 2, CutThickness.thick);
      await start(tester);
      expect(
        probe((await pending)!, 2).pullF10,
        1600,
        reason:
            'pulling ground beef at 152 °F on a promise of carryover is the '
            'promise USDA declines to make',
      );
    });
  });

  group('§D.4 — the safety strip', () {
    testWidgets('the raw-meat line is on the sheet from the first frame', (
      tester,
    ) async {
      await open(tester);
      expect(find.text(rawMeatAdvisory), findsOneWidget);
    });

    testWidgets('an intact red-meat target adds the tenderized-cut caveat', (
      tester,
    ) async {
      await open(tester);
      await chooseCustom(tester);
      expect(find.text(intactCutAdvisory), findsNothing);
      await setHazard(tester, 2, HazardClass.wholeMuscleRedMeat);
      expect(
        find.text(intactCutAdvisory),
        findsOneWidget,
        reason: 'once, in the strip — the switch has its own explanation',
      );
      expect(find.text(rawMeatAdvisory), findsOneWidget);
    });
  });

  group('presets, and the target the user actually reads', () {
    testWidgets('the eggs category reaches a 160°F preset', (tester) async {
      await open(tester);
      await chooseCategory(tester, 'Eggs');
      await tapKey(tester, 'preset-egg_bake');
      await start(tester);
      final plan = (await pending)!;
      expect(plan.hazard, HazardClass.egg);
      expect(probe(plan, 2).targetF10, 1600);
      expect(probe(plan, 2).pullF10, 1600);
    });

    testWidgets('choosing a preset fills the box the target is read from', (
      tester,
    ) async {
      // The box used to keep an `initialValue`, which is read once — so a
      // preset wrote 165 into the draft and left "" on screen, and an empty
      // target box is a target the user believes is unset.
      await open(tester);
      await chooseCategory(tester, 'Poultry');
      await tapKey(tester, 'preset-poultry_breast');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('target-2')))
            .controller
            ?.text,
        '165',
      );
    });

    testWidgets('an edited cook opens on its own targets and classes', (
      tester,
    ) async {
      final initial = CookPlan(
        presetId: 'custom',
        title: 'Mixed',
        hazard: HazardClass.wholeMuscleRedMeat,
        doneness: '',
        probes: [
          PlanProbe(jack: 1, isPit: true, name: 'Pit'),
          PlanProbe(
            jack: 2,
            isPit: false,
            role: ProbeRole.food,
            name: 'Thighs',
            targetF10: 1750,
            pullF10: 1750,
            hazard: HazardClass.poultry,
          ),
        ],
      );
      await open(tester, initial: initial);
      expect(find.text('Edit this cook'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('target-2')))
            .controller
            ?.text,
        '175',
      );
      // The stored pull comes back untouched: re-deriving it from a guessed
      // thickness would move a temperature the user chose.
      await start(tester);
      final p = probe((await pending)!, 2);
      expect(p.targetF10, 1750);
      expect(p.pullF10, 1750);
      expect(p.hazard, HazardClass.poultry);
    });
  });

  group('§16.7 — the states render', () {
    /// Walk the whole list. An overflow is only reported once its row has been
    /// laid out, so a sheet that is only ever measured at the top is untested.
    Future<void> walk(WidgetTester tester) async {
      // A step shorter than the viewport, so no row slips past unbuilt.
      for (var i = 0; i < 40; i++) {
        if (find.text(rawMeatAdvisory).evaluate().isNotEmpty) {
          break;
        }
        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pumpAndSettle();
      }
      expect(find.text(rawMeatAdvisory), findsOneWidget);
    }

    testWidgets('the preset flow lays out at 360 dp', (tester) async {
      await open(tester, size: const Size(360, 800));
      await walk(tester);
    });

    testWidgets('the custom flow lays out at 360 dp', (tester) async {
      // Opened on a custom plan so every added control is on screen without a
      // tap: seven hazard chips, four thickness chips, the intact switch and
      // the mode track, on the narrowest phone the design system supports.
      await open(
        tester,
        size: const Size(360, 800),
        initial: CookPlan(
          presetId: 'custom',
          title: 'Ribeye',
          hazard: HazardClass.wholeMuscleRedMeat,
          doneness: '',
          probes: [
            PlanProbe(jack: 1, isPit: true, name: 'Pit'),
            PlanProbe(
              jack: 2,
              isPit: false,
              role: ProbeRole.food,
              name: 'Ribeye',
              targetF10: 1350,
              pullF10: 1330,
            ),
          ],
        ),
      );
      await walk(tester);
    });
  });
}
