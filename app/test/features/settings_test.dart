/// §F's settings tree, checked against 16 §16.4–§16.7 rather than against
/// prose.
///
/// Four rules are pinned here, because they are the four the last pass broke
/// and a paint job cannot fix:
///
///  1. **No constructor default is ever rendered as a device fact.** The
///     network mode is the headline case — `NetMode.sta` rendered as "Joined a
///     network" over a bridge hosting its own AP — but the audit found the same
///     class of bug on the paired flag, the MQTT port and the battery saver,
///     and each one has a test below.
///  2. **A row the active lane cannot write is rendered, dimmed, with its
///     reason on screen.** Never hidden, never live-looking-and-inert.
///  3. **A write reports what actually happened**, including the honest
///     "the bridge doesn't report this one back, so the app can't confirm it".
///  4. **Destructive actions state what they keep and what they lose** before
///     they run.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/settings/settings.dart';
import 'package:smoke_bridge/ui/ui.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: SmokeTheme.dark,
  home: Scaffold(body: child),
);

/// Settings pages are long lists; on the default 800x600 test surface the rows
/// at the bottom are never built, let alone tappable. A taller surface is the
/// honest fix — the alternative is asserting against widgets a real phone would
/// also have to scroll to.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Taps the verb inside a [SettingsActionRow] — the row itself is not the
/// control, the button on it is.
Future<void> _tapAction(WidgetTester tester, String rowKey) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(Key(rowKey)),
      matching: find.byType(OutlinedButton),
    ),
  );
  await tester.pumpAndSettle();
}

/// The [SettingsRow] behind a key — whether the key is on the row itself or on
/// one of the wrappers ([SettingsActionRow], [SettingsSwitchRow],
/// [SettingsChoiceRow]) that build one.
SettingsRow _row(WidgetTester tester, String key) => tester.widget<SettingsRow>(
  find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(SettingsRow),
    matchRoot: true,
  ),
);

/// The open cost sheet's ledger. Read off the widget rather than off the
/// screen because `keeps`/`loses` render through `RichText`, which the text
/// finders deliberately do not match.
CostSheet _costSheet(WidgetTester tester) =>
    tester.widget<CostSheet>(find.byType(CostSheet));

