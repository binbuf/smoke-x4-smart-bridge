/// A23 integration — the composition root for `/setup` (design 13 §13.2,
/// §13.5.1).
///
/// The one place the real radio, the real HTTP handoff race and the real
/// AP-binder are wired to [SetupMachine], and its ~34 states are projected
/// through the two shipping dispatchers ([setupScreenFor] for hop 0/1,
/// [setupNetScreenFor] for hop 2/3/finish). It is the exact shape
/// `onboarding_route.dart` took for the old wizard (which this replaces),
/// which is why it is a widget and not a library: everything it assembles is
/// tested against fakes elsewhere (the machine in `setup_machine_test.dart`,
/// the screens in `setup_hop*_test.dart`, the whole flow in
/// `lab/setup_lab.dart`); only the wiring lives here.
///
/// **Seams and their production peers:**
///
///  * [_FbpPreflightProbe] reads the adapter through `flutter_blue_plus` and
///    permissions through `permission_handler` — both REAL now (A24.2). Only the
///    Android SDK≤32 location-services gate (check 1) stays a conservative stub
///    (no platform-version seam), which is correct on modern Android. The
///    adapter and permission branches — off / unsupported / unauthorized /
///    denied / permanently-denied — are all real.
///  * [_PairListenStub] backs hop 2, whose `pair_status` characteristic
///    (§13.8.2) does not exist in firmware. Opening a listen window fails fast,
///    so the machine lands on `SetupBaseFailed(timeoutNoBeacon)` — from which
///    "Skip for now" and "Try again" both work — rather than sitting on a dead
///    120 s budget. When the firmware characteristic lands this becomes a real
///    listen + notify and nothing else changes.
///
/// The persistence proof points of §13.2.4 (setupResumeAt, redefining
/// `LaunchNeedsOnboarding` to weigh a partial setup) remain a separate task;
/// what IS wired here is the one that makes "finish → dashboard" not bounce:
/// the verified base URL is recorded so the launch race has a known-good lane.
///
/// **Re-entry (design 16 §16.3).** Every door into `/setup` used to open on
/// hop 0. This route now reconciles first: what the phone remembers becomes
/// [SituationFacts], [setupResumePlanFor] turns that into the hop that is
/// actually unfinished, and [SetupMachine.startFrom] opens there. A caller
/// that already knows more than preferences do — a situation banner, a
/// recovery card — passes [SetupRoute.resumeFrom] instead; with no argument
/// the route derives it, so the automatic path is the default rather than an
/// opt-in.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/app_env.dart';
import '../../app/router.dart';
import '../../data/prefs/bridge_prefs.dart';
import '../../data/transport/ble_gatt_fbp.dart';
import '../../data/transport/ble_transport.dart';
import '../../data/transport/connection_manager.dart';
import '../../data/transport/http_transport.dart';
import '../../design/design.dart';
import '../../domain/situation/situation.dart';
import '../../platform/network_binder.dart';
import '../shell/situation_probe_platform.dart';
import 'preflight.dart';
import 'screens/finish_screens.dart';
import 'screens/hop1_screens.dart';
import 'screens/preflight_screens.dart';
import 'setup_entry.dart';
import 'setup_machine.dart';

class SetupRoute extends StatefulWidget {
  const SetupRoute({super.key, this.resumeFrom});

  /// Where this entry into setup should pick up (§16.3). Null means "work it
  /// out": [setupResumePlanFor] over what this phone has stored, which is the
  /// case every existing caller takes and the reason none of them had to
  /// change.
  final SetupResumePlan? resumeFrom;

  @override
  State<SetupRoute> createState() => _SetupRouteState();
}

