/// Re-entry into guided setup (design 16 §16.3, 13 §13.2.4) — the paths that
/// pick up from what this phone already knows instead of restarting at hop 0.
///
/// The complaint these tests exist to hold closed: *"whatever state all the
/// devices are in gets recovered — esp32 was reset, esp32 was connected to
/// wifi but can no longer connect, flutter was reset but esp32 still has
/// pairing info."* Each of those is a case below, and each is asserted twice —
/// once on [setupResumePlanFor], which is pure and decides *where*, and once on
/// the machine, which does it against the A6.1 fake peripheral.
///
/// Three things are checked on every resume path, because they are the rails
/// the first-time flow is built on and a resume that broke them would be worse
/// than no resume at all:
///
///  * **R2 — no state without a next step.** Every failure edge below lands on
///    a state with a live action.
///  * **R3 — no raw exception escapes.** A resume against a hostile fake ends
///    in a named state, never a throw.
///  * **the generation counter** — a superseded resume cannot drag the user
///    backwards.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dto/records.g.dart';
import 'package:smoke_bridge/data/prefs/bridge_prefs.dart';
import 'package:smoke_bridge/data/transport/ble_gatt.dart';
import 'package:smoke_bridge/data/transport/ble_transport.dart';
import 'package:smoke_bridge/domain/situation/situation.dart';
import 'package:smoke_bridge/features/setup/copy/setup_copy.dart';
import 'package:smoke_bridge/features/setup/copy/setup_net_copy.dart';
import 'package:smoke_bridge/features/setup/copy/setup_resume_copy.dart';
import 'package:smoke_bridge/features/setup/preflight.dart';
import 'package:smoke_bridge/features/setup/screens/finish_screens.dart';
import 'package:smoke_bridge/features/setup/screens/hop1_screens.dart';
import 'package:smoke_bridge/features/setup/screens/preflight_screens.dart';
import 'package:smoke_bridge/features/setup/setup_entry.dart';
import 'package:smoke_bridge/features/setup/setup_machine.dart';
import 'package:smoke_bridge/features/setup/setup_route.dart';
import 'package:smoke_bridge/features/setup/setup_stage.dart';
import 'package:smoke_bridge/ui/ui.dart';

import '../data/fake_peripheral.dart';
import '../support/load_fonts.dart';

/// The three phone widths the design tests against (§14.7 golden matrix).
const _widths = <double>[360, 393, 430];

const _bleId = 'AA:BB:CC:DD:A4:F2';

// ══ fakes ════════════════════════════════════════════════════════════════

/// Records every delay; NOTHING fires until [fire] is called.
class _Clock {
  final _gates = <Completer<void>>[];