void main() {
  group('§16.5 — the layout system', () {
    testWidgets('every section is a card of rows, never a flat list', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(SettingsHomeView(onOpen: (_) {})));
      expect(find.byType(SmokeCard), findsWidgets);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('a disabled row is rendered, dimmed, with its reason beneath', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const SettingsGroup(
            children: [
              SettingsRow(
                key: Key('r'),
                label: 'A thing',
                reason: 'Connect over Wi-Fi to change this.',
              ),
            ],
          ),
        ),
      );
      // Present…
      expect(find.text('A thing'), findsOneWidget);
      // …dimmed…
      expect(find.byType(Opacity), findsWidgets);
      // …and the reason is on screen, not in a tooltip or a toast.
      expect(find.text('Connect over Wi-Fi to change this.'), findsOneWidget);
    });

    testWidgets('a row with no value renders the em dash, never a zero', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const SettingsGroup(children: [SettingsRow(label: 'Battery')])),
      );
      expect(find.text('—'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.text('0%'), findsNothing);
    });

    testWidgets('a row holds at 360 dp and 200% text scale', (tester) async {
      // 16 §16.7: it works at 360 dp and at 200% text scale. A settings row is
      // the widest thing in the tree — a long address plus a two-word verb is
      // the case that breaks a naive Row.
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: SmokeTheme.dark,
          home: Builder(
            builder: (ctx) => MediaQuery(
              data: MediaQuery.of(
                ctx,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: Scaffold(
                body: SettingsGroup(
                  children: [
                    const SettingsRow(
                      label: 'Reached at',
                      subtitle: 'The address this phone is using right now',
                      value: 'http://smokebridge-8274.local',
                    ),
                    SettingsActionRow(
                      label: 'Look for the base station',
                      subtitle: 'Re-runs the pairing scan',
                      buttonLabel: 'Re-scan',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a whole-subject block carries its reason once, not per row', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const SettingsGroup(
            reason: 'Connect over Wi-Fi to rename probes.',
            children: [
              SettingsRow(label: 'Name'),
              SettingsRow(label: 'Used for'),
              SettingsRow(label: 'Target'),
            ],
          ),
        ),
      );
      // One sentence, not three. Repetition is what people stop reading.
      expect(find.text('Connect over Wi-Fi to rename probes.'), findsOneWidget);
    });
  });

  group('the section list', () {
    testWidgets('offers every §F section and opens one', (tester) async {
      _tall(tester);
      final opened = <SettingsSection>[];
      await tester.pumpWidget(_wrap(SettingsHomeView(onOpen: opened.add)));
      for (final s in SettingsSection.values) {
        expect(
          find.byKey(Key('settings-section-${s.name}')),
          findsOneWidget,
          reason: 'missing ${s.name}',
        );
      }
      // §F's frozen scope, named in the user's words rather than the wire's.
      expect(find.text('Probes'), findsOneWidget);
      expect(find.text('Power and sleep'), findsOneWidget);
      expect(find.text('Data and export'), findsOneWidget);
      expect(find.text('Diagnostics'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-section-probes')));
      expect(opened, [SettingsSection.probes]);
    });

    test('the order is a cook’s priority, not declaration order', () {
      // It used to lead with Identity: four read-only rows and a permanently
      // disabled rename, at the top of the screen somebody opens mid-cook.
      expect(SettingsSection.values.first, SettingsSection.probes);
      expect(SettingsSection.deviceSections.first, SettingsSection.probes);
      expect(SettingsSection.deviceSections, const [
        SettingsSection.probes,
        SettingsSection.alarms,
        SettingsSection.network,
        SettingsSection.display,
        SettingsSection.power,
        SettingsSection.data,
        SettingsSection.firmware,
        SettingsSection.led,
        SettingsSection.homeAssistant,
        SettingsSection.identity,
      ]);
      // The slugs are the live deep links and must not move with the order.
      expect(SettingsSection.advanced.slug, 'advanced');
      expect(SettingsSection.homeAssistant.slug, 'homeassistant');
    });

    test('no section subtitle merely repeats its own title', () {
      for (final s in SettingsSection.values) {
        expect(
          s.subtitle.toLowerCase(),
          isNot(contains(s.title.toLowerCase())),
          reason: '${s.name}: the subtitle explains, it never restates',
        );
      }
    });

    test('the two alarm entry points no longer compete for the same name', () {
      // A row "Alarm rules" and a row "Alarms and notifications", three rows
      // apart, going to different screens. This one is about delivery.
      expect(SettingsSection.alarms.title, 'Notifications on this phone');
    });
  });

  group('identity', () {
    testWidgets('nothing read means nothing claimed', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const IdentitySettingsView()));
      for (final k in [
        'identity-device-id',
        'identity-model',
        'identity-firmware',
        'identity-address',
      ]) {
        expect(_row(tester, k).value, isNull, reason: k);
      }
    });

    testWidgets('a bridge that has not answered is not "not paired"', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const IdentitySettingsView()));
      // The old code read `status?.paired ?? false` — "No" for a bridge that
      // had simply not replied, on the page whose whole job is to say.
      expect(_row(tester, 'identity-paired').value, isNull);
      expect(find.textContaining('hasn’t reported this yet'), findsWidgets);
    });

    testWidgets('a real read renders as a fact', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const IdentitySettingsView(
            deviceId: 'SB-8274',
            model: 'smokebridge-c6',
            firmware: '1.2.0',
            paired: true,
          ),
        ),
      );
      expect(_row(tester, 'identity-device-id').value, 'SB-8274');
      expect(_row(tester, 'identity-paired').value, 'Yes');
    });

    testWidgets('renaming is present, disabled, and explains itself', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const IdentitySettingsView()));
      expect(_row(tester, 'identity-rename').reason, isNotEmpty);
      expect(find.textContaining('can’t rename a bridge'), findsOneWidget);
    });

    testWidgets('§F’s mDNS name is present, and is a real value once read', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const IdentitySettingsView()));
      expect(_row(tester, 'identity-mdns').value, isNull);
      await tester.pumpWidget(
        _wrap(const IdentitySettingsView(deviceId: 'SB-8274')),
      );
      expect(_row(tester, 'identity-mdns').value, 'sb-8274.local');
      expect(_row(tester, 'identity-mdns').reason, isNotEmpty);
    });

    testWidgets('with no link the verbs say why, they are not just dead', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          IdentitySettingsView(
            controlReason: SettingsLane.none.control,
            onPair: () {},
          ),
        ),
      );
      expect(
        find.textContaining('isn’t connected to your bridge'),
        findsWidgets,
      );
    });
  });

  group('probes', () {
    testWidgets('saving sends the whole draft', (tester) async {
      _tall(tester);
      List<Probe>? saved;
      await tester.pumpWidget(
        _wrap(
          ProbeSettingsView(
            probes: const [Probe(n: 1, name: 'Pit', role: ProbeRole.pit)],
            probesKnown: true,
            onSave: (p) async => saved = p,
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('probe-name-2')), 'Brisket');
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('probe-role-row-2')),
          matching: find.text('Food'),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byKey(const Key('probe-target-2')), '203.0');
      await tester.pump();
      await tester.tap(find.byKey(const Key('probes-save')));
      await tester.pump();

      expect(saved, isNotNull);
      final p2 = saved!.firstWhere((p) => p.n == 2);
      expect(p2.name, 'Brisket');
      expect(p2.role, ProbeRole.food);
      expect(p2.targetF10, 2030);
      // Roles drive which tile is large — probe 1 stays the pit.
      expect(saved!.firstWhere((p) => p.n == 1).role, ProbeRole.pit);
    });

    testWidgets('a probe is a card, so there are four of them', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          ProbeSettingsView(
            probes: const [],
            probesKnown: true,
            onSave: (_) async {},
          ),
        ),
      );
      for (var n = 1; n <= 4; n++) {
        expect(find.byKey(Key('probe-editor-$n')), findsOneWidget);
      }
    });

    testWidgets('the role row explains what a role buys', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          ProbeSettingsView(
            probes: const [Probe(n: 1, role: ProbeRole.pit)],
            probesKnown: true,
            onSave: (_) async {},
          ),
        ),
      );
      // "Pit" alone is a wire value. This says what selecting it does.
      expect(find.textContaining('Shown large, and watched'), findsOneWidget);
    });

    // The defect this group exists for: the route hands this view `const []`
    // on its first build and the bridge's four probes a round trip later.
    testWidgets('before the bridge answers there is no form to save', (
      tester,
    ) async {
      _tall(tester);
      var saves = 0;
      await tester.pumpWidget(
        _wrap(
          ProbeSettingsView(
            probes: const [],
            probesKnown: false,
            onSave: (_) async => saves++,
          ),
        ),
      );
      // Four blank name boxes over an unread configuration is the shape that
      // wiped it. They are not there.
      for (var n = 1; n <= 4; n++) {
        expect(find.byKey(Key('probe-editor-$n')), findsNothing);
        expect(find.byKey(Key('probe-name-$n')), findsNothing);
      }
      // Present, dimmed, with the reason on screen — never hidden.
      expect(find.byKey(const Key('probes-unread')), findsOneWidget);
      expect(
        find.textContaining('hasn’t sent its probe settings'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('probes-unread')),
          matching: find.text('—'),
        ),
        findsNWidgets(4),
        reason: 'absent is the em dash, never a blank name box',
      );
      expect(
        tester
            .widget<PrimaryAction>(find.byKey(const Key('probes-save')))
            .onPressed,
        isNull,
        reason: 'saving blanks over a real configuration is the whole bug',
      );
      expect(saves, 0);
    });

    testWidgets(
      'the read arriving fills the form in, not just the rows above',
      (tester) async {
        _tall(tester);
        List<Probe>? saved;
        Widget view({required bool known, required List<Probe> probes}) =>
            _wrap(
              ProbeSettingsView(
                probes: probes,
                probesKnown: known,
                onSave: (p) async => saved = p,
              ),
            );

        await tester.pumpWidget(view(known: false, probes: const []));
        await tester.pumpWidget(
          view(
            known: true,
            probes: const [
              Probe(n: 1, name: 'Firebox', role: ProbeRole.pit),
              Probe(
                n: 2,
                name: 'Brisket',
                role: ProbeRole.food,
                targetF10: 2030,
              ),
            ],
          ),
        );
        await tester.pump();

        // Seeded into the fields, not only into the draft.
        expect(find.text('Firebox'), findsOneWidget);
        expect(find.text('Brisket'), findsOneWidget);
        expect(find.text('203.0'), findsOneWidget);

        await tester.tap(find.byKey(const Key('probes-save')));
        await tester.pump();
        expect(saved!.firstWhere((p) => p.n == 1).name, 'Firebox');
        expect(saved!.firstWhere((p) => p.n == 2).targetF10, 2030);
      },
    );

    testWidgets('a later read never takes back what somebody is typing', (
      tester,
    ) async {
      _tall(tester);
      List<Probe>? saved;
      Widget view(List<Probe> probes) => _wrap(
        ProbeSettingsView(
          probes: probes,
          probesKnown: true,
          onSave: (p) async => saved = p,
        ),
      );

      await tester.pumpWidget(view(const [Probe(n: 1, name: 'Pit')]));
      await tester.enterText(find.byKey(const Key('probe-name-1')), 'Kettle');
      await tester.pump();

      // The bridge answers again — a status refresh, or the read-back after
      // somebody else's save. Jack 1 is being edited; jack 2 is not.
      await tester.pumpWidget(
        view(const [Probe(n: 1, name: 'Pit'), Probe(n: 2, name: 'Point')]),
      );
      await tester.pump();

      expect(find.text('Kettle'), findsOneWidget);
      expect(find.text('Point'), findsOneWidget);
      await tester.tap(find.byKey(const Key('probes-save')));
      await tester.pump();
      expect(saved!.firstWhere((p) => p.n == 1).name, 'Kettle');
      expect(saved!.firstWhere((p) => p.n == 2).name, 'Point');
    });

    testWidgets('an out-of-range target is refused in the form', (
      tester,
    ) async {
      _tall(tester);
      var saves = 0;
      await tester.pumpWidget(
        _wrap(
          ProbeSettingsView(
            probes: const [],
            probesKnown: true,
            onSave: (_) async => saves++,
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('probe-target-1')), '9999');
      await tester.pump();
      expect(find.textContaining('Between'), findsOneWidget);
      expect(
        tester
            .widget<PrimaryAction>(find.byKey(const Key('probes-save')))
            .onPressed,
        isNull,
      );
      expect(saves, 0);
    });

    testWidgets('a lane that cannot write says so, dims, and disables', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          ProbeSettingsView(
            probes: const [],
            probesKnown: true,
            onSave: (_) async {},
            unsupportedReason: SettingsLane.bluetooth.probes,
          ),
        ),
      );
      expect(find.byKey(const Key('probes-unsupported')), findsOneWidget);
      expect(
        find.textContaining('Connect over Wi-Fi to rename probes'),
        findsWidgets,
      );
      expect(
        tester
            .widget<PrimaryAction>(find.byKey(const Key('probes-save')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('a failed save keeps the edits and states the failure', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          ProbeSettingsView(
            probes: const [],
            probesKnown: true,
            onSave: (_) async => throw StateError('bridge said no'),
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('probe-name-1')), 'Kettle');
      await tester.pump();
      await tester.tap(find.byKey(const Key('probes-save')));
      await tester.pump();
      expect(find.byKey(const Key('probes-save-error')), findsOneWidget);
      // Ten minutes of typing must not vanish on one dropped packet.
      expect(find.text('Kettle'), findsOneWidget);
    });

    testWidgets('the fields §F names but nothing can carry are explained', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          ProbeSettingsView(
            probes: const [],
            probesKnown: true,
            onSave: (_) async {},
          ),
        ),
      );
      expect(_row(tester, 'probe-pull-offset').reason, isNotEmpty);
      expect(_row(tester, 'probe-calibration').reason, isNotEmpty);
      expect(
        find.textContaining('lives on the Smoke X base station'),
        findsOneWidget,
      );
      // §F names a doneness per jack. The bridge stores degrees and nothing
      // else, so the row is present and says which.
      expect(_row(tester, 'probe-doneness-1').reason, isNotEmpty);
    });
  });

  group('alarms', () {
    testWidgets('the two tiers are distinct, and say what they promise', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const AlarmSettingsView(
            deviceRules: {'target_reached': true, 'pit_crash': false},
            alarms: [],
          ),
        ),
      );
      expect(find.byKey(const Key('alarms-device-tier')), findsOneWidget);
      expect(find.byKey(const Key('alarms-app-tier')), findsOneWidget);
      expect(find.textContaining('phone switched off'), findsOneWidget);
      expect(find.textContaining('never replace'), findsOneWidget);
      // Counted, not listed twice — the rules themselves live in the editor.
      expect(_row(tester, 'alarms-device-count').value, '1 of 2 on');
      // And it names what is OFF, which is the question somebody is actually
      // asking when they open this page.
      expect(
        find.textContaining('Switched off: The fire is dying'),
        findsOneWidget,
      );
    });

    testWidgets('with the bridge silent, the count is a dash and says why', (
      tester,
    ) async {
      // The worst default-as-fact left on this screen: the route handed in a
      // `const` map of six rules, all on, so a phone that had never met a
      // bridge printed "6 of 6 on" as a statement about a device.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const AlarmSettingsView(deviceRules: null, alarms: [])),
      );
      expect(_row(tester, 'alarms-device-count').value, isNull);
      expect(find.textContaining('6 of 6'), findsNothing);
      expect(
        find.textContaining('hasn’t reported its rules yet'),
        findsOneWidget,
      );
    });

    testWidgets('the two app-tier rows that were hardcoded "On" are gone', (
      tester,
    ) async {
      // They were `const SettingsRow(value: 'On')` with no switch and no tap,
      // for rules that ARE editable at /device/alarms — turning one off there
      // left this page still saying On. One of them ("Stall started or ended")
      // was not a rule the app has at all.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const AlarmSettingsView(deviceRules: null, alarms: [])),
      );
      expect(find.byKey(const Key('alarm-app-eta')), findsNothing);
      expect(find.byKey(const Key('alarm-app-stall')), findsNothing);
      // The editor still owns them, and the row that opens it says so.
      expect(
        find.textContaining('whether the bridge or this phone watches'),
        findsOneWidget,
      );
    });

    testWidgets('the rule editor is one tap away', (tester) async {
      _tall(tester);
      var opened = 0;
      await tester.pumpWidget(
        _wrap(
          AlarmSettingsView(
            deviceRules: const {},
            alarms: const [],
            onOpenRules: () => opened++,
          ),
        ),
      );
      await _tapAction(tester, 'alarms-open-rules');
      expect(opened, 1);
    });

    testWidgets('with no rules reported, the count is absent not zero', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const AlarmSettingsView(deviceRules: {}, alarms: [])),
      );
      expect(_row(tester, 'alarms-device-count').value, isNull);
    });

    testWidgets('A13 landed: the M4 caveat is gone and monitoring is real', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const AlarmSettingsView(deviceRules: {}, alarms: [])),
      );
      expect(find.textContaining('later release'), findsNothing);
      expect(find.byKey(const Key('alarm-monitoring')), findsOneWidget);
      expect(
        find.byKey(const Key('alarms-battery-optimisation')),
        findsOneWidget,
      );
      // The claim that survives every switch on this screen being off.
      expect(find.textContaining('bridge keeps logging'), findsOneWidget);
    });

    testWidgets('the battery-optimisation offer disappears once granted', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const AlarmSettingsView(
            deviceRules: {},
            alarms: [],
            batteryExempt: true,
          ),
        ),
      );
      expect(
        find.byKey(const Key('alarms-battery-optimisation')),
        findsNothing,
      );
    });

    testWidgets('quiet hours and monitoring round-trip their callbacks', (
      tester,
    ) async {
      _tall(tester);
      bool? quiet;
      bool? monitor;
      await tester.pumpWidget(
        _wrap(
          AlarmSettingsView(
            deviceRules: const {},
            alarms: const [],
            onQuietHours: (v) => quiet = v,
            onMonitoring: (v) => monitor = v,
          ),
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('alarm-quiet-hours')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      expect(quiet, isFalse);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('alarm-monitoring')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      expect(monitor, isFalse);
    });

    testWidgets('an alarm raised before the app connected is still latched', (
      tester,
    ) async {
      _tall(tester);
      final acked = <Alarm>[];
      await tester.pumpWidget(
        _wrap(
          AlarmSettingsView(
            deviceRules: const {},
            alarms: const [
              Alarm(
                id: 3,
                rule: 'target_reached',
                probe: 2,
                severity: AlarmSeverity.critical,
              ),
            ],
            onAck: acked.add,
          ),
        ),
      );
      expect(find.textContaining('Not acknowledged yet'), findsOneWidget);
      await tester.tap(find.byKey(const Key('alarm-ack-3')));
      await tester.pump();
      expect(acked.single.id, 3);
    });

    testWidgets('with no link, Silence is disabled and the card says why', (
      tester,
    ) async {
      // It used to be fully enabled behind `_transport?.control(...) ??
      // Future.value()` — a button that did nothing, said nothing, and left
      // the alarm sounding.
      _tall(tester);
      final acked = <Alarm>[];
      await tester.pumpWidget(
        _wrap(
          AlarmSettingsView(
            deviceRules: null,
            alarms: const [Alarm(id: 7, rule: 'pit_crash')],
            ackReason: SettingsLane.none.control,
            onAck: acked.add,
          ),
        ),
      );
      final button = tester.widget<OutlinedButton>(
        find.byKey(const Key('alarm-ack-7')),
      );
      expect(button.onPressed, isNull);
      await tester.tap(
        find.byKey(const Key('alarm-ack-7')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(acked, isEmpty);
      // The reason is on screen, once, at the foot of the card.
      expect(
        find.textContaining('isn’t connected to your bridge'),
        findsOneWidget,
      );
    });

    testWidgets('an acked alarm shows as silenced, not resolved', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const AlarmSettingsView(
            deviceRules: {},
            alarms: [Alarm(id: 4, rule: 'pit_crash', acked: true)],
          ),
        ),
      );
      expect(find.byKey(const Key('alarm-entry-4')), findsOneWidget);
      expect(_row(tester, 'alarm-entry-4').value, 'Silenced');
      expect(find.byKey(const Key('alarm-ack-4')), findsNothing);
      expect(find.textContaining('does not resolve it'), findsOneWidget);
    });
  });

  group('display and units', () {
    testWidgets('units travel, and the row says where to', (tester) async {
      _tall(tester);
      final chosen = <String>[];
      await tester.pumpWidget(
        _wrap(DisplaySettingsView(units: 'F', onUnits: chosen.add)),
      );
      expect(find.textContaining('travels to the bridge'), findsOneWidget);
      await tester.tap(find.text('°C'));
      await tester.pump();
      expect(chosen, ['C']);
    });

    testWidgets('with no link, units still change — they are a phone setting', (
      tester,
    ) async {
      // The row carried `deviceReason`, so °F/°C became unchangeable whenever
      // the bridge was unreachable. It is applied to prefs immediately; only
      // the mirror to the bridge's own screen needs a link, and the card one
      // section below states that principle out loud.
      _tall(tester);
      final chosen = <String>[];
      await tester.pumpWidget(
        _wrap(
          DisplaySettingsView(
            units: 'F',
            onUnits: chosen.add,
            deviceReason: SettingsLane.none.deviceConfig,
          ),
        ),
      );
      expect(_row(tester, 'settings-units').reason, isEmpty);
      await tester.tap(find.text('°C'));
      await tester.pump();
      expect(chosen, ['C']);
      // The caveat is in the sentence, not on the control.
      expect(
        find.textContaining('bridge’s own screen will catch up'),
        findsOneWidget,
      );
    });

    testWidgets('the theme is marked as a phone-only setting', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(DisplaySettingsView(units: 'F', onUnits: (_) {})),
      );
      expect(find.textContaining('only about your phone'), findsOneWidget);
    });

    testWidgets('an unread screen timeout is absent, never a default', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(DisplaySettingsView(units: 'F', onUnits: (_) {})),
      );
      // The old page rendered a 60-second timeout nobody had read. The chips
      // still offer "1m" as a shortcut — a shortcut is not a claim — but the
      // row's own value is the em dash.
      expect(_row(tester, 'settings-display-timeout').value, isNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('settings-display-timeout')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a reported screen timeout is a fact, and settable', (
      tester,
    ) async {
      _tall(tester);
      final sent = <int>[];
      await tester.pumpWidget(
        _wrap(
          DisplaySettingsView(
            units: 'F',
            onUnits: (_) {},
            displayTimeoutS: 60,
            onDisplayTimeout: sent.add,
          ),
        ),
      );
      expect(_row(tester, 'settings-display-timeout').value, '1m');
      await tester.tap(find.text('5m'));
      await tester.pump();
      expect(sent, [300]);
    });

    testWidgets('a value no shortcut matches still renders as the fact', (
      tester,
    ) async {
      // The firmware clamps to {0} ∪ [15,600]; somebody can still have set 45
      // over USB. Showing nothing selected and no value would read as broken.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          DisplaySettingsView(
            units: 'F',
            onUnits: (_) {},
            displayTimeoutS: 45,
            onDisplayTimeout: (_) {},
          ),
        ),
      );
      expect(_row(tester, 'settings-display-timeout').value, '45s');
    });

    testWidgets('never sleeping is a state in words, not a zero', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          DisplaySettingsView(
            units: 'F',
            onUnits: (_) {},
            displayTimeoutS: 0,
            onDisplayTimeout: (_) {},
          ),
        ),
      );
      expect(_row(tester, 'settings-display-timeout').value, 'Never sleeps');
      expect(find.text('0s'), findsNothing);
      expect(find.textContaining('burns the panel'), findsOneWidget);
    });

    testWidgets('a bridge whose screen is on the other unit says so', (
      tester,
    ) async {
      // Now readable, and worth reading: a bridge provisioned by another
      // phone, or a units write that never landed, is only discoverable here.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          DisplaySettingsView(units: 'F', deviceUnits: 'C', onUnits: (_) {}),
        ),
      );
      expect(
        find.textContaining('the bridge’s own screen is still on Celsius'),
        findsOneWidget,
      );
    });

    testWidgets('when both agree, the row says so rather than staying silent', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          DisplaySettingsView(units: 'F', deviceUnits: 'F', onUnits: (_) {}),
        ),
      );
      expect(
        find.textContaining('own screen is showing Fahrenheit too'),
        findsOneWidget,
      );
    });

    testWidgets('over Bluetooth the screen timeout is dimmed, units are not', (
      tester,
    ) async {
      _tall(tester);
      final units = <String>[];
      await tester.pumpWidget(
        _wrap(
          DisplaySettingsView(
            units: 'F',
            onUnits: units.add,
            onDisplayTimeout: (_) {},
            hardwareReason: SettingsLane.bluetooth.deviceHardware,
          ),
        ),
      );
      // Bluetooth carries the units op and drops display_timeout_s silently —
      // so one row stays live and the other says why it cannot.
      expect(_row(tester, 'settings-display-timeout').reason, isNotEmpty);
      expect(_row(tester, 'settings-units').reason, isEmpty);
      await tester.tap(find.text('°C'));
      await tester.pump();
      expect(units, ['C']);
    });

    testWidgets('brightness and rotation stay absent, and blame the bridge', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(DisplaySettingsView(units: 'F', onUnits: (_) {})),
      );
      expect(_row(tester, 'settings-oled').reason, isNotEmpty);
      expect(
        find.textContaining('doesn’t offer these over the network'),
        findsOneWidget,
      );
    });
  });

  group('the status light', () {
    testWidgets(
      'unread, the switch is absent and inert — not a confident off',
      (tester) async {
        _tall(tester);
        await tester.pumpWidget(_wrap(LedSettingsView(onEnabled: (_) {})));
        final led = tester.widget<Switch>(
          find.descendant(
            of: find.byKey(const Key('led-enabled')),
            matching: find.byType(Switch),
          ),
        );
        expect(
          led.onChanged,
          isNull,
          reason:
              'a switch that cannot know its own state must not offer to '
              'change it',
        );
        expect(_row(tester, 'led-enabled').reason, isNotEmpty);
      },
    );

    testWidgets('a reported light is live, and round-trips', (tester) async {
      _tall(tester);
      final sent = <bool>[];
      await tester.pumpWidget(
        _wrap(LedSettingsView(enabled: true, onEnabled: sent.add)),
      );
      expect(
        find.textContaining('Lit while the bridge is awake'),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('led-enabled')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      expect(sent, [false]);
    });

    testWidgets('over Bluetooth it is dimmed and names Wi-Fi', (tester) async {
      _tall(tester);
      final sent = <bool>[];
      await tester.pumpWidget(
        _wrap(
          LedSettingsView(
            enabled: true,
            onEnabled: sent.add,
            reason: SettingsLane.bluetooth.deviceHardware,
          ),
        ),
      );
      // BleTransport.configure drops led_enabled without a word. A live switch
      // here would be the exact defect §F was opened to delete.
      expect(find.textContaining('Connect over Wi-Fi'), findsOneWidget);
      final led = tester.widget<Switch>(
        find.descendant(
          of: find.byKey(const Key('led-enabled')),
          matching: find.byType(Switch),
        ),
      );
      expect(led.onChanged, isNull);
    });

    testWidgets('the page does not say "status light" three times', (
      tester,
    ) async {
      // Section label, row label, and half the section's own subtitle on the
      // index — the same two words before anything had been said.
      _tall(tester);
      await tester.pumpWidget(_wrap(const LedSettingsView(enabled: true)));
      expect(find.text('THE LIGHT ON THE BRIDGE'), findsOneWidget);
      expect(find.text('STATUS LIGHT'), findsNothing);
      expect(
        SettingsSection.led.subtitle,
        'Off, or lit while it’s hearing the base station',
      );
    });

    testWidgets('what the firmware genuinely lacks says so, separately', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const LedSettingsView(enabled: true)));
      expect(_row(tester, 'led-behaviour').reason, isNotEmpty);
      expect(_row(tester, 'led-brightness').value, isNull);
      // The reason blames the right thing: the bridge stores on/off and
      // nothing else. Blaming the app here would be as wrong as the reverse.
      expect(
        find.textContaining('on or off, with no alarms-only'),
        findsOneWidget,
      );
    });
  });

  group('power and sleep', () {
    testWidgets('battery saver offers the tri-state and reports it', (
      tester,
    ) async {
      _tall(tester);
      final chosen = <String>[];
      await tester.pumpWidget(
        _wrap(
          PowerSettingsView(batterySaver: 'auto', onBatterySaver: chosen.add),
        ),
      );
      // `auto` is the point: it engages below 20 % and releases at 30 %, which
      // a switch could not express.
      expect(find.textContaining('below 20%'), findsOneWidget);
      await tester.tap(find.text('On'));
      await tester.pump();
      await tester.tap(find.text('Off'));
      await tester.pump();
      expect(chosen, ['on', 'off']);
    });

    testWidgets('nothing is selected until the bridge has said which', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const PowerSettingsView()));
      expect(
        find.textContaining('hasn’t reported which of these'),
        findsOneWidget,
      );
      expect(_row(tester, 'power-charge').value, isNull);
      expect(_row(tester, 'power-saver-now').value, isNull);
    });

    testWidgets('an unconfirmed choice is labelled as a request, not a fact', (
      tester,
    ) async {
      // The Bluetooth shape: the lane carried the write and cannot read it
      // back, so the row reports what was asked for and says so.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(PowerSettingsView(batterySaver: 'on', onBatterySaver: (_) {})),
      );
      expect(
        find.textContaining('can’t read the setting back'),
        findsOneWidget,
      );
    });

    testWidgets('a read-back mode is stated flatly, with no hedge', (
      tester,
    ) async {
      // The Wi-Fi shape, now that `GET /config/device` exists: the same row
      // that used to hedge on every lane states a fact on this one.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const PowerSettingsView(
            batterySaver: 'auto',
            batterySaverConfirmed: true,
            saverEngaged: false,
          ),
        ),
      );
      expect(find.textContaining('can’t read the setting back'), findsNothing);
      // The subtitle says what saving COSTS rather than restating the label.
      expect(
        find.textContaining('readings keep their 30-second cadence'),
        findsOneWidget,
      );
      expect(_row(tester, 'power-saver-now').value, 'No');
    });

    testWidgets('what the bridge reports it is doing is stated flatly', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const PowerSettingsView(
            batterySaver: 'auto',
            batterySaverConfirmed: true,
            saverEngaged: true,
            socPct: 42,
            charging: false,
          ),
        ),
      );
      expect(_row(tester, 'power-saver-now').value, 'Yes');
      expect(_row(tester, 'power-charge').value, '42%');
    });

    testWidgets('the permanently-disabled calibration row is gone', (
      tester,
    ) async {
      // It was disabled behind "this bridge does not report a battery voltage,
      // so there is nothing to calibrate against", and per its own comment it
      // always would be. A row whose reason can never stop being true is not a
      // disabled control, it is noise on a page somebody reads at 3 a.m.
      _tall(tester);
      await tester.pumpWidget(_wrap(const PowerSettingsView()));
      expect(
        find.byKey(const Key('settings-battery-calibration')),
        findsNothing,
      );
      expect(find.textContaining('nothing to calibrate'), findsNothing);
    });

    testWidgets('restart states what it keeps and what it loses', (
      tester,
    ) async {
      _tall(tester);
      var restarts = 0;
      await tester.pumpWidget(
        _wrap(PowerSettingsView(onRestart: () async => restarts++)),
      );
      await _tapAction(tester, 'power-restart');
      // Nothing has happened yet — the cost sheet is the gate.
      expect(restarts, 0);
      final sheet = _costSheet(tester);
      expect(sheet.keeps, contains('every cook it has recorded'));
      expect(sheet.loses, contains('nothing'));
      await tester.tap(find.byKey(const Key('cost-confirm')));
      await tester.pumpAndSettle();
      expect(restarts, 1);
    });

    testWidgets('cancelling a destructive verb does nothing at all', (
      tester,
    ) async {
      _tall(tester);
      var wipes = 0;
      await tester.pumpWidget(
        _wrap(PowerSettingsView(onFactoryReset: () async => wipes++)),
      );
      await _tapAction(tester, 'power-factory-reset');
      // The escape hatch names the outcome, never "Cancel".
      expect(find.text('Keep it as it is'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cost-cancel')));
      await tester.pumpAndSettle();
      expect(wipes, 0);
    });

    testWidgets('power off warns that only the PRG button can undo it', (
      tester,
    ) async {
      _tall(tester);
      var offs = 0;
      await tester.pumpWidget(
        _wrap(PowerSettingsView(onPowerOff: () async => offs++)),
      );
      await _tapAction(tester, 'power-off');
      expect(find.textContaining('hold the PRG button'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cost-confirm')));
      await tester.pumpAndSettle();
      expect(offs, 1);
    });

    testWidgets('factory reset says the phone will have to pair again', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(PowerSettingsView(onFactoryReset: () async {})),
      );
      await _tapAction(tester, 'power-factory-reset');
      final sheet = _costSheet(tester);
      expect(sheet.loses, contains('pair with it again'));
      // And it says what survives, so the decision is made on facts.
      expect(sheet.keeps, contains('already copied to this phone'));
    });

    testWidgets('with no transport the verbs are disabled WITH A REASON', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(PowerSettingsView(controlReason: SettingsLane.none.control)),
      );
      for (final k in ['power-restart', 'power-off', 'power-factory-reset']) {
        expect(_row(tester, k).reason, isNotEmpty, reason: k);
      }
      expect(
        find.textContaining('isn’t connected to your bridge'),
        findsWidgets,
      );
    });

    testWidgets('sleep is absent rather than invented', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const PowerSettingsView()));
      expect(_row(tester, 'power-auto-sleep').value, isNull);
      expect(_row(tester, 'power-auto-sleep').reason, isNotEmpty);
    });
  });

  group('network — the default-as-fact bug', () {
    testWidgets('an unread mode renders as absent, not as "Joined"', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(NetworkSettingsView(onSwitchMode: (_, _, _) async {})),
      );
      // THE bug: `NetMode _netMode = NetMode.sta` rendered "Joined a network"
      // over a bridge that was hosting its own access point.
      expect(_row(tester, 'network-current').value, isNull);
      expect(find.text('Joined yours'), findsNothing);
      expect(find.text('Hosting its own'), findsNothing);
      expect(find.textContaining('The app does not guess'), findsOneWidget);
    });

    testWidgets('a real read renders the mode it actually is', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            mode: NetMode.ap,
            ssid: 'SmokeBridge-8274',
            apClients: 1,
            onSwitchMode: (_, _, _) async {},
          ),
        ),
      );
      expect(_row(tester, 'network-current').value, 'Hosting its own');
      expect(_row(tester, 'network-strength').value, '1');
    });

    testWidgets('hosting shows the key the user needs to join', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            mode: NetMode.ap,
            ssid: 'SmokeBridge-8274',
            apPsk: 'Gk7mR2xQpT',
            onSwitchMode: (_, _, _) async {},
          ),
        ),
      );
      expect(find.text('Gk7mR2xQpT'), findsOneWidget);
    });

    testWidgets('an address the bridge never reported stays absent', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(NetworkSettingsView(onSwitchMode: (_, _, _) async {})),
      );
      expect(_row(tester, 'network-address').value, isNull);
      expect(_row(tester, 'network-ssid').value, isNull);
    });

    testWidgets('a signal is a word first and a number second', (tester) async {
      // §16.4 rule 3 scopes dBm to Diagnostics. A bare "-58 dBm" on a settings
      // page tells a tired reader nothing they can act on.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            mode: NetMode.sta,
            wifiDbm: -58,
            onSwitchMode: (_, _, _) async {},
          ),
        ),
      );
      expect(_row(tester, 'network-strength').value, 'Strong · -58 dBm');
    });

    testWidgets('the two rows no longer both open with the word "Network"', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            mode: NetMode.sta,
            ssid: 'Backyard',
            onSwitchMode: (_, _, _) async {},
          ),
        ),
      );
      expect(_row(tester, 'network-current').label, 'What it’s doing');
      expect(_row(tester, 'network-ssid').label, 'Network name');
    });
  });

  group('network — changing it', () {
    testWidgets('switching to hosting goes through the wizard callback', (
      tester,
    ) async {
      _tall(tester);
      final asked = <(NetMode, String, String)>[];
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            mode: NetMode.sta,
            onSwitchMode: (m, s, p) async => asked.add((m, s, p)),
          ),
        ),
      );
      await _tapAction(tester, 'network-mode-ap');
      expect(asked.single, (NetMode.ap, '', ''));
    });

    testWidgets('joining sends one request with both fields', (tester) async {
      _tall(tester);
      final asked = <(NetMode, String, String)>[];
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            mode: NetMode.ap,
            onSwitchMode: (m, s, p) async => asked.add((m, s, p)),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('network-ssid-field')),
        'Backyard',
      );
      await tester.enterText(find.byKey(const Key('network-psk')), 'hunter2');
      await _tapAction(tester, 'network-join');
      expect(asked.single, (NetMode.sta, 'Backyard', 'hunter2'));
    });

    testWidgets('joining with no network name is refused in the form', (
      tester,
    ) async {
      _tall(tester);
      final asked = <NetMode>[];
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            mode: NetMode.ap,
            onSwitchMode: (m, _, _) async => asked.add(m),
          ),
        ),
      );
      await _tapAction(tester, 'network-join');
      expect(asked, isEmpty);
      expect(find.textContaining('Enter the name'), findsOneWidget);
    });

    testWidgets('a pending rollback is reported as a plan with a number', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(revertInS: 87, onSwitchMode: (_, _, _) async {}),
        ),
      );
      expect(find.byKey(const Key('network-revert-pending')), findsOneWidget);
      expect(find.textContaining('87 seconds'), findsOneWidget);
      expect(find.textContaining('Nothing to undo'), findsOneWidget);
    });

    testWidgets('an unreachable bridge lands on copy, not a spinner', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            onSwitchMode: (_, _, _) async {},
            recoveryMessage:
                'The bridge joined the network but this phone cannot reach it.',
          ),
        ),
      );
      expect(find.byKey(const Key('network-recovery')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a manual address is normalised and handed on', (tester) async {
      _tall(tester);
      final entered = <String>[];
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            onSwitchMode: (_, _, _) async {},
            onManualAddress: entered.add,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('network-manual')),
        '192.168.1.42',
      );
      await _tapAction(tester, 'network-manual-connect');
      expect(entered, ['http://192.168.1.42']);
    });

    testWidgets('a malformed address is refused in the field', (tester) async {
      _tall(tester);
      final entered = <String>[];
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            onSwitchMode: (_, _, _) async {},
            onManualAddress: entered.add,
          ),
        ),
      );
      await _tapAction(tester, 'network-manual-connect');
      expect(find.textContaining('not an address'), findsOneWidget);
      expect(entered, isEmpty);
    });

    testWidgets('an address nothing answers on stays on this page, named', (
      tester,
    ) async {
      // It used to record the string and `context.go('/live')` regardless, so
      // one mistyped digit landed the reader on the live screen with no
      // message at all (16 §16.4 rule 10).
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            onSwitchMode: (_, _, _) async {},
            onManualAddress: (_) {},
            manualAddressError:
                'Nothing answered at that address. Check it against the '
                'bridge’s own screen, which shows the one it is using.',
          ),
        ),
      );
      expect(
        find.textContaining('Nothing answered at that address'),
        findsOneWidget,
      );
      // And the verb no longer promises what it cannot know.
      expect(find.textContaining('checks the address answers'), findsOneWidget);
    });

    testWidgets('while it is checking, the verb says so and is inert', (
      tester,
    ) async {
      _tall(tester);
      final entered = <String>[];
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            onSwitchMode: (_, _, _) async {},
            onManualAddress: entered.add,
            manualAddressBusy: true,
          ),
        ),
      );
      expect(find.text('Trying…'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('network-manual-connect')),
          matching: find.byType(OutlinedButton),
        ),
      );
      await tester.pump();
      expect(entered, isEmpty);
    });

    testWidgets('the network the bridge is on prefills the join field', (
      tester,
    ) async {
      // `late final _ssid = TextEditingController(text: widget.ssid)` and
      // `widget.ssid` is '' on the first build — the route learns the SSID a
      // round trip later, so this field was permanently empty.
      _tall(tester);
      Widget view(String ssid) => _wrap(
        NetworkSettingsView(ssid: ssid, onSwitchMode: (_, _, _) async {}),
      );
      await tester.pumpWidget(view(''));
      await tester.pumpWidget(view('Backyard'));
      await tester.pump();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('network-ssid-field')))
            .controller
            ?.text,
        'Backyard',
      );
    });

    testWidgets('§F’s SoftAP credentials and revert timer are stated', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(NetworkSettingsView(onSwitchMode: (_, _, _) async {})),
      );
      expect(_row(tester, 'network-ap-credentials').reason, isNotEmpty);
      // The revert timer was a hardcoded constant nobody could see.
      expect(_row(tester, 'network-revert-timer').value, '120 seconds');
      expect(_row(tester, 'network-revert-timer').reason, isNotEmpty);
    });

    testWidgets('with no link the change block is dimmed with its reason', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            onSwitchMode: (_, _, _) async {},
            unsupportedReason: SettingsLane.none.network,
          ),
        ),
      );
      expect(
        find.textContaining('isn’t connected to your bridge'),
        findsWidgets,
      );
    });
  });

  group('the §E.3 wizard sheet', () {
    testWidgets('every phase has words, and the rollback is not an error', (
      tester,
    ) async {
      _tall(tester);
      final machine = NetModeSwitch(
        apply: (_, _, _) async => '',
        probe: () async => false,
        commit: () async {},
        attemptDelay: Duration.zero,
        maxAttempts: 2,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: SmokeTheme.dark,
          home: Scaffold(
            body: NetModeSwitchSheet(machine: machine, mode: NetworkMode.ap),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('netmode-title')), findsOneWidget);
      // Never an unexplained spinner: the attempt counter is on screen.
      expect(find.byKey(const Key('netmode-attempt')), findsOneWidget);
      await tester.pumpAndSettle();
      // Out of attempts. This is the device's plan, with a number on it —
      // not a failure the user has to fix.
      expect(find.text('Couldn’t reach the bridge'), findsOneWidget);
      expect(find.textContaining('nobody has to walk over'), findsOneWidget);
      expect(find.byKey(const Key('netmode-progress')), findsNothing);
    });
  });

  group('home assistant', () {
    testWidgets('an unread config renders absence, not port 1883', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          MqttSettingsView(
            config: const MqttConfig(),
            configKnown: false,
            onApply: _noApply,
          ),
        ),
      );
      // MqttConfig()'s own defaults are port 1883 and prefix `smokebridge`.
      // Neither was ever reported by this bridge.
      expect(_row(tester, 'mqtt-status').value, isNull);
      expect(_row(tester, 'mqtt-current-broker').value, isNull);
    });

    testWidgets('an unread config offers no form to save over a live broker', (
      tester,
    ) async {
      // The summary rows honoured `configKnown` from the day it was added; the
      // fields below them seeded `late final` controllers from a
      // default-constructed MqttConfig and never looked again. Saving that
      // wrote an empty broker over a working one — and the read-back agreed,
      // because it was now true.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          MqttSettingsView(
            config: const MqttConfig(),
            configKnown: false,
            onApply: _noApply,
          ),
        ),
      );
      expect(find.byKey(const Key('mqtt-host')), findsNothing);
      expect(find.byKey(const Key('mqtt-save')), findsNothing);
      expect(find.byKey(const Key('mqtt-unread')), findsOneWidget);
      expect(
        find.textContaining('hasn’t sent its broker settings'),
        findsOneWidget,
      );
    });

    testWidgets('the read arriving fills the form with the real broker', (
      tester,
    ) async {
      _tall(tester);
      Map<String, Object?>? applied;
      Widget view({required bool known, required MqttConfig config}) => _wrap(
        MqttSettingsView(
          config: config,
          configKnown: known,
          onApply:
              ({
                required enabled,
                required host,
                required port,
                required user,
                password,
                required prefix,
                required haDiscovery,
              }) async {
                applied = {
                  'enabled': enabled,
                  'host': host,
                  'port': port,
                  'prefix': prefix,
                };
              },
        ),
      );

      await tester.pumpWidget(view(known: false, config: const MqttConfig()));
      await tester.pumpWidget(
        view(
          known: true,
          config: const MqttConfig(
            enabled: true,
            host: 'broker.lan',
            port: 8883,
            prefix: 'garden',
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('mqtt-save')));
      await tester.pump();
      // Saving without touching anything writes back what the bridge has —
      // not a blank form.
      expect(applied, {
        'enabled': true,
        'host': 'broker.lan',
        'port': 8883,
        'prefix': 'garden',
      });
    });

    testWidgets('a read arriving mid-edit does not take back the typing', (
      tester,
    ) async {
      _tall(tester);
      String? savedHost;
      Widget view(MqttConfig config) => _wrap(
        MqttSettingsView(
          config: config,
          onApply:
              ({
                required enabled,
                required host,
                required port,
                required user,
                password,
                required prefix,
                required haDiscovery,
              }) async {
                savedHost = host;
              },
        ),
      );

      await tester.pumpWidget(view(const MqttConfig(host: 'old.lan')));
      await tester.enterText(find.byKey(const Key('mqtt-host')), 'new.lan');
      await tester.pump();
      await tester.pumpWidget(view(const MqttConfig(host: 'old.lan')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('mqtt-save')));
      await tester.pump();
      expect(savedHost, 'new.lan');
    });

    testWidgets('save reports the edited config, blank password kept', (
      tester,
    ) async {
      _tall(tester);
      Map<String, Object?>? applied;
      await tester.pumpWidget(
        _wrap(
          MqttSettingsView(
            config: const MqttConfig(host: 'old', port: 1883),
            onApply:
                ({
                  required enabled,
                  required host,
                  required port,
                  required user,
                  password,
                  required prefix,
                  required haDiscovery,
                }) async {
                  applied = {
                    'enabled': enabled,
                    'host': host,
                    'port': port,
                    'password': password,
                  };
                },
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('mqtt-host')), 'broker.lan');
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('mqtt-enabled')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('mqtt-save')));
      await tester.pump();

      expect(applied, isNotNull);
      expect(applied!['host'], 'broker.lan');
      expect(applied!['enabled'], true);
      // A blank password field must NOT wipe the stored one.
      expect(applied!['password'], isNull);
    });

    testWidgets('enabling without a host is refused with a reason', (
      tester,
    ) async {
      _tall(tester);
      var called = false;
      await tester.pumpWidget(
        _wrap(
          MqttSettingsView(
            config: const MqttConfig(),
            onApply:
                ({
                  required enabled,
                  required host,
                  required port,
                  required user,
                  password,
                  required prefix,
                  required haDiscovery,
                }) async {
                  called = true;
                },
          ),
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('mqtt-enabled')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('mqtt-save')));
      await tester.pump();
      expect(find.byKey(const Key('mqtt-error')), findsOneWidget);
      expect(called, isFalse);
    });

    testWidgets('a Bluetooth link dims the rows and names the reason', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          MqttSettingsView(
            config: const MqttConfig(),
            unsupportedReason: SettingsLane.bluetooth.mqtt,
            onApply: _noApply,
          ),
        ),
      );
      expect(find.textContaining('Home Assistant needs Wi-Fi'), findsOneWidget);
      expect(find.byKey(const Key('mqtt-unsupported')), findsOneWidget);
      // No live-looking form over a lane that cannot carry it.
      expect(find.byKey(const Key('mqtt-host')), findsNothing);
      expect(find.byKey(const Key('mqtt-save')), findsNothing);
    });
  });

  group('firmware', () {
    testWidgets('a lane that cannot OTA explains instead of offering', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          FirmwareSettingsView(
            currentVersion: '1.0.0',
            otaSupported: false,
            unsupportedReason: SettingsLane.bluetooth.firmware,
          ),
        ),
      );
      expect(find.byKey(const Key('firmware-upload')), findsNothing);
      expect(find.byKey(const Key('firmware-unsupported')), findsOneWidget);
      expect(
        find.textContaining('far too big to send over Bluetooth'),
        findsOneWidget,
      );
    });

    testWidgets('an unknown version is absent, not an empty string', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const FirmwareSettingsView(currentVersion: '', otaSupported: true),
        ),
      );
      expect(_row(tester, 'firmware-version').value, isNull);
    });

    testWidgets('progress renders from real ota frames', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const FirmwareSettingsView(
            currentVersion: '1.0.0',
            otaSupported: true,
            imageSourceAvailable: true,
            progressPct: 42,
            phase: 'writing',
          ),
        ),
      );
      expect(find.byKey(const Key('firmware-progress')), findsOneWidget);
      expect(find.text('writing — 42%'), findsWidgets);
    });

    testWidgets('the 409 is explained, and force is a separate action', (
      tester,
    ) async {
      _tall(tester);
      final forced = <bool>[];
      await tester.pumpWidget(
        _wrap(
          FirmwareSettingsView(
            currentVersion: '1.0.0',
            otaSupported: true,
            imageSourceAvailable: true,
            sessionActive: true,
            refusal: 'session_active',
            onUpload: ({required bool force}) async => forced.add(force),
          ),
        ),
      );
      expect(find.byKey(const Key('firmware-refusal')), findsOneWidget);
      expect(
        find.textContaining('fourteen hours into a brisket'),
        findsWidgets,
      );
      await _tapAction(tester, 'firmware-upload-force');
      expect(forced, [true]);
    });

    testWidgets('with no cook running there is no force button at all', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          FirmwareSettingsView(
            currentVersion: '1.0.0',
            otaSupported: true,
            imageSourceAvailable: true,
            onUpload: ({required bool force}) async {},
          ),
        ),
      );
      expect(find.byKey(const Key('firmware-upload')), findsOneWidget);
      expect(find.byKey(const Key('firmware-upload-force')), findsNothing);
    });

    testWidgets('OTA-capable but no picker explains, with no dead button', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const FirmwareSettingsView(
            currentVersion: '1.0.0',
            otaSupported: true,
          ),
        ),
      );
      expect(find.byKey(const Key('firmware-no-image-source')), findsOneWidget);
      expect(find.byKey(const Key('firmware-upload')), findsNothing);
      // The version still renders — the page is not degraded, only the upload.
      expect(_row(tester, 'firmware-version').value, '1.0.0');
      // And it points somewhere a user can go, not at a repository file.
      expect(find.textContaining('README'), findsNothing);
      expect(find.textContaining('web installer'), findsOneWidget);
    });

    testWidgets('§F’s "check for update" is present and says why it cannot', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const FirmwareSettingsView(
            currentVersion: '1.0.0',
            otaSupported: true,
          ),
        ),
      );
      expect(_row(tester, 'firmware-check').reason, isNotEmpty);
      expect(find.textContaining('There is nowhere to ask'), findsOneWidget);
    });

    testWidgets('the version subtitle says something the label does not', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const FirmwareSettingsView(
            currentVersion: '1.0.0',
            otaSupported: true,
          ),
        ),
      );
      expect(find.textContaining('never touch your cooks'), findsWidgets);
      expect(
        find.text('What the bridge is running now'),
        findsNothing,
        reason: 'a subtitle explains; that one restated the label',
      );
    });
  });

  group('data and export', () {
    testWidgets('what this phone keeps is counted, and explained', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const DataSettingsView(
            sessions: 3,
            samples: 7440,
            approxBytes: 262144,
          ),
        ),
      );
      expect(_row(tester, 'storage-sessions').value, '3');
      expect(_row(tester, 'storage-samples').value, '62 h');
      expect(find.byKey(const Key('storage-explainer')), findsOneWidget);
      expect(find.textContaining('Nothing expires on its own'), findsOneWidget);
    });

    testWidgets('clearing states what it keeps and what it loses', (
      tester,
    ) async {
      _tall(tester);
      var cleared = 0;
      await tester.pumpWidget(
        _wrap(
          DataSettingsView(
            sessions: 2,
            samples: 1200,
            approxBytes: 4096,
            onClear: () async => cleared++,
          ),
        ),
      );
      await _tapAction(tester, 'storage-clear');
      expect(cleared, 0);
      final sheet = _costSheet(tester);
      expect(sheet.loses, contains('already deleted to make room'));
      expect(sheet.keeps, contains('copied back'));
      expect(find.text('Keep them'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cost-confirm')));
      await tester.pumpAndSettle();
      expect(cleared, 1);
    });

    testWidgets('with nothing stored, clearing is disabled with its reason', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          DataSettingsView(
            sessions: 0,
            samples: 0,
            approxBytes: 0,
            onClear: () async {},
          ),
        ),
      );
      expect(_row(tester, 'storage-clear').reason, isNotEmpty);
    });

    testWidgets('an unread retention limit is absent, never 64', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const DataSettingsView(sessions: 0, samples: 0, approxBytes: 0)),
      );
      expect(_row(tester, 'data-bridge-retention').value, isNull);
      // The old device page rendered "64 — the oldest are deleted first" from
      // a constructor default.
      expect(find.textContaining('64 —'), findsNothing);
      // Wiping the bridge's own buffer is not a thing this firmware offers;
      // the row says where the nearest real answer is.
      expect(find.textContaining('factory reset'), findsOneWidget);
    });

    testWidgets('a reported retention limit is a fact, and settable', (
      tester,
    ) async {
      _tall(tester);
      final sent = <int>[];
      await tester.pumpWidget(
        _wrap(
          DataSettingsView(
            sessions: 0,
            samples: 0,
            approxBytes: 0,
            maxSessionsOnBridge: 64,
            minFreePct: 10,
            onMaxSessions: sent.add,
          ),
        ),
      );
      expect(_row(tester, 'data-bridge-retention').value, '64');
      // The consequence at the limit, said on the row rather than left to be
      // discovered when a cook goes missing.
      expect(find.textContaining('the oldest cook is deleted'), findsOneWidget);
      expect(
        find.textContaining('keeps 10% of its storage free'),
        findsOneWidget,
      );
      await tester.tap(find.text('128'));
      await tester.pump();
      expect(sent, [128]);
    });

    testWidgets('over Bluetooth the retention row is dimmed with its reason', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          DataSettingsView(
            sessions: 0,
            samples: 0,
            approxBytes: 0,
            onMaxSessions: (_) {},
            hardwareReason: SettingsLane.bluetooth.deviceHardware,
          ),
        ),
      );
      expect(_row(tester, 'data-bridge-retention').reason, isNotEmpty);
      expect(find.textContaining('how many cooks it keeps'), findsWidgets);
    });

    testWidgets('space left on the bridge is absent until reported', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const DataSettingsView(sessions: 0, samples: 0, approxBytes: 0)),
      );
      expect(_row(tester, 'data-bridge-free').value, isNull);
    });
  });

  group('diagnostics', () {
    testWidgets('with nothing read, every row is a dash and none is a zero', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const DiagnosticsSettingsView()));
      for (final k in [
        'diag-address',
        'diag-signal',
        'diag-firmware',
        'diag-model',
        'diag-device-id',
        'diag-uptime',
        'diag-storage',
        'diag-battery',
        'diag-paired',
        'diag-probes-reported',
        'diag-last-packet',
        'diag-clock',
        'diag-capabilities',
      ]) {
        expect(_row(tester, k).value, isNull, reason: k);
      }
      expect(find.text('0'), findsNothing);
      expect(find.text('0%'), findsNothing);
    });

    testWidgets('measured values render, and name the hop they measured', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const DiagnosticsSettingsView(
            lane: SettingsLane.bluetooth,
            linkDbm: -62,
            firmware: '1.2.0',
            uptimeS: 3600,
            socPct: 88,
            paired: true,
            probesReported: 2,
            lastPacketSAgo: 30,
            canFullHistory: true,
            canConfigure: false,
          ),
        ),
      );
      expect(_row(tester, 'diag-transport').value, 'Bluetooth');
      expect(_row(tester, 'diag-signal').value, '-62 dBm');
      expect(find.textContaining('phone to bridge'), findsOneWidget);
      expect(_row(tester, 'diag-capabilities').value, 'Full history');
      expect(_row(tester, 'diag-battery').value, '88%');
    });

    testWidgets('the mislabelled packet counter is gone', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const DiagnosticsSettingsView(probesReported: 2)),
      );
      // `packets_seen: numProbes` was a wrong fact on the page people open
      // when they already suspect something is wrong.
      expect(find.textContaining('packets seen'), findsNothing);
      expect(find.textContaining('packets_seen'), findsNothing);
      expect(_row(tester, 'diag-probes-reported').value, '2');
    });

    testWidgets('an unset clock says what it costs, and offers the remedy', (
      tester,
    ) async {
      _tall(tester);
      var set = 0;
      await tester.pumpWidget(
        _wrap(DiagnosticsSettingsView(clockUnixMs: 0, onSetClock: () => set++)),
      );
      expect(_row(tester, 'diag-clock').value, isNull);
      expect(find.textContaining('cannot be dated'), findsOneWidget);
      await _tapAction(tester, 'diag-set-clock');
      expect(set, 1);
    });

    testWidgets('with no sync yet, the section says so rather than showing 0', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const DiagnosticsSettingsView()));
      expect(find.byKey(const Key('diag-sync-empty')), findsOneWidget);
      expect(find.textContaining('no high-water mark'), findsOneWidget);
    });

    testWidgets('a rollover gap is stated, never smoothed over', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const DiagnosticsSettingsView(
            syncRows: [('Cook 4 — copied up to', '2h 10m')],
            rolloverLoss: 'cook 4, 42m',
          ),
        ),
      );
      expect(find.byKey(const Key('diag-rollover')), findsOneWidget);
      expect(find.textContaining('That time is gone'), findsOneWidget);
    });

    testWidgets('nothing wrong reads as "None", not as a blank', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const DiagnosticsSettingsView()));
      expect(_row(tester, 'diag-last-problem').value, 'None');
    });

    testWidgets('the log export that could never work is gone', (tester) async {
      // Permanently disabled behind "There is nothing logged this session to
      // export." — and there was no log buffer anywhere in the app, so there
      // never would be. A reason nobody can act on is not a reason.
      _tall(tester);
      await tester.pumpWidget(
        _wrap(DiagnosticsSettingsView(onFieldReport: () {})),
      );
      expect(find.byKey(const Key('settings-export-logs')), findsNothing);
      expect(find.byKey(const Key('settings-logs')), findsNothing);
      expect(find.byKey(const Key('settings-field-report')), findsOneWidget);
    });

    testWidgets('with no field report there is no empty section either', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const DiagnosticsSettingsView()));
      expect(find.text('THIS APP'), findsNothing);
    });
  });

  group('about', () {
    testWidgets('carries the D9 MIT attribution', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const AboutView(appVersion: '1.0.0', firmwareVersion: '1.0.0')),
      );
      expect(find.byKey(const Key('settings-attribution')), findsOneWidget);
      expect(find.textContaining('MIT'), findsOneWidget);
    });

    testWidgets('an unknown firmware renders as absence', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const AboutView(appVersion: '1.0.0')));
      expect(find.text('—'), findsNWidgets(2));
    });
  });

  // §F's transport column, as data rather than as nine hand-typed strings.
  group('§F — the transport table', () {
    test('Bluetooth cannot write probes, MQTT or firmware, and says why', () {
      expect(SettingsLane.bluetooth.probes, contains('Connect over Wi-Fi'));
      expect(SettingsLane.bluetooth.mqtt, contains('needs Wi-Fi'));
      expect(SettingsLane.bluetooth.firmware, contains('too big'));
    });

    test('Bluetooth CAN write units, the verbs and the network switch', () {
      // §E.3: Bluetooth is the lane that carries a mode switch *safely*, so it
      // is never the blocked one.
      expect(SettingsLane.bluetooth.deviceConfig, isEmpty);
      expect(SettingsLane.bluetooth.control, isEmpty);
      expect(SettingsLane.bluetooth.network, isEmpty);
    });

    test('Bluetooth cannot write the bridge’s own hardware, and says so', () {
      // §F marks these ✅ on every lane; BleTransport.configure carries units
      // and the saver and drops display_timeout_s, led_enabled and
      // max_sessions with no throw and no result frame. This column is what
      // stops that becoming a live-looking control.
      expect(SettingsLane.bluetooth.deviceHardware, contains('Wi-Fi'));
      expect(
        SettingsLane.bluetooth.deviceHardware,
        contains('the battery saver'),
        reason: 'the sentence draws the line where the firmware draws it',
      );
    });

    test('Wi-Fi blocks nothing', () {
      expect(SettingsLane.wifi.probes, isEmpty);
      expect(SettingsLane.wifi.mqtt, isEmpty);
      expect(SettingsLane.wifi.firmware, isEmpty);
      expect(SettingsLane.wifi.deviceConfig, isEmpty);
      expect(SettingsLane.wifi.deviceHardware, isEmpty);
    });

    test(
      'no link blocks everything, with one sentence that names the cause',
      () {
        for (final reason in [
          SettingsLane.none.probes,
          SettingsLane.none.mqtt,
          SettingsLane.none.firmware,
          SettingsLane.none.deviceConfig,
          SettingsLane.none.deviceHardware,
          SettingsLane.none.control,
          SettingsLane.none.network,
        ]) {
          expect(reason, contains('isn’t connected'));
          expect(reason, contains('keeps trying'));
        }
      },
    );

    test('a lane names itself in words, never as a class name', () {
      expect(SettingsLane.bluetooth.title, 'Bluetooth');
      expect(SettingsLane.wifi.title, 'Wi-Fi');
      expect(SettingsLane.none.title, 'Not connected');
    });
  });

  group('16 §16.4 rule 10 — a write reports what happened', () {
    test('an unverifiable write never claims to have been saved', () {
      final msg = writeOutcomeMessage(WriteOutcome.unverified, 'the units');
      expect(msg, isNot(contains('Saved')));
      expect(msg, contains('can’t confirm'));
      expect(msg, contains('the units'));
    });

    test('a verified write is the only one that says saved', () {
      expect(
        writeOutcomeMessage(WriteOutcome.verified, 'anything'),
        contains('Saved'),
      );
      for (final o in WriteOutcome.values.where(
        (o) => o != WriteOutcome.verified,
      )) {
        expect(
          writeOutcomeMessage(o, 'a thing'),
          isNot(startsWith('Saved')),
          reason: o.name,
        );
      }
    });

    test('a device that kept its own values says so in the user’s terms', () {
      final msg = writeOutcomeMessage(WriteOutcome.changedByDevice, 'x');
      expect(msg, contains('what it actually has'));
    });

    test('no link is never silence', () {
      expect(
        writeOutcomeMessage(WriteOutcome.noLink, 'x'),
        contains('nothing was saved'),
      );
    });

    test('every message is free of status codes and jargon', () {
      for (final o in WriteOutcome.values) {
        final msg = writeOutcomeMessage(o, 'the units');
        expect(msg, isNot(contains('HTTP')));
        expect(msg, isNot(contains('40')));
        expect(msg, isNot(contains('null')));
      }
    });
  });
}

Future<void> _noApply({
  required bool enabled,
  required String host,
  required int port,
  required String user,
  String? password,
  required String prefix,
  required bool haDiscovery,
}) async {}
