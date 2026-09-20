/// `/device/alarms` — the rule editor, checked against 16 §16.5's layout
/// system rather than against prose.
///
/// Two defects are pinned here, and both are about the same thing: the screen
/// was built out of raw cards and raw text rather than out of the elements the
/// rest of the app is built from.
///
///  1. **One card per rule.** Eleven floating [SmokeCard]s down a page whose
///     entire point is that the two tiers are different things. §16.5: "Groups
///     rows that share a subject. Never one card per row."
///  2. **The blurb — the best copy on the screen — was hidden on exactly the
///     rules somebody had configured.** `_summary()` fell back to
///     `type.blurb` only when a rule carried no parameters at all, so a
///     working rule read "Probe 3 · 203°F · held 5m" and never said what it
///     actually does. The blurb explains; the parameters are the value.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/app_env.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/alarms/alarm_rule.dart';
import 'package:smoke_bridge/features/alarms/alarm_rules_route.dart';
import 'package:smoke_bridge/ui/ui.dart';

import '../support/fake_env.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Installs an environment with one known bridge, so the editor seeds its
/// eleven rules and has something real to lay out.
Future<AppEnv> _envWithBridge(String bridgeId) async {
  final env = fakeEnv();
  await env.db.sessionDao.upsertBridge(bridgeId);
  AppEnv.instance = env;
  return env;
}

Future<void> _pumpEditor(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(theme: SmokeTheme.dark, home: const AlarmRulesRoute()),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AppEnv.instance = null);
  tearDown(() => AppEnv.instance = null);

  testWidgets('the tiers are two cards, not eleven', (tester) async {
    _tall(tester);
    await _envWithBridge('b');
    await _pumpEditor(tester);

    // Nine device rules plus two app-tier ones are seeded on first run. They
    // belong to two subjects, so they live in two cards — plus the test-alarm
    // card, which is a third subject and earns its own.
    expect(find.byType(SmokeCard), findsNWidgets(3));
    expect(find.text('ON THE BRIDGE'), findsOneWidget);
    expect(find.text('ON THIS PHONE'), findsOneWidget);
  });

  testWidgets('a configured rule still says what it does', (tester) async {
    _tall(tester);
    await _envWithBridge('b');
    await _pumpEditor(tester);

    // `pitCrash` seeds with a 300-second dwell, so under the old `_summary()`
    // it rendered "held 5m" and nothing else.
    expect(find.text(AlarmRuleType.pitCrash.blurb), findsOneWidget);
    // Both the crash rule and the base-lost rule seed with a 300-second dwell.
    expect(find.text('held 5m'), findsNWidgets(2));
    // And a rule with no parameters at all is not left blank on the right.
    expect(find.text(AlarmRuleType.targetReached.blurb), findsOneWidget);
  });

  testWidgets('the editor names itself the same thing its entry points do', (
    tester,
  ) async {
    _tall(tester);
    await _envWithBridge('b');
    await _pumpEditor(tester);
    // The AppBar said "Alarms", matching neither the row called "Alarm rules"
    // nor the one called "Alarms and notifications".
    expect(find.text('Alarm rules'), findsOneWidget);
  });

  testWidgets('the test-alarm heading is a heading, not a dare', (
    tester,
  ) async {
    _tall(tester);
    await _envWithBridge('b');
    await _pumpEditor(tester);
    // 16 §16.4: never cute.
    expect(find.text('PROVE IT'), findsNothing);
    expect(find.text('TEST ALARM'), findsOneWidget);
    expect(find.byKey(const Key('alarm-send-test')), findsOneWidget);
  });

  testWidgets('with no link the bridge rules are inert, with one reason', (
    tester,
  ) async {
    _tall(tester);
    await _envWithBridge('b');
    await _pumpEditor(tester);

    // No ShellScope, so no transport: `capabilities.config` is false and the
    // device tier cannot be pushed.
    final deviceSwitch = tester
        .widgetList<Switch>(find.byType(Switch))
        .firstWhere((s) => s.onChanged == null);
    expect(deviceSwitch.onChanged, isNull);
    // Once at the foot of the card, not nine times.
    expect(
      find.textContaining('Connect over Wi-Fi to change the bridge’s own'),
      findsOneWidget,
    );
  });

  testWidgets('an app-tier rule is still editable with no bridge in sight', (
    tester,
  ) async {
    _tall(tester);
    await _envWithBridge('b');
    await _pumpEditor(tester);

    // §G.3: app-tier rules are local only and always editable. At least one
    // switch has to be live, or the promise in the section header is a lie.
    expect(
      tester
          .widgetList<Switch>(find.byType(Switch))
          .any((s) => s.onChanged != null),
      isTrue,
    );
  });

  testWidgets('with no bridge remembered it says so rather than seeding', (
    tester,
  ) async {
    _tall(tester);
    AppEnv.instance = fakeEnv();
    await _pumpEditor(tester);
    expect(find.text('No rules here yet.'), findsNWidgets(2));
  });
}