/// What this phone remembers, as the same facts the reconciler on `/live`
/// reads (§16.3). Preferences are the only source available before any radio
/// is up — the *observable* and *device says* columns fill in during the
/// re-link, and the machine reconciles them there.
/// [bondedBridgeName] is the *observable* column, and it is the one fact that
/// separates "a stranger" from "this phone forgot a bridge it is still paired
/// to". Without it `setupResumePlanFor` can only ever see an empty name
/// against empty preferences and return [SetupResumePlan.fresh] — which made
/// [SetupResumeKind.adoptBridge] unreachable in the shipping app, and sent a
/// user whose phone had been reset (or restored from backup) through the full
/// three-hop first-time wizard, scan and all, while the OS bond to their
/// bridge sat there the whole time.
SetupResumePlan resumePlanFromPrefs(
  BridgePrefs? prefs, {
  int nowUnixMs = 0,
  String? bondedBridgeName,
}) {
  if (prefs == null && bondedBridgeName == null) {
    return SetupResumePlan.fresh;
  }
  return setupResumePlanFor(
    SituationFacts(
      rememberedBridgeId: prefs?.lastBridgeId,
      rememberedBaseUrl: prefs?.lastBaseUrl,
      rememberedBleDeviceId: prefs?.lastBleDeviceId,
      lastSeenUnixMs: prefs?.lastSeenUnixMs,
      bondedBridgeName: bondedBridgeName,
      nowUnixMs: nowUnixMs,
    ),
  );
}

/// The OS bond, if this phone still holds one to a `SmokeBridge-*`.
///
/// Best-effort and never throws: a phone that will not answer is simply a
/// phone with no bond to report, and setup then greets the user as new —
/// which is what it did unconditionally before.
Future<String?> bondedBridgeNameNow() async {
  try {
    final probe = await PlatformSituationProbe.create();
    return (await probe?.bondedBridge())?.name;
  } on Object {
    return null;
  }
}

class _SetupRouteState extends State<SetupRoute> {
  late final FlutterBlueGattClient _client;
  late final BleTransport _transport;
  late final ChannelNetworkBinder _binder;
  late final _LivePairListen _listen;
  late final SetupMachine _machine;
  StreamSubscription<SetupState>? _sub;
  SetupState _state = const SetupPermissionPrimer();

  @override
  void initState() {
    super.initState();
    _client = FlutterBlueGattClient();
    _transport = BleTransport(_client);
    _binder = ChannelNetworkBinder();
    _listen = _LivePairListen(_transport);
    _machine = SetupMachine(
      transport: _transport,
      client: _client,
      probe: _FbpPreflightProbe(),
      listen: _listen,
      verify: _verifyOverHttp,
      joinAp: _joinAp,
    );
    _state = _machine.state;
    _sub = _machine.states.listen(_onState);
    // Reconcile before the first frame: a phone that already knows a bridge
    // must never be greeted as a stranger (§16.3).
    //
    // The bond read is a round trip, so the wizard starts from what
    // preferences alone can say and re-plans if the bond turns out to name a
    // bridge. That only ever *upgrades* the plan — a stranger becomes an
    // adoption — so the first frame is never wrong, only sometimes less
    // informed than the second.
    final injected = widget.resumeFrom;
    final prefs = AppEnv.instance?.prefs;
    final now = DateTime.now().millisecondsSinceEpoch;
    final plan = injected ?? resumePlanFromPrefs(prefs, nowUnixMs: now);
    unawaited(_machine.startFrom(plan));
    if (injected == null && plan.kind == SetupResumeKind.fresh) {
      unawaited(_adoptIfBonded(prefs, now));
    }
  }

  /// Ask the OS whether this phone is still bonded to a bridge, and re-plan
  /// if it is. Only runs when preferences produced a from-scratch plan, which
  /// is exactly the reset-phone case.
  Future<void> _adoptIfBonded(BridgePrefs? prefs, int nowUnixMs) async {
    final name = await bondedBridgeNameNow();
    if (!mounted || name == null || name.isEmpty) {
      return;
    }
    final better = resumePlanFromPrefs(
      prefs,
      nowUnixMs: nowUnixMs,
      bondedBridgeName: name,
    );
    if (better.kind == SetupResumeKind.fresh) {
      return; // nothing gained — leave the wizard where it is
    }
    await _machine.startFrom(better);
  }

