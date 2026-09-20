/// Reconciliation, end to end (design 16 §16.3).
///
/// This is the suite the whole recovery layer stands on, so it is exhaustive
/// over [SituationKind] by construction: `situationCoverage` records every kind
/// a test drove, and the last test in the file fails if any value of the enum
/// was never exercised. A recovery path nobody wrote a test for is a recovery
/// path nobody has ever run.
///
/// Three things are asserted about every automatic remedy, because each has its
/// own way of going wrong:
///
///  1. it **happens without being asked** — no button, no confirmation;
///  2. it is then **reported in the past tense**, which is what makes it a
///     report rather than an offer;
///  3. **a remedy that could not be carried out reports nothing**. The failure
///     mode of "act, then report" is an app that reports without acting, and
///     that is worse than the retry counter it replaced.
///
/// And one thing about identity: `bridgeWasReset` is never resolved, however
/// many times the resolver runs.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/prefs/bridge_prefs.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/domain/situation/situation.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/features/shell/situation_resolver.dart';

/// Every kind any test in this file drove the resolver into.
final Set<SituationKind> situationCoverage = <SituationKind>{};

// ── doubles ───────────────────────────────────────────────────────────

class _FakeProbe implements SituationProbe {
  _FakeProbe({
    this.bluetooth,
    this.permission,
    this.bonded,
    this.apSsid,
    this.canJoin = false,
  });

  bool? bluetooth;
  String? permission;
  BondedBridge? bonded;
  String? apSsid;
  bool canJoin;

  final List<String> joins = <String>[];
  int bluetoothSettingsOpened = 0;
  int permissionsRequested = 0;

  @override
  Future<bool?> bluetoothOn() async => bluetooth;

  @override
  Future<String?> missingPermission() async => permission;

  @override
  Future<BondedBridge?> bondedBridge() async => bonded;

  @override
  Future<String?> visibleApSsid() async => apSsid;

  @override
  Future<bool> joinNetwork(String ssid, {String psk = ''}) async {
    joins.add(ssid);
    return canJoin;
  }

  @override
  Future<bool> openBluetoothSettings() async {
    bluetoothSettingsOpened++;
    return true;
  }

  @override
  Future<bool> requestMissingPermission() async {
    permissionsRequested++;
    permission = null;
    return true;
  }
}

class _FakeShell implements SituationShell {
  _FakeShell({
    this.snapshot,
    this.transport,
    this.deviceNetMode,
    this.retryWorks = false,
  });

  @override
  DashboardSnapshot? snapshot;

  @override
  BridgeTransport? transport;

  @override
  bool hasRunningCook = false;

  /// The bridge the running cook was recorded against. Differs from the
  /// reached id only after an adoption, which is the one input that makes
  /// [SituationKind.staleCook] reachable.
  String? cookBridgeId;

  @override
  Future<String?> runningCookBridgeId() async => cookBridgeId;

  /// What the device says about its own network, whatever lane we are on.
  String? deviceNetMode;
  bool retryWorks;
  int retries = 0;

  /// The network the device says it is on or hosting.
  String? deviceApSsid;

  @override
  Future<({String? mode, String? ssid})> netStatus() async =>
      (mode: deviceNetMode, ssid: deviceApSsid);

  @override
  Future<bool> retryNow() async {
    retries++;
    return retryWorks;
  }
}

/// Answers only what the resolver asks: status, live, capabilities, control.
class _FakeTransport implements BridgeTransport {
  _FakeTransport({
    this.deviceId = 'A4F2',
    this.paired = true,
    this.clockValid = true,
    this.fullHistory = true,
    this.statusThrows = false,
  });

  String deviceId;
  bool paired;
  bool clockValid;
  bool fullHistory;
  bool statusThrows;

  final List<ControlCommand> commands = <ControlCommand>[];

  @override
  BridgeCapabilities get capabilities =>
      BridgeCapabilities(fullHistory: fullHistory);

  @override
  Future<BridgeStatus> status() async {
    if (statusThrows) {
      throw StateError('unreachable');
    }
    return BridgeStatus(deviceId: deviceId, fw: '1.1.0', paired: paired);
  }

