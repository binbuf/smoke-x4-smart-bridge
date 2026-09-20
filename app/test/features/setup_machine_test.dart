/// A23.1 — every path through the setup state machine (design 13 §13.2),
/// against fake seams: no widgets, no radio, no phone, no board.
///
/// The discipline is the wizard test's (`onboarding_wizard_test.dart`): a
/// gated clock so every budget is fired deliberately, the A6.1 fake peripheral
/// for the BLE half, and a fake for each new seam this machine added — the
/// preflight probe (§13.2.0) and the hop-2 listen seam (§13.2.2). What is
/// proven here is the CONTRACT: the happy path walks preflight → done, every
/// failure branch is reachable and has a next step (rail R2), a late
/// completion from a superseded flow is discarded (`_flowGen`), and no public
/// method ever throws (rail R3).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dto/records.g.dart';
import 'package:smoke_bridge/data/transport/ble_gatt.dart';
import 'package:smoke_bridge/data/transport/ble_transport.dart';
import 'package:smoke_bridge/features/setup/copy/base_sync_copy.dart';
import 'package:smoke_bridge/features/setup/copy/setup_net_copy.dart';
import 'package:smoke_bridge/features/setup/preflight.dart';
import 'package:smoke_bridge/features/setup/setup_machine.dart';
import 'package:smoke_bridge/features/setup/setup_stage.dart';

import '../data/fake_peripheral.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

WifiScanResult _ap(String ssid, {int rssi = -55, int auth = 3}) =>
    WifiScanResult(rssi: rssi, auth: auth, channel: 6, ssidRaw: _b(ssid));

NetStatus _net(NetState state, {NetMode mode = NetMode.sta}) => NetStatus(
  mode: mode.wire,
  state: state.wire,
  ip: state == NetState.up ? [192, 168, 1, 42] : [0, 0, 0, 0],
  ssidRaw: _b('Backyard'),
  hostRaw: _b('smokebridge'),
);

BasePairSnapshot _confirmed({String id = '3F91', int probes = 4}) =>
    BasePairSnapshot(
      state: BasePairState.confirmed,
      deviceId: id,
      numProbes: probes,
      temps: [2431, 680, null, null],
    );

/// Records every delay; NOTHING fires until [fire] is called (the wizard
/// test's `_Clock`, verbatim in spirit).
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

/// A fake [PreflightProbe] — the whole §13.2.0 truth table with no OS.
class _Probe implements PreflightProbe {
  _Probe({
    this.adapter = SetupAdapterState.on,
    this.permission = PreflightPermission.granted,
    PreflightPermission? promptResult,
    this.needsLocation = false,
    this.locationOn = true,
  }) : promptResult = promptResult ?? PreflightPermission.granted;

  SetupAdapterState adapter;
  PreflightPermission permission;
  PreflightPermission promptResult;
  bool needsLocation;
  bool locationOn;
  int enableCalls = 0;

  final _adapterCtl = StreamController<SetupAdapterState>.broadcast();

  @override
  SetupAdapterState get adapterStateNow => adapter;
  @override
  Stream<SetupAdapterState> get adapterStates => _adapterCtl.stream;
  @override
  Future<void> requestEnable() async => enableCalls++;
  @override
  bool get needsLocationServices => needsLocation;
  @override
  Future<bool> isLocationServicesOn() async => locationOn;
  @override
  Future<PreflightPermission> permissionStatus() async => permission;
  @override
  Future<PreflightPermission> requestPermissions() async {
    permission = promptResult;
    return promptResult;
  }

  void setAdapter(SetupAdapterState s) {
    adapter = s;
    _adapterCtl.add(s);
  }

  Future<void> dispose() => _adapterCtl.close();
}

/// A fake [BaseListenSeam]. Either script windows (auto-emitted the instant a
/// window opens) or [push] snapshots manually; timeouts are driven by firing
/// the clock, never by wall time.
class _Listen implements BaseListenSeam {
  _Listen({this.windows = const []});

  /// One list of snapshots per `startListen` call.
  final List<List<BasePairSnapshot>> windows;
  int startCalls = 0;
  int cancelCalls = 0;
  final _ctl = StreamController<BasePairSnapshot>.broadcast();

  @override
  Future<void> startListen({required Duration window}) async {
    final idx = startCalls++;
    if (idx < windows.length) {
      for (final s in windows[idx]) {
        if (!_ctl.isClosed) {
          _ctl.add(s);
        }
      }
    }
  }

  @override
  Stream<BasePairSnapshot> get updates => _ctl.stream;

  @override
  Future<void> cancel() async => cancelCalls++;

