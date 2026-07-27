/// A8.2 — widget tests driving all five screens against the real state
/// machine and the A6.1 fake peripheral.
///
/// Two properties this file is here to hold:
///
///  * **The pair screen renders correct copy in both OEM cases.** Android
///    owns the passkey dialog; some OEMs show it instantly, some after a
///    beat, some only in the notification shade. The screen must read
///    correctly either way, because "type the code" with no dialog on
///    screen is where onboarding gets abandoned.
///  * **No platform channel is touched.** `flutter test` runs with no
///    device; the moment a screen reaches for one, this suite is the
///    thing that says so.
/// NOTE on pumping, because both traps here cost real time to find:
///
///  1. `testWidgets` runs its body inside a fake-async zone, and
///     microtasks only drain while the tester pumps. `await
///     wizard.select(...)` therefore deadlocks — the future it is waiting
///     on can never complete. Work is kicked off with [drive], which
///     starts it and then pumps frames until it lands.
///  2. These screens show INDETERMINATE progress indicators, which animate
///     forever, so `pumpAndSettle()` waits out its whole budget instead of
///     settling. Explicit `pump()` frames throughout.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/theme.dart';
import 'package:smoke_bridge/data/dto/records.g.dart';
import 'package:smoke_bridge/data/transport/ble_transport.dart';
import 'package:smoke_bridge/features/onboarding/onboarding.dart';

import '../data/fake_peripheral.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

WifiScanResult _ap(String ssid) =>
    WifiScanResult(rssi: -55, auth: 3, channel: 6, ssidRaw: _b(ssid));

class _Harness {
  _Harness({FakePeripheralConfig? config}) {
    fake = FakePeripheral(config: config);
    transport = BleTransport(fake);
    wizard = OnboardingWizard(
      transport: transport,
      client: fake,
      verify: (_) async => 'http://192.168.1.42',
      joinAp: (_, _) async => true,
      nowMs: () => 1774051200000,
      // Nothing fires on its own: the tests drive the flow, not a clock.
      delay: (_) => Completer<void>().future,
    );
  }

  late final FakePeripheral fake;
  late final BleTransport transport;
  late final OnboardingWizard wizard;

  Widget app() => MaterialApp(
    theme: SmokeTheme.dark,
    home: OnboardingScreen(wizard: wizard),
  );

  Future<void> dispose() async {
    await wizard.dispose();
    await transport.close();
  }
}

/// Starts wizard work and pumps until it settles. See the note at the top
/// of this file: awaiting it directly would deadlock the fake-async zone.
Future<void> drive(
  WidgetTester tester,
  Future<void> work, {
  int frames = 16,
}) async {
  unawaited(work);
  for (var i = 0; i < frames; i++) {
    await tester.pump();
  }
}