  void _onState(SetupState s) {
    if (!mounted) {
      return;
    }
    setState(() => _state = s);
  }

  /// The §5.7 verification step, unchanged from the old wizard
  /// (`onboarding_route.dart`): `net_status: up` means the radio associated,
  /// not that this phone can reach the bridge. Race the real ConnectionManager
  /// and require a real `/status` 200 — the BLE lane is excluded on purpose,
  /// because "reachable over BLE" is what setup is trying to graduate FROM.
  /// Must not throw (the machine's [HandoffVerifier] contract).
  Future<String?> _verifyOverHttp(String? ipHint) async {
    if (kDebugMode) {
      debugPrint('SETUP verify start hint=$ipHint');
    }
    final mgr = ConnectionManager(
      // The address the bridge just gave us over BLE goes in as the
      // known-address lane. Without it the race has only `smokebridge.local`
      // (which Android's resolver cannot answer) and `192.168.4.1` (the AP we
      // just left) — i.e. nothing.
      cachedBaseUrl: ipHint == null ? null : 'http://$ipHint',
      probe: (baseUrl) async {
        final t = HttpTransport(baseUrl);
        try {
          final s = await t.status();
          return s.deviceId.isNotEmpty;
        } on Object {
          return false;
        } finally {
          await t.close();
        }
      },
      writeCache: (_) async {},
    );
    final outcome = await mgr.race();
    return outcome is Connected && outcome.lane != ConnectionLane.ble
        ? outcome.baseUrl
        : null;
  }

  /// A14.1's binder. The join must also BIND, or Android leaves the default
  /// route on cellular and every request to 192.168.4.1 vanishes (05 §5.8.1) —
  /// the trap the whole binder exists for. Must not throw ([ApJoiner]).
  Future<bool> _joinAp(String ssid, String psk) async {
    try {
      await _binder.joinAp(ssid, psk);
      return _binder.state == BinderState.bound;
    } on Object {
      return false;
    }
  }

