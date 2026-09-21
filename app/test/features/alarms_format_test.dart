/// N11 — the Alerts sheet's pure projections.
///
/// `package:test` (no widgets), run by both `dart test` and `flutter test`.
library;

import 'package:smoke_bridge/data/alarms/notification_policy.dart';
import 'package:smoke_bridge/data/content/fixtures_data.dart';
import 'package:smoke_bridge/data/content/scenarios.dart';
import 'package:smoke_bridge/data/model/alarm.dart';
import 'package:smoke_bridge/data/model/bridge_snapshot.dart';
import 'package:smoke_bridge/features/alarms/alarms_format.dart';
import 'package:test/test.dart';

const int _now = 1700000000000;

BridgeSnapshot _snapshot(String key) =>
    allScenarios(nowMs: _now)[key]!.snapshot;

void main() {
  group('rule grouping keeps the two tiers separate (I2)', () {
    test(
      'nine device rules, three app insights, and the filters are disjoint',
      () {
        expect(deviceRules(kAlarmRules), hasLength(9));
        expect(appRules(kAlarmRules), hasLength(3));
        expect(
          deviceRules(kAlarmRules).every((r) => r.tier == AlarmTier.device),
          isTrue,
        );
        expect(
          appRules(kAlarmRules).every((r) => r.tier == AlarmTier.app),
          isTrue,
        );
      },
    );

    test('only app rules are editable', () {
      for (final rule in kAlarmRules) {
        expect(
          ruleIsEditable(rule),
          rule.tier == AlarmTier.app,
          reason: rule.id,
        );
      }
    });
  });

  group('deriveFindings (N11.15)', () {
    test('a stalled probe raises stallStarted; a near ETA raises etaSoon', () {
      final findings = deriveFindings(_snapshot('running'));
      expect(findings, contains(AppFinding.stallStarted));
      expect(findings, contains(AppFinding.etaSoon));
      expect(findings, isNot(contains(AppFinding.bridgeUnreachable)));
    });

    test('a link dropped mid-cook raises bridgeUnreachable', () {
      final findings = deriveFindings(_snapshot('offline'));
      expect(findings, contains(AppFinding.bridgeUnreachable));
    });

    test('an idle bridge raises nothing', () {
      expect(deriveFindings(_snapshot('idle')), isEmpty);
    });
  });

  group('delivery verdict (N11.3)', () {
    test('monitoring off means the phone will not wake you', () {
      final verdict = deliveryVerdict(
        monitoring: false,
        quietHours: true,
        preferManualAlarm: false,
      );
      expect(verdict.wake, isFalse);
      expect(verdict.title.toLowerCase(), contains('monitoring is off'));
    });

    test('quiet hours are named and critical still sounds', () {
      final verdict = deliveryVerdict(
        monitoring: true,
        quietHours: true,
        preferManualAlarm: false,
      );
      expect(verdict.wake, isTrue);
      expect(verdict.detail, contains('critical'));
      expect(verdict.detail, contains('10pm'));
    });

    test('prefer my own alarms is stated', () {
      final verdict = deliveryVerdict(
        monitoring: true,
        quietHours: false,
        preferManualAlarm: true,
      );
      expect(verdict.detail, contains('own insights'));
    });
  });

  group('words and times', () {
    test('severity and tier words', () {
      expect(severityWord(AlarmSeverity.critical), 'Critical');
      expect(severityWord(AlarmSeverity.warning), 'Warning');
      expect(severityWord(AlarmSeverity.info), 'Info');
      expect(tierWord(AlarmTier.device), 'Device');
      expect(tierWord(AlarmTier.app), 'Insight');
    });

    test('agoWord is relative and never negative', () {
      expect(agoWord(nowMs: _now, atMs: _now), 'just now');
      expect(agoWord(nowMs: _now, atMs: _now - 60 * 1000), '1 min ago');
      expect(agoWord(nowMs: _now, atMs: _now - 2 * 3600 * 1000), '2 h ago');
      expect(agoWord(nowMs: _now, atMs: _now + 5000), 'just now');
    });

    test('firedLine joins the clock and the ago word', () {
      final line = firedLine(nowMs: _now, atMs: _now - 12 * 60 * 1000);
      expect(line, contains('·'));
      expect(line, contains('12 min ago'));
    });
  });

  group('why this fired (N11.7)', () {
    test('always names the rule, and adds trigger/reading/suggestion when '
        'present', () {
      final alarm = _snapshot('offline').alarms.single;
      final rows = whyFiredRows(alarm);
      final labels = <String>[for (final r in rows) r.label];
      expect(labels, contains('Rule'));
      expect(labels, contains('Trigger'));
      expect(labels, contains('Suggestion'));
    });

    test('omits absent fields rather than printing an empty row', () {
      const alarm = Alarm(
        id: 'x',
        tier: AlarmTier.app,
        severity: AlarmSeverity.info,
        rule: 'An insight',
        atMs: _now,
        ruleId: 'eta_soon',
      );
      final labels = <String>[for (final r in whyFiredRows(alarm)) r.label];
      expect(labels, <String>['Rule']);
    });
  });
}