  Future<void> call(Duration d) {
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

class _Probe implements PreflightProbe {
  _Probe({this.adapter = SetupAdapterState.on});

  SetupAdapterState adapter;
  final _ctl = StreamController<SetupAdapterState>.broadcast();

  @override
  SetupAdapterState get adapterStateNow => adapter;
  @override
  Stream<SetupAdapterState> get adapterStates => _ctl.stream;
  @override
  Future<void> requestEnable() async {}
  @override
  bool get needsLocationServices => false;
  @override
  Future<bool> isLocationServicesOn() async => true;
  @override
  Future<PreflightPermission> permissionStatus() async =>
      PreflightPermission.granted;
  @override
  Future<PreflightPermission> requestPermissions() async =>
      PreflightPermission.granted;

  void setAdapter(SetupAdapterState s) {
    adapter = s;
    _ctl.add(s);
  }

  Future<void> dispose() => _ctl.close();
}

class _Listen implements BaseListenSeam {
  final _ctl = StreamController<BasePairSnapshot>.broadcast();
  @override
  Future<void> startListen({required Duration window}) async {}
  @override
  Stream<BasePairSnapshot> get updates => _ctl.stream;
  @override
  Future<void> cancel() async {}
  Future<void> dispose() => _ctl.close();
}

/// One access point, so a hop-3 resume's Wi-Fi scan settles on its own rather
/// than waiting out a budget the gated clock never fires.
WifiScanResult _ap(String ssid, {int rssi = -55, int auth = 3}) =>
    WifiScanResult(
      rssi: rssi,
      auth: auth,
      channel: 6,
      ssidRaw: Uint8List.fromList(ssid.codeUnits),
    );

class _Harness {
  _Harness({FakePeripheralConfig? config, _Probe? probe}) {
    fake = FakePeripheral(
      config: config ?? FakePeripheralConfig(scanResults: [_ap('Backyard')]),
    );
    transport = BleTransport(fake);
    this.probe = probe ?? _Probe();
    listen = _Listen();
    machine = SetupMachine(
      transport: transport,
      client: fake,
      probe: this.probe,
      listen: listen,
      verify: (ip) async {
        verifiedWith = ip;
        return verifyResult;
      },
      nowMs: () => nowMs,
      delay: clock.call,
    );
    seen = [];
    machine.states.listen(seen.add);
    _bondSub = fake.bondStates.listen(bondEvents.add);
  }

  late final FakePeripheral fake;
  late final BleTransport transport;
  late final _Probe probe;
  late final _Listen listen;
  late final SetupMachine machine;
  late final List<SetupState> seen;
  late final StreamSubscription<BleBondState> _bondSub;

  /// Every bond transition the client caused. `bond()` always announces itself
  /// as [BleBondState.bonding] first, so an empty list after a re-entry is
  /// proof that the existing pairing was reused rather than redone — which is
  /// the "do not re-pair" contract, asserted rather than assumed.
  final bondEvents = <BleBondState>[];

  final clock = _Clock();
  int nowMs = 1774051200000;
  String? verifyResult = 'http://192.168.4.1';
  String? verifiedWith;

  /// The world a re-entry actually meets: an OS bond that outlived the app.
  /// The fake keeps [BleBondState.bonded] across a disconnect, exactly as the
  /// platform does — which is the whole reason "do not re-pair" is possible.
  Future<void> bondedButDisconnected() async {
    await fake.connect(_bleId);
    await fake.bond();
    await fake.disconnect();
    await pump();
    bondEvents.clear();
  }

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  Future<void> dispose() async {
    await _bondSub.cancel();
    await machine.dispose();
    await transport.close();
    await probe.dispose();
    await listen.dispose();
  }
}

/// A plan of the shape prefs produce for a bridge set up over Bluetooth only.
SetupResumePlan _plan(
  SetupResumeKind kind, {
  String bridgeId = 'A4F2',
  String? bleDeviceId = _bleId,
  String name = 'SmokeBridge-A4F2',
  bool hasNetwork = false,
  String? reached,
}) => SetupResumePlan(
  kind: kind,
  bridgeName: name,
  bridgeId: bridgeId,
  bleDeviceId: bleDeviceId,
  hasNetwork: hasNetwork,
  reachedBridgeId: reached,
);

Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  double width = 393,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

_Harness _fresh({FakePeripheralConfig? config, _Probe? probe}) {
  final h = _Harness(config: config, probe: probe);
  addTearDown(h.dispose);
  return h;
}

void main() {
  setUpAll(loadAppFonts);

  // ══ the decision, pure (§16.3) ═════════════════════════════════════════
  group('setupResumePlanFor — which hop is actually unfinished', () {
    test('a phone that has never met a bridge starts at the top', () {
      final plan = setupResumePlanFor(const SituationFacts());
      expect(plan.kind, SetupResumeKind.fresh);
      expect(plan.skipsAhead, isFalse);
      expect(plan.stage, SetupStage.findBridge);
    });

    test('phone reset, bridge still bonded — adopt, do not re-pair', () {
      // The exact case in the verdict: "flutter was reset but esp32 still has
      // pairing info". The DEVICE holds the identity and it still holds it.
      final plan = setupResumePlanFor(
        const SituationFacts(bondedBridgeName: 'SmokeBridge-8274'),
      );
      expect(plan.kind, SetupResumeKind.adoptBridge);
      expect(plan.bridgeName, 'SmokeBridge-8274');
      expect(plan.skipsAhead, isTrue);
      expect(plan.stage, SetupStage.pair);
    });

    test('a visible SmokeBridge access point is equally adoptable', () {
      final plan = setupResumePlanFor(
        const SituationFacts(visibleApSsid: 'SmokeBridge-8274'),
      );
      expect(plan.kind, SetupResumeKind.adoptBridge);
      expect(plan.bridgeName, 'SmokeBridge-8274');
    });

    test('BLE bonded but no Wi-Fi goes straight to hop 3', () {
      final plan = setupResumePlanFor(
        const SituationFacts(
          rememberedBridgeId: 'A4F2',
          rememberedBleDeviceId: _bleId,
        ),
      );
      expect(plan.kind, SetupResumeKind.addNetwork);
      expect(plan.stage, SetupStage.network);
      expect(plan.hasNetwork, isFalse, reason: 'nothing to change yet');
      expect(plan.bleDeviceId, _bleId);
    });

    test('a bridge already on Wi-Fi re-enters hop 3 to CHANGE it', () {
      final plan = setupResumePlanFor(
        const SituationFacts(
          rememberedBridgeId: 'A4F2',
          rememberedBleDeviceId: _bleId,
          rememberedBaseUrl: 'http://192.168.1.57',
        ),
      );
      expect(plan.kind, SetupResumeKind.addNetwork);
      expect(plan.hasNetwork, isTrue);
    });

    test('reachable but never met a Smoke X goes straight to hop 2', () {
      final plan = setupResumePlanFor(
        const SituationFacts(
          rememberedBridgeId: 'A4F2',
          rememberedBleDeviceId: _bleId,
          rememberedBaseUrl: 'http://192.168.1.57',
          reachedDeviceId: 'A4F2',
          pairedToBase: false,
        ),
      );
      expect(plan.kind, SetupResumeKind.pairBase);
      expect(plan.stage, SetupStage.baseListen);
    });

    test('an identity mismatch outranks everything else', () {
      // Even with hop 2 unfinished: a different bridge invalidates every other
      // conclusion, so it is decided first and never automatically.
      final plan = setupResumePlanFor(
        const SituationFacts(
          rememberedBridgeId: 'A4F2',
          rememberedBleDeviceId: _bleId,
          reachedDeviceId: '91BE',
          pairedToBase: false,
        ),
      );
      expect(plan.kind, SetupResumeKind.bridgeWasReset);
      expect(plan.reachedBridgeId, '91BE');
      expect(plan.bridgeId, 'A4F2');
      expect(plan.skipsAhead, isFalse, reason: 'this IS a fresh setup');
      expect(plan.stage, SetupStage.findBridge);
    });

    test('a matching identity is NOT a mismatch', () {
      final plan = setupResumePlanFor(
        const SituationFacts(
          rememberedBridgeId: 'A4F2',
          rememberedBleDeviceId: _bleId,
          reachedDeviceId: 'A4F2',
        ),
      );
      expect(plan.kind, SetupResumeKind.addNetwork);
    });

    test('remembered with no Bluetooth address has nothing to skip', () {
      // An address alone cannot be re-linked over: setup drives over
      // Bluetooth, so hop 1 is the only honest door — and the plan says so
      // rather than promising a resume it cannot perform.
      final plan = setupResumePlanFor(
        const SituationFacts(
          rememberedBridgeId: 'A4F2',
          rememberedBaseUrl: 'http://192.168.1.57',
        ),
      );
      expect(plan.kind, SetupResumeKind.fresh);
      expect(plan.bridgeId, 'A4F2', reason: 'still known, just not dialable');
    });

    test('every kind lands on a stage, and only two start at the top', () {
      for (final k in SetupResumeKind.values) {
        expect(k.stage, isNotNull);
      }
      expect(SetupResumeKind.values.where((k) => !k.skipsAhead).toSet(), {
        SetupResumeKind.fresh,
        SetupResumeKind.bridgeWasReset,
      });
    });
  });

  // ══ prefs → plan, the door every existing caller takes ═════════════════
  group('resumePlanFromPrefs', () {
    test('no prefs at all is a first run', () {
      expect(resumePlanFromPrefs(null).kind, SetupResumeKind.fresh);
    });

    test('an empty store is a first run', () {
      expect(
        resumePlanFromPrefs(InMemoryBridgePrefs()).kind,
        SetupResumeKind.fresh,
      );
    });

    test('a reset phone still bonded to its bridge adopts it, not re-pairs', () {
      // The user's own words: "flutter was reset but esp32 still has pairing
      // or connection info". The app store is empty — cleared data, a
      // reinstall, a restored backup — but the OS bond table is not, and the
      // *device* still holds the identity. Sending this person through the
      // full three-hop wizard, scan and all, past a bridge they are already
      // paired to, is the opposite of "as automatic as possible".
      //
      // This was unreachable in the shipping app: `resumePlanFromPrefs` never
      // passed the bond, so `setupResumePlanFor` compared an empty name
      // against an empty store and always answered `fresh`. The whole
      // `adoptBridge` branch — written for exactly this — was dead code.
      final plan = resumePlanFromPrefs(
        InMemoryBridgePrefs(),
        bondedBridgeName: 'SmokeBridge-8274',
      );

      expect(plan.kind, SetupResumeKind.adoptBridge);
      expect(plan.bridgeName, 'SmokeBridge-8274');
    });

    test('no store and no bond is still a genuine first run', () {
      expect(
        resumePlanFromPrefs(InMemoryBridgePrefs(), bondedBridgeName: '').kind,
        SetupResumeKind.fresh,
      );
      expect(
        resumePlanFromPrefs(null, bondedBridgeName: null).kind,
        SetupResumeKind.fresh,
      );
    });

    test('a Bluetooth-only setup re-enters at Wi-Fi, not at hop 0', () {
      final plan = resumePlanFromPrefs(
        InMemoryBridgePrefs(lastBridgeId: 'A4F2', lastBleDeviceId: _bleId),
      );
      expect(plan.kind, SetupResumeKind.addNetwork);
      expect(plan.bleDeviceId, _bleId);
      expect(plan.hasNetwork, isFalse);
    });

    test('a fully provisioned bridge re-enters to change its network', () {
      final plan = resumePlanFromPrefs(
        InMemoryBridgePrefs(
          lastBridgeId: 'A4F2',
          lastBleDeviceId: _bleId,
          lastBaseUrl: 'http://192.168.1.57',
        ),
      );
      expect(plan.kind, SetupResumeKind.addNetwork);
      expect(plan.hasNetwork, isTrue);
    });
  });

  // ══ the machine acting on it ═══════════════════════════════════════════
  group('the machine resumes instead of restarting', () {
    test('hop 3: relinks over the existing bond and never re-pairs', () async {
      final h = _fresh();
      await h.bondedButDisconnected();
      await h.machine.startFrom(_plan(SetupResumeKind.addNetwork));

      expect(
        h.seen.whereType<SetupScanning>(),
        isEmpty,
        reason: 'a known bridge is dialled, never hunted for',
      );
      await h.pump();
      expect(
        h.bondEvents,
        isEmpty,
        reason: 'the bond survived; asking for a code again is the bug',
      );
      final pick = h.machine.state as SetupNetworkPick;
      expect(pick.resume, SetupResumeKind.addNetwork);
      expect(pick.hop, 3);
    });

    test('the re-link screen is shown, and it promises no code', () async {
      final h = _fresh();
      await h.bondedButDisconnected();
      await h.machine.startFrom(_plan(SetupResumeKind.addNetwork));
      final relink = h.seen.whereType<SetupPairing>().first;
      expect(relink.isRelink, isTrue);
      expect(relink.passkeyShown, isFalse);
      expect(relink.resume, SetupResumeKind.addNetwork);
      // A link lost mid-relink must resume at the hop being resumed to, not
      // at hop 1 — which is what carrying the stage on the state buys.
      expect(relink.stage, SetupStage.network);
    });

    test(
      'the relink sets the clock, so cooks can be dated (§16.3 #9)',
      () async {
        final h = _fresh();
        await h.bondedButDisconnected();
        await h.machine.startFrom(_plan(SetupResumeKind.addNetwork));
        final write = h.fake.writes.firstWhere(
          (w) => w.$1 == BridgeChar.deviceControl,
        );
        final ctrl = DeviceControl.unpack(write.$2);
        expect(ctrl.opEnum, ControlOp.setTime);
        expect(CtrlSetTime.decode(ctrl.bodyRaw).unixMs, 1774051200000);
      },
    );

    test('hop 2 first when the bridge has never met a Smoke X', () async {
      // Asked for hop 3, but the bridge itself says it is unpaired. RF before
      // Wi-Fi is load-bearing (§13.2), and hop 2 is one tap from hop 3.
      final h = _fresh();
      h.fake.state.paired = false;
      await h.bondedButDisconnected();
      await h.machine.startFrom(_plan(SetupResumeKind.addNetwork));
      final intro = h.machine.state as SetupBaseIntro;
      expect(intro.resume, SetupResumeKind.pairBase);
      expect(intro.hop, 2);
    });

    test('an explicit hop-2 resume lands on hop 2', () async {
      final h = _fresh();
      h.fake.state.paired = false;
      await h.bondedButDisconnected();
      await h.machine.startFrom(_plan(SetupResumeKind.pairBase));
      expect(h.machine.state, isA<SetupBaseIntro>());
      expect(
        (h.machine.state as SetupBaseIntro).resume,
        SetupResumeKind.pairBase,
      );
    });

    test('asking for hop 2 is honoured even on a paired bridge', () async {
      // Re-listening for a base is deliberate — "that is not my thermometer"
      // is a real thing to want, and a resume that overruled it would send
      // the user somewhere they did not ask to go.
      final h = _fresh();
      expect(h.fake.state.paired, isTrue);
      await h.bondedButDisconnected();
      await h.machine.startFrom(_plan(SetupResumeKind.pairBase));
      expect(h.machine.state, isA<SetupBaseIntro>());
    });

    test('adopt verifies over HTTP and lands on name + units', () async {
      final h = _fresh();
      await h.bondedButDisconnected();
      await h.machine.startFrom(_plan(SetupResumeKind.adoptBridge));
      expect(h.machine.state, isA<SetupNameAndUnits>());
      expect(h.verifiedWith, isNotNull, reason: 'never claims an address');
      await h.pump();
      expect(h.bondEvents, isEmpty);
    });

    test('adopt that cannot be reached is a state, not a strand', () async {
      final h = _fresh()..verifyResult = null;
      await h.bondedButDisconnected();
      final pending = h.machine.startFrom(_plan(SetupResumeKind.adoptBridge));
      await h.pump();
      h.clock.fire(); // expire the verify budget
      await pending;
      expect(h.machine.state, isA<SetupUnreachable>());
    });

    test('a bridge with no network adopts anyway (Bluetooth only)', () async {
      // Verifying an address that does not exist would strand a finished
      // adoption on "this phone can't see it".
      final h = _fresh()..verifyResult = null;
      h.fake.state.net = NetStatus(
        mode: NetMode.sta.wire,
        state: NetState.idle.wire,
        ip: const [0, 0, 0, 0],
        ssidRaw: Uint8List(0),
        hostRaw: Uint8List(0),
      );
      await h.bondedButDisconnected();
      await h.machine.startFrom(_plan(SetupResumeKind.adoptBridge));
      expect(h.machine.state, isA<SetupNameAndUnits>());
      expect(h.verifiedWith, isNull, reason: 'nothing to verify');
    });

    test(
      'with nothing to dial, a resume falls back to the find list',
      () async {
        final h = _fresh();
        await h.machine.startFrom(
          _plan(SetupResumeKind.addNetwork, bleDeviceId: null),
        );
        expect(h.machine.state, isA<Hop1State>());
      },
    );
  });

  // ══ identity — the one case that is never automatic (§16.3 #7) ═════════
  group('a bridge that came back as somebody else', () {
    test('the plan alone states it, before anything is dialled', () async {
      final h = _fresh();
      await h.machine.startFrom(
        _plan(SetupResumeKind.bridgeWasReset, reached: '91BE'),
      );
      final s = h.machine.state as SetupRebondNeeded;
      expect(s.identityChanged, isTrue);
      expect(s.reachedBridgeId, '91BE');
      expect(s.rememberedBridgeId, 'A4F2');
      expect(
        h.fake.connectionState,
        BleConnectionState.disconnected,
        reason: 'identity is decided before a link is claimed',
      );
    });

    test('a mismatch found DURING the relink stops there', () async {
      final h = _fresh();
      await h.bondedButDisconnected();
      // The bridge answers to A4F2; this phone was set up with something else.
      await h.machine.startFrom(
        _plan(SetupResumeKind.addNetwork, bridgeId: '91BE'),
      );
      final s = h.machine.state as SetupRebondNeeded;
      expect(s.identityChanged, isTrue);
      expect(s.reachedBridgeId, 'A4F2');
      expect(s.rememberedBridgeId, '91BE');
      expect(
        h.machine.state,
        isNot(isA<SetupNetworkPick>()),
        reason: 'never silently adopts a device that did not record the cooks',
      );
    });

    test('"set it up as new" is a real fresh flow (R2)', () async {
      final h = _fresh();
      await h.machine.startFrom(
        _plan(SetupResumeKind.bridgeWasReset, reached: '91BE'),
      );
      await h.machine.restart();
      await h.pump();
      expect(h.machine.state, isA<SetupScanning>());
      expect(
        (h.machine.state as SetupScanning).resume,
        isNull,
        reason: 'a restart claims nothing is already done',
      );
    });

    test(
      'a dead bond names the same situation without inventing ids',
      () async {
        final h = _fresh(
          config: FakePeripheralConfig(
            staleBond: true,
            refuseRemoveBond: true,
            scanResults: [_ap('Backyard')],
          ),
        );
        await h.bondedButDisconnected();
        await h.machine.startFrom(_plan(SetupResumeKind.addNetwork));
        final s = h.machine.state as SetupRebondNeeded;
        expect(s.identityChanged, isFalse, reason: 'no id was ever read');
      },
    );
  });

  // ══ the rails, on the resume paths ═════════════════════════════════════
  group('rails R2/R3 across re-entry', () {
    test('preflight still gates a resume, and returns to it', () async {
      final probe = _Probe(adapter: SetupAdapterState.off);
      final h = _fresh(probe: probe);
      await h.bondedButDisconnected();
      await h.machine.startFrom(_plan(SetupResumeKind.addNetwork));
      final off = h.machine.state as SetupBluetoothOff;
      expect(
        off.resumeAt,
        SetupStage.network,
        reason: 'turning Bluetooth back on must not cost the resume',
      );
      // Adapter returns → the machine re-enters the PLAN, not hop 1.
      probe.adapter = SetupAdapterState.on;
      await h.machine.enableBluetooth();
      await h.pump();
      expect(h.machine.state, isA<SetupNetworkPick>());
    });

    test('a relink that cannot connect offers reconnect-or-restart', () async {
      final h = _fresh();
      // Never bonded, and the fake refuses secured reads without one.
      await h.machine.startFrom(_plan(SetupResumeKind.addNetwork));
      expect(h.machine.state, isA<SetupRebondNeeded>());
      // R2: the state has a live next step.
      await h.machine.restart();
      await h.pump();
      expect(h.machine.state, isA<SetupScanning>());
    });

    test('no resume path throws — R3 holds', () async {
      final h = _fresh();
      for (final kind in SetupResumeKind.values) {
        await h.machine.startFrom(_plan(kind, bleDeviceId: null));
        expect(h.machine.state, isNot(isA<SetupFault>()));
      }
    });

    test('a superseded resume cannot drag the user backwards', () async {
      final h = _fresh();
      await h.bondedButDisconnected();
      final pending = h.machine.startFrom(_plan(SetupResumeKind.addNetwork));
      await h.machine.restart();
      await pending;
      await h.pump();
      // The restart owns the screen; the superseded relink published nothing
      // over it.
      expect(h.machine.state, isA<Hop1State>());
    });

    test('cancelling at hop 3 with an empty list keeps a next step', () async {
      final h = _fresh(config: const FakePeripheralConfig(emptyScan: true));
      await h.bondedButDisconnected();
      final pending = h.machine.startFrom(_plan(SetupResumeKind.addNetwork));
      await h.pump();
      h.clock.fire(); // expire the scan budget
      await pending;
      expect(h.machine.state, isA<SetupNetworkEmpty>());
      await h.machine.cancel();
      // Never a picker with nothing in it and no way to look again — a state
      // whose only control is an empty list is a state without a next step.
      expect(h.machine.state, isA<SetupNetworkEmpty>());
    });
  });

  // ══ the screens say WHY (§16.4) ════════════════════════════════════════
  group('re-entry copy explains why setup is open', () {
    late FakePeripheral fake;
    late BleTransport transport;
    late _Probe probe;
    late _Listen listen;
    late SetupMachine machine;
    late SetupExternals externals;
    var left = 0;

    setUp(() {
      fake = FakePeripheral();
      transport = BleTransport(fake);
      probe = _Probe();
      listen = _Listen();
      machine = SetupMachine(
        transport: transport,
        client: fake,
        probe: probe,
        listen: listen,
        verify: (_) async => null,
      );
      left = 0;
      externals = SetupExternals(onLeaveSetup: () => left++);
      addTearDown(() async {
        await machine.dispose();
        await transport.close();
        await probe.dispose();
        await listen.dispose();
      });
    });

    BridgeDiscovery bridge() =>
        const BridgeDiscovery(deviceId: _bleId, name: 'Backyard smoker');

    testWidgets('the re-link renders NO passkey display', (tester) async {
      // PasskeyDisplay points at six digits on the bridge's glass. A bridge
      // that already recognises this phone never generates them, so showing
      // the frame would be the same broken promise the screen exists to end.
      await _pumpAt(
        tester,
        setupScreenFor(
          SetupPairing(bridge: bridge(), resume: SetupResumeKind.addNetwork),
          machine,
          externals: externals,
        )!,
      );
      expect(find.byType(PasskeyDisplay), findsNothing);
      expect(find.textContaining('6-digit'), findsNothing);
      expect(
        find.text(SetupResumeCopy.relinkTitle('Backyard smoker')),
        findsOneWidget,
      );
      expect(
        find.text(
          SetupResumeCopy.relinkBody(
            SetupResumeKind.addNetwork,
            'Backyard smoker',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the first-time passkey screen is untouched', (tester) async {
      await _pumpAt(
        tester,
        setupScreenFor(
          SetupPairing(bridge: bridge(), passkeyShown: true),
          machine,
          externals: externals,
        )!,
      );
      expect(find.byType(PasskeyDisplay), findsOneWidget);
      expect(find.text(SetupCopy.pairTitle), findsOneWidget);
    });

    testWidgets('the re-link says which hop is left, per kind', (tester) async {
      for (final kind in [
        SetupResumeKind.adoptBridge,
        SetupResumeKind.pairBase,
        SetupResumeKind.addNetwork,
      ]) {
        await _pumpAt(
          tester,
          setupScreenFor(
            SetupPairing(bridge: bridge(), resume: kind),
            machine,
            externals: externals,
          )!,
        );
        expect(
          find.text(SetupResumeCopy.relinkBody(kind, 'Backyard smoker')),
          findsOneWidget,
          reason: '$kind must name its own reason',
        );
      }
    });

    testWidgets('adoption reframes "add this phone"', (tester) async {
      await _pumpAt(
        tester,
        setupScreenFor(
          SetupAddThisPhone(bridge(), resume: SetupResumeKind.adoptBridge),
          machine,
          externals: externals,
        )!,
      );
      expect(find.text(SetupCopy.addPhoneTitle), findsNothing);
      expect(
        find.text(SetupResumeCopy.relinkTitle('Backyard smoker')),
        findsOneWidget,
      );
    });

    testWidgets('the second-phone fork keeps its own words', (tester) async {
      await _pumpAt(
        tester,
        setupScreenFor(
          SetupAddThisPhone(bridge()),
          machine,
          externals: externals,
        )!,
      );
      expect(find.text(SetupCopy.addPhoneTitle), findsOneWidget);
    });

    testWidgets('the adopt scan says no code is coming', (tester) async {
      await _pumpAt(
        tester,
        setupScreenFor(
          const SetupScanning(resume: SetupResumeKind.adoptBridge),
          machine,
          externals: externals,
        )!,
      );
      expect(find.text(SetupResumeCopy.adoptScanBody), findsOneWidget);
    });

    testWidgets('a settled empty scan offers "Look again", not a spinner', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        setupScreenFor(
          const SetupScanning(scanning: false),
          machine,
          externals: externals,
        )!,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(SetupCopy.noBridgesLookAgain), findsOneWidget);
    });

    testWidgets('the reset bridge is named, explained and never retried', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        setupScreenFor(
          SetupRebondNeeded(
            bridge(),
            reachedBridgeId: '91BE',
            rememberedBridgeId: 'A4F2',
          ),
          machine,
          externals: externals,
        )!,
      );
      expect(find.text(SetupResumeCopy.resetTitle), findsOneWidget);
      expect(find.textContaining('91BE'), findsOneWidget);
      expect(find.textContaining('A4F2'), findsOneWidget);
      expect(find.text(SetupResumeCopy.resetPrimary), findsOneWidget);
      // Retrying cannot make a different device into the old one.
      expect(find.text(SetupCopy.rebondRetry), findsNothing);
      // And there is a way out that is not the flow.
      await tester.tap(find.text(SetupResumeCopy.resetLeave));
      expect(left, 1);
    });

    testWidgets('a dead bond keeps the Bluetooth-settings route', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        setupScreenFor(
          SetupRebondNeeded(bridge()),
          machine,
          externals: externals,
        )!,
      );
      expect(find.text(SetupCopy.rebondTitle), findsOneWidget);
      expect(find.text(SetupCopy.rebondRetry), findsOneWidget);
      expect(find.text(SetupResumeCopy.resetPrimary), findsNothing);
    });

    testWidgets('hop 2 entered directly leads with why', (tester) async {
      await _pumpAt(
        tester,
        setupNetScreenFor(
          const SetupBaseIntro(resume: SetupResumeKind.pairBase),
          machine,
        ),
      );
      expect(find.textContaining(SetupResumeCopy.pairBaseWhy), findsOneWidget);
    });

    testWidgets('hop 3 entered directly distinguishes add from change', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        setupNetScreenFor(
          const SetupNetworkPick(
            scanning: false,
            networks: [],
            resume: SetupResumeKind.addNetwork,
          ),
          machine,
        ),
      );
      expect(
        find.textContaining(SetupResumeCopy.addNetworkWhy),
        findsOneWidget,
      );

      await _pumpAt(
        tester,
        setupNetScreenFor(
          const SetupNetworkPick(
            scanning: false,
            networks: [],
            resume: SetupResumeKind.addNetwork,
            hasNetwork: true,
          ),
          machine,
        ),
      );
      expect(
        find.textContaining(SetupResumeCopy.changeNetworkWhy),
        findsOneWidget,
      );
      // The radio fact survives every rewording above it.
      expect(find.textContaining(SetupNetCopy.pickBand), findsOneWidget);
    });

    testWidgets('a first run is never told it is resuming', (tester) async {
      await _pumpAt(
        tester,
        setupNetScreenFor(
          const SetupNetworkPick(scanning: false, networks: []),
          machine,
        ),
      );
      expect(find.text(SetupNetCopy.pickSubtitle), findsOneWidget);
      expect(find.textContaining(SetupResumeCopy.addNetworkWhy), findsNothing);
    });

    for (final w in _widths) {
      testWidgets('no overflow at $w — re-entry screens', (tester) async {
        for (final screen in <Widget>[
          setupScreenFor(
            SetupPairing(bridge: bridge(), resume: SetupResumeKind.adoptBridge),
            machine,
            externals: externals,
          )!,
          setupScreenFor(
            SetupRebondNeeded(
              bridge(),
              reachedBridgeId: '91BE',
              rememberedBridgeId: 'A4F2',
            ),
            machine,
            externals: externals,
          )!,
          setupScreenFor(
            const SetupScanning(
              scanning: false,
              resume: SetupResumeKind.adoptBridge,
            ),
            machine,
            externals: externals,
          )!,
          setupNetScreenFor(
            const SetupBaseIntro(resume: SetupResumeKind.pairBase),
            machine,
          ),
          setupNetScreenFor(
            const SetupNetworkPick(
              scanning: false,
              networks: [],
              resume: SetupResumeKind.addNetwork,
            ),
            machine,
          ),
        ]) {
          await _pumpAt(tester, screen, width: w);
          expect(tester.takeException(), isNull);
        }
      });
    }
  });

  // ══ the copy rules themselves (§16.4) ══════════════════════════════════
  group('§16.4 holds over the re-entry strings', () {
    final all = <String>[
      SetupResumeCopy.adoptScanBody,
      SetupResumeCopy.pairBaseWhy,
      SetupResumeCopy.addNetworkWhy,
      SetupResumeCopy.changeNetworkWhy,
      SetupResumeCopy.resetTitle,
      SetupResumeCopy.resetPrimary,
      SetupResumeCopy.resetLeave,
      SetupResumeCopy.relinkCancel,
      SetupResumeCopy.relinkTitle('Backyard smoker'),
      SetupResumeCopy.resetBody(reachedId: '91BE', rememberedId: 'A4F2'),
      for (final k in SetupResumeKind.values)
        SetupResumeCopy.relinkBody(k, 'Backyard smoker'),
      for (final r in WifiFailure.values)
        SetupNetCopy.wifiRetryBanner(r, 'Backyard'),
    ];

    test('no jargon and no status codes', () {
      const banned = [
        'mDNS',
        'GATT',
        'MTU',
        'RSSI',
        'BLE',
        'SSID',
        'PSK',
        'NVS',
        'LoRa',
        'error',
        'failed',
        'exception',
        'invalid',
      ];
      for (final s in all) {
        for (final word in banned) {
          expect(
            s.toLowerCase(),
            isNot(contains(word.toLowerCase())),
            reason: '"$word" in: $s',
          );
        }
      }
    });

    test('never blames the user, and never shouts', () {
      for (final s in all) {
        expect(s, isNot(contains('!')));
        for (final blame in const [
          'you did',
          'you must',
          'you failed',
          'incorrect',
          'wrong',
          'you entered',
          'you typed',
        ]) {
          expect(
            s.toLowerCase(),
            isNot(contains(blame)),
            reason: '"$blame" in: $s',
          );
        }
      }
    });

    test('buttons are verbs that name the outcome', () {
      for (final label in const [
        SetupResumeCopy.resetPrimary,
        SetupResumeCopy.resetLeave,
        SetupResumeCopy.relinkCancel,
      ]) {
        expect(label, isNot('OK'));
        expect(label, isNot('Cancel'));
        expect(label.trim(), isNotEmpty);
      }
    });

    test('a nameless bridge reads as a bridge, never as an id', () {
      expect(SetupResumeCopy.named(''), 'your bridge');
      expect(SetupResumeCopy.named('   '), 'your bridge');
      expect(SetupResumeCopy.relinkTitle(''), contains('your bridge'));
    });

    test('the reset body works with ids missing', () {
      final none = SetupResumeCopy.resetBody(reachedId: '', rememberedId: '');
      expect(none, isNot(contains('  ')));
      expect(none, contains('start from the beginning'));
      expect(none, contains('saved cooks stay'));
    });
  });
}
