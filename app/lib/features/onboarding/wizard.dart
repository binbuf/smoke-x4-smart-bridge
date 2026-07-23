/// A8.1 — the onboarding wizard as a pure state machine (design 05 §5.7,
/// 08 §8.6).
///
/// The deliberate exception to "no Flutter screens before M4"
/// ([§12.6 rule 1](../../../../docs/design/12-task-planning-notes.md)): the
/// M3 exit gate is *a phone provisions the bridge*, and that cannot be
/// demonstrated from a unit test. So the wizard ships — but its logic
/// lives here, in a machine with no widgets in it, which A8.2's screens
/// merely project. M4 restyles; it does not rewire.
///
/// **Failure edges are first-class states, not error dialogs.** Bond
/// rejected, scan empty, config refused, handoff timed out, link lost:
/// each is a state with a defined next step, because §5.7's whole point is
/// that there is always a next step. A spinner that never resolves is the
/// one outcome this machine may not produce.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/dto/records.g.dart'
    show NetMode, NetState, NetStatus, WifiScanResult;
import '../../data/transport/ble_gatt.dart';
import '../../data/transport/ble_transport.dart';
import '../../data/transport/bridge_transport.dart';

/// Which way the user chose to run the bridge (05 §5.1).
enum BridgeMode {
  /// The bridge hosts its own AP. Works anywhere; costs battery and range.
  hosted,

  /// The bridge joins the house network. Better range, needs credentials.
  joined,
}

/// Why the wizard is offering a recovery, so the copy can say which.
enum RecoveryReason {
  /// STA came up but nothing answered over HTTP inside the budget. The
  /// bridge is fine and still on BLE — this is the escape hatch working.
  httpUnreachable,

  /// `net_status` said `failed`: almost always a wrong password.
  wifiFailed,

  /// The device refused the config outright.
  configRefused,
}

sealed class WizardState {
  const WizardState();
}

/// Step 1 — find. The list is blob-decorated before any connection
/// exists, which is the whole point of the §2.3 advertising blob.
class WizardFind extends WizardState {
  const WizardFind({this.found = const [], this.scanning = true});
  final List<BridgeDiscovery> found;
  final bool scanning;
}

/// Step 2 — pair. On Android the passkey dialog is owned by the OS, so
/// this step *instructs and observes*: it points at the bridge's OLED and
/// watches bond state. It does not host a six-digit field (A6 epic flag).
class WizardPair extends WizardState {
  const WizardPair(this.bridge, {this.bonding = false});
  final BridgeDiscovery bridge;
  final bool bonding;
}

class WizardBondRejected extends WizardState {
  const WizardBondRejected(this.bridge);
  final BridgeDiscovery bridge;
}

/// The bridge was factory-reset since we last bonded. A distinct state
/// because the fix is distinct: forget the pairing and start again, which
/// "retry" does not do.
class WizardRebondNeeded extends WizardState {
  const WizardRebondNeeded(this.bridge);
  final BridgeDiscovery bridge;
}

/// Step 3 — time. Written silently; the user never sees this step do
/// anything, which is why F6.2's back-patch matters (a session started
/// before this point is still dated correctly).
class WizardSettingTime extends WizardState {
  const WizardSettingTime();
}

/// Step 4a — hosted or joined, with the honest battery/range copy.
class WizardChooseMode extends WizardState {
  const WizardChooseMode();
}

/// Step 4b — the network picker, fed by the device-side scan.
class WizardPickNetwork extends WizardState {
  const WizardPickNetwork({
    this.networks = const [],
    this.scanning = true,
    this.error,
  });
  final List<WifiScanResult> networks;
  final bool scanning;

  /// Set when the previous attempt came back — "incorrect password", not
  /// a spinner. The user lands back HERE with the reason stated.
  final String? error;

  bool get isEmpty => !scanning && networks.isEmpty;
}

