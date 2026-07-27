/// A23.5 — the hardware-free lab driver test (design 13 §13.2, §13.5.1).
///
/// Proves the fakes in `lib/lab/fake_bridge.dart` can drive the real
/// [SetupMachine] end to end with **no radio, no board, and no real timers**:
/// the happy script reaches [SetupDone] through the expected milestone
/// sequence, and a failure script (Wi-Fi wrong password) reaches its stated
/// failure state and then *recovers* to the finish. A couple of shorter
/// scripts pin the other early failure edges the lab offers.
///
/// Timing is entirely on [LabClock.manual]: scripted events pace on microtasks
/// (timer-free, deterministic) and budgets fire only when a test calls
/// [LabClock.fireBudgets] — which is exactly how the base-timeout case turns a
/// silent window into `timeout_no_beacon`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/features/setup/copy/base_sync_copy.dart';
import 'package:smoke_bridge/features/setup/setup_machine.dart';
import 'package:smoke_bridge/lab/fake_bridge.dart';
import 'package:smoke_bridge/lab/setup_lab.dart';
import 'package:smoke_bridge/ui/setup/setup_rail.dart';

import '../support/load_fonts.dart';

/// Drain the microtask queue so broadcast `states` deliveries and the fakes'
/// microtask-paced events settle. Timer-free by construction.
Future<void> _pump([int cycles = 12]) async {
  for (var i = 0; i < cycles; i++) {
    await Future<void>.microtask(() {});
  }
}