  /// "See my probes" on [SetupDone]: record the verified base URL so the launch
  /// race lands on a known-good lane instead of bouncing back here (§13.2.4),
  /// then leave `/setup` for the dashboard. Recording mirrors the race's own
  /// `writeCache`; the fuller resume-persistence of §13.2.4 is a separate task.
  Future<void> _finish() async {
    final s = _state;
    if (s is SetupDone) {
      await _persist(s.summary);
    }
    if (mounted) {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _persist(SetupSummary summary) async {
    final prefs = AppEnv.instance?.prefs;
    if (prefs == null) {
      return;
    }
    // A25 — the BLE address FIRST, and unconditionally. It is the only
    // reconnect lane a Bluetooth-only setup has, and the launch race needs a
    // device to dial. Recording nothing here is what sent finished setups
    // straight back into onboarding, on a loop (board-found).
    final bleId = summary.bleDeviceId;
    if (bleId != null && bleId.isNotEmpty) {
      try {
        await prefs.recordBleBridge(bleId, bridgeId: summary.bridgeId);
      } on Object {
        // Best-effort; the scan lane still finds it.
      }
    }
    final ip = summary.ip;
    final url = (ip != null && ip.isNotEmpty)
        ? 'http://$ip'
        : (summary.hosted ? 'http://192.168.4.1' : null);
    if (url == null) {
      return; // Wi-Fi skipped / BLE-only: the bond above is the lane.
    }
    try {
      await prefs.recordConnection(url, bridgeId: summary.bridgeId);
    } on Object {
      // Best-effort: discovery is the fallback, exactly as post-onboarding.
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_machine.dispose());
    unawaited(_listen.dispose());
    unawaited(_transport.close());
    unawaited(_binder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The setup screens are a SafeArea/Column, not a Scaffold (14 §14.7.1), so
    // the composition root supplies the Material surface and the design bg — as
    // `SetupLab` does for the review harness.
    final externals = SetupExternals(
      // The ✕ leaves `/setup`; the dashboard re-decides where the user lands.
      onLeaveSetup: () {
        if (context.mounted) {
          context.go(AppRoutes.home);
        }
      },
      // The one OS deep-link this build genuinely has. It is also the one that
      // matters most: a permanently denied permission has no other route, and
      // leaving it dark left that screen with no working control at all.
      openAppSettings: () => unawaited(_openAppSettings()),
      // The rest live in platform/system_settings.dart, which is not built yet
      // (§13.2.0). A null callback disables the control **and renders its
      // reason beneath it** (16 §16.5), while the machine-backed action beside
      // it keeps a live next step.
    );
    final screen =
        setupScreenFor(_state, _machine, externals: externals) ??
        setupNetScreenFor(
          _state,
          _machine,
          onFinish: () => unawaited(_finish()),
        );
    return Scaffold(backgroundColor: context.tokens.bg, body: screen);
  }
}

/// `permission_handler`'s app-settings deep link, wrapped so a platform that
/// refuses simply leaves the user where they were (the [SetupExternals]
/// contract: a callback must not throw).
Future<void> _openAppSettings() async {
  try {
    await openAppSettings();
  } on Object {
    // A refusal is not an error the user can act on; the "I've allowed it"
    // re-check beside this button is still live.
  }
}

/// The production [PreflightProbe] (§13.2.0). Adapter checks are real through
/// `flutter_blue_plus`; permissions are real through `permission_handler`
/// (A24.2). Only the Android SDK≤32 location-services gate stays a conservative
/// stub (no platform-version seam) — correct on modern Android.
class _FbpPreflightProbe implements PreflightProbe {
  @override
  SetupAdapterState get adapterStateNow =>
      _map(fbp.FlutterBluePlus.adapterStateNow);

  @override
  Stream<SetupAdapterState> get adapterStates =>
      fbp.FlutterBluePlus.adapterState.map(_map);

  @override
  Future<void> requestEnable() async {
    try {
      await fbp.FlutterBluePlus.turnOn();
    } on Object {
      // A refusal simply leaves the adapter off; the gate re-reads it.
    }
  }

  // No platform-version seam, so the Android SDK≤32 location gate (check 1) is
  // conservatively skipped. On modern Android this is correct; on old Android a
  // scan needing location-on would fail into "No bridges" without the warning.
  @override
  bool get needsLocationServices => false;

  @override
  Future<bool> isLocationServicesOn() async => true;

  // A24.2 — real runtime permissions via permission_handler. On Android 12+
  // (API 31+) these are `bluetoothScan` + `bluetoothConnect`; on API ≤ 30 the
  // package maps them to the granted-by-manifest legacy pair, so the primer is
  // correctly skipped there. Reads never prompt; requestPermissions() does.
  @override
  Future<PreflightPermission> permissionStatus() async => _mapPerm(
    await Permission.bluetoothScan.status,
    await Permission.bluetoothConnect.status,
  );

  @override
  Future<PreflightPermission> requestPermissions() async {
    try {
      final r = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      return _mapPerm(
        r[Permission.bluetoothScan] ?? PermissionStatus.denied,
        r[Permission.bluetoothConnect] ?? PermissionStatus.denied,
      );
    } on Object {
      // Must not throw (§13.2.0); a failed request reads as still-denied so the
      // gate offers retry rather than dead-ending.
      return PreflightPermission.denied;
    }
  }

  static PreflightPermission _mapPerm(
    PermissionStatus scan,
    PermissionStatus connect,
  ) {
    bool ok(PermissionStatus s) =>
        s.isGranted || s.isLimited || s.isProvisional;
    if (ok(scan) && ok(connect)) {
      return PreflightPermission.granted;
    }
    // "Don't ask again" on either → only app-settings can recover (§13.2.0).
    if (scan.isPermanentlyDenied || connect.isPermanentlyDenied) {
      return PreflightPermission.permanentlyDenied;
    }
    return PreflightPermission.denied;
  }

  static SetupAdapterState _map(fbp.BluetoothAdapterState s) => switch (s) {
    fbp.BluetoothAdapterState.on => SetupAdapterState.on,
    fbp.BluetoothAdapterState.off ||
    fbp.BluetoothAdapterState.turningOff => SetupAdapterState.off,
    fbp.BluetoothAdapterState.unavailable => SetupAdapterState.unsupported,
    fbp.BluetoothAdapterState.unauthorized => SetupAdapterState.unauthorized,
    fbp.BluetoothAdapterState.turningOn ||
    fbp.BluetoothAdapterState.unknown => SetupAdapterState.unknown,
  };
}

/// The production [BaseListenSeam] for hop 2 (§13.2.2).
///
/// The dedicated `pair_status` characteristic (§13.8.2) is not in firmware, but
/// the bridge already broadcasts everything hop 2 actually needs over the
/// **existing** `live_state` characteristic: `paired` is set from
/// `smoke_x_ctrl_state() == CONFIRMED` (`app_ble_core.c:231`) and the transport
/// surfaces it plus the probe count on `status()` (`ble_transport.dart:307`).
///
/// So this is real, not a stub, and needs no reflash: a **non-destructive**
/// poll of `status()` — it never sends the destructive `pair`/`unpair` op, so a
/// button labelled "Pair" cannot unpair (§13.2.2). The firmware pairs
/// autonomously over LoRa the moment the base is put in sync mode; this simply
/// watches `paired` flip. An already-paired bridge confirms on the first read.
/// When `pair_status` eventually lands, its richer notify (listening/heard/
/// garbled) drops in behind [updates] with no machine change — but hop 2 works
/// today.
class _LivePairListen implements BaseListenSeam {
  _LivePairListen(this._transport);

  final BleTransport _transport;
  final _updates = StreamController<BasePairSnapshot>.broadcast();
  Timer? _poll;
  bool _stopped = false;

  @override
  Stream<BasePairSnapshot> get updates => _updates.stream;

  @override
  Future<void> startListen({required Duration window}) async {
    _stopped = false;
    // Fire the first read async so a slow BLE read never blocks the machine's
    // `await startListen`; an already-paired bridge still confirms on it.
    unawaited(_tick());
    _poll = Timer.periodic(
      const Duration(milliseconds: 2500),
      (_) => unawaited(_tick()),
    );
  }

  Future<void> _tick() async {
    if (_stopped) {
      return;
    }
    try {
      final st = await _transport.status();
      if (!st.paired) {
        _emit(const BasePairSnapshot(state: BasePairState.listening));
        return;
      }
      // A25 — the payoff screen's whole point is REAL temperatures, and
      // `status()` does not carry any: they live on `live()`. Reading only
      // status left every probe rendering "——°F" on the one screen that
      // exists to prove the bridge is reading the base (board-found).
      List<int?> temps = const [null, null, null, null];
      try {
        final live = await _transport.live();
        if (live.tempsF10.isNotEmpty) {
          temps = live.tempsF10;
        }
      } on Object {
        // A live read that failed still leaves a confirmed pairing; the
        // dashes are then honest rather than invented.
      }
      _emit(
        BasePairSnapshot(
          state: BasePairState.confirmed,
          deviceId: st.deviceId,
          numProbes: st.numProbes,
          temps: temps,
        ),
      );
    } on Object {
      // A read that failed is not a pairing failure — stay listening; the
      // machine's listen budget bounds the window either way.
      _emit(const BasePairSnapshot(state: BasePairState.listening));
    }
  }

  void _emit(BasePairSnapshot s) {
    if (_stopped || _updates.isClosed) {
      return;
    }
    _updates.add(s);
    if (s.state == BasePairState.confirmed) {
      _poll?.cancel(); // done; no need to keep polling
    }
  }

  @override
  Future<void> cancel() async {
    _stopped = true;
    _poll?.cancel();
  }

  Future<void> dispose() async {
    _stopped = true;
    _poll?.cancel();
    await _updates.close();
  }
}
