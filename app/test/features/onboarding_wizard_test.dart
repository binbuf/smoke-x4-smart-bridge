/// A8.1 — every path through the onboarding state machine, against the
/// A6.1 fake peripheral, on a fake clock.
///
/// The M3 exit gate is "a phone provisions the bridge **and recovers from
/// a deliberately wrong Wi-Fi password without touching the hardware**".
/// That second clause is the one that is easy to ship broken and hard to
/// notice, so it is walked here in three shapes before anyone stands at a
/// smoker: wrong password, unreachable-after-up, and a refused config.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dto/records.g.dart';
import 'package:smoke_bridge/data/transport/ble_gatt.dart';
import 'package:smoke_bridge/data/transport/ble_transport.dart';
import 'package:smoke_bridge/features/onboarding/wizard.dart';

import '../data/fake_peripheral.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

WifiScanResult _ap(String ssid) =>
    WifiScanResult(rssi: -55, auth: 3, channel: 6, ssidRaw: _b(ssid));

NetStatus _net(NetState state, {NetMode mode = NetMode.sta}) => NetStatus(
  mode: mode.wire,
  state: state.wire,
  ip: state == NetState.up ? [192, 168, 1, 42] : [0, 0, 0, 0],
  ssidRaw: _b('Backyard'),
  hostRaw: _b('smokebridge'),
);

/// Records every delay asked for; NOTHING fires until [fire] is called.
///
/// The same discipline the A7 race tests use, for the same reason: every
/// budget in this machine bounds a `Future.any` against real async work,
/// and a budget that completes on its own races that work. Letting even
/// the 12 s scan budget resolve "instantly" silently truncated a two-AP
/// scan to one — a deterministic test turned into a coin flip. So the
/// tests that WANT a budget to expire say so, mid-flight, explicitly.
class _Clock {
  final asked = <Duration>[];
  final _gates = <Completer<void>>[];

  Future<void> call(Duration d) {
    asked.add(d);
    final c = Completer<void>();
    _gates.add(c);
    return c.future;
  }

  void fire() {
    for (final c in _gates) {
      if (!c.isCompleted) {
        c.complete();
      }
    }
    _gates.clear();
  }
}

class _Harness {
  _Harness({FakePeripheralConfig? config}) {
    fake = FakePeripheral(config: config);
    transport = BleTransport(fake);
    wizard = OnboardingWizard(
      transport: transport,
      client: fake,
      verify: (ip) async {
        verifiedWith = ip;
        return verifyResult;
      },
      joinAp: (ssid, psk) async {
        joinedAp = (ssid, psk);
        return joinApSucceeds;
      },
      nowMs: () => 1774051200000,
      delay: clock.call,
    );
    seen = [];
    wizard.states.listen(seen.add);
  }

  late final FakePeripheral fake;
  late final BleTransport transport;
  late final OnboardingWizard wizard;
  late final List<WizardState> seen;
  final clock = _Clock();
  String? verifyResult = 'http://192.168.1.42';
  String? verifiedWith;
  bool joinApSucceeds = true;
  (String, String)? joinedAp;

  Future<void> toModeChoice() async {
    await wizard.startScan();
    final found = (wizard.state as WizardFind).found;
    await wizard.select(found.single);
  }

  Future<void> dispose() async {
    await wizard.dispose();
    await transport.close();
  }
}

