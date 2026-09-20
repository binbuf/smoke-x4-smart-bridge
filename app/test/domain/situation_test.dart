/// Reconciliation (design 16 §16.3).
///
/// **The bench failure this exists to end**, reproduced as the first test: a
/// bridge was reflashed, came up hosting its own access point, and the app —
/// which knew its Bluetooth bond, its device id and its last address — sat on
/// "Offline · retry 6" indefinitely. It told the user nothing and did nothing.
///
/// Every recovery path in the product is decided here, in pure Dart, which is
/// the only reason they are testable at all. If a situation cannot be provoked
/// in this file, it cannot be relied on in a yard at 3 a.m.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/situation/situation.dart';

const int _now = 1770000000000;

/// A phone that has been set up and is talking to its bridge.
SituationFacts healthy({
  String? reachedDeviceId = 'SmokeBridge-8274',
  String? reachedAddress = 'http://192.168.1.50',
  String? reachedNetMode = 'sta',
  bool? pairedToBase = true,
  bool? clockValid = true,
  bool? fullHistory = true,
  String? rememberedBaseUrl = 'http://192.168.1.50',
  bool hasRunningCook = false,
}) => SituationFacts(
  rememberedBridgeId: 'SmokeBridge-8274',
  rememberedBaseUrl: rememberedBaseUrl,
  rememberedBleDeviceId: 'AA:BB:CC:DD:82:76',
  lastSeenUnixMs: _now - 30000,
  hasRunningCook: hasRunningCook,
  bluetoothOn: true,
  reachedDeviceId: reachedDeviceId,
  reachedAddress: reachedAddress,
  reachedNetMode: reachedNetMode,
  pairedToBase: pairedToBase,
  deviceClockValid: clockValid,
  supportsFullHistory: fullHistory,
  nowUnixMs: _now,
);

extension on SituationFacts {
  SituationFacts copyWithCook(String cookBridgeId) => SituationFacts(
    rememberedBridgeId: rememberedBridgeId,
    rememberedBaseUrl: rememberedBaseUrl,
    rememberedBleDeviceId: rememberedBleDeviceId,
    lastSeenUnixMs: lastSeenUnixMs,
    hasRunningCook: hasRunningCook,
    runningCookBridgeId: cookBridgeId,
    bluetoothOn: bluetoothOn,
    reachedDeviceId: reachedDeviceId,
    reachedAddress: reachedAddress,
    reachedNetMode: reachedNetMode,
    pairedToBase: pairedToBase,
    deviceClockValid: deviceClockValid,
    supportsFullHistory: supportsFullHistory,
    nowUnixMs: nowUnixMs,
  );
}