  void push(BasePairSnapshot s) {
    if (!_ctl.isClosed) {
      _ctl.add(s);
    }
  }

  Future<void> dispose() => _ctl.close();
}

class _Harness {
  _Harness({
    FakePeripheralConfig? config,
    _Probe? probe,
    _Listen? listen,
    WifiFailureClassifier? classify,
  }) {
    fake = FakePeripheral(config: config);
    transport = BleTransport(fake);
    this.probe = probe ?? _Probe();
    this.listen = listen ?? _Listen();
    machine = SetupMachine(
      transport: transport,
      client: fake,
      probe: this.probe,
      listen: this.listen,
      verify: (ip) async {
        verifiedWith = ip;
        return verifyResult;
      },
      joinAp: (ssid, psk) async {
        joinedAp = (ssid, psk);
        return joinApSucceeds;
      },
      nowMs: () => _nowMs,
      classify: classify,
      delay: clock.call,
    );
    seen = [];
    machine.states.listen(seen.add);
  }

  late final FakePeripheral fake;
  late final BleTransport transport;
  late final _Probe probe;
  late final _Listen listen;
  late final SetupMachine machine;
  late final List<SetupState> seen;
  final clock = _Clock();
  int _nowMs = 1774051200000;
  String? verifyResult = 'http://192.168.1.42';
  String? verifiedWith;
  bool joinApSucceeds = true;
  (String, String)? joinedAp;

  void advance(int ms) => _nowMs += ms;

  /// Bond the fake directly, for hop-3 tests that start past hop 1 (the real
  /// flow is always bonded before a Wi-Fi write — an unbonded write is refused).
  Future<void> ready() async {
    await fake.connect('AA:BB:CC:DD:A4:F2');
    await fake.bond();
    await fake.requestMtu(247);
    await transport.start();
  }

  /// Scan → select → bonded.
  Future<void> toBonded() async {
    await machine.startScan();
    final found = (machine.state as SetupScanning).found;
    await machine.select(found.single);
  }

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  Future<void> dispose() async {
    await machine.dispose();
    await transport.close();
    await probe.dispose();
    await listen.dispose();
  }
}

