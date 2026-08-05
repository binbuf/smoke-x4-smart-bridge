/// Editable alarm rules, both tiers (newapp §G.2, §G.3).
///
/// The claims worth pinning are not "a rule has a threshold" but the three
/// that stop this feature becoming the settings tree's silent no-op again:
///
///  1. **The app cannot invent a tenth device rule.** The firmware's nine are
///     the nine (`bridge_alarm_rule_str`), and a type without one is app-tier
///     by definition rather than by a hand-maintained list that can drift.
///  2. **The patch is the shape the firmware actually parses** — a rules array
///     plus global tunables, not a per-rule threshold field the bridge would
///     discard while the UI said "saved".
///  3. **The read-back fails closed.** Anything short of a confirmed echo is
///     not saved.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/alarms/alarm_rule.dart';

AlarmRuleSpec _rule(
  AlarmRuleType type, {
  AlarmTier tier = AlarmTier.device,
  bool enabled = true,
  int? threshold,
  int? windowS,
  int? jack,
}) => AlarmRuleSpec(
  id: 1,
  bridgeId: 'b',
  tier: tier,
  type: type,
  enabled: enabled,
  threshold: threshold,
  windowS: windowS,
  jack: jack,
);

/// A device config in the firmware's own shape.
Map<String, Object?> _config({
  Map<String, bool> enabled = const {},
  Map<String, Object?> tunables = const {},
}) => {
  'rules': [
    for (final r in const [
      'smoke_x_alarm',
      'target_reached',
      'pit_out_of_band',
      'pit_crash',
      'probe_detached',
      'base_lost',
      'battery_low',
      'storage_low',
      'system_fault',
    ])
      {'rule': r, 'enabled': enabled[r] ?? true, 'severity': 'warning'},
  ],
  ...tunables,
};