void main() {
  group('the bench failure, reproduced', () {
    test('a reflashed bridge hosting its own AP is NAMED and self-healing', () {
      // Exactly what happened: the bridge came up in AP mode. The phone still
      // remembered it and was still bonded. The old app said "Offline · retry 6"
      // forever.
      final s = reconcile(
        const SituationFacts(
          rememberedBridgeId: 'SmokeBridge-8274',
          rememberedBaseUrl: 'http://192.168.1.50',
          rememberedBleDeviceId: 'AA:BB:CC:DD:82:76',
          lastSeenUnixMs: _now - 600000,
          bluetoothOn: true,
          visibleApSsid: 'SmokeBridge-8274',
          nowUnixMs: _now,
        ),
      );

      expect(s.kind, SituationKind.bridgeHostingOwnNetwork);
      expect(
        s.automatic,
        isTrue,
        reason: 'the app can join it — asking would be making its problem the '
            'user’s decision',
      );
      expect(s.headline, 'Your bridge is hosting its own network');
      expect(
        s.detail,
        contains('could not reach your Wi-Fi'),
        reason: 'name the CAUSE, not the mechanism',
      );
      // The copy names the thing the user can actually see in their Wi-Fi list.
      expect(s.detail, contains('SmokeBridge-8274'));
    });

    test('and it says nothing about mDNS, GATT or retry counters', () {
      final s = reconcile(
        const SituationFacts(
          rememberedBridgeId: 'b',
          bluetoothOn: true,
          visibleApSsid: 'SmokeBridge-8274',
          nowUnixMs: _now,
        ),
      );
      final text = '${s.headline} ${s.detail} ${s.actionLabel}'.toLowerCase();
      for (final jargon in ['mdns', 'gatt', 'rssi', 'retry', 'socket', 'http']) {
        expect(text, isNot(contains(jargon)), reason: 'jargon: $jargon');
      }
    });
  });

  group('priority — the OS is diagnosed before the bridge', () {
    test('bluetooth off beats everything', () {
      // Telling someone their bridge is unreachable when the real answer is
      // "Bluetooth is off" sends them to the yard for nothing.
      final s = reconcile(
        const SituationFacts(bluetoothOn: false, nowUnixMs: _now),
      );
      expect(s.kind, SituationKind.bluetoothOff);
      expect(s.actionLabel, isNotEmpty);
    });

    test('a missing permission beats a missing bridge', () {
      final s = reconcile(
        const SituationFacts(
          bluetoothOn: true,
          missingPermission: 'Notifications',
          nowUnixMs: _now,
        ),
      );
      expect(s.kind, SituationKind.permissionMissing);
      expect(s.headline, contains('Notifications'));
      expect(s.actionLabel, contains('Notifications'));
    });

    test('unknown bluetooth is NOT treated as off', () {
      // null means "not checked yet". Treating it as false would tell a user
      // their radio is off while the app is still booting.
      final s = reconcile(healthy());
      expect(s.kind, SituationKind.healthy);
    });
  });

  group('a phone that knows nothing', () {
    test('with no bond and nothing in range, it needs setting up', () {
      final s = reconcile(
        const SituationFacts(bluetoothOn: true, nowUnixMs: _now),
      );
      expect(s.kind, SituationKind.neverSetUp);
      expect(s.actionLabel, 'Set up a bridge');
    });

    test('but a surviving bond means the PHONE was reset — adopt it', () {
      // The device holds the identity, and it still holds it.
      final s = reconcile(
        const SituationFacts(
          bluetoothOn: true,
          bondedBridgeName: 'SmokeBridge-8274',
          nowUnixMs: _now,
        ),
      );
      expect(s.kind, SituationKind.phoneForgotBridge);
      expect(s.automatic, isTrue);
      expect(s.headline, contains('SmokeBridge-8274'));
      expect(
        s.actionLabel,
        isEmpty,
        reason: 'nothing for a human to do — the app just reconnects',
      );
    });

    test('a visible AP works as the same tell', () {
      final s = reconcile(
        const SituationFacts(
          bluetoothOn: true,
          visibleApSsid: 'SmokeBridge-8274',
          nowUnixMs: _now,
        ),
      );
      expect(s.kind, SituationKind.phoneForgotBridge);
    });
  });

  group('identity is never automatic', () {
    test('a different device id is bridgeWasReset, and needs a human', () {
      final s = reconcile(healthy(reachedDeviceId: 'SmokeBridge-9999'));
      expect(s.kind, SituationKind.bridgeWasReset);
      expect(
        s.automatic,
        isFalse,
        reason:
            'adopting a reset bridge silently would attach this phone’s '
            'history to a device that did not record it',
      );
      expect(s.actionLabel, isNotEmpty);
    });

    test('it names both ids, so the user can tell them apart', () {
      final s = reconcile(healthy(reachedDeviceId: 'SmokeBridge-9999'));
      expect(s.detail, contains('SmokeBridge-9999'));
      expect(s.detail, contains('SmokeBridge-8274'));
    });

    test('and reassures that saved cooks survive either way', () {
      final s = reconcile(healthy(reachedDeviceId: 'SmokeBridge-9999'));
      expect(s.detail.toLowerCase(), contains('cooks'));
    });

    test('it outranks everything else that could be wrong at the same time', () {
      // A reset bridge is also unpaired, also clockless, also on a new
      // address. Identity is the one that matters first.
      final s = reconcile(
        healthy(
          reachedDeviceId: 'SmokeBridge-9999',
          reachedNetMode: 'ap',
          pairedToBase: false,
          clockValid: false,
        ),
      );
      expect(s.kind, SituationKind.bridgeWasReset);
    });
  });

  group('reached, but not where or how we expected', () {
    test('hosting its own network is named and automatic', () {
      final s = reconcile(healthy(reachedNetMode: 'ap'));
      expect(s.kind, SituationKind.bridgeHostingOwnNetwork);
      expect(s.automatic, isTrue);
      expect(s.detail, contains('recording the whole time'));
    });

    test('a moved address is re-learned silently and reported', () {
      final s = reconcile(
        healthy(
          reachedAddress: 'http://192.168.1.77',
          rememberedBaseUrl: 'http://192.168.1.50',
        ),
      );
      expect(s.kind, SituationKind.bridgeMovedAddress);
      expect(s.automatic, isTrue);
      expect(s.detail, contains('192.168.1.77'));
      expect(
        s.actionLabel,
        isEmpty,
        reason: 'there is nothing to ask — the app already knows',
      );
    });

    test('the same address is not a move', () {
      expect(reconcile(healthy()).kind, SituationKind.healthy);
    });
  });

  group('reached and correctly identified — but is it useful?', () {
    test('not paired to a base is guided, not automatic', () {
      final s = reconcile(healthy(pairedToBase: false));
      expect(s.kind, SituationKind.bridgeNotPairedToBase);
      expect(s.automatic, isFalse);
      expect(
        s.detail,
        contains('SYNC'),
        reason: 'the user has to press something physical',
      );
      // The copy must NOT be "plug a probe" — a board-found wrong-cause bug.
      expect(s.detail.toLowerCase(), isNot(contains('plug a probe')));
    });

    test('an unset clock is fixed automatically', () {
      final s = reconcile(healthy(clockValid: false));
      expect(s.kind, SituationKind.deviceClockUnset);
      expect(s.automatic, isTrue);
      expect(
        s.detail,
        contains('still in order'),
        reason: 'the user needs to know nothing was lost',
      );
    });

    test('old firmware names the CAPABILITY, not a version number', () {
      final s = reconcile(healthy(fullHistory: false));
      expect(s.kind, SituationKind.firmwareTooOld);
      expect(s.headline, contains('2 hours'));
      expect(
        RegExp(r'\d+\.\d+\.\d+').hasMatch('${s.headline}${s.detail}'),
        isFalse,
        reason: 'a version number is not something a user can act on',
      );
    });

    test('health is checked in the order that unblocks the most', () {
      // Unpaired outranks a bad clock: a bridge with nothing to listen to has
      // a bigger problem than undated readings.
      final s = reconcile(healthy(pairedToBase: false, clockValid: false));
      expect(s.kind, SituationKind.bridgeNotPairedToBase);
    });
  });

  group('unreachable', () {
    test('carries the last-seen — a state plus information', () {
      final s = reconcile(
        SituationFacts(
          rememberedBridgeId: 'b',
          rememberedBaseUrl: 'http://x',
          lastSeenUnixMs: _now - 12 * 60 * 1000,
          bluetoothOn: true,
          nowUnixMs: _now,
        ),
      );
      expect(s.kind, SituationKind.bridgeOutOfRange);
      expect(s.detail, contains('12 minutes ago'));
      expect(s.detail, contains('still recording'));
    });

    test('scales the phrasing rather than printing a duration', () {
      SituationFacts at(int msAgo) => SituationFacts(
        rememberedBridgeId: 'b',
        lastSeenUnixMs: _now - msAgo,
        bluetoothOn: true,
        nowUnixMs: _now,
      );
      expect(reconcile(at(30000)).detail, contains('moments ago'));
      expect(reconcile(at(20 * 60000)).detail, contains('20 minutes ago'));
      expect(reconcile(at(5 * 3600000)).detail, contains('5 hours ago'));
      expect(reconcile(at(3 * 86400000)).detail, contains('3 days ago'));
    });

    test('with no last-seen it still says the bridge is recording', () {
      final s = reconcile(
        const SituationFacts(rememberedBridgeId: 'b', bluetoothOn: true),
      );
      expect(s.detail, contains('still recording'));
    });

    test('does NOT raise a banner — the chip already says offline', () {
      final s = reconcile(
        const SituationFacts(rememberedBridgeId: 'b', bluetoothOn: true),
      );
      expect(
        s.showsBanner,
        isFalse,
        reason:
            'a second strip saying what the transport chip already says is '
            'noise on the one screen that must stay readable',
      );
    });
  });

  group('every situation is well formed', () {
    test('non-healthy situations always have a headline', () {
      final all = <Situation>[
        reconcile(const SituationFacts(bluetoothOn: false)),
        reconcile(
          const SituationFacts(bluetoothOn: true, missingPermission: 'X'),
        ),
        reconcile(const SituationFacts(bluetoothOn: true)),
        reconcile(
          const SituationFacts(bluetoothOn: true, bondedBridgeName: 'b'),
        ),
        reconcile(healthy(reachedNetMode: 'ap')),
        reconcile(healthy(reachedAddress: 'http://other')),
        reconcile(healthy(reachedDeviceId: 'other')),
        reconcile(healthy(pairedToBase: false)),
        reconcile(healthy(clockValid: false)),
        reconcile(healthy(fullHistory: false)),
        reconcile(const SituationFacts(rememberedBridgeId: 'b')),
      ];
      for (final s in all) {
        expect(s.headline, isNotEmpty, reason: s.kind.name);
        expect(s.detail, isNotEmpty, reason: s.kind.name);
        // Sentence case: never SHOUTING, never a bare code.
        expect(s.headline, isNot(equals(s.headline.toUpperCase())));
      }
    });

    test('a situation is either actionable or automatic, never neither', () {
      final stuck = <Situation>[
        reconcile(healthy(reachedNetMode: 'ap')),
        reconcile(healthy(pairedToBase: false)),
        reconcile(healthy(clockValid: false)),
        reconcile(healthy(reachedDeviceId: 'other')),
        reconcile(const SituationFacts(bluetoothOn: true)),
      ];
      for (final s in stuck) {
        expect(
          s.automatic || s.actionLabel.isNotEmpty,
          isTrue,
          reason:
              '${s.kind.name} leaves the user with no next step — the one '
              'outcome this app may not produce',
        );
      }
    });

    test('resolved() flips to past tense and retires the action', () {
      final s = reconcile(healthy(reachedNetMode: 'ap'))
          .resolved('Reconnected on your bridge’s own network');
      expect(s.resolvedAutomatically, isTrue);
      expect(s.headline, startsWith('Reconnected'));
      expect(s.actionLabel, isEmpty);
    });

    test('healthy renders nothing at all', () {
      final s = reconcile(healthy());
      expect(s.isHealthy, isTrue);
      expect(s.showsBanner, isFalse);
      expect(s.headline, isEmpty);
    });
  });

  group('staleCook is reachable — it was not', () {
    // Found by the /device agent: the original guard was
    // `hasRunningCook && rememberedId != null && reachedId != rememberedId`,
    // which is a STRICT SUBSET of bridgeWasReset's. bridgeWasReset is checked
    // first, so staleCook could not fire for any input in the whole space.
    // A dead branch in a recovery matrix is worse than a missing one: it reads
    // as covered.
    test('a cook recorded on another bridge, after adopting this one', () {
      final s = reconcile(
        SituationFacts(
          // The user adopted the new bridge, so `remembered` moved on...
          rememberedBridgeId: 'SmokeBridge-9999',
          rememberedBaseUrl: 'http://192.168.1.50',
          lastSeenUnixMs: _now,
          hasRunningCook: true,
          // ...and the cook on screen did not follow it.
          runningCookBridgeId: 'SmokeBridge-8274',
          bluetoothOn: true,
          reachedDeviceId: 'SmokeBridge-9999',
          reachedAddress: 'http://192.168.1.50',
          reachedNetMode: 'sta',
          pairedToBase: true,
          deviceClockValid: true,
          supportsFullHistory: true,
          nowUnixMs: _now,
        ),
      );
      expect(s.kind, SituationKind.staleCook);
      expect(s.actionLabel, 'End the cook');
      expect(
        s.detail,
        contains('safe in your history'),
        reason: 'ending a stale cook must not read as losing it',
      );
    });

    test('a cook on the bridge we are actually talking to is not stale', () {
      final s = reconcile(
        healthy(hasRunningCook: true).copyWithCook('SmokeBridge-8274'),
      );
      expect(s.kind, SituationKind.healthy);
    });

    test('a running cook with no recorded bridge is not stale', () {
      // Absent ≠ mismatched. A cook from before the id was tracked must not
      // be accused of belonging to another device.
      final s = reconcile(healthy(hasRunningCook: true));
      expect(s.kind, SituationKind.healthy);
    });

    test('identity still outranks it — a reset bridge is the bigger fact', () {
      final s = reconcile(
        SituationFacts(
          rememberedBridgeId: 'SmokeBridge-8274',
          hasRunningCook: true,
          runningCookBridgeId: 'SmokeBridge-8274',
          bluetoothOn: true,
          reachedDeviceId: 'SmokeBridge-9999',
          nowUnixMs: _now,
        ),
      );
      expect(s.kind, SituationKind.bridgeWasReset);
    });
  });

  group('resolved() keeps what /device needs', () {
    test('it clears the present-tense detail by default', () {
      final s = reconcile(healthy(reachedNetMode: 'ap'))
          .resolved('Joined your bridge’s own network');
      expect(s.detail, isEmpty, reason: '"joining it now" is now a lie');
      expect(s.actionLabel, isEmpty);
    });

    test('but carries past-tense detail when the caller has one', () {
      // §16.6 wants the full explanation on /device. Dropping it forced
      // callers to rebuild the whole value by hand.
      final s = reconcile(healthy(reachedNetMode: 'ap')).resolved(
        'Joined your bridge’s own network',
        detail: 'It could not reach your Wi-Fi, so the app joined it instead.',
      );
      expect(s.detail, contains('joined it instead'));
      expect(s.resolvedAutomatically, isTrue);
      expect(s.kind, SituationKind.bridgeHostingOwnNetwork);
    });
  });

  group('the enum order IS the priority', () {
    test('kinds are declared most-blocking first', () {
      // The reconciler returns the first that applies, so a reordering of the
      // enum silently reorders the product's triage.
      const expected = [
        SituationKind.bluetoothOff,
        SituationKind.permissionMissing,
        SituationKind.neverSetUp,
        SituationKind.phoneForgotBridge,
        SituationKind.bridgeHostingOwnNetwork,
        SituationKind.bridgeMovedAddress,
        SituationKind.bridgeWasReset,
        SituationKind.bridgeNotPairedToBase,
        SituationKind.deviceClockUnset,
        SituationKind.firmwareTooOld,
        SituationKind.bridgeOutOfRange,
        SituationKind.staleCook,
        SituationKind.healthy,
      ];
      expect(SituationKind.values, expected);
    });
  });
}
