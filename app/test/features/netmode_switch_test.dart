/// The mode switch and its rollback (newapp §E.3; §I.2 asks for exactly this
/// as an integration test — "simulate the link dropping").
///
/// The case under test is the one that used to need a USB cable: a switch whose
/// credentials are wrong takes the link with it, so the phone cannot retract
/// the instruction. Everything here is about making that recoverable **without
/// anyone walking to the smoker**.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/features/settings/netmode_switch.dart';

class _Refusal implements BridgeRefusal {
  const _Refusal(this.message);
  @override
  final String message;
}

void main() {
  group('the happy path commits', () {
    test('found on the new network, confirmed, done', () async {
      var applied = 0;
      var commits = 0;
      final sw = NetModeSwitch(
        apply: (mode, ssid, psk) async {
          applied++;
          return '';
        },
        probe: () async => true,
        commit: () async => commits++,
        attemptDelay: Duration.zero,
      );
      final seen = <NetSwitchPhase>[];
      sw.states.listen((s) => seen.add(s.phase));

      final end = await sw.run(mode: NetworkMode.sta, ssid: 'Backyard');

      expect(end.phase, NetSwitchPhase.committed);
      expect(applied, 1);
      expect(commits, 1, reason: 'the device must be told to keep it');
      await Future<void>.delayed(Duration.zero);
      expect(seen.first, NetSwitchPhase.requesting);
      expect(seen, contains(NetSwitchPhase.reconnecting));
    });

    test('it keeps trying while the phone changes networks', () async {
      var attempts = 0;
      final sw = NetModeSwitch(
        apply: (m, s, p) async => '',
        // The first four fail: the phone is still leaving the old network,
        // Android is asking about "no internet", DHCP has not finished.
        probe: () async => ++attempts >= 5,
        commit: () async {},
        attemptDelay: Duration.zero,
      );
      final end = await sw.run(mode: NetworkMode.ap);
      expect(end.phase, NetSwitchPhase.committed);
      expect(end.attempt, 5);
    });
  });

  group('§E.3 — the link dropping is the case this exists for', () {
    test('never found: the rollback is reported as the plan, not an error',
        () async {
      var commits = 0;
      final sw = NetModeSwitch(
        apply: (m, s, p) async => '',
        // The typo'd password: the bridge left and never arrived.
        probe: () async => false,
        commit: () async => commits++,
        attemptDelay: Duration.zero,
        maxAttempts: 4,
        revertAfterS: 120,
      );
      final end = await sw.run(mode: NetworkMode.sta, ssid: 'Nieghbour');

      expect(end.phase, NetSwitchPhase.revertPending);
      expect(commits, 0);
      expect(
        end.body,
        contains('go back to the network that was working'),
        reason:
            'the user must be told the device fixes itself — this is not a '
            '"contact support" state',
      );
      expect(end.isTerminal, isTrue);
    });

    test('the countdown shown is what is actually left', () async {
      final sw = NetModeSwitch(
        apply: (m, s, p) async => '',
        probe: () async => false,
        commit: () async {},
        attemptDelay: const Duration(seconds: 3),
        maxAttempts: 4,
        revertAfterS: 120,
      );
      final end = await sw.run(mode: NetworkMode.ap);
      // Four attempts at 3 s each is 12 s of the 120 s window.
      expect(end.revertInS, 108);
    });

    test('the countdown never goes negative', () async {
      final sw = NetModeSwitch(
        apply: (m, s, p) async => '',
        probe: () async => false,
        commit: () async {},
        // A window shorter than the hunt: by the time the app gives up, the
        // device has already put back what worked.
        attemptDelay: const Duration(seconds: 1),
        maxAttempts: 3,
        revertAfterS: 1,
      );
      final end = await sw.run(mode: NetworkMode.ap);
      expect(end.revertInS, 0);
    });

    test('a lost reply is treated as accepted, not as a failure', () async {
      // The device answers before it switches, but the answer can still be
      // lost as the interface comes down. Reporting a failure there would be
      // wrong: the switch probably happened.
      var probed = 0;
      final sw = NetModeSwitch(
        apply: (m, s, p) async => throw StateError('socket closed'),
        probe: () async => ++probed >= 2,
        commit: () async {},
        attemptDelay: Duration.zero,
      );
      final end = await sw.run(mode: NetworkMode.ap);
      expect(
        end.phase,
        NetSwitchPhase.committed,
        reason: 'we go looking rather than declaring the switch failed',
      );
    });

    test('a stated refusal IS a failure, and says what the device said',
        () async {
      var probed = 0;
      final sw = NetModeSwitch(
        apply: (m, s, p) async => throw const _Refusal('mode must be ap|sta.'),
        probe: () async {
          probed++;
          return true;
        },
        commit: () async {},
        attemptDelay: Duration.zero,
      );
      final end = await sw.run(mode: NetworkMode.sta);
      expect(end.phase, NetSwitchPhase.refused);
      expect(end.body, contains('mode must be ap|sta'));
      expect(end.body, contains('Nothing changed'));
      expect(probed, 0, reason: 'nothing switched, so there is nothing to find');
    });
  });

  group('reached but not confirmed is not success', () {
    test('a commit that throws keeps hunting rather than saying Done',
        () async {
      var commitCalls = 0;
      final sw = NetModeSwitch(
        apply: (m, s, p) async => '',
        probe: () async => true,
        commit: () async {
          commitCalls++;
          throw StateError('409');
        },
        attemptDelay: Duration.zero,
        maxAttempts: 3,
      );
      final end = await sw.run(mode: NetworkMode.ap);
      expect(
        end.phase,
        NetSwitchPhase.revertPending,
        reason:
            'an uncommitted switch is one the device is still going to undo; '
            'saying "Done" would be a lie with a two-minute fuse on it',
      );
      expect(commitCalls, 3);
    });
  });

  group('cancelling', () {
    test('stops the hunt without stranding the device', () async {
      late final NetModeSwitch sw;
      sw = NetModeSwitch(
        apply: (m, s, p) async => '',
        probe: () async {
          sw.cancel();
          return false;
        },
        commit: () async {},
        attemptDelay: Duration.zero,
        maxAttempts: 20,
      );
      final end = await sw.run(mode: NetworkMode.ap);
      expect(end.phase, NetSwitchPhase.revertPending);
      expect(
        end.attempt,
        lessThan(20),
        reason: 'it stopped early — the device still rolls back on its own',
      );
    });
  });

  group('every state names what is happening', () {
    test('no state is a bare spinner', () {
      for (final phase in NetSwitchPhase.values) {
        final s = NetSwitchState(phase: phase, revertInS: 90);
        expect(s.title, isNotEmpty, reason: phase.name);
        expect(s.body, isNotEmpty, reason: phase.name);
      }
    });

    test('the reconnecting state promises the Bluetooth escape hatch', () {
      const s = NetSwitchState(phase: NetSwitchPhase.reconnecting);
      expect(s.body, contains('Bluetooth'));
    });
  });
}