void main() {
  // The platform-channel tripwire: any screen that reaches for a plugin
  // records here, and the assertion at the end of each test fails.
  final channelCalls = <String>[];
  setUp(() {
    channelCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('smokebridge/network_binder', (message) async {
          channelCalls.add('network_binder');
          return null;
        });
  });

  testWidgets('1. find — the list is decorated from the advertising blob', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.app());
    await drive(tester, h.wizard.startScan());

    expect(find.byKey(const Key('onboarding-find-list')), findsOneWidget);
    expect(find.text('SmokeBridge-A4F2'), findsOneWidget);
    // "pit 243.1 °F · 4 h 12 m", before any connection exists.
    expect(find.textContaining('pit 243.1 °F'), findsOneWidget);
    expect(find.textContaining('4 h 12 m'), findsOneWidget);
    expect(channelCalls, isEmpty);
    await drive(tester, h.dispose(), frames: 4);
  });

  testWidgets('1. find — an empty scan offers a way forward', (tester) async {
    final h = _Harness(
      config: const FakePeripheralConfig(advertiseNothing: true),
    );
    await tester.pumpWidget(h.app());
    await drive(tester, h.wizard.startScan());
    expect(find.byKey(const Key('onboarding-find-empty')), findsOneWidget);
    expect(find.text('Scan again'), findsOneWidget);
    await drive(tester, h.dispose(), frames: 4);
  });

  testWidgets('2. pair — copy works whether or not the OS dialog appears', (
    tester,
  ) async {
    final h = _Harness();
    // Rendered directly, in both sub-states: against the real fake the
    // bond completes inside a single microtask drain, so the pair screen
    // is transient. That transition is the state machine's test
    // (onboarding_wizard_test); what matters HERE is the copy, and both
    // OEM cases have to be legible.
    for (final bonding in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: SmokeTheme.dark,
          home: Scaffold(
            body: PairStep(
              state: WizardPair(
                const BridgeDiscovery(deviceId: 'x', name: 'SmokeBridge-A4F2'),
                bonding: bonding,
              ),
              wizard: h.wizard,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('onboarding-pair')), findsOneWidget);
      expect(find.text('Look at the bridge'), findsOneWidget);
      // The instruction points at the BRIDGE, and the app never claims to
      // be collecting the digits itself...
      expect(
        find.textContaining('type the code from the screen, not from here'),
        findsOneWidget,
      );
      // ...which is only true if there is no six-digit field here. The OS
      // owns that dialog (A6 epic flag).
      expect(find.byType(TextField), findsNothing);
    }
    expect(channelCalls, isEmpty);
    await drive(tester, h.dispose(), frames: 4);
  });

  testWidgets('2. pair — the bonding status names the notification shade', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.app());
    // Render the bonding sub-state directly: it is the frame a hostile
    // OEM leaves the user sitting on.
    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeTheme.dark,
        home: Scaffold(
          body: PairStep(
            state: WizardPair(
              const BridgeDiscovery(deviceId: 'x', name: 'SmokeBridge-A4F2'),
              bonding: true,
            ),
            wizard: h.wizard,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('check your notifications'), findsOneWidget);
    expect(channelCalls, isEmpty);
    await drive(tester, h.dispose(), frames: 4);
  });

  testWidgets('3+4a. mode — both options state their real trade-off', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.app());
    await drive(tester, h.wizard.startScan());
    await drive(
      tester,
      h.wizard.select((h.wizard.state as WizardFind).found.single),
    );

    expect(find.byKey(const Key('onboarding-mode')), findsOneWidget);
    expect(find.byKey(const Key('mode-joined')), findsOneWidget);
    expect(find.byKey(const Key('mode-hosted')), findsOneWidget);
    // The honest battery/range copy §8.6 asks for, not marketing.
    expect(find.textContaining('Uses more battery'), findsOneWidget);
    expect(find.textContaining('Best range'), findsOneWidget);
    await drive(tester, h.dispose(), frames: 4);
  });

  testWidgets('4b. network — scan results, manual entry, and the gate', (
    tester,
  ) async {
    final h = _Harness(
      config: FakePeripheralConfig(
        scanResults: [_ap('Backyard'), _ap('Neighbour')],
      ),
    );
    await tester.pumpWidget(h.app());
    await drive(tester, h.wizard.startScan());
    await drive(
      tester,
      h.wizard.select((h.wizard.state as WizardFind).found.single),
    );
    await drive(tester, h.wizard.chooseMode(BridgeMode.joined));

    expect(find.byKey(const Key('ap-Backyard')), findsOneWidget);
    expect(find.byKey(const Key('ap-Neighbour')), findsOneWidget);

    // Connect stays disabled until a network is actually chosen.
    final button = find.byKey(const Key('onboarding-network-submit'));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.tap(find.byKey(const Key('ap-Backyard')));
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

    // Manual SSID entry works too — hidden networks, and the empty-scan
    // case, both land here.
    await tester.enterText(
      find.byKey(const Key('onboarding-ssid-field')),
      'Hidden-Net',
    );
    await tester.pump();
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(channelCalls, isEmpty);
    await drive(tester, h.dispose(), frames: 4);
  });

  testWidgets('5. handoff — each phase says what is happening', (tester) async {
    for (final (phase, copy) in [
      (HandoffPhase.applying, 'Sending the settings'),
      (HandoffPhase.connecting, 'joining the network'),
      (HandoffPhase.joiningAp, "Joining the bridge's own network"),
      (HandoffPhase.verifying, 'Checking that we can reach it'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: SmokeTheme.dark,
          home: Scaffold(body: HandoffStep(state: WizardHandoff(phase))),
        ),
      );
      await tester.pump();
      expect(find.textContaining(copy), findsOneWidget, reason: '$phase');
    }
  });

  testWidgets('recovery — both escape hatches are offered, and BLE is up', (
    tester,
  ) async {
    final h = _Harness();
    for (final reason in RecoveryReason.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: SmokeTheme.dark,
          home: Scaffold(
            body: RecoverStep(state: WizardRecover(reason), wizard: h.wizard),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('onboarding-recover-retry')), findsOneWidget);
      expect(find.byKey(const Key('onboarding-recover-host')), findsOneWidget);
      // The line that makes the recovery believable: the bridge is still
      // reachable, so neither offer requires walking to it.
      expect(find.text('Still connected over Bluetooth.'), findsOneWidget);
    }
    expect(
      find.textContaining('That password did not work'),
      findsNothing,
      reason: 'the last reason rendered was configRefused',
    );
    await drive(tester, h.dispose(), frames: 4);
  });

  testWidgets('the wrong-password recovery names the failure', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeTheme.dark,
        home: Scaffold(
          body: RecoverStep(
            state: const WizardRecover(RecoveryReason.wifiFailed),
            wizard: h.wizard,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('That password did not work'), findsOneWidget);
    expect(find.textContaining('no need to touch the bridge'), findsOneWidget);
    await drive(tester, h.dispose(), frames: 4);
  });

  testWidgets('done — the mode is stated, not assumed', (tester) async {
    for (final (mode, copy) in [
      (BridgeMode.hosted, 'hosting its own network'),
      (BridgeMode.joined, 'on your Wi-Fi'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: SmokeTheme.dark,
          home: Scaffold(
            body: DoneStep(state: WizardDone(mode: mode)),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining(copy), findsOneWidget);
    }
  });

  testWidgets('failure edges are screens with a next step', (tester) async {
    final h = _Harness(config: const FakePeripheralConfig(rejectBond: true));
    await tester.pumpWidget(h.app());
    await drive(tester, h.wizard.startScan());
    await drive(
      tester,
      h.wizard.select((h.wizard.state as WizardFind).found.single),
    );

    expect(find.byKey(const Key('onboarding-bond-rejected')), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Start over'), findsOneWidget);

    // restart() is async (it cancels the link watcher), so the tap needs
    // frames to land — same fake-async rule as everything else here.
    await tester.tap(find.byKey(const Key('onboarding-problem-secondary')));
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(find.byKey(const Key('onboarding-find-empty')), findsOneWidget);
    expect(channelCalls, isEmpty);
    await drive(tester, h.dispose(), frames: 4);
  });
}
