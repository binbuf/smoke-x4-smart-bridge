/// N1.19 — the reconciliation priority ladder.
library;

import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('a radio that is off is diagnosed before anything behind it', () {
    final s = reconcile(
      const SituationFacts(
        bluetoothOn: false,
        missingPermission: 'Bluetooth',
        nowUnixMs: 1000,
      ),
    );
    expect(s.kind, SituationKind.bluetoothOff);
    expect(s.actionLabel, 'Turn on Bluetooth');
  });

  test('null is unknown, not false', () {
    final s = reconcile(const SituationFacts(nowUnixMs: 1000));
    expect(s.kind, isNot(SituationKind.bluetoothOff));
  });

  test('a missing permission comes next', () {
    final s = reconcile(
      const SituationFacts(
        bluetoothOn: true,
        missingPermission: 'Location',
        nowUnixMs: 1000,
      ),
    );
    expect(s.kind, SituationKind.permissionMissing);
    expect(s.actionLabel, 'Allow Location');
  });

  test('a phone that remembers nothing has never been set up', () {
    final s = reconcile(const SituationFacts(nowUnixMs: 1000));
    expect(s.kind, SituationKind.neverSetUp);
  });

  test(
    'a surviving bond means the phone forgot, and adoption is automatic',
    () {
      final s = reconcile(
        const SituationFacts(bondedBridgeName: 'SmokeBridge-A4F2'),
      );
      expect(s.kind, SituationKind.phoneForgotBridge);
      expect(s.automatic, isTrue);
    },
  );

  test('identity mismatch is never automatic', () {
    final s = reconcile(
      const SituationFacts(
        rememberedBridgeId: 'old',
        reachedDeviceId: 'new',
        reachedNetMode: 'sta',
        nowUnixMs: 1000,
      ),
    );
    expect(s.kind, SituationKind.bridgeWasReset);
    expect(s.automatic, isFalse);
  });

  test('reached on its own AP names the network', () {
    final s = reconcile(
      const SituationFacts(
        rememberedBridgeId: 'id',
        reachedDeviceId: 'id',
        reachedNetMode: 'ap',
        reachedApSsid: 'SmokeBridge-8274',
        nowUnixMs: 1000,
      ),
    );
    expect(s.kind, SituationKind.bridgeHostingOwnNetwork);
    expect(s.headline, contains('SmokeBridge-8274'));
  });

  test('a moved address is noted, then usefulness checks follow', () {
    final moved = reconcile(
      const SituationFacts(
        rememberedBridgeId: 'id',
        rememberedBaseUrl: 'http://192.168.1.42',
        reachedDeviceId: 'id',
        reachedNetMode: 'sta',
        reachedAddress: 'http://192.168.1.99',
        nowUnixMs: 1000,
      ),
    );
    expect(moved.kind, SituationKind.bridgeMovedAddress);

    final unpaired = reconcile(
      const SituationFacts(
        rememberedBridgeId: 'id',
        rememberedBaseUrl: 'http://192.168.1.42',
        reachedDeviceId: 'id',
        reachedNetMode: 'sta',
        reachedAddress: 'http://192.168.1.42',
        pairedToBase: false,
        nowUnixMs: 1000,
      ),
    );
    expect(unpaired.kind, SituationKind.bridgeNotPairedToBase);

    final noClock = reconcile(
      const SituationFacts(
        rememberedBridgeId: 'id',
        rememberedBaseUrl: 'http://192.168.1.42',
        reachedDeviceId: 'id',
        reachedNetMode: 'sta',
        reachedAddress: 'http://192.168.1.42',
        pairedToBase: true,
        deviceClockValid: false,
        nowUnixMs: 1000,
      ),
    );
    expect(noClock.kind, SituationKind.deviceClockUnset);

    final oldFirmware = reconcile(
      const SituationFacts(
        rememberedBridgeId: 'id',
        rememberedBaseUrl: 'http://192.168.1.42',
        reachedDeviceId: 'id',
        reachedNetMode: 'sta',
        reachedAddress: 'http://192.168.1.42',
        pairedToBase: true,
        deviceClockValid: true,
        supportsFullHistory: false,
        nowUnixMs: 1000,
      ),
    );
    expect(oldFirmware.kind, SituationKind.firmwareTooOld);
  });

  test('a cook recorded on another bridge is a stale cook', () {
    final s = reconcile(
      const SituationFacts(
        rememberedBridgeId: 'id',
        reachedDeviceId: 'id',
        reachedNetMode: 'sta',
        reachedAddress: 'http://192.168.1.42',
        pairedToBase: true,
        deviceClockValid: true,
        supportsFullHistory: true,
        hasRunningCook: true,
        runningCookBridgeId: 'other',
        nowUnixMs: 1000,
      ),
    );
    expect(s.kind, SituationKind.staleCook);
  });

  test('everything remembered and answering is healthy', () {
    final s = reconcile(
      const SituationFacts(
        rememberedBridgeId: 'id',
        reachedDeviceId: 'id',
        reachedNetMode: 'sta',
        reachedAddress: 'http://192.168.1.42',
        pairedToBase: true,
        deviceClockValid: true,
        supportsFullHistory: true,
        nowUnixMs: 1000,
      ),
    );
    expect(s.kind, SituationKind.healthy);
    expect(s.showsBanner, isFalse);
  });

  test('nothing answering carries the last-seen, and raises no banner', () {
    final s = reconcile(
      const SituationFacts(
        rememberedBridgeId: 'id',
        lastSeenUnixMs: 1000,
        nowUnixMs: 1000 + 12 * 60 * 1000,
      ),
    );
    expect(s.kind, SituationKind.bridgeOutOfRange);
    expect(s.detail, contains('12 minutes ago'));
    expect(s.showsBanner, isFalse);
  });
}