void main() {
  // Load fonts once, outside any FakeAsync test body — real file I/O inside a
  // `testWidgets` zone would deadlock (design 14 §14.5; the components-test
  // pattern).
  setUpAll(loadAppFonts);

  test('happy path drives all three hops to SetupDone', () async {
    final fb = FakeBridge(scriptById('happy'), clock: LabClock.manual());
    addTearDown(fb.dispose);
    final m = fb.machine;
    final seen = <SetupState>[];
    final sub = m.states.listen(seen.add);
    addTearDown(sub.cancel);

    // Hop 0 → hop 1: preflight is clear (granted, adapter on), so start lands
    // on a settled scan list.
    await m.start();
    await _pump();
    expect(m.state, isA<SetupScanning>());
    final scan = m.state as SetupScanning;
    expect(scan.scanning, isFalse);
    expect(scan.found, isNotEmpty);

    // Hop 1: select → bond succeeds.
    await m.select(scan.found.first);
    await _pump();
    expect(m.state, isA<SetupBonded>());

    // Hop 2: intro → listen → a real reading confirms.
    await m.startHop2();
    await _pump();
    expect(m.state, isA<SetupBaseIntro>());

    await m.startBaseListen();
    await _pump();
    expect(m.state, isA<SetupBaseConfirmed>());
    final confirmed = m.state as SetupBaseConfirmed;
    expect(confirmed.numProbes, 2);
    expect(confirmed.temps.first, 1650);

    // Hop 3: the picker is pre-warmed, so it is already populated.
    await m.continueFromConfirmed();
    await _pump();
    expect(m.state, isA<SetupNetworkPick>());
    final pick = m.state as SetupNetworkPick;
    expect(pick.networks, isNotEmpty);

    await m.pickNetwork(pick.networks.first);
    await _pump();
    expect(m.state, isA<SetupNetworkPassword>());

    await m.submitPassword('hunter2');
    await _pump();
    expect(m.state, isA<SetupNameAndUnits>());

    // Finish.
    await m.submitNameAndUnits('My Smoker');
    await _pump();
    expect(m.state, isA<SetupDone>());
    final done = m.state as SetupDone;
    expect(done.summary.bridgeName, 'My Smoker');
    expect(done.summary.blePaired, isTrue);
    expect(done.summary.baseNumProbes, 2);
    expect(done.summary.wifiSsid, 'Homestead');

    // The milestone sequence, in order (other states may sit between).
    final types = seen.map((s) => s.runtimeType).toList();
    expect(
      types,
      containsAllInOrder(<Type>[
        SetupScanning,
        SetupPairing,
        SetupBonded,
        SetupBaseIntro,
        SetupBaseListening,
        SetupBaseHeard,
        SetupBaseConfirmed,
        SetupNetworkPick,
        SetupNetworkPassword,
        SetupApplying,
        SetupNameAndUnits,
        SetupDone,
      ]),
    );
  });

  test('wifi wrong password reaches SetupWifiFailed then recovers', () async {
    final fb = FakeBridge(
      scriptById('wifi-wrong-password'),
      clock: LabClock.manual(),
    );
    addTearDown(fb.dispose);
    final m = fb.machine;

    // Fast-forward through the identical hops 0–2 to the password screen.
    await m.start();
    await _pump();
    await m.select((m.state as SetupScanning).found.first);
    await _pump();
    await m.startHop2();
    await _pump();
    await m.startBaseListen();
    await _pump();
    await m.continueFromConfirmed();
    await _pump();
    await m.pickNetwork((m.state as SetupNetworkPick).networks.first);
    await _pump();
    expect(m.state, isA<SetupNetworkPassword>());

    // First attempt: the stated failure, not a generic one.
    await m.submitPassword('wrong');
    await _pump();
    expect(m.state, isA<SetupWifiFailed>());
    expect((m.state as SetupWifiFailed).reason, WifiFailure.wrongPassword);

    // Retry lands back on the password field, prefilled and explained.
    await m.retryWifi();
    await _pump();
    expect(m.state, isA<SetupNetworkPassword>());
    final retry = m.state as SetupNetworkPassword;
    expect(retry.prefill, 'wrong');
    expect(retry.error, isNotNull);

    // Corrected password now joins and the flow recovers to the finish.
    await m.submitPassword('correct');
    await _pump();
    expect(m.state, isA<SetupNameAndUnits>());
  });

  test(
    'base never heard: firing the budget yields timeout_no_beacon',
    () async {
      final fb = FakeBridge(
        scriptById('base-timeout'),
        clock: LabClock.manual(),
      );
      addTearDown(fb.dispose);
      final m = fb.machine;

      await m.start();
      await _pump();
      await m.select((m.state as SetupScanning).found.first);
      await _pump();
      await m.startHop2();
      await _pump();

      // The window opens and stays silent — a spinner with no resolution, until
      // the listen budget fires.
      final listening = m.startBaseListen();
      await _pump();
      expect(m.state, isA<SetupBaseListening>());

      fb.clock.fireBudgets();
      await listening;
      await _pump();
      expect(m.state, isA<SetupBaseFailed>());
      expect(
        (m.state as SetupBaseFailed).reason,
        BaseSyncFailure.timeoutNoBeacon,
      );
    },
  );

  test('wrong passkey reaches SetupPasskeyWrong', () async {
    final fb = FakeBridge(
      scriptById('wrong-passkey'),
      clock: LabClock.manual(),
    );
    addTearDown(fb.dispose);
    final m = fb.machine;

    await m.start();
    await _pump();
    await m.select((m.state as SetupScanning).found.first);
    await _pump();
    expect(m.state, isA<SetupPasskeyWrong>());
  });

  test('no bridges reaches the SetupNoBridges checklist', () async {
    final fb = FakeBridge(scriptById('no-bridges'), clock: LabClock.manual());
    addTearDown(fb.dispose);
    final m = fb.machine;

    await m.start();
    await _pump();
    expect(m.state, isA<SetupNoBridges>());
  });

  test('permission primer precedes the prompt, then proceeds', () async {
    final fb = FakeBridge(
      scriptById('permission-primer'),
      clock: LabClock.manual(),
    );
    addTearDown(fb.dispose);
    final m = fb.machine;

    await m.start();
    await _pump();
    expect(m.state, isA<SetupPermissionPrimer>());

    await m.continueFromPrimer();
    await _pump();
    expect(m.state, isA<SetupScanning>());
  });

  // The lab screen itself: the live machine rendered through the shipping
  // SetupScaffold/SetupRail and ui/ components — what a reviewer sees is what
  // ships. A manual clock keeps the whole screen timer-free.
  testWidgets('SetupLab mounts and renders the live scan', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeTheme.dark,
        home: SetupLab(clock: LabClock.manual()),
      ),
    );
    // Flush the microtask-paced scan to its settled list.
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(find.byType(SetupRail), findsOneWidget);
    expect(find.text('SmokeBridge-A4F2'), findsOneWidget);

    // Stepping is a tap on the rendered row — it advances the real machine.
    await tester.tap(find.text('SmokeBridge-A4F2'));
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(find.text('Paired'), findsOneWidget);
  });
}
