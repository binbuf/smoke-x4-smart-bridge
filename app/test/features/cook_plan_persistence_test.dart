/// The guided cook survives a process death (design 13 §13.3.1).
///
/// The defect this pins: `CookPlan? _plan` lived on the shell's State, so a
/// guided cook existed only for as long as that State did. An OS kill at hour
/// nine of an eighteen-hour brisket dropped the user silently back to
/// instrument mode — targets, gauges and cook name gone — with nothing on
/// screen to say it had happened.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/app_env.dart';
import 'package:smoke_bridge/data/prefs/bridge_prefs.dart';
import 'package:smoke_bridge/domain/plan/plan.dart';
import 'package:smoke_bridge/features/shell/shell_session.dart';

import '../support/fake_env.dart';

CookPlan _brisket() => CookPlan(
  presetId: 'brisket',
  title: 'Texas brisket — pitmaster shred',
  hazard: HazardClass.wholeMuscleRedMeat,
  doneness: 'pitmaster shred',
  pitBandMinF10: 2200,
  pitBandMaxF10: 2600,
  probes: const [
    PlanProbe(jack: 1, isPit: true, name: 'Pit'),
    PlanProbe(
      jack: 2,
      isPit: false,
      name: 'Brisket',
      targetF10: 2030,
      pullF10: 1950,
    ),
  ],
);

void main() {
  group('CookPlan JSON', () {
    test('round-trips every field that drives the screen', () {
      final plan = _brisket()..startedUnixMs = 1753000000000;
      final back = CookPlan.fromJson(
        jsonDecode(jsonEncode(plan.toJson())) as Map<String, Object?>,
      )!;

      expect(back.presetId, 'brisket');
      expect(back.title, 'Texas brisket — pitmaster shred');
      expect(back.hazard, HazardClass.wholeMuscleRedMeat);
      expect(back.doneness, 'pitmaster shred');
      expect(back.pitBandMinF10, 2200);
      expect(back.pitBandMaxF10, 2600);
      expect(back.startedUnixMs, 1753000000000);
      expect(back.probes.length, 2);
      expect(back.pit?.jack, 1);
      expect(back.probes[1].targetF10, 2030);
      expect(back.probes[1].pullF10, 1950);
    });

    test(
      'malformed stored text degrades to instrument mode, never a throw',
      () {
        expect(CookPlan.fromJson(const {}), isNull);
        expect(CookPlan.fromJson(const {'probes': 'not a list'}), isNull);
      },
    );

    test(
      'a stored plan that would now be refused is dropped, not restored',
      () {
        // Chicken at 140 °F is below the USDA floor, so the constructor refuses
        // it. A plan written by a build with a different table must not sneak
        // past the food-safety gate on the way back in.
        final unsafe = {
          'preset_id': 'chicken',
          'title': 'Chicken',
          'hazard': HazardClass.poultry.name,
          'doneness': 'juicy',
          'probes': [
            {'jack': 2, 'is_pit': false, 'name': 'Chicken', 'target_f10': 1400},
          ],
        };
        expect(CookPlan.fromJson(unsafe), isNull);
      },
    );
  });

  group('ShellSession', () {
    test('a plan set on one session is read back by the next', () async {
      final prefs = InMemoryBridgePrefs();
      AppEnv.instance = fakeEnv(prefs: prefs);
      addTearDown(() => AppEnv.instance = null);

      final first = ShellSession();
      expect(first.plan, isNull, reason: 'nothing stored yet');
      await first.setPlan(_brisket());
      expect(prefs.cookPlanJson, isNotNull);
      first.dispose();

      // The app is killed and relaunched.
      final second = ShellSession();
      addTearDown(second.dispose);
      expect(second.plan, isNotNull);
      expect(second.plan!.title, 'Texas brisket — pitmaster shred');
      expect(second.plan!.probes[1].targetF10, 2030);
    });

    test(
      'ending a cook clears it, so the next launch is instrument mode',
      () async {
        final prefs = InMemoryBridgePrefs();
        AppEnv.instance = fakeEnv(prefs: prefs);
        addTearDown(() => AppEnv.instance = null);

        final session = ShellSession();
        await session.setPlan(_brisket());
        await session.setPlan(null);
        session.dispose();

        expect(prefs.cookPlanJson, isNull);
        final next = ShellSession();
        addTearDown(next.dispose);
        expect(next.plan, isNull);
      },
    );

    test('forgetting the bridge ends the cook it was recording', () async {
      final prefs = InMemoryBridgePrefs(lastBaseUrl: 'http://10.0.0.5');
      AppEnv.instance = fakeEnv(prefs: prefs);
      addTearDown(() => AppEnv.instance = null);

      final session = ShellSession();
      await session.setPlan(_brisket());
      session.dispose();

      await prefs.forgetBridge();
      expect(
        prefs.cookPlanJson,
        isNull,
        reason:
            'a plan for a bridge this phone no longer talks to would '
            'render targets against readings that can never arrive',
      );
    });

    test('units come from the one pref setup already writes', () async {
      final prefs = InMemoryBridgePrefs(displayUnits: 'C');
      AppEnv.instance = fakeEnv(prefs: prefs);
      addTearDown(() => AppEnv.instance = null);

      final session = ShellSession();
      addTearDown(session.dispose);
      expect(session.celsius, isTrue);
    });
  });
}