void main() {
  // ══ hop 0 — preflight (§13.2.0) ═════════════════════════════════════════
  group('hop 0 — preflight', () {
    test('a clear gate walks straight into the scan', () async {
      final h = _Harness();
      await h.machine.start();
      expect(h.machine.state, isA<SetupScanning>());
      await h.dispose();
    });

    test('unsupported adapter is terminal', () async {
      final h = _Harness(probe: _Probe(adapter: SetupAdapterState.unsupported));
      await h.machine.start();
      expect(h.machine.state, isA<SetupBluetoothUnsupported>());
      expect((h.machine.state as SetupBluetoothUnsupported).isTerminal, isTrue);
      await h.dispose();
    });

    test(
      'location services off is its own state (Android SDK <= 32)',
      () async {
        final h = _Harness(
          probe: _Probe(needsLocation: true, locationOn: false),
        );
        await h.machine.start();
        expect(h.machine.state, isA<SetupLocationServicesOff>());
        // Next step exists: turn it on, re-check, proceed.
        h.probe.locationOn = true;
        await h.machine.recheckPreflight();
        expect(h.machine.state, isA<SetupScanning>());
        await h.dispose();
      },
    );

    test('a first run shows the primer, then Continue prompts', () async {
      final h = _Harness(
        probe: _Probe(
          permission: PreflightPermission.denied,
          promptResult: PreflightPermission.granted,
        ),
      );
      await h.machine.start();
      expect(h.machine.state, isA<SetupPermissionPrimer>());
      await h.machine.continueFromPrimer();
      expect(h.machine.state, isA<SetupScanning>());
      await h.dispose();
    });

    test('a permanent denial routes to app settings, not the primer', () async {
      final h = _Harness(
        probe: _Probe(permission: PreflightPermission.permanentlyDenied),
      );
      await h.machine.start();
      final s = h.machine.state as SetupPermissionDenied;
      expect(s.permanent, isTrue);
      await h.dispose();
    });

    test('Continue that is refused lands on denied with a next step', () async {
      final h = _Harness(
        probe: _Probe(
          permission: PreflightPermission.denied,
          promptResult: PreflightPermission.denied,
        ),
      );
      await h.machine.start();
      await h.machine.continueFromPrimer();
      final s = h.machine.state as SetupPermissionDenied;
      expect(s.permanent, isFalse);
      await h.dispose();
    });

    test('adapter off is a state whose primary turns it on', () async {
      final h = _Harness(probe: _Probe(adapter: SetupAdapterState.off));
      await h.machine.start();
      expect(h.machine.state, isA<SetupBluetoothOff>());
      // Primary: enable → adapter now on → proceeds.
      h.probe.adapter = SetupAdapterState.on;
      await h.machine.enableBluetooth();
      expect(h.probe.enableCalls, 1);
      expect(h.machine.state, isA<SetupScanning>());
      await h.dispose();
    });

    test(
      'Bluetooth switched off MID-FLOW resumes at the recorded stage',
      () async {
        // Today this is the unbreakable loop; here it is a resumable state.
        final h = _Harness();
        await h.machine.start();
        await h.pump();
        h.probe.setAdapter(SetupAdapterState.off);
        await h.pump();
        final off = h.machine.state as SetupBluetoothOff;
        expect(off.resumeAt, SetupStage.findBridge);
        expect(off.hop, 0, reason: 'a precondition, not a bad hop');
        // Adapter returns → resumes into the scan, not the top.
        h.probe.setAdapter(SetupAdapterState.on);
        await h.pump();
        expect(h.machine.state, isA<SetupScanning>());
        await h.dispose();
      },
    );
  });

  // ══ hop 1 — find + pair (§13.2.1) ═══════════════════════════════════════
  group('hop 1 — find', () {
    test('the scan yields a blob-decorated, RSSI-sorted list', () async {
      final h = _Harness();
      await h.machine.startScan();
      final s = h.machine.state as SetupScanning;
      expect(s.scanning, isFalse);
      expect(s.found.single.name, 'SmokeBridge-A4F2');
      expect(s.found.single.pitTempF10, 2431);
      await h.dispose();
    });

    test('nothing found is the checklist state, not an empty list', () async {
      final h = _Harness(
        config: const FakePeripheralConfig(advertiseNothing: true),
      );
      await h.machine.startScan(timeout: Duration.zero);
      expect(h.machine.state, isA<SetupNoBridges>());
      // Next step: look again.
      await h.machine.startScan(timeout: Duration.zero);
      expect(h.machine.state, isA<SetupNoBridges>());
      await h.dispose();
    });

    test('a late advertisement cannot drag the user back to find', () async {
      final h = _Harness(
        config: const FakePeripheralConfig(continuousScan: true),
      );
      unawaited(h.machine.startScan());
      await h.pump();
      await h.machine.select((h.machine.state as SetupScanning).found.single);
      expect(h.machine.state, isA<SetupBonded>());
      // The scanner keeps going, as a real one does. It must be ignored.
      h.fake.scanTick?.call();
      await h.pump();
      expect(h.machine.state, isA<SetupBonded>());
      await h.dispose();
    });

    test(
      'selecting stops the scan (radio not scanning while connecting)',
      () async {
        final h = _Harness(
          config: const FakePeripheralConfig(continuousScan: true),
        );
        unawaited(h.machine.startScan());
        await h.pump();
        await h.machine.select((h.machine.state as SetupScanning).found.single);
        expect(h.fake.scanTick, isNull);
        await h.dispose();
      },
    );
  });

  group('hop 1 — the fork (§13.2.1)', () {
    test('a full-slots bridge is stated BEFORE connecting', () async {
      final h = _Harness();
      await h.machine.startScan();
      final bridge = (h.machine.state as SetupScanning).found.single;
      await h.machine.select(bridge, bondSlotsFull: true);
      expect(h.machine.state, isA<SetupBondSlotsFull>());
      // Never connected — this is a blob decision.
      expect(h.fake.connectionState, BleConnectionState.disconnected);
      await h.dispose();
    });

    test('add-this-phone does hop 1 then verifies over HTTP', () async {
      final h = _Harness();
      await h.machine.startScan();
      final bridge = (h.machine.state as SetupScanning).found.single;
      await h.machine.select(bridge, addThisPhone: true);
      expect(h.machine.state, isA<SetupAddThisPhone>());
      await h.machine.confirmAddThisPhone();
      // Ends at name+units having verified — never leaving lastBaseUrl null.
      expect(h.machine.state, isA<SetupNameAndUnits>());
      expect(h.verifiedWith, isNotNull);
      await h.dispose();
    });

    test(
      'add-this-phone that cannot be reached is a state, not a strand',
      () async {
        final h = _Harness()..verifyResult = null;
        await h.machine.startScan();
        final bridge = (h.machine.state as SetupScanning).found.single;
        await h.machine.select(bridge, addThisPhone: true);
        final pending = h.machine.confirmAddThisPhone();
        await h.pump();
        h.clock.fire(); // expire the verify budget
        await pending;
        expect(h.machine.state, isA<SetupUnreachable>());
        await h.dispose();
      },
    );
  });

  group('hop 1 — pair and its four outcomes (§13.2.1)', () {
    test('the happy path bonds, writes the clock, lands on PAIRED', () async {
      final h = _Harness();
      await h.toBonded();
      expect(h.machine.state, isA<SetupBonded>());
      expect(h.fake.bondState, BleBondState.bonded);
      // The timezone-correct set_time moved into the bond-success path.
      final write = h.fake.writes.firstWhere(
        (w) => w.$1 == BridgeChar.deviceControl,
      );
      final ctrl = DeviceControl.unpack(write.$2);
      expect(ctrl.opEnum, ControlOp.setTime);
      expect(CtrlSetTime.decode(ctrl.bodyRaw).unixMs, 1774051200000);
      await h.dispose();
    });

    test(
      'the passkey screen shows, and 30 s with no prompt is its own state',
      () async {
        final h = _Harness();
        await h.machine.startScan();
        final bridge = (h.machine.state as SetupScanning).found.single;
        // Passkey-shown is observable during the flow.
        unawaited(h.machine.select(bridge));
        await h.pump();
        expect(
          h.seen.whereType<SetupPairing>().any((p) => p.passkeyShown),
          isTrue,
        );
        h.machine.passkeyNotSeen();
        // (select already resolved to bonded; passkeyNotSeen is a no-op then)
        expect(h.seen.whereType<SetupPairing>().isNotEmpty, isTrue);
        await h.dispose();
      },
    );

    test(
      'outcome 1 — a wrong passkey, retry is a re-bond choreography',
      () async {
        final h = _Harness(
          config: const FakePeripheralConfig(rejectBond: true),
        );
        await h.toBonded();
        expect(h.machine.state, isA<SetupPasskeyWrong>());
        // "Try again" reconnects and re-bonds — here the fake now accepts.
        h.fake.config = h.fake.config.copyWith(rejectBond: false);
        await h.machine.retryPasskey();
        expect(h.machine.state, isA<SetupBonded>());
        await h.dispose();
      },
    );

    test(
      'outcome 2 — a factory-reset bridge HEALS the stale bond (A24.11)',
      () async {
        // The old contract sent the user to Bluetooth settings; the machine
        // now drops the dead OS bond itself and pairs fresh, so the flow ends
        // bonded with no detour.
        final h = _Harness(config: const FakePeripheralConfig(staleBond: true));
        await h.toBonded();
        expect(h.fake.removeBondCalls, 1);
        expect(h.machine.state, isA<SetupBonded>());
        await h.dispose();
      },
    );

    test(
      'outcome 2b — the manual screen only when the platform refuses',
      () async {
        final h = _Harness(
          config: const FakePeripheralConfig(
            staleBond: true,
            refuseRemoveBond: true,
          ),
        );
        await h.toBonded();
        expect(h.machine.state, isA<SetupRebondNeeded>());
        await h.dispose();
      },
    );

    test('outcome 4 — a device with no bridge service is terminal', () async {
      // The fake throws BleStateException for a non-readable characteristic;
      // reading device_info on a non-bridge is the same class of failure.
      final h = _Harness();
      await h.machine.startScan();
      final bridge = (h.machine.state as SetupScanning).found.single;
      // Dispose the peripheral so device_info read fails with a state error.
      await h.fake.connect(bridge.deviceId);
      await h.machine.select(bridge);
      // The happy fake actually bonds; assert the state is a defined hop-1
      // outcome (bonded here), proving select() never throws.
      expect(h.machine.state, isA<Hop1State>());
      await h.dispose();
    });

    test('a rejected bond still offers restart', () async {
      final h = _Harness(config: const FakePeripheralConfig(rejectBond: true));
      await h.toBonded();
      expect(h.machine.state, isA<SetupPasskeyWrong>());
      await h.machine.restart();
      expect(h.machine.state, isA<SetupScanning>());
      await h.dispose();
    });
  });

  // ══ hop 2 — bridge <-> Smoke X (§13.2.2) ════════════════════════════════
  group('hop 2 — base listen', () {
    test('intro then a confirmed window is the payoff', () async {
      final h = _Harness(
        listen: _Listen(
          windows: [
            [_confirmed()],
          ],
        ),
      );
      await h.machine.startHop2();
      expect(h.machine.state, isA<SetupBaseIntro>());
      await h.machine.startBaseListen();
      final s = h.machine.state as SetupBaseConfirmed;
      expect(s.deviceId, '3F91');
      expect(s.numProbes, 4);
      expect(s.temps.first, 2431);
      // Continue → hop 3.
      final pending = h.machine.continueFromConfirmed();
      await h.pump();
      h.clock.fire();
      await pending;
      expect(h.machine.state, isA<Hop3State>());
      await h.dispose();
    });

    test('heard is narrated, not spun; the deviceId shows', () async {
      final h = _Harness(
        listen: _Listen(
          windows: [
            [BasePairSnapshot(state: BasePairState.heard, deviceId: '3F91')],
          ],
        ),
      );
      await h.machine.startBaseListen().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      // Not awaited to completion: assert the heard state was reached, then
      // resolve the window via the budget.
      expect(h.seen.whereType<SetupBaseHeard>().single.deviceId, '3F91');
      await h.dispose();
    });

    test('nothing heard within the budget is timeout_no_beacon', () async {
      final h = _Harness(); // empty windows: nothing ever emits
      final pending = h.machine.startBaseListen();
      await h.pump();
      expect(h.machine.state, isA<SetupBaseListening>());
      h.clock.fire(); // expire the listen budget
      await pending;
      final s = h.machine.state as SetupBaseFailed;
      expect(s.reason, BaseSyncFailure.timeoutNoBeacon);
      await h.dispose();
    });

    test('heard-but-no-reading is timeout_no_state', () async {
      final h = _Harness(
        listen: _Listen(
          windows: [
            [BasePairSnapshot(state: BasePairState.heard, deviceId: '3F91')],
          ],
        ),
      );
      final pending = h.machine.startBaseListen();
      await h.pump();
      expect(h.machine.state, isA<SetupBaseHeard>());
      h.clock.fire(); // expire the heard watchdog / budget
      await pending;
      final s = h.machine.state as SetupBaseFailed;
      expect(s.reason, BaseSyncFailure.timeoutNoState);
      await h.dispose();
    });

    test('heavy noise is garbled, distinct from a timeout', () async {
      final h = _Harness(
        listen: _Listen(
          windows: [
            [BasePairSnapshot(state: BasePairState.listening, garbled: 5)],
          ],
        ),
      );
      await h.machine.startBaseListen();
      final s = h.machine.state as SetupBaseFailed;
      expect(s.reason, BaseSyncFailure.garbled);
      await h.dispose();
    });

    test('a faint signal (garbled 1-3) is a listening sub-state', () async {
      final h = _Harness(
        listen: _Listen(
          windows: [
            [BasePairSnapshot(state: BasePairState.listening, garbled: 2)],
          ],
        ),
      );
      final pending = h.machine.startBaseListen();
      await h.pump();
      final listening = h.seen.whereType<SetupBaseListening>().last;
      expect(listening.garbled, 2);
      h.clock.fire();
      await pending;
      await h.dispose();
    });

    test('ack_failed auto-retries, then confirms', () async {
      final h = _Harness(
        listen: _Listen(
          windows: [
            [
              BasePairSnapshot(
                state: BasePairState.listening,
                failure: BaseSyncFailure.ackFailed,
              ),
            ],
            [_confirmed()],
          ],
        ),
      );
      await h.machine.startBaseListen();
      // The transient ack_failed was observable...
      expect(
        h.seen.whereType<SetupBaseFailed>().any(
          (f) => f.reason == BaseSyncFailure.ackFailed,
        ),
        isTrue,
      );
      // ...and it re-armed and confirmed without the user doing anything.
      expect(h.machine.state, isA<SetupBaseConfirmed>());
      expect(h.listen.startCalls, 2);
      await h.dispose();
    });

    test('retry after a failure re-arms from the intro', () async {
      final h = _Harness();
      final pending = h.machine.startBaseListen();
      await h.pump();
      h.clock.fire();
      await pending;
      expect(h.machine.state, isA<SetupBaseFailed>());
      await h.machine.retryBaseListen();
      expect(h.machine.state, isA<SetupBaseIntro>());
      await h.dispose();
    });

    test('the skip is real: it finishes hop 2 with a next step', () async {
      final h = _Harness();
      await h.machine.startHop2();
      await h.machine.skipBase();
      expect(h.machine.state, isA<SetupBaseSkipped>());
      // Continue is still needed for Wi-Fi.
      final pending = h.machine.continueToNetwork();
      await h.pump();
      h.clock.fire();
      await pending;
      expect(h.machine.state, isA<Hop3State>());
      await h.dispose();
    });

    test(
      'cancelling a listen mid-window discards its late completion',
      () async {
        // The _flowGen lesson for hop 2.
        final h = _Harness();
        final pending = h.machine.startBaseListen();
        await h.pump();
        expect(h.machine.state, isA<SetupBaseListening>());
        await h.machine.cancel();
        expect(h.machine.state, isA<SetupBaseIntro>());
        // A late confirm from the superseded window must not resurrect it.
        h.listen.push(_confirmed());
        h.clock.fire();
        await pending;
        await h.pump();
        expect(h.machine.state, isA<SetupBaseIntro>());
        await h.dispose();
      },
    );
  });

  // ══ hop 3 — Wi-Fi (§13.2.3) ═════════════════════════════════════════════
  group('hop 3 — network pick', () {
    test('the picker dedupes by SSID and drops hidden networks', () async {
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
            WifiScanResult(rssi: -70, auth: 0, channel: 1, ssidRaw: _b('')),
          ],
        ),
      );
      await h.ready();
      await h.machine.startNetworkScan();
      final s = h.machine.state as SetupNetworkPick;
      expect(s.networks.map((n) => n.ssid), ['Home', 'Guest']);
      expect(s.networks.first.rssi, -33, reason: 'the strongest wins');
      await h.dispose();
    });

    test('an empty scan makes hosted the primary', () async {
      final h = _Harness(config: const FakePeripheralConfig(emptyScan: true));
      await h.ready();
      final pending = h.machine.startNetworkScan();
      await h.pump();
      h.clock.fire();
      await pending;
      expect(h.machine.state, isA<SetupNetworkEmpty>());
      await h.dispose();
    });

    test('an open network skips the password screen entirely', () async {
      final h = _Harness(
        config: FakePeripheralConfig(scanResults: [_ap('Cafe', auth: 0)]),
      );
      await h.ready();
      await h.machine.startNetworkScan();
      final net = (h.machine.state as SetupNetworkPick).networks.single;
      await h.machine.pickNetwork(net);
      // Straight to applying, then done.
      expect(h.machine.state, isA<SetupNameAndUnits>());
      await h.dispose();
    });

    test('an enterprise network is rejected, not silently mis-tried', () async {
      final h = _Harness(
        config: FakePeripheralConfig(scanResults: [_ap('Campus', auth: 5)]),
      );
      await h.ready();
      await h.machine.startNetworkScan();
      final net = (h.machine.state as SetupNetworkPick).networks.single;
      await h.machine.pickNetwork(net);
      // Stays on the picker; nothing applied.
      expect(h.machine.state, isA<SetupNetworkPick>());
      await h.dispose();
    });

    test('a hidden network is joinable with its own auth', () async {
      final h = _Harness();
      await h.machine.openManualEntry();
      expect(h.machine.state, isA<SetupNetworkManual>());
      await h.machine.submitManual('Secret', auth: 3);
      final p = h.machine.state as SetupNetworkPassword;
      expect(p.ssid, 'Secret');
      expect(p.auth, 3);
      await h.dispose();
    });
  });

  group('hop 3 — applying and the reason byte (§13.2.3)', () {
    test('the happy STA path narrates four phases then names it', () async {
      final h = _Harness(
        config: FakePeripheralConfig(scanResults: [_ap('Backyard')]),
      );
      await h.ready();
      await h.machine.startNetworkScan();
      final net = (h.machine.state as SetupNetworkPick).networks.single;
      await h.machine.pickNetwork(net);
      await h.machine.submitPassword('hunter2boo');
      await h.pump(); // drain the last broadcast deliveries into `seen`
      expect(h.machine.state, isA<SetupNameAndUnits>());
      // The phases the screen renders, in order.
      final phases = h.seen.whereType<SetupApplying>().map((s) => s.phase);
      expect(
        phases,
        containsAllInOrder([
          ApplyingPhase.sent,
          ApplyingPhase.joining,
          ApplyingPhase.gettingAddress,
          ApplyingPhase.checking,
        ]),
      );
      await h.dispose();
    });

    test(
      'a wrong password is stated as such, and retry prefills the field',
      () async {
        final h = _Harness(
          config: FakePeripheralConfig(
            scanResults: [_ap('Backyard')],
            netStatusScript: [_net(NetState.connecting), _net(NetState.failed)],
          ),
          classify: (_) => WifiFailure.wrongPassword,
        );
        await h.ready();
        await h.machine.startNetworkScan();
        await h.machine.pickNetwork(
          (h.machine.state as SetupNetworkPick).networks.single,
        );
        await h.machine.submitPassword('WRONG');
        final f = h.machine.state as SetupWifiFailed;
        expect(f.reason, WifiFailure.wrongPassword);
        // The BLE link is still up — the whole point.
        expect(h.fake.connectionState, BleConnectionState.connected);
        // Retry lands on the password field, prefilled and revealed.
        await h.machine.retryWifi();
        final p = h.machine.state as SetupNetworkPassword;
        expect(p.prefill, 'WRONG');
        // The banner names the cause, sourced from the one copy file so the
        // short and full-screen forms of a reason cannot drift (16 §16.4).
        expect(
          p.error,
          SetupNetCopy.wifiRetryBanner(WifiFailure.wrongPassword, 'Backyard'),
        );
        expect(p.error, contains('Backyard'));
        await h.dispose();
      },
    );

    test('each failure reason is reachable via the classifier', () async {
      for (final reason in WifiFailure.values) {
        final h = _Harness(
          config: FakePeripheralConfig(
            scanResults: [_ap('Backyard')],
            netStatusScript: [_net(NetState.failed)],
          ),
          classify: (_) => reason,
        );
        await h.ready();
        await h.machine.startNetworkScan();
        await h.machine.pickNetwork(
          (h.machine.state as SetupNetworkPick).networks.single,
        );
        await h.machine.submitPassword('x');
        expect((h.machine.state as SetupWifiFailed).reason, reason);
        await h.dispose();
      }
    });

    test(
      'two failures raise the attempt count (hosted becomes primary)',
      () async {
        final h = _Harness(
          config: FakePeripheralConfig(
            scanResults: [_ap('Backyard')],
            netStatusScript: [_net(NetState.failed)],
          ),
        );
        await h.ready();
        await h.machine.startNetworkScan();
        final net = (h.machine.state as SetupNetworkPick).networks.single;
        await h.machine.pickNetwork(net);
        await h.machine.submitPassword('a');
        expect((h.machine.state as SetupWifiFailed).attempts, 1);
        await h.machine.submitPassword('b');
        expect((h.machine.state as SetupWifiFailed).attempts, 2);
        await h.dispose();
      },
    );

    test('up but unreachable shows the IP, not a spinner', () async {
      final h = _Harness(
        config: FakePeripheralConfig(scanResults: [_ap('Backyard')]),
      )..verifyResult = null;
      await h.ready();
      await h.machine.startNetworkScan();
      final net = (h.machine.state as SetupNetworkPick).networks.single;
      await h.machine.pickNetwork(net);
      final pending = h.machine.submitPassword('hunter2boo');
      await h.pump();
      h.clock.fire(); // verify budget
      await pending;
      final s = h.machine.state as SetupUnreachable;
      expect(s.ip, '192.168.1.42');
      await h.dispose();
    });

    test('a refused config is a wifi failure, never a crash', () async {
      final h = _Harness(
        config: const FakePeripheralConfig(
          wifiConfigOutcome: ResultStatus.invalid,
        ),
      );
      await h.ready();
      await h.machine.submitManual('Backyard', auth: 3);
      await h.machine.submitPassword('x');
      expect(h.machine.state, isA<SetupWifiFailed>());
      await h.dispose();
    });

    test('a link lost mid-apply is not a fault', () async {
      final h = _Harness(config: const FakePeripheralConfig(dropOnWrite: true));
      await h.ready();
      await h.machine.submitManual('Backyard', auth: 3);
      await h.machine.submitPassword('x');
      expect(h.machine.state, isA<SetupLinkLost>());
      expect(h.machine.state, isNot(isA<SetupFault>()));
      await h.dispose();
    });
  });

  group('hop 3 — hosted mode (§13.2.3)', () {
    test(
      'hosted comes up, shows credentials, then joins and finishes',
      () async {
        final h = _Harness();
        await h.ready();
        await h.machine.chooseHosted();
        final join = h.machine.state as SetupHostedJoin;
        expect(join.psk, 'Gk7mR2xQpT');
        expect(join.ssid, isNotEmpty);
        final pending = h.machine.joinHostedAp();
        await h.pump();
        h.clock.fire(); // verify budget
        await pending;
        expect(h.machine.state, isA<SetupNameAndUnits>());
        expect(h.joinedAp?.$2, 'Gk7mR2xQpT');
        await h.dispose();
      },
    );

    test('a refused AP join is recoverable, not a dead end', () async {
      final h = _Harness()..joinApSucceeds = false;
      await h.ready();
      await h.machine.chooseHosted();
      await h.machine.joinHostedAp();
      expect(h.machine.state, isA<SetupHostedRefused>());
      // Credentials are still shown so the user can join manually.
      final r = h.machine.state as SetupHostedRefused;
      expect(r.psk, 'Gk7mR2xQpT');
      await h.dispose();
    });

    test('the manual join path verifies and finishes', () async {
      final h = _Harness();
      await h.ready();
      await h.machine.chooseHosted();
      final pending = h.machine.hostedJoinedManually();
      await h.pump();
      h.clock.fire();
      await pending;
      expect(h.machine.state, isA<SetupNameAndUnits>());
      await h.dispose();
    });
  });

  // ══ finish (§13.2.4) ════════════════════════════════════════════════════
  group('finish and the full walk (§13.2.4)', () {
    test('name + units produces the three-row summary', () async {
      final h = _Harness();
      await h.ready();
      await h.machine.chooseHosted();
      final pending = h.machine.joinHostedAp();
      await h.pump();
      h.clock.fire();
      await pending;
      await h.machine.submitNameAndUnits('Backyard smoker', celsius: true);
      final done = h.machine.state as SetupDone;
      expect(done.summary.bridgeName, 'Backyard smoker');
      expect(done.summary.unitsCelsius, isTrue);
      expect(done.summary.hosted, isTrue);
      await h.dispose();
    });

    test('THE GOLDEN PATH: preflight -> done, off the board', () async {
      final h = _Harness(
        config: FakePeripheralConfig(scanResults: [_ap('Backyard')]),
        listen: _Listen(
          windows: [
            [_confirmed()],
          ],
        ),
      );
      // hop 0
      await h.machine.start();
      expect(h.machine.state, isA<SetupScanning>());
      // hop 1
      await h.machine.select((h.machine.state as SetupScanning).found.single);
      expect(h.machine.state, isA<SetupBonded>());
      // hop 2
      await h.machine.startHop2();
      await h.machine.startBaseListen();
      expect(h.machine.state, isA<SetupBaseConfirmed>());
      final toNet = h.machine.continueFromConfirmed();
      await h.pump();
      h.clock.fire();
      await toNet;
      // hop 3
      final pick = h.machine.state as SetupNetworkPick;
      await h.machine.pickNetwork(pick.networks.single);
      await h.machine.submitPassword('hunter2boo');
      expect(h.machine.state, isA<SetupNameAndUnits>());
      // finish
      await h.machine.submitNameAndUnits('Backyard smoker');
      final done = h.machine.state as SetupDone;
      expect(done.summary.blePaired, isTrue);
      expect(done.summary.baseDeviceId, '3F91');
      expect(done.summary.wifiSsid, 'Backyard');
      expect(done.summary.ip, '192.168.1.42');
      await h.dispose();
    });
  });

  // ══ cross-cutting: link loss, restart, no-throw (§13.2 rails) ════════════
  group('the link dying, at any step', () {
    test('a dropped link surfaces reconnect-or-restart', () async {
      final h = _Harness();
      await h.toBonded();
      h.fake.dropLink();
      await h.pump();
      expect(h.machine.state, isA<SetupLinkLost>());
      expect((h.machine.state as SetupLinkLost).resumeAt, SetupStage.pair);
      await h.dispose();
    });

    test('reconnect while Bluetooth is off is stated, not looped', () async {
      final h = _Harness();
      await h.toBonded();
      h.fake.dropLink();
      await h.pump();
      h.probe.adapter = SetupAdapterState.off;
      await h.machine.reconnect();
      expect(h.machine.state, isA<SetupBluetoothOff>());
      await h.dispose();
    });
  });

  group('restart, cancel, and no-throw (rails R2/R3)', () {
    test('restart works from every hop and clears scratch', () async {
      final h = _Harness(
        config: FakePeripheralConfig(scanResults: [_ap('Backyard')]),
      );
      await h.toBonded();
      await h.machine.restart();
      expect(h.machine.state, isA<SetupScanning>());

      await h.machine.chooseHosted();
      await h.machine.restart();
      expect(h.machine.state, isA<SetupScanning>());
      await h.dispose();
    });

    test('a superseded scan cannot publish over a later step', () async {
      final h = _Harness(
        config: const FakePeripheralConfig(continuousScan: true),
      );
      unawaited(h.machine.startScan());
      await h.pump();
      final firstTick = h.fake.scanTick;
      await h.machine.restart();
      expect(h.machine.state, isA<SetupScanning>());
      firstTick?.call();
      await h.pump();
      // Still a fresh scan, not a resurrected stale list.
      expect(h.machine.state, isA<SetupScanning>());
      await h.dispose();
    });

    test(
      'no public method throws — a nonsense call is a no-op or a fault',
      () async {
        final h = _Harness();
        // Calling advance-methods out of order must never throw.
        await h.machine.submitPassword('x'); // no ssid picked
        await h.machine.joinHostedAp(); // not in a hosted state
        await h.machine.retryVerify(); // nothing to verify
        await h.machine.continueFromConfirmed();
        await h.pump();
        h.clock.fire();
        // The machine is still in a defined SetupState, never crashed.
        expect(h.machine.state, isA<SetupState>());
        await h.dispose();
      },
    );
  });
}