void main() {
  group('the app cannot invent a rule the firmware does not have', () {
    test('every deviceRuleId is one of bridge_alarm_rule_str’s nine', () {
      const firmware = {
        'smoke_x_alarm',
        'target_reached',
        'pit_out_of_band',
        'pit_crash',
        'probe_detached',
        'base_lost',
        'battery_low',
        'storage_low',
        'system_fault',
      };
      for (final type in AlarmRuleType.values) {
        final id = type.deviceRuleId;
        if (id != null) {
          expect(firmware, contains(id), reason: type.name);
        }
      }
    });

    test('all nine are reachable from some type', () {
      final mapped = {
        for (final t in AlarmRuleType.values)
          if (t.deviceRuleId != null) t.deviceRuleId,
      };
      expect(mapped, hasLength(9));
    });

    test('fromDeviceRule round-trips every one', () {
      for (final type in AlarmRuleType.values) {
        final id = type.deviceRuleId;
        if (id != null) {
          expect(AlarmRuleType.fromDeviceRule(id), type);
        }
      }
      expect(AlarmRuleType.fromDeviceRule('nonsense'), isNull);
    });

    test('a type with no firmware rule is app-tier only', () {
      for (final type in AlarmRuleType.values) {
        if (type.deviceRuleId == null) {
          expect(
            type.tiers,
            {AlarmTier.app},
            reason:
                '${type.name} would write a rule name the bridge ignores — '
                'the editor must not offer it as a device rule',
          );
        }
      }
    });

    test('a rule the device cannot run produces no patch at all', () {
      for (final type in AlarmRuleType.values) {
        if (type.deviceRuleId == null) {
          expect(_rule(type).toDeviceJson(), isNull, reason: type.name);
        }
      }
    });

    test('an app-tier rule never produces a device patch', () {
      expect(
        _rule(AlarmRuleType.targetReached, tier: AlarmTier.app).toDeviceJson(),
        isNull,
      );
    });
  });

  group('§G.3 — the patch is the shape the firmware parses', () {
    test('a plain enable is a one-entry rules array', () {
      expect(_rule(AlarmRuleType.targetReached, enabled: false).toDeviceJson(), {
        'rules': [
          {'rule': 'target_reached', 'enabled': false},
        ],
      });
    });

    test('a pit band writes the GLOBAL tunables, not a per-rule field', () {
      // The firmware's rules array carries only {rule, enabled, severity};
      // thresholds are twelve global tunables beside it. Writing
      // `{"threshold": 250}` inside the rule object would be discarded while
      // the UI said "saved" — the exact class of bug this whole pattern
      // exists to prevent.
      final patch = _rule(
        AlarmRuleType.pitOutOfBand,
        threshold: 250,
        windowS: 180,
      ).toDeviceJson()!;
      expect(patch['pit_band_f10'], 250);
      expect(patch['pit_band_sustain_s'], 180);
      expect((patch['rules']! as List).single, {
        'rule': 'pit_out_of_band',
        'enabled': true,
      });
    });

    test('each tunable-carrying rule writes its own keys', () {
      expect(
        _rule(AlarmRuleType.pitCrash, threshold: -100, windowS: 300)
            .toDeviceJson(),
        containsPair('pit_crash_below_f10', -100),
      );
      expect(
        _rule(AlarmRuleType.pitCrash, threshold: -100, windowS: 300)
            .toDeviceJson(),
        containsPair('pit_crash_sustain_s', 300),
      );
      expect(
        _rule(AlarmRuleType.baseLost, windowS: 600).toDeviceJson(),
        containsPair('base_lost_s', 600),
      );
      expect(
        _rule(AlarmRuleType.batteryLow, threshold: 20).toDeviceJson(),
        containsPair('battery_warn_pct', 20),
      );
      expect(
        _rule(AlarmRuleType.storageFull, threshold: 85).toDeviceJson(),
        containsPair('storage_free_pct', 85),
      );
    });

    test('a rule with no tunables never writes one', () {
      // Even if a threshold got stored against it somehow.
      final patch = _rule(
        AlarmRuleType.probeUnplugged,
        threshold: 999,
        windowS: 999,
      ).toDeviceJson()!;
      expect(patch.keys, ['rules']);
    });

    test('absent fields are omitted — it is a merge patch', () {
      final patch = _rule(AlarmRuleType.pitOutOfBand).toDeviceJson()!;
      expect(patch.containsKey('pit_band_f10'), isFalse);
      expect(patch.containsKey('pit_band_sustain_s'), isFalse);
    });
  });

  group('§G.3 — the read-back fails closed', () {
    test('a matching echo confirms', () {
      final rule = _rule(AlarmRuleType.pitOutOfBand, threshold: 250);
      expect(
        rule.matchesReadBack(_config(tunables: const {'pit_band_f10': 250})),
        isTrue,
      );
    });

    test('a device that ignored the enable does NOT confirm', () {
      final rule = _rule(AlarmRuleType.targetReached, enabled: false);
      expect(
        rule.matchesReadBack(_config()),
        isFalse,
        reason: 'the config still says enabled: true',
      );
    });

    test('a device that ignored the tunable does NOT confirm', () {
      final rule = _rule(AlarmRuleType.pitOutOfBand, threshold: 250);
      expect(
        rule.matchesReadBack(_config(tunables: const {'pit_band_f10': 200})),
        isFalse,
      );
    });

    test('a config with no rules array does NOT confirm', () {
      expect(
        _rule(AlarmRuleType.targetReached).matchesReadBack(const {}),
        isFalse,
      );
    });

    test('a config missing this rule does NOT confirm', () {
      expect(
        _rule(AlarmRuleType.targetReached).matchesReadBack(const {
          'rules': [
            {'rule': 'base_lost', 'enabled': true},
          ],
        }),
        isFalse,
      );
    });

    test('the other eleven tunables are not a mismatch', () {
      final rule = _rule(AlarmRuleType.batteryLow, threshold: 15);
      expect(
        rule.matchesReadBack(
          _config(
            tunables: const {
              'battery_warn_pct': 15,
              'pit_band_f10': 999,
              'lid_grace_s': 42,
            },
          ),
        ),
        isTrue,
        reason: 'only what was sent is compared',
      );
    });

    test('a rule the device cannot run never reads as confirmed', () {
      expect(
        _rule(AlarmRuleType.preAlarm).matchesReadBack(_config()),
        isFalse,
      );
    });
  });

  group('the two tiers keep two different promises', () {
    test('and say so in words', () {
      expect(AlarmTier.device.promise, contains('switched off'));
      expect(AlarmTier.app.promise, contains('Advisory'));
      expect(
        AlarmTier.app.promise,
        contains('never replace'),
        reason:
            'the app tier must never read as a substitute for the device tier',
      );
    });

    test('device-health rules are device-only — the phone cannot see them', () {
      for (final type in const [
        AlarmRuleType.baseLost,
        AlarmRuleType.batteryLow,
        AlarmRuleType.storageFull,
        AlarmRuleType.restart,
        AlarmRuleType.baseStationAlarm,
      ]) {
        expect(type.tiers, {AlarmTier.device}, reason: type.name);
      }
    });

    test('isLive is only true for an app rule or a confirmed device rule', () {
      expect(_rule(AlarmRuleType.targetReached).isLive, isFalse);
      expect(
        _rule(AlarmRuleType.targetReached)
            .copyWith(pushedToDevice: true)
            .isLive,
        isTrue,
      );
      expect(
        _rule(AlarmRuleType.preAlarm, tier: AlarmTier.app).isLive,
        isTrue,
      );
    });
  });

  group('the seeded defaults', () {
    test('are the device’s nine, all unpushed', () {
      final rules = defaultDeviceRules('b');
      expect(rules, hasLength(9));
      for (final r in rules) {
        expect(r.tier, AlarmTier.device);
        expect(
          r.pushedToDevice,
          isFalse,
          reason:
              'the app does not get to claim the bridge agreed to something '
              'nobody has asked it about yet',
        );
        expect(r.type.deviceRuleId, isNotNull);
      }
    });

    test('the app defaults are app-tier and runnable there', () {
      for (final r in defaultAppRules('b')) {
        expect(r.tier, AlarmTier.app);
        expect(r.type.tiers, contains(AlarmTier.app));
      }
    });
  });

  group('threshold units never mislabel a field', () {
    test('a pre-alarm is a distance, not a temperature', () {
      expect(
        AlarmRuleType.preAlarm.thresholdUnit,
        AlarmThresholdUnit.degreesBelowTarget,
      );
    });

    test('time rules are seconds and battery is percent', () {
      expect(
        AlarmRuleType.timeElapsed.thresholdUnit,
        AlarmThresholdUnit.seconds,
      );
      expect(
        AlarmRuleType.batteryLow.thresholdUnit,
        AlarmThresholdUnit.percent,
      );
    });

    test('rules with no threshold say so rather than defaulting to one', () {
      expect(AlarmRuleType.targetReached.thresholdUnit, isNull);
      expect(AlarmRuleType.probeUnplugged.thresholdUnit, isNull);
      expect(AlarmRuleType.restart.thresholdUnit, isNull);
    });
  });
}