/// Step 5 — handoff. `phase` tracks the §5.7 choreography so the screen
/// can say what is happening rather than spinning.
enum HandoffPhase { applying, connecting, verifying, joiningAp }

class WizardHandoff extends WizardState {
  const WizardHandoff(this.phase, {this.mode = BridgeMode.joined});
  final HandoffPhase phase;
  final BridgeMode mode;
}

/// **Not a failure state.** BLE is still connected, so the wizard offers
/// the two ways out §5.7 promises: revert to hosting, or retry with
/// corrected credentials.
class WizardRecover extends WizardState {
  const WizardRecover(this.reason, {this.detail = ''});
  final RecoveryReason reason;
  final String detail;
}

/// The BLE link died mid-flow. Every state can reach this, and it always
/// offers reconnect-or-restart rather than stranding the user.
class WizardLinkLost extends WizardState {
  const WizardLinkLost();
}

class WizardDone extends WizardState {
  const WizardDone({required this.mode, this.baseUrl = ''});
  final BridgeMode mode;

  /// Where HTTP answered. Empty when the wizard finished on BLE alone.
  final String baseUrl;
}

/// ── Injected seams ───────────────────────────────────────────────────

/// Verifies the bridge over HTTP after the transition. Production races
/// the ConnectionManager and requires a real `/status` 200; returns the
/// winning base URL, or null. Must not throw.
///
/// [ipHint] is the address the bridge JUST reported over BLE in
/// `net_status` (§5.2). It is not a nicety — it is the address §5.7's
/// choreography actually uses (`GET http://<ip>/api/v1/status`), and on
/// Android it is usually the only one that can work: Dart's HttpClient
/// resolves through the platform resolver, which does not answer `.local`
/// mDNS names. Board-found: ignoring it made every handoff end in
/// "the bridge joined but we cannot reach it" against a bridge that was
/// serving HTTP perfectly well.
typedef HandoffVerifier = Future<String?> Function(String? ipHint);

/// Joins the bridge's AP with credentials we already hold, through
/// A14.1's binder. Must not throw; returns success.
typedef ApJoiner = Future<bool> Function(String ssid, String psk);

typedef WizardDelay = Future<void> Function(Duration d);

/// §5.7: HTTP unreachable after 20 s is the recovery state, not failure.
const kHandoffBudget = Duration(seconds: 20);

class OnboardingWizard {
  OnboardingWizard({
    required this.transport,
    required this.client,
    required this.verify,
    this.joinAp,
    this.nowMs,
    WizardDelay? delay,
  }) : _delay = delay ?? ((d) => Future<void>.delayed(d));

  final BleTransport transport;
  final BleGattClient client;
  final HandoffVerifier verify;
  final ApJoiner? joinAp;

  /// Wall clock for `set_time`; injected so the written value is
  /// assertable rather than "whatever the test machine thinks".
  final int Function()? nowMs;
  final WizardDelay _delay;

  final _states = StreamController<WizardState>.broadcast();
  WizardState _state = const WizardFind();
  StreamSubscription<void>? _connSub;

  WizardState get state => _state;
  Stream<WizardState> get states => _states.stream;

  /// The AP PSK the bridge generated, once a hosted handoff has been
  /// accepted — the phone needs it to join (§5.5).
  String? apPsk;

  BridgeDiscovery? _bridge;

  /// Bumped every time a scan starts. A scan that is still draining when
  /// the user has moved on must not publish anything — see [startScan].
  int _scanGen = 0;
  BridgeMode _mode = BridgeMode.joined;
  String _ssid = '';
  int _auth = 3;

  void _to(WizardState s) {
    // Debug-only breadcrumbs. Kept in the tree deliberately: three
    // separate M3 bench failures were mis-diagnosed by reasoning and
    // only settled by reading these.
    if (kDebugMode) {
      debugPrint('WIZ ${_state.runtimeType} -> ${s.runtimeType}');
    }
    _state = s;
    if (!_states.isClosed) {
      _states.add(s);
    }
  }