void main() {
  group('step 1 — find', () {
    test('the scan yields a blob-decorated entry', () async {
      final h = _Harness();
      await h.wizard.startScan();
      final s = h.wizard.state as WizardFind;
      expect(s.scanning, isFalse);
      expect(s.found, hasLength(1));
      expect(s.found.single.name, 'SmokeBridge-A4F2');
      expect(s.found.single.pitTempF10, 2431);
      await h.dispose();
    });

    test('a scan that finds nothing is a state, not a spinner', () async {
      final h = _Harness();
      // A peripheral that never advertises: the wizard must still settle.
      await h.wizard.startScan(timeout: Duration.zero);
      expect(h.wizard.state, isA<WizardFind>());
      expect((h.wizard.state as WizardFind).scanning, isFalse);
      await h.dispose();
    });
  });

  group('a scan that never ends (BOARD-FOUND)', () {
    // The first real run: the Wi-Fi picker flickered and went blank in a
    // loop. A real BLE scan stream does not stop when the user walks away
    // from the find step, so a still-draining scan kept republishing
    // WizardFind on top of whatever step they had moved to. The fake used
    // to end its scan on its own, which is exactly why the suite was
    // blind to it.
    test('a late advertisement cannot drag the user back to find', () async {
      final h = _Harness(
        config: FakePeripheralConfig(
          continuousScan: true,
          scanResults: [_ap('Backyard')],
        ),
      );
      unawaited(h.wizard.startScan());
      await Future<void>.delayed(Duration.zero);
      expect(h.wizard.state, isA<WizardFind>());

      await h.wizard.select((h.wizard.state as WizardFind).found.single);
      expect(h.wizard.state, isA<WizardChooseMode>());

      // The scanner keeps going, as a real one does. It must be ignored.
      h.fake.scanTick?.call();
      await Future<void>.delayed(Duration.zero);
      expect(h.wizard.state, isA<WizardChooseMode>());

      // ...and all the way through the network step, which is where the
      // flicker was actually visible.
      await h.wizard.chooseMode(BridgeMode.joined);
      expect(h.wizard.state, isA<WizardPickNetwork>());
      h.fake.scanTick?.call();
      await Future<void>.delayed(Duration.zero);
      expect(h.wizard.state, isA<WizardPickNetwork>());
      expect(
        (h.wizard.state as WizardPickNetwork).networks.single.ssid,
        'Backyard',
      );
      await h.dispose();
    });

    test('selecting a bridge stops the scan', () async {
      final h = _Harness(
        config: const FakePeripheralConfig(continuousScan: true),
      );
      unawaited(h.wizard.startScan());
      await Future<void>.delayed(Duration.zero);
      await h.wizard.select((h.wizard.state as WizardFind).found.single);
      // Stopped, so the radio is not scanning while we connect.
      expect(h.fake.scanTick, isNull);
      await h.dispose();
    });

    test('restart supersedes an in-flight scan', () async {
      final h = _Harness(
        config: const FakePeripheralConfig(continuousScan: true),
      );
      unawaited(h.wizard.startScan());
      await Future<void>.delayed(Duration.zero);
      final first = h.fake.scanTick;
      await h.wizard.restart();
      expect(h.wizard.state, isA<WizardFind>());
      // The OLD scan's emissions must not resurrect a stale list.
      first?.call();
      await Future<void>.delayed(Duration.zero);
      expect((h.wizard.state as WizardFind).scanning, isFalse);
      await h.dispose();
    });
  });

  group('step 2 — pair', () {
    test('the happy path bonds and moves to the mode choice', () async {
      final h = _Harness();
      await h.toModeChoice();
      expect(h.wizard.state, isA<WizardChooseMode>());
      expect(h.fake.bondState, BleBondState.bonded);
      // Step 3 happened silently in between, and wrote the clock.
      expect(h.seen.whereType<WizardSettingTime>(), hasLength(1));
      final write = h.fake.writes.firstWhere(
        (w) => w.$1 == BridgeChar.deviceControl,
      );
      final ctrl = DeviceControl.unpack(write.$2);
      expect(ctrl.opEnum, ControlOp.setTime);
      expect(CtrlSetTime.decode(ctrl.bodyRaw).unixMs, 1774051200000);
      await h.dispose();
    });

    test('a rejected bond is a state with a next step', () async {
      final h = _Harness(config: const FakePeripheralConfig(rejectBond: true));
      await h.wizard.startScan();
      await h.wizard.select((h.wizard.state as WizardFind).found.single);
      expect(h.wizard.state, isA<WizardBondRejected>());
      // And the next step exists: start over from the scan.
      await h.wizard.restart();
      expect(h.wizard.state, isA<WizardFind>());
      await h.dispose();
    });

    test('a factory-reset bridge asks to re-bond, not to retry', () async {
      // "Retry" would loop forever against a bridge that threw our key
      // away. The state is distinct because the ACTION is distinct.
      final h = _Harness(config: const FakePeripheralConfig(staleBond: true));
      await h.wizard.startScan();
      await h.wizard.select((h.wizard.state as WizardFind).found.single);
      expect(h.wizard.state, isA<WizardRebondNeeded>());
      await h.dispose();
    });
  });

  group('step 4 — mode and network', () {
    test('hosted skips the picker and captures the AP PSK', () async {
      final h = _Harness();
      await h.toModeChoice();
      await h.wizard.chooseMode(BridgeMode.hosted);
      expect(h.wizard.apPsk, 'Gk7mR2xQpT');
      expect(h.wizard.state, isA<WizardDone>());
      expect((h.wizard.state as WizardDone).mode, BridgeMode.hosted);
      // The phone joined the AP with the credentials it was just handed —
      // no Settings round-trip (A14.1's joinAp).
      expect(h.joinedAp?.$2, 'Gk7mR2xQpT');
      await h.dispose();
    });

    test('joined shows the device-side scan results', () async {
      final h = _Harness(
        config: FakePeripheralConfig(
          scanResults: [_ap('Backyard'), _ap('Neighbour')],
        ),
      );
      await h.toModeChoice();
      await h.wizard.chooseMode(BridgeMode.joined);
      final s = h.wizard.state as WizardPickNetwork;
      expect(s.scanning, isFalse);
      expect(s.networks.map((n) => n.ssid), ['Backyard', 'Neighbour']);
      expect(s.isEmpty, isFalse);
      await h.dispose();
    });

    test('duplicate SSIDs collapse to the strongest', () async {
      // A mesh reports the same SSID once per node. Three "Home_WiFi"
      // rows differing only in signal is a worse list, not a richer one —
      // seen on the real phone (18 raw results, 3x Home_WiFi).
      final h = _Harness(
        config: FakePeripheralConfig(
          scanResults: [
            WifiScanResult(rssi: -65, auth: 3, channel: 1, ssidRaw: _b('Home')),
            WifiScanResult(rssi: -33, auth: 3, channel: 1, ssidRaw: _b('Home')),
            WifiScanResult(
              rssi: -49,
              auth: 3,
              channel: 6,
              ssidRaw: _b('Guest'),
            ),
            // Hidden network: unselectable, so it must not take a row.
            WifiScanResult(rssi: -70, auth: 0, channel: 1, ssidRaw: _b('')),
          ],
        ),
      );
      await h.toModeChoice();
      await h.wizard.chooseMode(BridgeMode.joined);
      final s = h.wizard.state as WizardPickNetwork;
      expect(s.networks.map((n) => n.ssid), ['Home', 'Guest']);
      expect(s.networks.first.rssi, -33, reason: 'the strongest wins');
      await h.dispose();
    });

    test('an empty scan is a state the user can act on', () async {
      final h = _Harness(config: const FakePeripheralConfig(emptyScan: true));
      await h.toModeChoice();
      // Nothing ever answers, so the scan budget is what ends this — the
      // wizard must not wait forever for a list that is empty.
      final pending = h.wizard.chooseMode(BridgeMode.joined);
      await Future<void>.delayed(Duration.zero);
      h.clock.fire();
      await pending;
      final s = h.wizard.state as WizardPickNetwork;
      expect(s.scanning, isFalse);
      expect(s.isEmpty, isTrue); // manual SSID entry is the way forward
      await h.dispose();
    });
  });

  group('step 5 — handoff and the escape hatch', () {
    test(
      'the happy STA path verifies over HTTP before declaring victory',
      () async {
        final h = _Harness(
          config: FakePeripheralConfig(scanResults: [_ap('Backyard')]),
        );
        await h.toModeChoice();
        await h.wizard.chooseMode(BridgeMode.joined);
        h.wizard.pickNetwork('Backyard');
        await h.wizard.submitCredentials('hunter2boo');

        expect(h.wizard.state, isA<WizardDone>());
        expect((h.wizard.state as WizardDone).baseUrl, 'http://192.168.1.42');
        // The phases the screen renders, in order.
        expect(h.seen.whereType<WizardHandoff>().map((s) => s.phase).toList(), [
          HandoffPhase.applying,
          HandoffPhase.connecting,
          HandoffPhase.verifying,
        ]);
        await h.dispose();
      },
    );

    test(
      'WRONG PASSWORD lands back at the network step with the reason',
      () async {
        // The M3 exit gate's second clause, walked entirely off the board.
        final h = _Harness(
          config: FakePeripheralConfig(
            scanResults: [_ap('Backyard')],
            netStatusScript: [_net(NetState.connecting), _net(NetState.failed)],
          ),
        );
        await h.toModeChoice();
        await h.wizard.chooseMode(BridgeMode.joined);
        h.wizard.pickNetwork('Backyard');
        await h.wizard.submitCredentials('WRONG');

        expect(h.wizard.state, isA<WizardRecover>());
        expect(
          (h.wizard.state as WizardRecover).reason,
          RecoveryReason.wifiFailed,
        );
        // The BLE link is still up — which is the whole point.
        expect(h.fake.connectionState, BleConnectionState.connected);

        // ...correct it, and finish. Not a spinner, and not a walk to the
        // smoker to power-cycle anything.
        h.fake.config = h.fake.config.copyWith(netStatusScript: const []);
        await h.wizard.retryCredentials();
        final picker = h.wizard.state as WizardPickNetwork;
        expect(picker.error, contains('Incorrect password'));
        h.wizard.pickNetwork('Backyard');
        await h.wizard.submitCredentials('hunter2boo');
        expect(h.wizard.state, isA<WizardDone>());
        await h.dispose();
      },
    );

    test('UNREACHABLE after net_status up offers revert-to-hosting', () async {
      final h = _Harness(
        config: FakePeripheralConfig(scanResults: [_ap('Backyard')]),
      );
      h.verifyResult = null; // STA came up; nothing answers over HTTP
      await h.toModeChoice();
      await h.wizard.chooseMode(BridgeMode.joined);
      h.wizard.pickNetwork('Backyard');
      await h.wizard.submitCredentials('hunter2boo');

      expect(h.wizard.state, isA<WizardRecover>());
      expect(
        (h.wizard.state as WizardRecover).reason,
        RecoveryReason.httpUnreachable,
      );

      // One wifi_config{mode: AP} write over the still-connected link.
      h.verifyResult = 'http://192.168.4.1';
      await h.wizard.revertToHosting();
      expect(h.wizard.state, isA<WizardDone>());
      expect((h.wizard.state as WizardDone).mode, BridgeMode.hosted);
      expect(h.wizard.apPsk, 'Gk7mR2xQpT');
      await h.dispose();
    });

    test('a refused config is its own recovery reason', () async {
      final h = _Harness(
        config: const FakePeripheralConfig(
          wifiConfigOutcome: ResultStatus.invalid,
        ),
      );
      await h.toModeChoice();
      await h.wizard.chooseMode(BridgeMode.hosted);
      expect(h.wizard.state, isA<WizardRecover>());
      expect(
        (h.wizard.state as WizardRecover).reason,
        RecoveryReason.configRefused,
      );
      await h.dispose();
    });

    test('a failed AP join is recoverable, not a dead end', () async {
      final h = _Harness()..joinApSucceeds = false;
      await h.toModeChoice();
      await h.wizard.chooseMode(BridgeMode.hosted);
      expect(h.wizard.state, isA<WizardRecover>());
      await h.dispose();
    });

    test('an already-joined bridge is read, not assumed unreachable', () async {
      // BOARD-FOUND: re-provisioning a bridge that was ALREADY on the
      // target network is a no-op on the device, so no net_status
      // transition is emitted. The wizard used to burn its whole 20 s
      // budget and then report "joined but cannot be reached" about a
      // bridge that was serving HTTP perfectly well. Notifications report
      // CHANGES; asking is how you learn the current state.
      final h = _Harness(
        config: FakePeripheralConfig(
          scanResults: [_ap('Backyard')],
          silentAfterConfig: true, // accepted, then nothing to report
        ),
      );
      // The readable net_status says: already up, on this address.
      h.fake.state.net = _net(NetState.up);
      await h.toModeChoice();
      await h.wizard.chooseMode(BridgeMode.joined);
      h.wizard.pickNetwork('Backyard');
      final pending = h.wizard.submitCredentials('hunter2boo');
      await Future<void>.delayed(Duration.zero);
      // Expire the wait-for-a-transition budget. The verify budget is
      // registered afterwards and is deliberately left running, so the
      // real verification is what resolves the race.
      h.clock.fire();
      await pending;
      expect(h.wizard.state, isA<WizardDone>());
      expect(h.verifiedWith, '192.168.1.42');
      await h.dispose();
    });

    test('the 20 s budget bounds the handoff', () async {
      // A bridge that accepts the config and then says nothing at all:
      // the wizard must reach the recovery state on the budget rather
      // than wait forever.
      final h = _Harness(
        config: const FakePeripheralConfig(silentAfterConfig: true),
      );
      // ...and the readable net_status agrees it is not up, so there is
      // genuinely nothing to go on but the budget.
      h.fake.state.net = _net(NetState.connecting, mode: NetMode.ap);
      await h.toModeChoice();
      final pending = h.wizard.chooseMode(BridgeMode.hosted);
      await Future<void>.delayed(Duration.zero);
      h.clock.fire();
      await pending;
      expect(h.clock.asked, contains(kHandoffBudget));
      expect(h.wizard.state, isA<WizardRecover>());
      await h.dispose();
    });
  });

  group('the link dying, at any step', () {
    test('a dropped link surfaces reconnect-or-restart', () async {
      final h = _Harness();
      await h.toModeChoice();
      h.fake.dropLink();
      await Future<void>.delayed(Duration.zero);
      expect(h.wizard.state, isA<WizardLinkLost>());
      await h.dispose();
    });

    test('a link lost mid-write does not strand the wizard', () async {
      final h = _Harness();
      await h.toModeChoice();
      h.fake.config = h.fake.config.copyWith(dropOnWrite: true);
      await h.wizard.chooseMode(BridgeMode.hosted);
      expect(h.wizard.state, isA<WizardLinkLost>());
      await h.dispose();
    });
  });

  group('abandon and restart', () {
    test('restart works from every step', () async {
      final h = _Harness(
        config: FakePeripheralConfig(scanResults: [_ap('Backyard')]),
      );
      // find → restart
      await h.wizard.startScan();
      await h.wizard.restart();
      expect(h.wizard.state, isA<WizardFind>());

      // pair/mode → restart
      await h.toModeChoice();
      await h.wizard.restart();
      expect(h.wizard.state, isA<WizardFind>());

      // network picker → restart
      await h.toModeChoice();
      await h.wizard.chooseMode(BridgeMode.joined);
      await h.wizard.restart();
      expect(h.wizard.state, isA<WizardFind>());
      expect(h.wizard.apPsk, isNull);

      // ...and the flow still completes afterwards.
      await h.toModeChoice();
      await h.wizard.chooseMode(BridgeMode.hosted);
      expect(h.wizard.state, isA<WizardDone>());
      await h.dispose();
    });
  });
}
