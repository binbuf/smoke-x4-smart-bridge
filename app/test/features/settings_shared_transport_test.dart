/// The settings tree writes through the **shared** connection and verifies by
/// read-back (newapp §F, §I.1 Phase 0; 16 §16.6).
///
/// Three defects are pinned here, and they are the three §F was opened for:
///
///  1. **On a Bluetooth-only setup, saving probe settings appeared to succeed
///     while writing nothing.** `SettingsRoute` built its own `HttpTransport`
///     from `prefs.lastBaseUrl`; a Bluetooth-only phone has no base URL, so the
///     transport stayed null, and every write went through a null-aware
///     `_transport?.configure(...)` that silently did nothing. The form said
///     saved. The bridge never heard.
///  2. **Rows rendered constructor defaults as facts** — a 60-second display
///     timeout, the status LED on, 64 cooks kept, and worst of all a network
///     mode of `sta` rendered as "Joined a network" over a bridge that was
///     hosting its own access point.
///  3. **A 200 was reported as "Saved"** even for settings nothing on any lane
///     reads back.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/app_env.dart';
import 'package:smoke_bridge/data/prefs/bridge_prefs.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/data/transport/mock_transport.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/settings/settings_kit.dart';
import 'package:smoke_bridge/features/settings/settings_network.dart';
import 'package:smoke_bridge/features/settings/settings_probes.dart';
import 'package:smoke_bridge/features/settings/settings_route.dart';
import 'package:smoke_bridge/features/settings/settings_screen.dart';

import '../data/records_parity_test.dart' show repoRoot;
import '../support/fake_env.dart';

Widget _route(SettingsSection section) => MaterialApp(
  theme: SmokeTheme.dark,
  home: SettingsRoute(initialSection: section, embedded: true),
);