  /// Any state can lose the link. Watching it from one place means no
  /// step has to remember to.
  void _watchLink() {
    _connSub ??= client.connectionStates.listen((s) {
      if (s == BleConnectionState.disconnected && _state is! WizardDone) {
        _to(const WizardLinkLost());
      }
    });
  }

  // ── step 1: find ───────────────────────────────────────────────────

  Future<void> startScan({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _to(const WizardFind());
    final gen = ++_scanGen;
    final found = <BridgeDiscovery>[];

    // BOARD-FOUND: a real BLE scan stream does not end when the user
    // walks away from the find step, and publishing from a superseded
    // scan drags them back to it from under the step they moved to. Every
    // emission below is therefore gated on "this scan is still the
    // current one, and we are still on the find step".
    bool stillOurs() => gen == _scanGen && _state is WizardFind;

    try {
      await for (final adv in client.scan(timeout: timeout)) {
        if (!stillOurs()) {
          break;
        }
        final d = BridgeDiscovery.fromAdvertisement(adv);
        // De-duplicate by device id: advertisements repeat.
        if (found.every((e) => e.deviceId != d.deviceId)) {
          found.add(d);
          _to(WizardFind(found: List.of(found), scanning: true));
        }
      }
    } on Object {
      // A scan that errors is a scan that found nothing, which is a state
      // the user can act on (move closer, power-cycle) — not a crash.
    }
    if (stillOurs()) {
      _to(WizardFind(found: List.of(found), scanning: false));
    }
  }

  // ── step 2: pair ───────────────────────────────────────────────────

  Future<void> select(BridgeDiscovery bridge) async {
    _bridge = bridge;
    // Retire the scan BEFORE changing step: scanning while connecting is
    // wasteful on the radio, and a still-draining scan publishing WizardFind
    // over the pair screen is the flicker this ordering prevents.
    _scanGen++;
    _to(WizardPair(bridge));
    try {
      await client.stopScan();
    } on Object {
      // Best-effort: never block the flow on tearing a scan down.
    }
    await connectAndBond();
  }

  Future<void> connectAndBond() async {
    final bridge = _bridge;
    if (bridge == null) {
      return;
    }
    _to(WizardPair(bridge, bonding: true));
    try {
      if (client.connectionState != BleConnectionState.connected) {
        await client.connect(bridge.deviceId);
      }
      _watchLink();
      if (client.bondState != BleBondState.bonded) {
        await client.bond();
      }
      // Ask for the MTU that makes history_preview one PDU. Whatever
      // comes back is fine — 23 included (§4).
      await client.requestMtu(247);
      await transport.start();
    } on BleBondRejectedException {
      _to(WizardBondRejected(bridge));
      return;
    } on BleRebondRequiredException {
      _to(WizardRebondNeeded(bridge));
      return;
    } on BleConnectionLostException {
      _to(const WizardLinkLost());
      return;
    } on BleException {
      _to(WizardBondRejected(bridge));
      return;
    }
    await _setTime();
  }

  /// Abandon and restart from the top. Available at every step, because
  /// "start over" is the one action that always makes sense.
  Future<void> restart() async {
    _bridge = null;
    apPsk = null;
    _scanGen++;
    // Detach the link watcher, but do NOT wait for the cancellation before
    // repainting: the user pressed "start over" and the screen owes them
    // an immediate answer, not a stream teardown round-trip.
    unawaited(_connSub?.cancel());
    _connSub = null;
    _to(const WizardFind(scanning: false));
  }

  // ── step 3: time (silent) ──────────────────────────────────────────

  Future<void> _setTime() async {
    _to(const WizardSettingTime());
    try {
      await transport.control(
        ControlCommand.setTime(
          unixMs: nowMs?.call() ?? DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } on Object {
      // A clock the bridge would not take is not worth stopping for: the
      // cook is still recorded, just dated from the monotonic floor
      // (04 §4.4). Onboarding continues.
    }
    _to(const WizardChooseMode());
  }

  // ── step 4: mode and network ───────────────────────────────────────

  Future<void> chooseMode(BridgeMode mode) async {
    _mode = mode;
    if (mode == BridgeMode.hosted) {
      await _applyConfig();
      return;
    }
    await scanNetworks();
  }

  Future<void> scanNetworks({String? error}) async {
    _to(WizardPickNetwork(error: error));
    final aps = <WifiScanResult>[];
    final done = Completer<void>();
    final sub = transport.scanResults.listen((r) {
      // Completion is a property of index/total, so it is decided FIRST
      // and unconditionally: a result we choose not to display is still
      // a result, and if it is the last one it still ends the scan.
      // (Getting this order wrong hung the picker until the 12 s budget.)
      if (r.index >= r.total - 1 && !done.isCompleted) {
        done.complete();
      }
      // A mesh reports the same SSID once per node — three "Home_WiFi"
      // rows differing only in signal is a worse list, not a richer one.
      // Keep the strongest, and drop hidden networks (empty SSID), which
      // cannot be selected anyway; manual entry covers those.
      if (r.ssid.isEmpty) {
        return;
      }
      final at = aps.indexWhere((e) => e.ssid == r.ssid);
      if (at < 0) {
        aps.add(r);
      } else if (r.rssi > aps[at].rssi) {
        aps[at] = r;
      } else {
        return;
      }
      _to(WizardPickNetwork(networks: List.of(aps), error: error));
    });
    try {
      await transport.startWifiScan();
      // An empty scan answers nothing at all, so the budget is what ends
      // it — the wizard must not wait forever for a list that is empty.
      await Future.any([done.future, _delay(const Duration(seconds: 12))]);
    } on Object {
      // fall through: an empty list with a next step beats an error
    }
    await sub.cancel();
    _to(WizardPickNetwork(networks: aps, scanning: false, error: error));
  }

  /// A picked network, or a manually typed SSID for a hidden one.
  void pickNetwork(String ssid, {int auth = 3}) {
    _ssid = ssid;
    _auth = auth;
  }

  Future<void> submitCredentials(String psk) => _applyConfig(psk: psk);

  Future<void> _applyConfig({String psk = ''}) async {
    _to(WizardHandoff(HandoffPhase.applying, mode: _mode));
    final hosted = _mode == BridgeMode.hosted;
    try {
      final r = await transport.applyWifiConfig(
        mode: hosted ? NetMode.ap : NetMode.sta,
        ssid: hosted ? '' : _ssid,
        psk: hosted ? '' : psk,
        auth: _auth,
      );
      if (hosted) {
        apPsk = r.detail; // the phone needs it to join
      }
    } on BridgeControlException catch (e) {
      _to(WizardRecover(RecoveryReason.configRefused, detail: e.detail));
      return;
    } on BleException {
      _to(const WizardLinkLost());
      return;
    }
    await _awaitHandoff();
  }

  // ── step 5: handoff ────────────────────────────────────────────────

  /// Watches `net_status` across the transition, then verifies over HTTP.
  /// The BLE link stays up throughout — which is the entire reason a
  /// wrong password is recoverable from a lawn chair (§5.7).
  Future<void> _awaitHandoff() async {
    _to(WizardHandoff(HandoffPhase.connecting, mode: _mode));

    final settled = Completer<NetState>();
    NetStatus? settledStatus;
    final sub = transport.netStatus.listen((n) {
      final s = n.stateEnum;
      if (kDebugMode) {
        debugPrint(
          'WIZ net_status ${s?.name} ip=${n.ip.join('.')} '
          'ssid=${n.ssid}',
        );
      }
      if ((s == NetState.up || s == NetState.failed) && !settled.isCompleted) {
        settledStatus = n;
        settled.complete(s!);
      }
    });
    NetState? outcome;
    await Future.any([
      settled.future.then((s) => outcome = s),
      _delay(kHandoffBudget),
    ]);
    await sub.cancel();

    // No transition arrived. That is NOT the same as failure: applying a
    // config the bridge is already running is a no-op on the device, so
    // there is nothing for it to notify. Notifications report changes —
    // ask for the current state rather than assuming the worst.
    //
    // BOARD-FOUND: re-provisioning an already-joined bridge sat here for
    // the full 20 s and then reported "the bridge joined but we cannot
    // reach it", about a bridge that was serving HTTP the whole time.
    if (outcome == null) {
      try {
        final now = await transport.readNetStatus();
        if (now.stateEnum == NetState.up) {
          settledStatus = now;
          outcome = NetState.up;
        } else if (now.stateEnum == NetState.failed) {
          outcome = NetState.failed;
        }
      } on Object {
        // Unreadable: fall through to the recovery state below.
      }
    }

    if (kDebugMode) {
      debugPrint(
        'WIZ handoff settled=${outcome?.name} '
        'hint=${_ipOf(settledStatus)}',
      );
    }
    if (outcome == NetState.failed) {
      // Almost always a wrong password. Back to the network step with the
      // reason stated — never a spinner (A8.3's done-when).
      _to(const WizardRecover(RecoveryReason.wifiFailed));
      return;
    }
    if (outcome == null) {
      _to(const WizardRecover(RecoveryReason.httpUnreachable));
      return;
    }

    if (_mode == BridgeMode.hosted) {
      _to(WizardHandoff(HandoffPhase.joiningAp, mode: _mode));
      final joiner = joinAp;
      final ssid = 'SmokeBridge-${_bridge?.name.split('-').last ?? ''}';
      if (joiner != null && !await joiner(ssid, apPsk ?? '')) {
        _to(const WizardRecover(RecoveryReason.httpUnreachable));
        return;
      }
    }

    _to(WizardHandoff(HandoffPhase.verifying, mode: _mode));
    // A real /status 200 before declaring victory. `net_status: up` means
    // the radio associated; it does not mean the app can reach it.
    String? baseUrl;
    await Future.any([
      verify(_ipOf(settledStatus)).then((u) => baseUrl = u),
      _delay(kHandoffBudget),
    ]);
    if (kDebugMode) {
      debugPrint('WIZ verify -> ${baseUrl ?? "NOTHING"}');
    }
    if (baseUrl == null) {
      _to(const WizardRecover(RecoveryReason.httpUnreachable));
      return;
    }
    _to(WizardDone(mode: _mode, baseUrl: baseUrl!));
  }

  /// The dotted-quad from a `net_status`, or null when it carried none
  /// (0.0.0.0 means "not assigned", not "the address is zero").
  static String? _ipOf(NetStatus? n) {
    final ip = n?.ip;
    if (ip == null || ip.length != 4 || ip.every((o) => o == 0)) {
      return null;
    }
    return ip.join('.');
  }

  // ── recovery (§5.7's escape hatch) ─────────────────────────────────

  /// One `wifi_config{mode: AP}` write over the still-connected BLE link.
  Future<void> revertToHosting() async {
    _mode = BridgeMode.hosted;
    await _applyConfig();
  }

  /// Back to the network step with the reason stated, so the user can
  /// correct the password rather than guess.
  Future<void> retryCredentials() async {
    final reason = _state is WizardRecover
        ? (_state as WizardRecover).reason
        : null;
    _mode = BridgeMode.joined;
    await scanNetworks(
      error: switch (reason) {
        RecoveryReason.wifiFailed => 'Incorrect password for $_ssid',
        RecoveryReason.configRefused => 'The bridge refused that network',
        _ => 'The bridge joined but could not be reached',
      },
    );
  }

  Future<void> dispose() async {
    await _connSub?.cancel();
    await _states.close();
  }
}