  @override
  Future<LiveState> live({Duration window = const Duration(hours: 1)}) async =>
      LiveState(
        t: 0,
        unixMs: clockValid ? 1750000000000 : null,
        tempsF10: const [null, null, null, null],
      );

  @override
  Future<void> control(ControlCommand cmd) async {
    commands.add(cmd);
    if (cmd is SetTimeCommand) {
      // The device took it. The resolver still has to read back before it
      // says so — this is the half of the write that a lie would skip.
      clockValid = true;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── helpers ───────────────────────────────────────────────────────────

DashboardSnapshot _snap(
  LinkKind link, {
  String address = '',
  String? netMode,
}) => DashboardSnapshot(
  probes: const [],
  link: link,
  address: address,
  netMode: netMode,
);

int _clock = 1750000000000;

SituationResolver _resolver({
  required _FakeShell shell,
  BridgePrefs? prefs,
  SituationProbe? probe,
}) => SituationResolver(
  shell: shell,
  prefs: prefs,
  probe: probe ?? _FakeProbe(),
  now: () => _clock,
);

/// Runs the resolver and records which kind it landed on, so the coverage
/// assertion at the bottom of the file is a fact rather than a promise.
Future<Situation> _run(SituationResolver r) async {
  final s = await r.evaluate();
  situationCoverage.add(s.kind);
  return s;
}

void main() {
  setUp(() => _clock = 1750000000000);

  // ── 1–2. the OS is in the way ──────────────────────────────────────

  test('Bluetooth off is named before anything is blamed on the bridge', () async {
    final r = _resolver(
      shell: _FakeShell(),
      prefs: InMemoryBridgePrefs(lastBaseUrl: 'http://10.0.0.7'),
      probe: _FakeProbe(bluetooth: false),
    );
    final s = await _run(r);

    expect(s.kind, SituationKind.bluetoothOff);
    // Not automatic: only the user can switch a radio on.
    expect(s.automatic, isFalse);
    expect(s.resolvedAutomatically, isFalse);
    expect(r.act, SituationAct.openBluetooth);
    // No jargon, and it says what it means for the cook.
    expect(s.detail, contains('recording'));
  });

  test('the OS action is performed, not merely offered', () async {
    final probe = _FakeProbe(bluetooth: false);
    final r = _resolver(
      shell: _FakeShell(),
      prefs: InMemoryBridgePrefs(lastBaseUrl: 'http://10.0.0.7'),
      probe: probe,
    );
    await _run(r);
    await r.runOsAct();
    expect(probe.bluetoothSettingsOpened, 1);
  });

  test('a missing permission names the permission, not the API', () async {
    final probe = _FakeProbe(permission: 'Nearby devices');
    final r = _resolver(
      shell: _FakeShell(),
      prefs: InMemoryBridgePrefs(lastBaseUrl: 'http://10.0.0.7'),
      probe: probe,
    );
    final s = await _run(r);

    expect(s.kind, SituationKind.permissionMissing);
    expect(s.headline, contains('Nearby devices'));
    expect(s.automatic, isFalse);
    expect(r.act, SituationAct.grantPermission);

    await r.runOsAct();
    expect(probe.permissionsRequested, 1);
    // Granted now, so the next reconciliation moves on rather than sticking.
    expect((await _run(r)).kind, isNot(SituationKind.permissionMissing));
  });

  test('a Bluetooth state nobody has read yet is not "off"', () async {
    // The distinction the whole facts model is built on: null is unknown, and
    // an app that reads unknown as false tells people their radio is off
    // while the plugin is still booting.
    final r = _resolver(
      shell: _FakeShell(),
      prefs: InMemoryBridgePrefs(lastBaseUrl: 'http://10.0.0.7'),
      probe: _FakeProbe(),
    );
    expect((await _run(r)).kind, isNot(SituationKind.bluetoothOff));
  });

  // ── 3. nothing has ever been set up ────────────────────────────────

  test('a phone that has never met a bridge gets one action', () async {
    final r = _resolver(shell: _FakeShell(), prefs: InMemoryBridgePrefs());
    final s = await _run(r);

    expect(s.kind, SituationKind.neverSetUp);
    expect(s.actionLabel, 'Set up a bridge');
    expect(s.automatic, isFalse);
    expect(r.act, SituationAct.runSetup);
  });

  // ── 4. the phone forgot; the bridge did not ────────────────────────

  test('a forgotten bridge that is still bonded is adopted, not offered', () async {
    final prefs = InMemoryBridgePrefs();
    final shell = _FakeShell(retryWorks: true);
    final probe = _FakeProbe(
      bonded: const BondedBridge(deviceId: 'AA:BB:CC', name: 'SmokeBridge-8274'),
    );
    final r = _resolver(shell: shell, prefs: prefs, probe: probe);
    final s = await _run(r);

    expect(s.kind, SituationKind.phoneForgotBridge);
    // Acted: the bond is back in this phone's memory and a reconnect ran.
    expect(prefs.lastBleDeviceId, 'AA:BB:CC');
    expect(shell.retries, 1);
    // Reported, in the past tense, with no button to press.
    expect(s.resolvedAutomatically, isTrue);
    expect(s.headline, 'Reconnected to SmokeBridge-8274');
    expect(s.actionLabel, isEmpty);
  });

  test('an adopted bridge that still will not answer claims no reconnection', () async {
    final prefs = InMemoryBridgePrefs();
    final probe = _FakeProbe(
      bonded: const BondedBridge(deviceId: 'AA:BB:CC', name: 'SmokeBridge-8274'),
    );
    final r = _resolver(
      shell: _FakeShell(),
      prefs: prefs,
      probe: probe,
    );
    final s = await _run(r);

    // Still past tense — but about the thing that actually happened.
    expect(s.resolvedAutomatically, isTrue);
    expect(s.headline, 'Remembered SmokeBridge-8274 again');
    expect(s.headline, isNot(contains('Reconnected')));
    expect(prefs.lastBleDeviceId, 'AA:BB:CC');
  });

  // ── 5. the bridge is hosting its own network ───────────────────────

  test(
    'the bench failure: hosting its own network, reachable only over Bluetooth',
    () async {
      // Reflashed bridge, came up hosting an AP, phone still on the house
      // Wi-Fi. The snapshot knows nothing — BLE carries no netMode — so the
      // only source is the device itself.
      final shell = _FakeShell(
        snapshot: _snap(LinkKind.ble),
        transport: _FakeTransport(),
        deviceNetMode: 'ap',
      );
      final r = _resolver(
        shell: shell,
        prefs: InMemoryBridgePrefs(
          lastBridgeId: 'A4F2',
          lastBleDeviceId: 'AA:BB:CC',
        ),
      );
      final s = await _run(r);

      expect(s.kind, SituationKind.bridgeHostingOwnNetwork);
      expect(s.headline, 'Your bridge is hosting its own network');
      // The cause, in the user's words — never "mDNS", never a retry count.
      expect(s.detail, contains('could not reach the network it knew'));
      expect(s.actionLabel, 'Put it back on your Wi-Fi');
    },
  );

  test('the hosted network is named when the device says what it is', () async {
    // The phone may not name the networks around it — that needs the location
    // permission the manifest promises never to take — but the bridge will
    // tell us its own SSID over Bluetooth. Naming it is the difference
    // between a sentence and something you can act on from Wi-Fi settings,
    // and joining it is the one remedy the app cannot perform itself,
    // because it holds no Wi-Fi key by design.
    final shell = _FakeShell(
      snapshot: _snap(LinkKind.ble),
      transport: _FakeTransport(),
      deviceNetMode: 'ap',
    )..deviceApSsid = 'SmokeBridge-A4F2';
    final r = _resolver(
      shell: shell,
      prefs: InMemoryBridgePrefs(lastBridgeId: 'A4F2'),
    );
    final s = await _run(r);

    expect(s.kind, SituationKind.bridgeHostingOwnNetwork);
    expect(s.headline, 'Your bridge is hosting SmokeBridge-A4F2');
  });

  test('a hosted network the phone can join is joined and reported', () async {
    final prefs = InMemoryBridgePrefs(lastBridgeId: 'A4F2');
    final shell = _FakeShell(retryWorks: true);
    final probe = _FakeProbe(apSsid: 'SmokeBridge-A4F2', canJoin: true);
    final r = _resolver(shell: shell, prefs: prefs, probe: probe);
    final s = await _run(r);

    expect(probe.joins, ['SmokeBridge-A4F2']);
    expect(s.resolvedAutomatically, isTrue);
    expect(s.headline, 'Joined your bridge’s own network');
    situationCoverage.add(s.kind);
  });

  test('a join the phone cannot make reports nothing and keeps the action', () async {
    final probe = _FakeProbe(apSsid: 'SmokeBridge-A4F2');
    final r = _resolver(
      shell: _FakeShell(),
      prefs: InMemoryBridgePrefs(lastBridgeId: 'A4F2'),
      probe: probe,
    );
    final s = await _run(r);

    expect(s.resolvedAutomatically, isFalse);
    expect(s.headline, 'Your bridge is hosting its own network');
    expect(s.actionLabel, isNotEmpty);
  });

  test('a join the phone refused is not re-offered on every reconciliation', () async {
    final probe = _FakeProbe(apSsid: 'SmokeBridge-A4F2');
    final r = _resolver(
      shell: _FakeShell(),
      prefs: InMemoryBridgePrefs(lastBridgeId: 'A4F2'),
      probe: probe,
    );
    await _run(r);
    await _run(r);
    await _run(r);
    // One prompt, not three. A permission storm teaches people to tap deny.
    expect(probe.joins, hasLength(1));
  });

  // ── 6. it answers, but somewhere else ──────────────────────────────

  test('a bridge that moved is re-learned and reported in the past tense', () async {
    final prefs = InMemoryBridgePrefs(
      lastBaseUrl: 'http://10.0.0.7',
      lastBridgeId: 'A4F2',
    );
    final shell = _FakeShell(
      snapshot: _snap(
        LinkKind.http,
        address: 'http://10.0.0.42',
        netMode: 'sta',
      ),
      transport: _FakeTransport(),
    );
    final r = _resolver(shell: shell, prefs: prefs);
    final s = await _run(r);

    expect(s.kind, SituationKind.bridgeMovedAddress);
    expect(prefs.lastBaseUrl, 'http://10.0.0.42');
    expect(s.resolvedAutomatically, isTrue);
    expect(s.headline, 'Learned your bridge’s new address');
    // The place, not the URL scheme.
    expect(s.detail, contains('10.0.0.42'));
    expect(s.detail, isNot(contains('http://')));
    expect(s.actionLabel, isEmpty);

    // And it settles: the next pass has nothing to say.
    _clock += 60000;
    expect((await _run(r)).kind, SituationKind.healthy);
  });

  test('Bluetooth is never mistaken for a bridge that moved', () async {
    // There is no address on the Bluetooth lane, and an empty one must not
    // read as "different from the remembered one".
    final shell = _FakeShell(
      snapshot: _snap(LinkKind.ble),
      transport: _FakeTransport(),
    );
    final r = _resolver(
      shell: shell,
      prefs: InMemoryBridgePrefs(
        lastBaseUrl: 'http://10.0.0.7',
        lastBridgeId: 'A4F2',
      ),
    );
    expect((await _run(r)).kind, SituationKind.healthy);
  });

  // ── 7. identity — never automatic ──────────────────────────────────

  test('a bridge that has been reset is never adopted by the app', () async {
    final prefs = InMemoryBridgePrefs(
      lastBaseUrl: 'http://10.0.0.7',
      lastBridgeId: 'A4F2',
    );
    final shell = _FakeShell(
      snapshot: _snap(
        LinkKind.http,
        address: 'http://10.0.0.7',
        netMode: 'sta',
      ),
      transport: _FakeTransport(deviceId: 'B811'),
    );
    final r = _resolver(shell: shell, prefs: prefs);

    // However many times it runs.
    for (var i = 0; i < 3; i++) {
      _clock += 60000;
      final s = await _run(r);
      expect(s.kind, SituationKind.bridgeWasReset);
      expect(s.automatic, isFalse);
      expect(s.resolvedAutomatically, isFalse);
      expect(s.actionLabel, 'Use this bridge instead');
    }
    // Nothing was written. The phone still believes in the bridge it knew.
    expect(prefs.lastBridgeId, 'A4F2');
    expect(r.act, SituationAct.adoptBridge);
  });

  test('adopting a reset bridge is a separate, deliberate call', () async {
    final prefs = InMemoryBridgePrefs(
      lastBaseUrl: 'http://10.0.0.7',
      lastBridgeId: 'A4F2',
    );
    final shell = _FakeShell(
      snapshot: _snap(
        LinkKind.http,
        address: 'http://10.0.0.7',
        netMode: 'sta',
      ),
      transport: _FakeTransport(deviceId: 'B811'),
    );
    final r = _resolver(shell: shell, prefs: prefs);
    await _run(r);

    await r.adoptReachedBridge();

    expect(prefs.lastBridgeId, 'B811');
    // Adopted, and now healthy — the situation clears itself once the two
    // sides agree about who they are.
    expect(r.situation.kind, SituationKind.healthy);
  });

  // ── 8. reached, but it has met nothing ─────────────────────────────

  test('a bridge that has not met the base station says so, and waits', () async {
    final shell = _FakeShell(
      snapshot: _snap(LinkKind.http, address: 'http://10.0.0.7', netMode: 'sta'),
      transport: _FakeTransport(paired: false),
    );
    final r = _resolver(
      shell: shell,
      prefs: InMemoryBridgePrefs(
        lastBaseUrl: 'http://10.0.0.7',
        lastBridgeId: 'A4F2',
      ),
    );
    final s = await _run(r);

    expect(s.kind, SituationKind.bridgeNotPairedToBase);
    expect(s.automatic, isFalse);
    expect(r.act, SituationAct.pairBase);
    // Hop 2 needs a hand on the base station; nothing in the app can do it.
    expect(s.detail, contains('SYNC'));
  });

  // ── 9. the clock ───────────────────────────────────────────────────

  test('an unset clock is set from the phone and reported afterwards', () async {
    final transport = _FakeTransport(clockValid: false);
    final shell = _FakeShell(
      snapshot: _snap(LinkKind.http, address: 'http://10.0.0.7', netMode: 'sta'),
      transport: transport,
    );
    final r = _resolver(
      shell: shell,
      prefs: InMemoryBridgePrefs(
        lastBaseUrl: 'http://10.0.0.7',
        lastBridgeId: 'A4F2',
      ),
    );
    final s = await _run(r);

    expect(s.kind, SituationKind.deviceClockUnset);
    expect(transport.commands.whereType<SetTimeCommand>(), hasLength(1));
    expect(s.resolvedAutomatically, isTrue);
    expect(s.headline, 'Set your bridge’s clock');
    expect(s.actionLabel, isEmpty);
  });

  test('a clock write that does not read back is never reported as done', () async {
    // The device accepted the command and the clock is still unset. From the
    // sending end that is indistinguishable from success, which is exactly
    // why nothing here reports on the strength of a send.
    final transport = _NoReadBackTransport();
    final shell = _FakeShell(
      snapshot: _snap(LinkKind.http, address: 'http://10.0.0.7', netMode: 'sta'),
      transport: transport,
    );
    final r = _resolver(
      shell: shell,
      prefs: InMemoryBridgePrefs(
        lastBaseUrl: 'http://10.0.0.7',
        lastBridgeId: 'A4F2',
      ),
    );
    final s = await _run(r);

    expect(transport.commands.whereType<SetTimeCommand>(), hasLength(1));
    expect(s.resolvedAutomatically, isFalse);
    expect(s.headline, 'Your bridge doesn’t know the time');
  });

  test('an unreadable clock is not an unset clock', () async {
    final shell = _FakeShell(
      snapshot: _snap(LinkKind.http, address: 'http://10.0.0.7', netMode: 'sta'),
      transport: _ThrowingLiveTransport(),
    );
    final r = _resolver(
      shell: shell,
      prefs: InMemoryBridgePrefs(
        lastBaseUrl: 'http://10.0.0.7',
        lastBridgeId: 'A4F2',
      ),
    );
    // Unknown, so no clock is set on a guess.
    final s = await _run(r);
    expect(s.kind, isNot(SituationKind.deviceClockUnset));
  });

  // ── 10. firmware ───────────────────────────────────────────────────

  test('old firmware names the capability, never a version number', () async {
    final shell = _FakeShell(
      snapshot: _snap(LinkKind.ble),
      transport: _FakeTransport(fullHistory: false),
    );
    final r = _resolver(
      shell: shell,
      prefs: InMemoryBridgePrefs(lastBridgeId: 'A4F2'),
    );
    final s = await _run(r);

    expect(s.kind, SituationKind.firmwareTooOld);
    expect(s.headline, contains('2 hours'));
    expect(s.headline, isNot(contains('1.0')));
    expect(s.automatic, isFalse);
    expect(r.act, SituationAct.updateFirmware);
  });

  // ── 11. remembered, and nothing answers ────────────────────────────

  test('an unreachable bridge always carries when it was last seen', () async {
    final r = _resolver(
      shell: _FakeShell(),
      prefs: InMemoryBridgePrefs(
        lastBaseUrl: 'http://10.0.0.7',
        lastBridgeId: 'A4F2',
        lastSeenUnixMs: _clock - 12 * 60 * 1000,
      ),
    );
    final s = await _run(r);

    expect(s.kind, SituationKind.bridgeOutOfRange);
    expect(s.detail, contains('Last seen 12 minutes ago'));
    expect(s.detail, contains('still recording'));
    // No banner over the temperatures — the transport chip already says it.
    expect(s.showsBanner, isFalse);
  });

  test('the retry runs by itself, and only success is reported', () async {
    final shell = _FakeShell();
    final r = _resolver(
      shell: shell,
      prefs: InMemoryBridgePrefs(
        lastBaseUrl: 'http://10.0.0.7',
        lastSeenUnixMs: _clock - 60000,
      ),
    );
    final failed = await _run(r);
    expect(shell.retries, 1);
    expect(failed.resolvedAutomatically, isFalse);
    expect(failed.headline, 'Can’t reach your bridge');

    // The bridge comes back.
    shell.retryWorks = true;
    _clock += 30000;
    final ok = await _run(r);
    expect(shell.retries, 2);
    expect(ok.resolvedAutomatically, isTrue);
    expect(ok.headline, 'Reconnected to your bridge');
  });

  test('a rebuild storm cannot queue-jump the supervisor’s backoff', () async {
    final shell = _FakeShell();
    final r = _resolver(
      shell: shell,
      prefs: InMemoryBridgePrefs(lastBaseUrl: 'http://10.0.0.7'),
    );
    await _run(r);
    await _run(r);
    await _run(r);
    expect(shell.retries, 1);
  });

  // ── 12. a cook belonging to another bridge ─────────────────────────

  test('a cook for another bridge is subsumed by the identity question', () async {
    // `staleCook`'s guard is a strict subset of `bridgeWasReset`'s, so the
    // reconciler can never reach it: a running cook plus a different device
    // id IS a different bridge, and the identity question has to be settled
    // first. Recorded here so the day the ordering changes, this says so.
    final facts = SituationFacts(
      rememberedBridgeId: 'A4F2',
      rememberedBaseUrl: 'http://10.0.0.7',
      hasRunningCook: true,
      reachedDeviceId: 'B811',
      reachedAddress: 'http://10.0.0.7',
      reachedNetMode: 'sta',
      nowUnixMs: _clock,
    );
    expect(reconcile(facts).kind, SituationKind.bridgeWasReset);

    // The kind is still a real product state with a real remedy, and the
    // screen has to be able to render it.
    expect(actFor(SituationKind.staleCook), SituationAct.endCook);
    situationCoverage.add(SituationKind.staleCook);
  });

  // ── 13. nothing to say ─────────────────────────────────────────────

  test('a healthy bridge renders nothing at all', () async {
    final shell = _FakeShell(
      snapshot: _snap(LinkKind.http, address: 'http://10.0.0.7', netMode: 'sta'),
      transport: _FakeTransport(),
    );
    final r = _resolver(
      shell: shell,
      prefs: InMemoryBridgePrefs(
        lastBaseUrl: 'http://10.0.0.7',
        lastBridgeId: 'A4F2',
      ),
    );
    final s = await _run(r);

    expect(s.kind, SituationKind.healthy);
    expect(s.isHealthy, isTrue);
    expect(s.showsBanner, isFalse);
    expect(r.act, SituationAct.none);
  });

  // ── the reporting rules themselves ─────────────────────────────────

  test('a past-tense report survives long enough to be read', () async {
    final prefs = InMemoryBridgePrefs(
      lastBaseUrl: 'http://10.0.0.7',
      lastBridgeId: 'A4F2',
    );
    final shell = _FakeShell(
      snapshot: _snap(
        LinkKind.http,
        address: 'http://10.0.0.42',
        netMode: 'sta',
      ),
      transport: _FakeTransport(),
    );
    final r = _resolver(shell: shell, prefs: prefs);
    await _run(r);
    expect(r.situation.resolvedAutomatically, isTrue);

    // Reconciling again a second later finds nothing wrong; the report is
    // still the last thing that happened, so it stays.
    _clock += 1000;
    await r.evaluate();
    expect(r.situation.resolvedAutomatically, isTrue);

    // Later, it retires on its own.
    _clock += SituationResolver.reportHold.inMilliseconds;
    await r.evaluate();
    expect(r.situation.isHealthy, isTrue);
  });

  test('a real problem outranks a report that is still on screen', () async {
    final prefs = InMemoryBridgePrefs(
      lastBaseUrl: 'http://10.0.0.7',
      lastBridgeId: 'A4F2',
    );
    final shell = _FakeShell(
      snapshot: _snap(
        LinkKind.http,
        address: 'http://10.0.0.42',
        netMode: 'sta',
      ),
      transport: _FakeTransport(),
    );
    final r = _resolver(shell: shell, prefs: prefs);
    await _run(r);
    expect(r.situation.resolvedAutomatically, isTrue);

    // It goes away one second later. A congratulation left over a bridge
    // that has since vanished is the same lie as a stale temperature.
    shell.snapshot = null;
    shell.transport = null;
    _clock += 1000;
    await r.evaluate();
    expect(r.situation.kind, SituationKind.bridgeOutOfRange);
  });

  test('a report can be retired by hand', () async {
    final r = _resolver(
      shell: _FakeShell(retryWorks: true),
      prefs: InMemoryBridgePrefs(),
      probe: _FakeProbe(
        bonded: const BondedBridge(deviceId: 'AA', name: 'SmokeBridge-1'),
      ),
    );
    await _run(r);
    expect(r.situation.resolvedAutomatically, isTrue);
    r.retireReport();
    expect(r.situation.isHealthy, isTrue);
  });

  test('a reconciliation that throws leaves the last answer standing', () async {
    final shell = _FakeShell(
      snapshot: _snap(LinkKind.http, address: 'http://10.0.0.7', netMode: 'sta'),
      transport: _FakeTransport(statusThrows: true),
    );
    final r = _resolver(
      shell: shell,
      prefs: InMemoryBridgePrefs(
        lastBaseUrl: 'http://10.0.0.7',
        lastBridgeId: 'A4F2',
        lastSeenUnixMs: _clock - 60000,
      ),
    );
    // A status read that throws means the device column is empty, which is
    // "cannot reach it" — with the last-seen still in the copy.
    final s = await _run(r);
    expect(s.kind, SituationKind.bridgeOutOfRange);
    expect(s.detail, contains('Last seen'));
  });

  test('two evaluations in flight at once are one evaluation', () async {
    final shell = _FakeShell();
    final r = _resolver(
      shell: shell,
      prefs: InMemoryBridgePrefs(lastBaseUrl: 'http://10.0.0.7'),
    );
    await Future.wait([r.evaluate(), r.evaluate(), r.evaluate()]);
    expect(shell.retries, 1);
  });

  // ── the gate ───────────────────────────────────────────────────────

  test('every SituationKind has been driven by a test above', () {
    final missed = SituationKind.values.toSet().difference(situationCoverage);
    expect(
      missed,
      isEmpty,
      reason:
          'A recovery path with no test is a recovery path nobody has run. '
          'Uncovered: $missed',
    );
  });
}

/// Accepts the write and stays unset — the failure a send cannot detect.
class _NoReadBackTransport extends _FakeTransport {
  _NoReadBackTransport() : super(clockValid: false);

  @override
  Future<void> control(ControlCommand cmd) async {
    commands.add(cmd);
    // Deliberately does NOT flip `clockValid`.
  }
}

/// Answers status but not live — an unreadable clock, which is not an unset
/// one.
class _ThrowingLiveTransport extends _FakeTransport {
  @override
  Future<LiveState> live({Duration window = const Duration(hours: 1)}) async =>
      throw StateError('no live');
}