SettingsRow _row(WidgetTester tester, String key) => tester.widget<SettingsRow>(
  find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(SettingsRow),
    matchRoot: true,
  ),
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('§F — no shared link means no live-looking controls', () {
    testWidgets('the probe page states why it cannot write, rather than '
        'offering a form that silently drops the save', (tester) async {
      // The Bluetooth-only shape: a bridge id remembered, no base URL. Under
      // the old code this produced `_transport == null` and a silent no-op
      // behind a form that reported success.
      _tall(tester);
      AppEnv.instance = fakeEnv(prefs: InMemoryBridgePrefs(lastBridgeId: 'b'));
      addTearDown(() => AppEnv.instance = null);

      await tester.pumpWidget(_route(SettingsSection.probes));
      await tester.pumpAndSettle();

      expect(find.byType(ProbeSettingsView), findsOneWidget);
      expect(
        find.textContaining('isn’t connected to your bridge'),
        findsWidgets,
        reason:
            'disabled-with-a-reason, never a live-looking form over a dead '
            'write',
      );
    });

    testWidgets('the verbs on the power page are dimmed with a reason', (
      tester,
    ) async {
      _tall(tester);
      AppEnv.instance = fakeEnv(prefs: InMemoryBridgePrefs(lastBridgeId: 'b'));
      addTearDown(() => AppEnv.instance = null);

      await tester.pumpWidget(_route(SettingsSection.power));
      await tester.pumpAndSettle();

      for (final k in ['power-restart', 'power-off', 'power-factory-reset']) {
        expect(_row(tester, k).reason, isNotEmpty, reason: k);
      }
    });

    testWidgets('the probe form does not exist before a read lands', (
      tester,
    ) async {
      // The route hands `ProbeSettingsView` `_probes`, which is `const []`
      // until the async `live()` in `_refreshStatus` answers. The form used to
      // seed four blank `Probe(n:)` from that and offer "Save to the bridge",
      // which wrote the blanks over the real configuration and then reported
      // success because the read-back matched what it had just written.
      _tall(tester);
      AppEnv.instance = fakeEnv(prefs: InMemoryBridgePrefs(lastBridgeId: 'b'));
      addTearDown(() => AppEnv.instance = null);

      await tester.pumpWidget(_route(SettingsSection.probes));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('probe-name-1')), findsNothing);
      expect(find.byKey(const Key('probes-unread')), findsOneWidget);
    });

    testWidgets('the bridge’s rule count is read, never a constant', (
      tester,
    ) async {
      // It was `const {six rules: true}` in the route, so a phone that had
      // never met a bridge printed "6 of 6 on" as a device fact — over any
      // lane, connected or not, and naming six of §G.1's nine at that.
      _tall(tester);
      AppEnv.instance = fakeEnv(prefs: InMemoryBridgePrefs(lastBridgeId: 'b'));
      addTearDown(() => AppEnv.instance = null);

      await tester.pumpWidget(_route(SettingsSection.alarms));
      await tester.pumpAndSettle();

      expect(_row(tester, 'alarms-device-count').value, isNull);
      expect(find.textContaining('6 of 6'), findsNothing);
      expect(
        find.textContaining('hasn’t reported its rules yet'),
        findsOneWidget,
      );
    });

    testWidgets('the Home Assistant form waits for the bridge to answer', (
      tester,
    ) async {
      _tall(tester);
      AppEnv.instance = fakeEnv(prefs: InMemoryBridgePrefs(lastBridgeId: 'b'));
      addTearDown(() => AppEnv.instance = null);

      await tester.pumpWidget(_route(SettingsSection.homeAssistant));
      await tester.pumpAndSettle();

      // `_mqtt ?? const MqttConfig()` is what reaches the view, and
      // `MqttConfig()` carries port 1883 and the prefix `smokebridge`. Neither
      // may reach a field the save button reads back out.
      expect(find.byKey(const Key('mqtt-host')), findsNothing);
      expect(find.byKey(const Key('mqtt-save')), findsNothing);
    });

    testWidgets(
      'units still change with no bridge — they are a phone setting',
      (tester) async {
        _tall(tester);
        final prefs = InMemoryBridgePrefs(lastBridgeId: 'b');
        AppEnv.instance = fakeEnv(prefs: prefs);
        addTearDown(() => AppEnv.instance = null);

        await tester.pumpWidget(_route(SettingsSection.display));
        await tester.pumpAndSettle();

        expect(_row(tester, 'settings-units').reason, isEmpty);
        await tester.tap(find.text('°C'));
        await tester.pumpAndSettle();
        expect(prefs.displayUnits, 'C');
        // And nothing claims a save that never left the phone.
        expect(find.textContaining('nothing was saved'), findsNothing);
      },
    );
  });

  group('§I.0 — the network mode was the worst default-as-fact', () {
    testWidgets('an un-read mode renders "—", never "Joined a network"', (
      tester,
    ) async {
      // `NetMode _netMode = NetMode.sta` in the route, rendered as
      // "Joined a network" at the top of the page a user opens precisely
      // because they cannot reach the bridge. It was fixed on the Device page
      // and missed here.
      _tall(tester);
      AppEnv.instance = fakeEnv(prefs: InMemoryBridgePrefs(lastBridgeId: 'b'));
      addTearDown(() => AppEnv.instance = null);

      await tester.pumpWidget(_route(SettingsSection.network));
      await tester.pumpAndSettle();

      expect(_row(tester, 'network-current').value, isNull);
      expect(find.text('Joined yours'), findsNothing);
      expect(find.text('Hosting its own'), findsNothing);
      expect(find.textContaining('The app does not guess'), findsOneWidget);
    });

    testWidgets('the view has no way to spell an unknown mode as a mode', (
      tester,
    ) async {
      // Structural, not incidental: `mode` is `NetMode?` and `NetMode` has no
      // `unknown` member, so absence has exactly one spelling.
      _tall(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: SmokeTheme.dark,
          home: Scaffold(
            body: NetworkSettingsView(onSwitchMode: (_, _, _) async {}),
          ),
        ),
      );
      expect(_row(tester, 'network-current').value, isNull);
      expect(find.text('—'), findsWidgets);
    });
  });

  group('§I.0 — absent is absent everywhere else too', () {
    testWidgets('the device pages render dashes until the bridge reports', (
      tester,
    ) async {
      _tall(tester);
      AppEnv.instance = fakeEnv(prefs: InMemoryBridgePrefs(lastBridgeId: 'b'));
      addTearDown(() => AppEnv.instance = null);

      await tester.pumpWidget(_route(SettingsSection.identity));
      await tester.pumpAndSettle();

      expect(_row(tester, 'identity-device-id').value, isNull);
      expect(_row(tester, 'identity-firmware').value, isNull);
      // "Not paired" for a bridge that never answered is the same lie in a
      // different hat.
      expect(_row(tester, 'identity-paired').value, isNull);
    });

    testWidgets('the display page invents neither a timeout nor an LED state', (
      tester,
    ) async {
      _tall(tester);
      AppEnv.instance = fakeEnv(prefs: InMemoryBridgePrefs(lastBridgeId: 'b'));
      addTearDown(() => AppEnv.instance = null);

      await tester.pumpWidget(_route(SettingsSection.display));
      await tester.pumpAndSettle();

      // A 60-second timeout nobody read. The chips still offer "1m" as a
      // shortcut — a shortcut is not a claim — but the row's own value is the
      // em dash.
      expect(_row(tester, 'settings-display-timeout').value, isNull);
    });

    testWidgets('the LED switch is inert while its own state is unknown', (
      tester,
    ) async {
      _tall(tester);
      AppEnv.instance = fakeEnv(prefs: InMemoryBridgePrefs(lastBridgeId: 'b'));
      addTearDown(() => AppEnv.instance = null);

      await tester.pumpWidget(_route(SettingsSection.led));
      await tester.pumpAndSettle();

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
            'a switch that cannot know its own state must not offer to change '
            'it',
      );
    });

    testWidgets('the data page invents no retention limit', (tester) async {
      _tall(tester);
      AppEnv.instance = fakeEnv(prefs: InMemoryBridgePrefs(lastBridgeId: 'b'));
      addTearDown(() => AppEnv.instance = null);

      await tester.pumpWidget(_route(SettingsSection.data));
      await tester.pumpAndSettle();

      expect(_row(tester, 'data-bridge-retention').value, isNull);
      // The old device page rendered "64 — the oldest are deleted first" from
      // a constructor default.
      expect(find.textContaining('64 —'), findsNothing);
    });

    testWidgets('the diagnostics page shows no zeros it was never given', (
      tester,
    ) async {
      _tall(tester);
      AppEnv.instance = fakeEnv(prefs: InMemoryBridgePrefs(lastBridgeId: 'b'));
      addTearDown(() => AppEnv.instance = null);

      await tester.pumpWidget(_route(SettingsSection.advanced));
      await tester.pumpAndSettle();

      expect(_row(tester, 'diag-uptime').value, isNull);
      expect(_row(tester, 'diag-storage').value, isNull);
      expect(_row(tester, 'diag-probes-reported').value, isNull);
      expect(find.text('0%'), findsNothing);
      expect(find.text('0'), findsNothing);
    });
  });

  // The half that was missing until `deviceConfig()` landed. These run against
  // the real `MockTransport`, whose `configure()` honours its own writes — so
  // a passing verification means the write was actually recorded, not that a
  // stub agreed with itself.
  group('write → read back → report, against a device that answers', () {
    final smk = File(
      '${repoRoot()}/protocol/fixtures/brisket-18h.smk',
    ).readAsBytesSync();
    MockTransport bridge() =>
        MockTransport.fromSmkBytes(Uint8List.fromList(smk));

    test('a device that takes the write reports verified', () async {
      final t = bridge();
      const cfg = BridgeConfig(displayTimeoutS: 300);
      await t.configure(cfg);
      final back = await t.deviceConfig();
      expect(back.displayTimeoutS, 300);
      expect(deviceWriteVerdict(back, cfg), isTrue);
    });

    test('units and the saver now round-trip, so neither is a guess', () async {
      // Both were `WriteOutcome.unverified` before there was a read for them.
      final t = bridge();
      const cfg = BridgeConfig(
        displayUnits: 'C',
        batterySaver: BatterySaverMode.on,
      );
      await t.configure(cfg);
      final back = await t.deviceConfig();
      expect(back.displayUnits, 'C');
      expect(back.batterySaver, BatterySaverMode.on);
      expect(deviceWriteVerdict(back, cfg), isTrue);
    });

    test(
      'a device that answers and changes nothing does NOT read as saved',
      () async {
        // `ignoreWrites` is the 200-that-did-nothing — the exact failure the
        // whole write-then-verify pattern exists to catch, and the one the old
        // settings tree reported as success.
        final t = bridge()..ignoreWrites = true;
        const cfg = BridgeConfig(displayTimeoutS: 300, ledEnabled: false);
        await t.configure(cfg);

        // It accepted the call and logged it. A return-value check would stop
        // here and call it saved.
        expect(t.configureLog.single, cfg);

        final back = await t.deviceConfig();
        expect(back.displayTimeoutS, 60, reason: 'it kept its own');
        expect(back.ledEnabled, isTrue);
        expect(deviceWriteVerdict(back, cfg), isFalse);
        expect(
          writeOutcomeMessage(WriteOutcome.changedByDevice, 'the light'),
          contains('what it actually has'),
        );
      },
    );

    test(
      'a lane that cannot read the config back is unverified, not failed',
      () {
        // `BleTransport.deviceConfig()` answers DeviceConfig.unknown rather than
        // throwing, so this is the shape every Bluetooth write lands in.
        const cfg = BridgeConfig(displayUnits: 'C');
        expect(deviceWriteVerdict(DeviceConfig.unknown, cfg), isNull);
        final msg = writeOutcomeMessage(WriteOutcome.unverified, 'the units');
        expect(msg, isNot(contains('Saved')));
        expect(msg, contains('can’t confirm'));
      },
    );

    test('absent is not disagreement — and the type now says so', () {
      // This used to work around `honoured()` returning a plain bool, which
      // collapsed "the lane cannot read" into "the bridge refused" — the app
      // accusing the device of rejecting a change it was never asked about.
      // `honoured()` is tri-state now, so the distinction lives in the type
      // rather than in a helper that has to remember to correct for it.
      const cfg = BridgeConfig(displayUnits: 'C');
      expect(
        DeviceConfig.unknown.honoured(cfg),
        isNull,
        reason: 'it said nothing — that is neither agreement nor refusal',
      );
      expect(deviceWriteVerdict(DeviceConfig.unknown, cfg), isNull);
    });

    test('a device that answered, and agreed, is a real yes', () {
      const cfg = BridgeConfig(displayUnits: 'C');
      expect(const DeviceConfig(displayUnits: 'C').honoured(cfg), isTrue);
    });

    test('a device that answered with something else is a real no', () {
      const cfg = BridgeConfig(displayUnits: 'C');
      expect(const DeviceConfig(displayUnits: 'F').honoured(cfg), isFalse);
    });

    test('a write with nothing comparable in it has no verdict to give', () {
      // A probes-only write must not be graded against the device config it
      // never touched.
      expect(
        const DeviceConfig(displayUnits: 'F').honoured(const BridgeConfig()),
        isNull,
      );
    });

    test('the three Bluetooth-only-absent fields are graded too', () {
      const sent = BridgeConfig(displayTimeoutS: 300, ledEnabled: false);
      expect(
        const DeviceConfig(
          displayTimeoutS: 300,
          ledEnabled: false,
        ).honoured(sent),
        isTrue,
      );
      expect(
        const DeviceConfig(
          displayTimeoutS: 60,
          ledEnabled: false,
        ).honoured(sent),
        isFalse,
      );
      expect(const DeviceConfig(ledEnabled: false).honoured(sent), isNull);
    });

    test('the verdict never says saved where honoured() says otherwise', () {
      const sent = BridgeConfig(
        displayUnits: 'C',
        batterySaver: BatterySaverMode.off,
      );
      const running = DeviceConfig(
        displayUnits: 'F',
        batterySaver: BatterySaverMode.off,
      );
      expect(running.honoured(sent), isFalse);
      expect(deviceWriteVerdict(running, sent), isFalse);
    });

    test('settings the write said nothing about are never a mismatch', () async {
      final t = bridge();
      const cfg = BridgeConfig(ledEnabled: false);
      await t.configure(cfg);
      final back = await t.deviceConfig();
      // It still reports units, a timeout, a saver mode and a retention limit.
      expect(back.isEmpty, isFalse);
      expect(deviceWriteVerdict(back, cfg), isTrue);
    });

    test('a probe-only write does not pretend to check the device config', () {
      expect(
        touchesDeviceConfig(
          const BridgeConfig(probes: [Probe(n: 1, name: 'Pit')]),
        ),
        isFalse,
      );
      expect(touchesDeviceConfig(const BridgeConfig(maxSessions: 32)), isTrue);
      expect(touchesDeviceConfig(const BridgeConfig()), isFalse);
    });

    test('the bridge keeping its own probe names is still caught', () async {
      // The other read-back, unchanged: `live()` echoes probe configuration.
      final t = bridge()..ignoreWrites = true;
      const sent = [Probe(n: 1, name: 'Firebox', role: ProbeRole.pit)];
      await t.configure(const BridgeConfig(probes: sent));
      final live = await t.live();
      expect(probeWriteWasHonoured(sent, live.probes), isFalse);
    });
  });

  group('§G.3 — the probe read-back comparison', () {
    test('an exact echo matches', () {
      const sent = [Probe(n: 1, name: 'Pit', role: ProbeRole.pit)];
      expect(probeWriteWasHonoured(sent, sent), isTrue);
    });

    test('a device that kept its own name does NOT match', () {
      const sent = [Probe(n: 1, name: 'Firebox', role: ProbeRole.pit)];
      const echoed = [Probe(n: 1, name: 'Pit', role: ProbeRole.pit)];
      expect(
        probeWriteWasHonoured(sent, echoed),
        isFalse,
        reason:
            'this is the whole point — a 200 that changed nothing must not '
            'read as saved',
      );
    });

    test('a device that clamped a target does NOT match', () {
      const sent = [Probe(n: 2, role: ProbeRole.food, targetF10: 6000)];
      const echoed = [Probe(n: 2, role: ProbeRole.food, targetF10: 5720)];
      expect(probeWriteWasHonoured(sent, echoed), isFalse);
    });

    test('a device that changed the role does NOT match', () {
      const sent = [Probe(n: 2, role: ProbeRole.food)];
      const echoed = [Probe(n: 2, role: ProbeRole.unused)];
      expect(probeWriteWasHonoured(sent, echoed), isFalse);
    });

    test('a probe missing from the echo does NOT match', () {
      const sent = [Probe(n: 3, name: 'Flat', role: ProbeRole.food)];
      expect(probeWriteWasHonoured(sent, const []), isFalse);
    });

    test('extra state the device manages itself is not a mismatch', () {
      const sent = [Probe(n: 1, name: 'Pit', role: ProbeRole.pit)];
      const echoed = [
        Probe(n: 1, name: 'Pit', role: ProbeRole.pit, alarmMinF10: 2250),
        Probe(n: 2, role: ProbeRole.food),
      ];
      expect(probeWriteWasHonoured(sent, echoed), isTrue);
    });
  });

  group('§G.3 — the Home Assistant read-back comparison', () {
    const args = (
      enabled: true,
      host: 'broker.lan',
      port: 1883,
      user: 'smoke',
      prefix: 'smokebridge',
      haDiscovery: true,
    );

    bool check(MqttConfig echoed) => mqttWriteWasHonoured(
      echoed,
      enabled: args.enabled,
      host: args.host,
      port: args.port,
      user: args.user,
      prefix: args.prefix,
      haDiscovery: args.haDiscovery,
    );

    test('an exact echo matches', () {
      expect(
        check(
          const MqttConfig(
            enabled: true,
            host: 'broker.lan',
            port: 1883,
            user: 'smoke',
            prefix: 'smokebridge',
            haDiscovery: true,
          ),
        ),
        isTrue,
      );
    });

    test('a broker the device did not take does NOT match', () {
      expect(
        check(
          const MqttConfig(
            enabled: true,
            host: 'other.lan',
            port: 1883,
            user: 'smoke',
            prefix: 'smokebridge',
            haDiscovery: true,
          ),
        ),
        isFalse,
      );
    });

    test('a device that quietly stayed off does NOT match', () {
      expect(
        check(
          const MqttConfig(
            host: 'broker.lan',
            port: 1883,
            user: 'smoke',
            prefix: 'smokebridge',
            haDiscovery: true,
          ),
        ),
        isFalse,
      );
    });

    test('the write-only password is never treated as a mismatch', () {
      // The device never returns it, so there is nothing to compare — and
      // treating its absence as a mismatch would report every successful save
      // as a failure.
      expect(
        check(
          const MqttConfig(
            enabled: true,
            host: 'broker.lan',
            port: 1883,
            user: 'smoke',
            prefix: 'smokebridge',
            haDiscovery: true,
            connected: false,
          ),
        ),
        isTrue,
      );
    });
  });
}
