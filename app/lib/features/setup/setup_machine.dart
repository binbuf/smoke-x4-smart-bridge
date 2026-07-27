/// A23.1 — the setup state machine for the three hops (design 13 §13.2,
/// §13.5.1).
///
/// This replaces `features/onboarding/wizard.dart` and is modelled exactly on
/// its discipline (05 §5.7 lineage), but covers the FULL flow the old wizard
/// lacked — a preflight gate (§13.2.0), the four bond outcomes as distinct
/// states (§13.2.1), and above all **hop 2, bridge ↔ Smoke X** (§13.2.2),
/// which `wizard.dart` has no step for at all.
///
/// **Three rails, obeyed here:**
/// - **R2 — no state without a next step.** Every `SetupState` below has at
///   least one `SetupMachine` method that advances it. A spinner that never
///   resolves is the one outcome this machine may not produce (§13.1 #5).
/// - **R3 — no raw exception escapes.** Every public async method runs through
///   [_run], which turns any un-modelled throw into [SetupFault] rather than
///   the full-screen crash page (§13.2.3's `TimeoutException` trap).
/// - **Failure edges are first-class states.** Bond rejected, base not heard,
///   Wi-Fi wrong-password, link lost: each names its own cause so the copy can
///   say which (§13.1 #5 is exactly the collapse of six causes into one line).
///
/// **`_flowGen`** is the wizard's `_scanGen` lesson generalised: a monotonic
/// counter bumped by [restart]/[cancel]/[dispose], checked after every await
/// in every loop, so a late async completion from a superseded flow can never
/// drag the user backwards (`wizard.dart:246` BOARD-FOUND).
///
/// **`_inFlight`** gates every public async method against the double-tap that
/// today overwrites the selected device mid-connect (§13.2.1).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../data/dto/records.g.dart'
    show NetMode, NetState, NetStatus, WifiScanResult;
import '../../data/transport/ble_gatt.dart';
import '../../data/transport/ble_transport.dart';
import '../../data/transport/bridge_transport.dart' show ControlCommand;
import 'copy/base_sync_copy.dart';
import 'preflight.dart';
import 'setup_stage.dart';

// ════════════════════════════════════════════════════════════════════════
//  The SetupState contract — the sealed hierarchy other agents build
//  screens against. Names and fields here are STABLE (§13.5.1).
// ════════════════════════════════════════════════════════════════════════

/// One node of the guided-setup flow (§13.2). Sealed, so a `switch` over
/// states is exhaustive and adding a state without a screen fails analysis.
///
/// Every state exposes [hop] (0–3, for `SetupRail` rendering, §14.7.4) and
/// [stage] (the coarse [SetupStage] to persist as `setupResumeAt`, §13.2.4).
sealed class SetupState {
  const SetupState();

  /// Which of the three hops the rail should highlight — 0 for a preflight
  /// precondition (§13.2.0: "a preflight failure is a precondition, not a bad
  /// hop", so all three circles render inactive).
  int get hop;

  /// The coarse coordinate this state persists as (§13.2.4).
  SetupStage get stage;
}

/// Hop 0 — preflight (§13.2.0). All render `SetupRail(hop: 0)`.
sealed class PreflightState extends SetupState {
  const PreflightState();
  @override
  int get hop => 0;
  @override
  SetupStage get stage => SetupStage.preflight;
}

/// Check 2 (§13.2.0) — the rationale screen shown BEFORE the OS prompt.
/// Not optional: `permission_handler` cannot tell first-denial from permanent,
/// and Android stops showing the dialog after two refusals forever.
/// Next: [SetupMachine.continueFromPrimer] (primary) · [SetupMachine.cancel].
class SetupPermissionPrimer extends PreflightState {
  const SetupPermissionPrimer();
}

/// Check 4 (§13.2.0), and the whole-lifetime adapter watcher: Bluetooth is
/// off. [resumeAt] records where to return when the adapter comes back, so a
/// mid-flow toggle is not the unbreakable loop it is today.
/// Next: [SetupMachine.enableBluetooth] (primary) · open Bluetooth settings.
class SetupBluetoothOff extends PreflightState {
  const SetupBluetoothOff({this.resumeAt = SetupStage.findBridge});
  final SetupStage resumeAt;
  @override
  SetupStage get stage => resumeAt;
}

/// Check 0 (§13.2.0) — no BLE hardware. **Terminal**: [isTerminal] is true and
/// there is deliberately no in-app next step. The copy directs the user to
/// read the SSID/PSK off the OLED, because a phone with no BLE cannot learn
/// them any other way.
class SetupBluetoothUnsupported extends PreflightState {
  const SetupBluetoothUnsupported();
  bool get isTerminal => true;
}

/// Check 3 (§13.2.0). [permanent] true → the dialog will never show again, so
/// the only route is app settings; false → "Allow" can prompt again.
/// Next: [SetupMachine.continueFromPrimer] (retry) or open app settings.
class SetupPermissionDenied extends PreflightState {
  const SetupPermissionDenied({required this.permanent});
  final bool permanent;
}

/// Check 1 (§13.2.0, Android SDK ≤ 32 only). Next: open location settings ·
/// [SetupMachine.recheckPreflight] ("I turned it on").
class SetupLocationServicesOff extends PreflightState {
  const SetupLocationServicesOff();
}

/// Hop 1 — phone ↔ bridge over BLE (§13.2.1). All render `SetupRail(hop: 1)`.
sealed class Hop1State extends SetupState {
  const Hop1State();
  @override
  int get hop => 1;
}

/// The radar/find list (§13.2.1). [found] is blob-decorated before any
/// connection exists — the whole point of the §2.3 advertising blob.
/// Next: [SetupMachine.select] a row · [SetupMachine.cancel].
class SetupScanning extends Hop1State {
  const SetupScanning({this.found = const [], this.scanning = true});
  final List<BridgeDiscovery> found;
  final bool scanning;
  @override
  SetupStage get stage => SetupStage.findBridge;
}

/// 10 s, nothing found (§13.2.1) — a checklist of the bridge's own tells, not
/// "check that it is powered on".
/// Next: [SetupMachine.startScan] ("Look again") · enter the address manually.
class SetupNoBridges extends Hop1State {
  const SetupNoBridges();
  @override
  SetupStage get stage => SetupStage.findBridge;
}

/// The already-provisioned fork (§13.2.1): a bridge already on the network,
/// adding a second phone in ~15 s. Reached when the blob says paired + net up.
/// Next: [SetupMachine.confirmAddThisPhone].
class SetupAddThisPhone extends Hop1State {
  const SetupAddThisPhone(this.bridge);
  final BridgeDiscovery bridge;
  @override
  SetupStage get stage => SetupStage.findBridge;
}

/// The passkey screen (§13.2.1) — the highest-value screen in the app. It does
/// not host a six-digit field; it points at the bridge's OLED. [passkeyShown]
/// flips true once the bond procedure is underway (the OS dialog is up).
/// Next: [SetupMachine.passkeyNotSeen] (30 s timer) · [SetupMachine.cancel].
class SetupPairing extends Hop1State {
  const SetupPairing({required this.bridge, this.passkeyShown = false});
  final BridgeDiscovery bridge;
  final bool passkeyShown;
  @override
  SetupStage get stage => SetupStage.pair;
}

/// 30 s with no OS prompt (§13.2.1): "some phones put it in the notification
/// shade". Next: check notifications · [SetupMachine.retryPasskey].
class SetupPasskeyNotSeen extends Hop1State {
  const SetupPasskeyNotSeen(this.bridge);
  final BridgeDiscovery bridge;
  @override
  SetupStage get stage => SetupStage.pair;
}

/// Bond succeeded — its own 3 s payoff (§13.2.1). Next: auto-advance to hop 2
/// via [SetupMachine.startHop2].
class SetupBonded extends Hop1State {
  const SetupBonded(this.bridge);
  final BridgeDiscovery bridge;
  @override
  SetupStage get stage => SetupStage.pair;
}

/// Bond outcome 1 of 4 (§13.2.1): the entered passkey did not match. Retrying
/// is a five-step choreography, not a retry — see [SetupMachine.retryPasskey].
class SetupPasskeyWrong extends Hop1State {
  const SetupPasskeyWrong(this.bridge);
  final BridgeDiscovery bridge;
  @override
  SetupStage get stage => SetupStage.pair;
}

/// Bond outcome 2 of 4 (§13.2.1): the bridge was factory-reset since we
/// bonded. The fix is distinct from "retry" — forget the pairing, then resume.
/// Next: open Bluetooth settings · [SetupMachine.retryPasskey].
class SetupRebondNeeded extends Hop1State {
  const SetupRebondNeeded(this.bridge);
  final BridgeDiscovery bridge;
  @override
  SetupStage get stage => SetupStage.pair;
}

/// Bond outcome 3 of 4 (§13.2.1): all three bond slots are taken. Detected
/// from the blob BEFORE connecting (`bonds_full`, §13.8.3). Next: remove a
/// phone (op 15) · choose a different bridge.
class SetupBondSlotsFull extends Hop1State {
  const SetupBondSlotsFull(this.bridge);
  final BridgeDiscovery bridge;
  @override
  SetupStage get stage => SetupStage.pair;
}

/// Bond outcome 4 of 4 (§13.2.1): the device does not expose the Bridge
/// Control Service. **No retry button on an unretryable failure** ([isTerminal]).
/// Next: [SetupMachine.startScan] to choose a different device.
class SetupNotABridge extends Hop1State {
  const SetupNotABridge(this.bridge);
  final BridgeDiscovery bridge;
  bool get isTerminal => true;
  @override
  SetupStage get stage => SetupStage.pair;
}

/// Hop 2 — bridge ↔ Smoke X over LoRa (§13.2.2). All render `SetupRail(hop: 2)`
/// and persist [SetupStage.baseListen].
sealed class Hop2State extends SetupState {
  const Hop2State();
  @override
  int get hop => 2;
  @override
  SetupStage get stage => SetupStage.baseListen;
}

/// The illustrated SYNC-hold instruction (§13.2.2). Copy in [BaseSyncCopy].
/// Next: [SetupMachine.startBaseListen] · [SetupMachine.skipBase].
class SetupBaseIntro extends Hop2State {
  const SetupBaseIntro();
}

/// A listen window is open (§13.2.2). [elapsed] is counted LOCALLY from the
/// state-change timestamp (a 1 Hz notify for a progress ring is not worth the
/// radio). [garbled] 1–3 renders "move closer"; >3 becomes a failure.
/// Next: [SetupMachine.cancel]. Budget: [BaseSyncTiming.listenBudget].
class SetupBaseListening extends Hop2State {
  const SetupBaseListening({required this.elapsed, this.garbled = 0});
  final Duration elapsed;
  final int garbled;
}

/// SYNC_RECEIVED (§13.2.2): the beacon decoded and the ACK was sent, now
/// narrating the real ~30 s wait for the base's first reading (not a spinner).
class SetupBaseHeard extends Hop2State {
  const SetupBaseHeard({this.deviceId});
  final String? deviceId;
}

/// The payoff (§13.2.2): a real temperature on screen. [temps] is F10 per
/// probe, null = detached — the same sentinel discipline as everywhere else.
/// Next: [SetupMachine.continueFromConfirmed].
class SetupBaseConfirmed extends Hop2State {
  const SetupBaseConfirmed({
    required this.deviceId,
    required this.numProbes,
    required this.temps,
  });
  final String deviceId;
  final int numProbes;
  final List<int?> temps;
}

/// The non-punitive skip (§13.2.2): finishes hop 2 unpaired and drops a
/// resumable card. Next: [SetupMachine.continueToNetwork].
class SetupBaseSkipped extends Hop2State {
  const SetupBaseSkipped();
}

/// A listen window ended without a confirm (§13.2.2). [reason] carries which,
/// so the copy differs by cause ([BaseSyncCopy.failureHeadline]). `ackFailed`
/// is auto-retried by the machine; the rest offer "Try again".
/// Next: [SetupMachine.retryBaseListen] · [SetupMachine.skipBase].
class SetupBaseFailed extends Hop2State {
  const SetupBaseFailed({required this.reason, this.garbled = 0});
  final BaseSyncFailure reason;
  final int garbled;
}

/// Hop 3 — bridge ↔ network over Wi-Fi (§13.2.3). All render `SetupRail(hop: 3)`.
sealed class Hop3State extends SetupState {
  const Hop3State();
  @override
  int get hop => 3;
}

/// The network picker (§13.2.3), pre-warmed during hop 2 so it is instant.
/// [failureCount] ≥ 2 makes hosted the primary. Rows: `auth == 0` → straight
/// to applying; `auth == 5` (enterprise) → disabled.
/// Next: [SetupMachine.pickNetwork] · [SetupMachine.openManualEntry] ·
/// [SetupMachine.chooseHosted] · [SetupMachine.skipNetwork].
class SetupNetworkPick extends Hop3State {
  const SetupNetworkPick({
    this.networks = const [],
    this.scanning = true,
    this.failureCount = 0,
  });
  final List<WifiScanResult> networks;
  final bool scanning;
  final int failureCount;
  bool get isEmpty => !scanning && networks.isEmpty;
  @override
  SetupStage get stage => SetupStage.network;
}

/// The scan found nothing (§13.2.3): hosted becomes the primary automatically.
/// Next: [SetupMachine.chooseHosted] · [SetupMachine.startNetworkScan].
class SetupNetworkEmpty extends Hop3State {
  const SetupNetworkEmpty();
  @override
  SetupStage get stage => SetupStage.network;
}

/// Join a hidden network (§13.2.3): an SSID field AND an auth dropdown, so a
/// hidden open network is joinable and a keystroke does not downgrade WPA3.
/// Next: [SetupMachine.submitManual].
class SetupNetworkManual extends Hop3State {
  const SetupNetworkManual();
  @override
  SetupStage get stage => SetupStage.network;
}

/// The password screen (§13.2.3) — its own screen, one job. On retry the field
/// is [prefill]ed and revealed, and [error] states the reason, because
/// `ssid`/`psk`/`auth` live on the machine, not in disposed widget state.
/// Next: [SetupMachine.submitPassword].
class SetupNetworkPassword extends Hop3State {
  const SetupNetworkPassword({
    required this.ssid,
    this.auth = 3,
    this.prefill = '',
    this.error,
  });
  final String ssid;
  final int auth;
  final String prefill;
  final String? error;
  @override
  SetupStage get stage => SetupStage.network;
}

/// The four narrated handoff phases with a cancel (§13.2.3), never one line of
/// text and no actions. [hosted] switches the copy.
/// Next: [SetupMachine.cancel].
class SetupApplying extends Hop3State {
  const SetupApplying({
    required this.phase,
    this.ssid = '',
    this.hosted = false,
  });
  final ApplyingPhase phase;
  final String ssid;
  final bool hosted;
  @override
  SetupStage get stage => SetupStage.applying;
}

/// Wi-Fi failed with a stated reason (§13.2.3), never "wrong password" for all
/// six causes. [attempts] ≥ 2 makes hosted the primary.
/// Next: [SetupMachine.submitPassword] (retry) · [SetupMachine.chooseHosted].
class SetupWifiFailed extends Hop3State {
  const SetupWifiFailed({
    required this.reason,
    this.ssid = '',
    this.attempts = 1,
  });
  final WifiFailure reason;
  final String ssid;
  final int attempts;
  @override
  SetupStage get stage => SetupStage.network;
}

/// Joined, but this phone cannot see it (§13.2.3): `net_status: up` means the
/// radio associated, not that the app can reach the bridge. The [ip] is shown,
/// never hidden. Next: [SetupMachine.retryVerify] · [SetupMachine.chooseHosted].
class SetupUnreachable extends Hop3State {
  const SetupUnreachable({required this.ip});
  final String ip;
  @override
  SetupStage get stage => SetupStage.applying;
}

/// Hosted mode is up (§13.2.3): the bridge is hosting [ssid]/[psk], which are
/// on screen because OEM join behaviour varies (05 §5.8.2).
/// Next: [SetupMachine.joinHostedAp] · [SetupMachine.hostedJoinedManually].
class SetupHostedJoin extends Hop3State {
  const SetupHostedJoin({required this.ssid, required this.psk});
  final String ssid;
  final String psk;
  @override
  SetupStage get stage => SetupStage.applying;
}

/// The AP join was refused, or the switch to AP never came up (§13.2.3). The
/// credentials are still shown so the user can join manually.
/// Next: [SetupMachine.joinHostedAp] (retry) · [SetupMachine.hostedJoinedManually].
class SetupHostedRefused extends Hop3State {
  const SetupHostedRefused({required this.ssid, required this.psk});
  final String ssid;
  final String psk;
  @override
  SetupStage get stage => SetupStage.applying;
}

/// The landing (§13.2.4). Both persist [SetupStage.done].
sealed class FinishState extends SetupState {
  const FinishState();
  @override
  int get hop => 3;
  @override
  SetupStage get stage => SetupStage.done;
}

/// Name + units, asked once (§13.2.4). Next: [SetupMachine.submitNameAndUnits].
class SetupNameAndUnits extends FinishState {
  const SetupNameAndUnits({this.suggestedName = ''});
  final String suggestedName;
}

/// The three-row summary (§13.2.4), a skipped hop shown as "— not set up".
/// Next: [SetupMachine.reset] / navigate to the Cook tab (screen concern).
class SetupDone extends FinishState {
  const SetupDone(this.summary);
  final SetupSummary summary;
}

/// A24.2 — the bridge was factory-reset over Bluetooth. It is now unprovisioned
/// and unbonded; this phone holds a stale OS pairing to forget before re-setup.
/// Next: [SetupMachine.restart] (set it up fresh) · leave setup.
class SetupResetDone extends FinishState {
  const SetupResetDone({this.bridgeName = ''});
  final String bridgeName;
}

/// The BLE link died mid-flow (§13.2.0 / §13.2.3). Every non-terminal state
/// can reach this; it always offers reconnect-or-restart, never a strand.
/// [resumeAt] is where to return on reconnect.
/// Next: [SetupMachine.reconnect] · [SetupMachine.restart].
class SetupLinkLost extends SetupState {
  const SetupLinkLost({this.resumeAt = SetupStage.findBridge});
  final SetupStage resumeAt;
  @override
  int get hop => hopForStage(resumeAt);
  @override
  SetupStage get stage => resumeAt;
}

/// The rail R3 backstop (§13.5.1): an un-modelled exception was caught here
/// rather than escaping to the crash page. Next: [SetupMachine.restart].
class SetupFault extends SetupState {
  const SetupFault({this.detail = ''});
  final String detail;
  @override
  int get hop => 0;
  @override
  SetupStage get stage => SetupStage.preflight;
}

/// The rail hop for a coarse [SetupStage] (§13.2). Used by [SetupLinkLost].
int hopForStage(SetupStage s) => switch (s) {
  SetupStage.preflight => 0,
  SetupStage.findBridge || SetupStage.pair => 1,
  SetupStage.baseListen => 2,
  SetupStage.network || SetupStage.applying || SetupStage.done => 3,
};

// ── enums and value types the states carry ──────────────────────────────

/// The four narrated rows of [SetupApplying] (§13.2.3), plus the hosted join.
enum ApplyingPhase {
  /// "Sent your network to the bridge".
  sent,

  /// "The bridge is joining `<ssid>`".
  joining,

  /// "Getting an address".
  gettingAddress,

  /// Hosted only: the phone is joining the bridge's AP.
  joiningAp,

  /// "Checking this phone can reach it".
  checking,
}

/// The Wi-Fi failure reason (§13.2.3), the `net_status.reason` byte named
/// (§13.8.3). Six distinct causes that today all read as "wrong password".
enum WifiFailure { wrongPassword, notFound, assocRefused, noIp, weakSignal }

/// The Smoke X pairing state (§13.8.2 `pair_state`), 1:1 with the firmware's
/// `smoke_x_ctrl_state()`.
enum BasePairState { unpaired, listening, heard, confirmed }

/// A single reading of the hop-2 listen seam (§13.8.2 `pair_status`), the
/// value the future `pair_status` characteristic will carry. [failure] is set
/// only on a terminal seam-reported failure (e.g. `ack_failed`).
class BasePairSnapshot {
  const BasePairSnapshot({
    required this.state,
    this.deviceId,
    this.numProbes = 0,
    this.temps = const [null, null, null, null],
    this.garbled = 0,
    this.rssi = 0,
    this.failure,
  });
  final BasePairState state;
  final String? deviceId;
  final int numProbes;
  final List<int?> temps;
  final int garbled;
  final int rssi;
  final BaseSyncFailure? failure;
}

/// The three-row summary rendered by [SetupDone] (§13.2.4). A null/false field
/// is a skipped hop, shown as "— not set up".
class SetupSummary {
  const SetupSummary({
    this.bridgeName = '',
    this.bridgeId,
    this.bleDeviceId,
    this.blePaired = false,
    this.baseDeviceId,
    this.baseNumProbes = 0,
    this.wifiSsid,
    this.ip,
    this.hosted = false,
    this.apPsk,
    this.unitsCelsius = false,
  });
  final String bridgeName;
  final String? bridgeId;

  /// A25 — the OS address of the bonded bridge. Persisted so the BLE lane can
  /// *connect* on the next launch; without it a Bluetooth-only setup left the
  /// app with nothing to dial and it bounced back into onboarding.
  final String? bleDeviceId;
  final bool blePaired;
  final String? baseDeviceId;
  final int baseNumProbes;
  final String? wifiSsid;
  final String? ip;
  final bool hosted;
  final String? apPsk;
  final bool unitsCelsius;

  SetupSummary copyWith({
    String? bridgeName,
    String? bridgeId,
    String? bleDeviceId,
    bool? blePaired,
    String? baseDeviceId,
    int? baseNumProbes,
    String? wifiSsid,
    String? ip,
    bool? hosted,
    String? apPsk,
    bool? unitsCelsius,
  }) => SetupSummary(
    bridgeName: bridgeName ?? this.bridgeName,
    bridgeId: bridgeId ?? this.bridgeId,
    bleDeviceId: bleDeviceId ?? this.bleDeviceId,
    blePaired: blePaired ?? this.blePaired,
    baseDeviceId: baseDeviceId ?? this.baseDeviceId,
    baseNumProbes: baseNumProbes ?? this.baseNumProbes,
    wifiSsid: wifiSsid ?? this.wifiSsid,
    ip: ip ?? this.ip,
    hosted: hosted ?? this.hosted,
    apPsk: apPsk ?? this.apPsk,
    unitsCelsius: unitsCelsius ?? this.unitsCelsius,
  );
}

// ── injected seams (the wizard's discipline, §13.5.1) ───────────────────

/// Verifies the bridge over HTTP after the transition, returning the winning
/// base URL or null. [ipHint] is the address `net_status` just reported — on
/// Android it is usually the only one that can work (mDNS `.local` does not
/// resolve through Dart's HttpClient). Must not throw. (`wizard.dart:160`.)
typedef HandoffVerifier = Future<String?> Function(String? ipHint);

/// Joins the bridge's AP with credentials already in hand, through A14.1's
/// binder. Must not throw; returns success (`wizard.dart:164`).
typedef ApJoiner = Future<bool> Function(String ssid, String psk);

/// The injectable clock's delay, so every budget is a `Future.any` a test can
/// hold open and fire deliberately (`wizard.dart:166`).
typedef SetupDelay = Future<void> Function(Duration d);

/// Maps a `failed` `net_status` to a [WifiFailure]. The real classifier reads
/// the `net_status.reason` byte (§13.8.3); it is injectable so each of the six
/// reasons is reachable in tests before that byte exists on the wire.
/// Default: [WifiFailure.wrongPassword] (the ESP 15/202/204 majority case).
typedef WifiFailureClassifier = WifiFailure Function(NetStatus status);

/// The hop-2 listen seam (§13.2.2).
///
/// `pair_status` (the BLE characteristic, §13.8.2) **does not exist in firmware
/// yet**, so hop 2 cannot subscribe to a real notify. Until it lands, the
/// machine drives progress off this seam: a non-destructive listen window plus
/// a stream of state-change snapshots. The real notify plugs into [updates].
abstract interface class BaseListenSeam {
  /// Begins a NON-DESTRUCTIVE listen window (§13.2.2) — `POST /pairing/listen`
  /// / the future `smoke_x_ctrl_listen(window_ms)`. **A button labelled "Pair"
  /// must never unpair**: the existing NVS binding stays and is restored if the
  /// window expires. Must not throw.
  Future<void> startListen({required Duration window});

  /// State-change snapshots for the open window.
  // NEEDS pair_status char (13 §13.8.2) — the real notify replaces the poller
  // that currently fills this stream; nothing else in the machine changes.
  Stream<BasePairSnapshot> get updates;

  /// Tears the window down early (cancel/restart). Must not throw.
  Future<void> cancel();
}

// ── tunable budgets (some unmeasured; see markers) ──────────────────────

/// §5.7: HTTP unreachable after this is the recovery state, not failure.
const Duration kHandoffBudget = Duration(seconds: 20);

/// The Wi-Fi scan budget — an empty scan answers nothing, so the budget is
/// what ends it (`wizard.dart:398`).
const Duration kScanBudget = Duration(seconds: 12);

/// Pre-warmed networks older than this are re-scanned on picker entry
/// (§13.2.3).
const Duration kScanFreshness = Duration(seconds: 90);

/// **[?] unmeasured** (§13.2.3, bench M8 W0/V6.3): the grace across the
/// ESP32-S3 Wi-Fi reconfigure, during which a brief BLE drop is expected and
/// link-lost is suppressed.
const Duration kApplyGraceMs = Duration(seconds: 5);

/// How many times `ack_failed` auto-retries before it becomes a user action.
const int kAckRetryCap = 2;

// ════════════════════════════════════════════════════════════════════════
//  The machine
// ════════════════════════════════════════════════════════════════════════

class SetupMachine {
  SetupMachine({
    required this.transport,
    required this.client,
    required this.probe,
    required this.listen,
    required this.verify,
    this.joinAp,
    this.nowMs,
    WifiFailureClassifier? classify,
    SetupDelay? delay,
  }) : _preflight = SetupPreflight(probe),
       _classify = classify ?? ((_) => WifiFailure.wrongPassword),
       _delay = delay ?? ((d) => Future<void>.delayed(d));

  final BleTransport transport;
  final BleGattClient client;
  final PreflightProbe probe;
  final BaseListenSeam listen;
  final HandoffVerifier verify;
  final ApJoiner? joinAp;

  /// Wall clock, injected so the base-listen elapsed count and the `set_time`
  /// write are assertable rather than "whatever the test machine thinks".
  final int Function()? nowMs;

  final SetupPreflight _preflight;
  final WifiFailureClassifier _classify;
  final SetupDelay _delay;

  final _states = StreamController<SetupState>.broadcast();
  SetupState _state = const SetupPermissionPrimer();
  StreamSubscription<BleConnectionState>? _connSub;
  StreamSubscription<SetupAdapterState>? _adapterSub;

  SetupState get state => _state;
  Stream<SetupState> get states => _states.stream;

  /// The coarse coordinate the route persists as `setupResumeAt` (§13.2.4).
  SetupStage get currentStage => _state.stage;

  // ── flow-control invariants (§13.5.1) ──────────────────────────────────

  /// Bumped by [restart]/[cancel]/[dispose]; checked after every await so a
  /// superseded flow's late completion cannot transition (`wizard.dart:206`).
  int _flowGen = 0;

  /// Gates every public async method against a double-tap (§13.2.1).
  bool _inFlight = false;

  /// True across a Wi-Fi apply, when a brief BLE drop is expected (§13.2.3).
  bool _applying = false;

  /// True across the stale-bond heal's deliberate disconnect (A24.11), so
  /// [_watchLink] does not mistake our own teardown for a lost link.
  bool _healing = false;

  // ── flow scratch (lives on the machine, never in widget state) ─────────

  BridgeDiscovery? _bridge;
  String? _bridgeId;
  String _ssid = '';
  String _psk = '';
  int _auth = 3;
  String? _apPsk;
  int _wifiFailCount = 0;
  int _ackRetries = 0;

  /// Completed by [cancel]/[restart]/[skipBase] to abort an in-flight listen
  /// window promptly rather than wait out its (real) budget.
  Completer<void>? _abortListen;

  List<WifiScanResult> _prewarm = const [];
  int _prewarmAtMs = 0;

  int _listenStartMs = 0;

  SetupSummary _summary = const SetupSummary();

  int _now() => nowMs?.call() ?? DateTime.now().millisecondsSinceEpoch;

  void _to(SetupState s) {
    if (kDebugMode) {
      debugPrint('SETUP ${_state.runtimeType} -> ${s.runtimeType}');
    }
    _state = s;
    if (!_states.isClosed) {
      _states.add(s);
    }
  }

  /// Every public async method runs through here: it drops re-entrant calls
  /// (R2 double-tap gate) and converts any un-modelled throw into [SetupFault]
  /// (R3 — no raw exception escapes).
  Future<void> _run(Future<void> Function() body) async {
    if (_inFlight) {
      return;
    }
    _inFlight = true;
    try {
      await body();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('SETUP fault: $e\n$st');
      }
      _to(SetupFault(detail: e.toString()));
    } finally {
      _inFlight = false;
    }
  }

  /// Watched from one place so no step has to remember to (`wizard.dart:226`).
  void _watchLink() {
    _connSub ??= client.connectionStates.listen((s) {
      if (s != BleConnectionState.disconnected) {
        return;
      }
      if (_applying) {
        return; // expected across the radio reconfigure (kApplyGraceMs)
      }
      if (_healing) {
        return; // the stale-bond heal disconnects on purpose (A24.11)
      }
      if (_isTerminal(_state)) {
        return;
      }
      _to(SetupLinkLost(resumeAt: currentStage));
    });
  }

  /// `adapterStates` is subscribed for the WHOLE setup lifetime (§13.2.0), so
  /// Bluetooth switched off at hop 3 resumes rather than dead-loops.
  void _watchAdapter() {
    _adapterSub ??= probe.adapterStates.listen((s) {
      if (_isTerminal(_state)) {
        return;
      }
      if (s == SetupAdapterState.off) {
        if (_state is! SetupBluetoothOff) {
          _to(SetupBluetoothOff(resumeAt: currentStage));
        }
        return;
      }
      if (s == SetupAdapterState.on && _state is SetupBluetoothOff) {
        final resumeAt = (_state as SetupBluetoothOff).resumeAt;
        unawaited(_resume(resumeAt));
      }
    });
  }

  /// Wakes an in-flight [_listenOnce] so it returns at once (the gen check in
  /// the loop then discards the superseded window).
  void _abort() {
    final c = _abortListen;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }

  bool _isTerminal(SetupState s) =>
      s is SetupDone ||
      (s is SetupBluetoothUnsupported && s.isTerminal) ||
      (s is SetupNotABridge && s.isTerminal);

  // ══ entry / preflight (hop 0, §13.2.0) ═════════════════════════════════

  /// The single entry point. Subscribes the lifetime adapter watcher, then
  /// runs preflight; a clear gate advances straight into hop 1.
  Future<void> start() => _run(() async {
    _watchAdapter();
    final gate = await _preflight.evaluate();
    if (gate != null) {
      _to(gate);
      return;
    }
    await _startScan();
  });

  /// The primer's "Continue" (§13.2.0 check 2): prompt, then evaluate 3 and 4.
  Future<void> continueFromPrimer() => _run(() async {
    final gate = await _preflight.continueFromPrimer();
    if (gate != null) {
      _to(gate);
      return;
    }
    await _startScan();
  });

  /// "I turned it on" / returning from settings — re-run the whole gate.
  Future<void> recheckPreflight() => _run(() async {
    final gate = await _preflight.evaluate();
    if (gate != null) {
      _to(gate);
      return;
    }
    await _startScan();
  });

  /// [SetupBluetoothOff] primary: ask the OS to enable Bluetooth, then
  /// re-check. The lifetime watcher also catches the adapter coming back.
  Future<void> enableBluetooth() => _run(() async {
    final resumeAt = _state is SetupBluetoothOff
        ? (_state as SetupBluetoothOff).resumeAt
        : SetupStage.findBridge;
    await probe.requestEnable();
    final gate = _preflight.adapterGate(resumeAt: resumeAt);
    if (gate != null) {
      _to(gate);
      return;
    }
    await _resume(resumeAt);
  });

  /// Routes to the entry of a coarse stage (adapter-back / reconnect resume).
  Future<void> _resume(SetupStage stage) async {
    switch (stage) {
      case SetupStage.preflight:
      case SetupStage.findBridge:
      case SetupStage.pair:
        await _startScan();
      case SetupStage.baseListen:
        _to(const SetupBaseIntro());
      case SetupStage.network:
      case SetupStage.applying:
        await _enterNetwork();
      case SetupStage.done:
        break;
    }
  }

  // ══ hop 1 — find + pair (§13.2.1) ══════════════════════════════════════

  /// NOT gated by [_inFlight]: a scan is a long-lived background listener, not
  /// a one-shot action, so gating it would block [select] (and be the very
  /// double-tap bug §13.2.1 warns of, inverted). A finite scan settles when
  /// awaited; a continuous one the caller unawaits. Still guarded by [_flowGen]
  /// and wrapped so no throw escapes (R3).
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      await _startScan(timeout: timeout);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('SETUP fault: $e\n$st');
      }
      _to(SetupFault(detail: e.toString()));
    }
  }

  Future<void> _startScan({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _to(const SetupScanning());
    final gen = ++_flowGen;
    final found = <BridgeDiscovery>[];

    // BOARD-FOUND (`wizard.dart:246`): a real scan stream keeps emitting after
    // the user has moved on; every publish is gated on "still our scan, still
    // on the find step".
    bool stillOurs() => gen == _flowGen && _state is SetupScanning;

    try {
      await for (final adv in client.scan(timeout: timeout)) {
        if (!stillOurs()) {
          break;
        }
        final d = BridgeDiscovery.fromAdvertisement(adv);
        if (found.every((e) => e.deviceId != d.deviceId)) {
          found.add(d);
          // Sort by RSSI descending (§13.2.1) — strongest first.
          found.sort((a, b) => b.rssi.compareTo(a.rssi));
          _to(SetupScanning(found: List.of(found), scanning: true));
        }
      }
    } on Object {
      // A scan that errors found nothing — a state, not a crash (§13.1 #5).
    }
    if (!stillOurs()) {
      return;
    }
    // Nothing found is its own checklist state, not an empty list (§13.2.1).
    if (found.isEmpty) {
      _to(const SetupNoBridges());
    } else {
      _to(SetupScanning(found: List.of(found), scanning: false));
    }
  }

  /// A tapped row (§13.2.1). The screen passes the blob-derived flags it holds:
  /// [bondSlotsFull] (blob `bonds_full` b5, §13.8.3) and [addThisPhone]
  /// (paired + net up). A guarded single entry point — no double-tap can
  /// overwrite the device mid-connect.
  Future<void> select(
    BridgeDiscovery bridge, {
    bool bondSlotsFull = false,
    bool addThisPhone = false,
  }) => _run(() async {
    _bridge = bridge;
    _flowGen++; // retire the scan before changing step
    try {
      await client.stopScan();
    } on Object {
      // best-effort
    }
    if (bondSlotsFull) {
      _to(SetupBondSlotsFull(bridge));
      return;
    }
    if (addThisPhone) {
      _to(SetupAddThisPhone(bridge));
      return;
    }
    await _connectAndBond(bridge);
  });

  Future<void> _connectAndBond(BridgeDiscovery bridge) async {
    final gen = _flowGen;
    for (var attempt = 0; ; attempt++) {
      _to(SetupPairing(bridge: bridge, passkeyShown: false));
      try {
        _healing = false;
        if (client.connectionState != BleConnectionState.connected) {
          await client.connect(bridge.deviceId);
        }
        _watchLink();
        _to(SetupPairing(bridge: bridge, passkeyShown: true));
        if (client.bondState != BleBondState.bonded) {
          await client.bond();
        }
        await client.requestMtu(247);
        await transport.start();
        // Confirm it really is a bridge (device_info is open, §3) — a device
        // with no Bridge Control Service throws here, which is
        // SetupNotABridge.
        final info = await transport.deviceInfo();
        _bridgeId = info.id;
        // First AUTHENTICATED op on this link — with a stale bond this is
        // exactly where the dead key surfaces (A24.11), so the rebond
        // signal must escape this otherwise best-effort write.
        try {
          await transport.control(ControlCommand.setTime(unixMs: _now()));
        } on BleRebondRequiredException {
          rethrow;
        } on Object {
          // A clock the bridge would not take is not worth stopping for.
        }
        break;
      } on BleBondRejectedException {
        _to(SetupPasskeyWrong(bridge));
        return;
      } on BleRebondRequiredException {
        // The bridge was factory-reset: this phone's OS bond is a dead key
        // Android will silently retry forever instead of showing a new
        // passkey prompt. Heal it — drop the stale bond and pair fresh
        // (A24.11). Only when the platform refuses does the user get the
        // manual route through Bluetooth settings.
        if (attempt == 0 && gen == _flowGen) {
          try {
            _healing = true; // the disconnect below is ours, not a loss
            await client.removeBond();
            await client.disconnect();
            continue;
          } on Object {
            _healing = false;
            // fall through to the manual screen
          }
        }
        _to(SetupRebondNeeded(bridge));
        return;
      } on BleConnectionLostException {
        _to(SetupLinkLost(resumeAt: SetupStage.pair));
        return;
      } on BleStateException {
        _to(SetupNotABridge(bridge));
        return;
      } on BleException {
        _to(SetupPasskeyWrong(bridge));
        return;
      }
    }
    if (gen != _flowGen) {
      return;
    }
    _summary = _summary.copyWith(
      bridgeId: _bridgeId,
      bleDeviceId: bridge.deviceId,
      blePaired: true,
      bridgeName: bridge.name,
    );
    // Proof point (§13.2.4): lastBridgeId/lastBleDeviceId are the route's to
    // persist off this transition — captured on [SetupSummary] and [state].
    _to(SetupBonded(bridge));
  }

  /// The 30 s countdown expired with no OS prompt (§13.2.1). Driven by the
  /// screen's local timer while [SetupPairing] is up.
  void passkeyNotSeen() {
    final b = _bridge;
    if (_state is SetupPairing && b != null) {
      _to(SetupPasskeyNotSeen(b));
    }
  }

  /// "Try again" after a wrong passkey (§13.2.1) — the FIVE-step choreography,
  /// shown as one uninterrupted state: terminate → re-advertise (device side)
  /// → reconnect → re-bond → fresh PASSKEY_SHOW. The user sees one button.
  Future<void> retryPasskey() => _run(() async {
    final bridge = _bridge;
    if (bridge == null) {
      return;
    }
    _to(SetupPairing(bridge: bridge, passkeyShown: false));
    try {
      await client.disconnect();
    } on Object {
      // best-effort teardown
    }
    await _connectAndBond(bridge);
  });

  /// The already-provisioned second-phone flow (§13.2.1): hop 1 only, then read
  /// `net_status` and verify over HTTP — because stopping at the bond leaves
  /// `lastBaseUrl` null and reintroduces failure #1 on this phone's next launch.
  Future<void> confirmAddThisPhone() => _run(() async {
    final bridge = _bridge;
    if (bridge == null) {
      return;
    }
    final gen = _flowGen;
    await _connectAndBond(bridge);
    if (gen != _flowGen || _state is! SetupBonded) {
      return; // a bond outcome already owns the screen
    }
    NetStatus? net;
    try {
      net = await transport.readNetStatus();
    } on Object {
      net = null;
    }
    final ip = _ipOf(net);
    final url = await _verify(ip);
    if (gen != _flowGen) {
      return;
    }
    if (url == null) {
      _to(SetupUnreachable(ip: ip ?? ''));
      return;
    }
    _summary = _summary.copyWith(
      wifiSsid: net?.ssid,
      ip: ip,
      hosted: net?.modeEnum == NetMode.ap,
    );
    _to(SetupNameAndUnits(suggestedName: bridge.name));
  });

  /// A24.2 — wipe the bonded bridge over Bluetooth. The recovery for a bridge
  /// stuck in a stale or unreachable state when the only tool is the phone (no
  /// USB, no hardware reset button): the BLE link is already bonded here, so
  /// the authenticated FACTORY_RESET goes straight over it. Like every
  /// destructive verb the bridge answers *before* it acts and then drops the
  /// link, so a throw is as likely the success path as a failure
  /// (`bridge_tab.dart:107`) — either way it is now resetting.
  Future<void> factoryResetBridge() => _run(() async {
    final name = _bridge?.name ?? '';
    try {
      await transport.control(const ControlCommand.factoryReset());
    } on Object {
      // Answered-then-rebooted; treat as done.
    }
    _to(SetupResetDone(bridgeName: name));
  });

  // ══ hop 2 — bridge ↔ Smoke X (§13.2.2) ═════════════════════════════════

  /// Auto-advance from [SetupBonded] into hop 2's illustrated instruction.
  Future<void> startHop2() => _run(() async {
    _to(const SetupBaseIntro());
  });

  /// "I've done it — start listening" (§13.2.2). Opens a non-destructive listen
  /// window, pre-warms the Wi-Fi scan (§13.2.3), and narrates progress off the
  /// listen seam. `ack_failed` re-arms automatically up to [kAckRetryCap].
  Future<void> startBaseListen() => _run(() async {
    final gen = _flowGen;
    _ackRetries = 0;
    unawaited(_prewarmNetworks(gen)); // §13.2.3: fire on BASE_LISTEN entry
    while (true) {
      final result = await _listenOnce(gen);
      if (gen != _flowGen) {
        return;
      }
      if (result.confirmed) {
        final snap = result.snap!;
        _summary = _summary.copyWith(
          baseDeviceId: snap.deviceId,
          baseNumProbes: snap.numProbes,
        );
        _to(
          SetupBaseConfirmed(
            deviceId: snap.deviceId ?? '',
            numProbes: snap.numProbes,
            temps: snap.temps,
          ),
        );
        return;
      }
      if (result.reason == BaseSyncFailure.ackFailed &&
          _ackRetries < kAckRetryCap) {
        _ackRetries++;
        _to(const SetupBaseFailed(reason: BaseSyncFailure.ackFailed));
        continue; // auto-retry — the bridge could not answer; try again
      }
      _to(SetupBaseFailed(reason: result.reason!, garbled: result.garbled));
      return;
    }
  });

  /// One listen window. Returns confirmation or a failure reason; never throws.
  Future<_ListenResult> _listenOnce(int gen) async {
    _listenStartMs = _now();
    _to(SetupBaseListening(elapsed: Duration.zero));
    final done = Completer<_ListenResult>();
    final abort = _abortListen = Completer<void>();
    var maxGarbled = 0;
    var everHeard = false;

    void finish(_ListenResult r) {
      if (gen == _flowGen && !done.isCompleted) {
        done.complete(r);
      }
    }

    // Subscribe BEFORE opening the window: a snapshot the seam emits the
    // instant the window opens must not be lost to a late listener.
    final sub = listen.updates.listen((snap) {
      if (gen != _flowGen) {
        return;
      }
      if (snap.failure != null) {
        finish(_ListenResult.fail(snap.failure!, snap.garbled));
        return;
      }
      switch (snap.state) {
        case BasePairState.unpaired:
        case BasePairState.listening:
          maxGarbled = math.max(maxGarbled, snap.garbled);
          if (snap.garbled > 3) {
            finish(_ListenResult.fail(BaseSyncFailure.garbled, snap.garbled));
            return;
          }
          _to(
            SetupBaseListening(
              elapsed: _listenElapsed(),
              garbled: snap.garbled,
            ),
          );
        case BasePairState.heard:
          if (!everHeard) {
            everHeard = true;
            // The heard→no-state watchdog: one broadcast period (§13.2.2).
            unawaited(
              _delay(BaseSyncTiming.heardWait).then((_) {
                finish(
                  _ListenResult.fail(
                    BaseSyncFailure.timeoutNoState,
                    maxGarbled,
                  ),
                );
              }),
            );
          }
          _to(SetupBaseHeard(deviceId: snap.deviceId));
        case BasePairState.confirmed:
          finish(_ListenResult.confirmed(snap));
      }
    });

    try {
      await listen.startListen(window: BaseSyncTiming.listenBudget);
    } on Object {
      await sub.cancel();
      return _ListenResult.fail(BaseSyncFailure.timeoutNoBeacon, 0);
    }

    // The overall listen budget bounds the window (§13.2.2). Nothing heard
    // by the deadline is `timeout_no_beacon`; heard-but-not-confirmed is
    // `timeout_no_state`; sustained noise is `garbled`.
    unawaited(
      _delay(BaseSyncTiming.listenBudget).then((_) {
        finish(
          _ListenResult.fail(
            maxGarbled > 3
                ? BaseSyncFailure.garbled
                : (everHeard
                      ? BaseSyncFailure.timeoutNoState
                      : BaseSyncFailure.timeoutNoBeacon),
            maxGarbled,
          ),
        );
      }),
    );

    // Race the outcome against an abort (cancel/restart/skip): a cancelled
    // window must return NOW, not wait out its budget. The loop's gen check
    // then discards it.
    final result = await Future.any([
      done.future,
      abort.future.then(
        (_) => const _ListenResult.fail(BaseSyncFailure.timeoutNoBeacon, 0),
      ),
    ]);
    await sub.cancel();
    try {
      await listen.cancel();
    } on Object {
      // best-effort: the binding is non-destructive either way (§13.2.2)
    }
    return result;
  }

  Duration _listenElapsed() => Duration(milliseconds: _now() - _listenStartMs);

  /// The non-punitive skip (§13.2.2): hop 2 finishes unpaired, and a resumable
  /// card is dropped on the Cook tab (the route's concern).
  Future<void> skipBase() => _run(() async {
    _flowGen++; // supersede any in-flight listen loop
    _abort();
    try {
      await listen.cancel();
    } on Object {
      // best-effort
    }
    _to(const SetupBaseSkipped());
  });

  /// "Try again" after a base-listen failure (§13.2.2): re-arm the instruction
  /// AND the listen, from the top.
  Future<void> retryBaseListen() => _run(() async {
    _to(const SetupBaseIntro());
  });

  /// [SetupBaseConfirmed] "Continue" → hop 3.
  Future<void> continueFromConfirmed() => _run(_enterNetwork);

  /// [SetupBaseSkipped] "Continue" → hop 3 (Wi-Fi is still needed).
  Future<void> continueToNetwork() => _run(_enterNetwork);

  // ══ hop 3 — bridge ↔ Wi-Fi (§13.2.3) ═══════════════════════════════════

  /// Enters the picker, using the pre-warmed buffer when it is fresh (§13.2.3)
  /// so the screen is instant, else a fresh scan.
  Future<void> _enterNetwork() async {
    final fresh = _now() - _prewarmAtMs < kScanFreshness.inMilliseconds;
    if (fresh && _prewarm.isNotEmpty) {
      _to(
        SetupNetworkPick(
          networks: List.of(_prewarm),
          scanning: false,
          failureCount: _wifiFailCount,
        ),
      );
      return;
    }
    await _scanNetworks();
  }

  /// Public re-scan for [SetupNetworkEmpty] / picker entry.
  Future<void> startNetworkScan() => _run(_scanNetworks);

  Future<void> _scanNetworks({String? error}) async {
    final gen = _flowGen;
    _to(SetupNetworkPick(scanning: true, failureCount: _wifiFailCount));
    final aps = <WifiScanResult>[];
    final scanDone = Completer<void>();
    final sub = transport.scanResults.listen((r) {
      // Completion is decided first and unconditionally (`wizard.dart:374`):
      // a result we drop is still a result, and if it is the last it still
      // ends the scan.
      if (r.index >= r.total - 1 && !scanDone.isCompleted) {
        scanDone.complete();
      }
      _mergeNetwork(aps, r);
      if (gen == _flowGen) {
        _to(
          SetupNetworkPick(
            networks: List.of(aps),
            scanning: true,
            failureCount: _wifiFailCount,
          ),
        );
      }
    });
    try {
      await transport.startWifiScan();
      await Future.any([scanDone.future, _delay(kScanBudget)]);
    } on Object {
      // An empty list with a next step beats an error.
    }
    await sub.cancel();
    if (gen != _flowGen) {
      return;
    }
    _prewarm = List.of(aps);
    _prewarmAtMs = _now();
    if (aps.isEmpty) {
      _to(const SetupNetworkEmpty());
    } else {
      _to(
        SetupNetworkPick(
          networks: aps,
          scanning: false,
          failureCount: _wifiFailCount,
        ),
      );
    }
  }

  /// Fired when hop 2 enters BASE_LISTEN (§13.2.3): builds the picker list in
  /// the background so Continue lands on a populated screen. Best-effort.
  Future<void> _prewarmNetworks(int gen) async {
    final aps = <WifiScanResult>[];
    final scanDone = Completer<void>();
    StreamSubscription<WifiScanResult>? sub;
    sub = transport.scanResults.listen((r) {
      if (r.index >= r.total - 1 && !scanDone.isCompleted) {
        scanDone.complete();
      }
      _mergeNetwork(aps, r);
    });
    try {
      await transport.startWifiScan();
      await Future.any([scanDone.future, _delay(kScanBudget)]);
    } on Object {
      // best-effort pre-warm; the picker re-scans if this yielded nothing
    }
    await sub.cancel();
    if (gen == _flowGen) {
      _prewarm = List.of(aps);
      _prewarmAtMs = _now();
    }
  }

  /// Dedupe by SSID keeping the strongest, drop hidden (empty SSID)
  /// (`wizard.dart:381`).
  void _mergeNetwork(List<WifiScanResult> aps, WifiScanResult r) {
    if (r.ssid.isEmpty) {
      return;
    }
    final at = aps.indexWhere((e) => e.ssid == r.ssid);
    if (at < 0) {
      aps.add(r);
    } else if (r.rssi > aps[at].rssi) {
      aps[at] = r;
    }
  }

  /// A picked row (§13.2.3). `auth == 0` (open) goes straight to applying;
  /// `auth == 5` (enterprise) is rejected — the firmware never implements it,
  /// and pretending would tell the user "wrong password" about a correct one.
  Future<void> pickNetwork(WifiScanResult net) => _run(() async {
    if (net.auth == 5) {
      // Enterprise: unsupported. Kept on the picker; the row is disabled in
      // the screen. Nothing to apply.
      return;
    }
    _ssid = net.ssid;
    _auth = net.auth;
    if (net.auth == 0) {
      await _applyJoined('');
      return;
    }
    _to(SetupNetworkPassword(ssid: net.ssid, auth: net.auth));
  });

  /// "Join a hidden network" (§13.2.3).
  Future<void> openManualEntry() => _run(() async {
    _to(const SetupNetworkManual());
  });

  /// A manually typed hidden SSID with its own auth (§13.2.3): a hidden open
  /// network is joinable; a keystroke does not downgrade the auth.
  Future<void> submitManual(String ssid, {int auth = 3}) => _run(() async {
    _ssid = ssid;
    _auth = auth;
    if (auth == 0) {
      await _applyJoined('');
      return;
    }
    _to(SetupNetworkPassword(ssid: ssid, auth: auth));
  });

  /// The password screen's Connect (§13.2.3).
  Future<void> submitPassword(String psk) => _run(() async {
    _psk = psk;
    await _applyJoined(psk);
  });

  Future<void> _applyJoined(String psk) async {
    final gen = _flowGen;
    _applying = true;
    _to(SetupApplying(phase: ApplyingPhase.sent, ssid: _ssid));
    final w = _watchNet(); // attach BEFORE the write
    try {
      await transport.applyWifiConfig(
        mode: NetMode.sta,
        ssid: _ssid,
        psk: psk,
        auth: _auth,
      );
    } on BridgeControlException {
      _applying = false;
      await w.sub.cancel();
      _wifiFail(WifiFailure.assocRefused);
      return;
    } on TimeoutException {
      // §13.2.3: a bridge that ACKs the write but never emits a result frame.
      // Caught here so it never escapes to the full-screen crash page.
      _applying = false;
      await w.sub.cancel();
      _wifiFail(WifiFailure.notFound);
      return;
    } on BleException {
      _applying = false;
      await w.sub.cancel();
      if (gen == _flowGen) {
        _to(SetupLinkLost(resumeAt: SetupStage.applying));
      }
      return;
    }
    if (gen != _flowGen) {
      _applying = false;
      await w.sub.cancel();
      return;
    }
    _to(SetupApplying(phase: ApplyingPhase.joining, ssid: _ssid));
    final outcome = await _settleNet(gen, w.settled);
    await w.sub.cancel();
    _applying = false;
    if (gen != _flowGen) {
      return;
    }
    if (outcome == null) {
      _wifiFail(WifiFailure.notFound);
      return;
    }
    if (outcome.stateEnum == NetState.failed) {
      _wifiFail(_classify(outcome));
      return;
    }
    // net_status: up — associated, but not yet proven reachable.
    _to(SetupApplying(phase: ApplyingPhase.gettingAddress, ssid: _ssid));
    final ip = _ipOf(outcome);
    _to(SetupApplying(phase: ApplyingPhase.checking, ssid: _ssid));
    final url = await _verify(ip);
    if (gen != _flowGen) {
      return;
    }
    if (url == null) {
      _to(SetupUnreachable(ip: ip ?? ''));
      return;
    }
    _wifiFailCount = 0;
    _summary = _summary.copyWith(wifiSsid: _ssid, ip: ip, hosted: false);
    _to(SetupNameAndUnits(suggestedName: _bridge?.name ?? ''));
  }

  void _wifiFail(WifiFailure reason) {
    _wifiFailCount++;
    _to(SetupWifiFailed(reason: reason, ssid: _ssid, attempts: _wifiFailCount));
  }

  /// [SetupWifiFailed] "Try again" (§13.2.3): back to the password field,
  /// PREFILLED and revealed with the reason stated, so a single typo does not
  /// cost a fresh scan and a full retype. `ssid`/`psk`/`auth` live here, not in
  /// disposed widget state, which is what makes the prefill possible.
  Future<void> retryWifi() => _run(() async {
    _to(
      SetupNetworkPassword(
        ssid: _ssid,
        auth: _auth,
        prefill: _psk,
        error: _wifiErrorLine(),
      ),
    );
  });

  String _wifiErrorLine() {
    final st = _state;
    final reason = st is SetupWifiFailed
        ? st.reason
        : WifiFailure.wrongPassword;
    return switch (reason) {
      WifiFailure.wrongPassword => 'Incorrect password for $_ssid',
      WifiFailure.notFound => "The bridge couldn't find $_ssid",
      WifiFailure.assocRefused => 'Your router turned the bridge away',
      WifiFailure.noIp => 'The bridge joined but never got an address',
      WifiFailure.weakSignal => 'The signal is too weak where the bridge is',
    };
  }

  /// "My phone IS on this network — try again" (§13.2.3): re-verify without a
  /// re-provision, since the bridge is already up.
  Future<void> retryVerify() => _run(() async {
    final gen = _flowGen;
    NetStatus? net;
    try {
      net = await transport.readNetStatus();
    } on Object {
      net = null;
    }
    final ip = _ipOf(net);
    _to(SetupApplying(phase: ApplyingPhase.checking, ssid: net?.ssid ?? _ssid));
    final url = await _verify(ip);
    if (gen != _flowGen) {
      return;
    }
    if (url == null) {
      _to(SetupUnreachable(ip: ip ?? ''));
      return;
    }
    _summary = _summary.copyWith(wifiSsid: net?.ssid ?? _ssid, ip: ip);
    _to(SetupNameAndUnits(suggestedName: _bridge?.name ?? ''));
  });

  /// Hosted mode (§13.2.3): the quiet tertiary link, the auto-primary on empty,
  /// and the auto-primary after two Wi-Fi failures all land here.
  Future<void> chooseHosted() => _run(() async {
    final gen = _flowGen;
    _applying = true;
    _to(const SetupApplying(phase: ApplyingPhase.sent, hosted: true));
    final w = _watchNet(); // attach BEFORE the write
    try {
      final r = await transport.applyWifiConfig(mode: NetMode.ap);
      _apPsk = r.detail; // the phone needs it to join (§5.5)
    } on BridgeControlException {
      _applying = false;
      await w.sub.cancel();
      _to(SetupHostedRefused(ssid: _hostedSsid(null), psk: ''));
      return;
    } on TimeoutException {
      _applying = false;
      await w.sub.cancel();
      _to(SetupHostedRefused(ssid: _hostedSsid(null), psk: _apPsk ?? ''));
      return;
    } on BleException {
      _applying = false;
      await w.sub.cancel();
      if (gen == _flowGen) {
        _to(SetupLinkLost(resumeAt: SetupStage.applying));
      }
      return;
    }
    if (gen != _flowGen) {
      _applying = false;
      await w.sub.cancel();
      return;
    }
    _to(const SetupApplying(phase: ApplyingPhase.joining, hosted: true));
    final outcome = await _settleNet(gen, w.settled);
    await w.sub.cancel();
    _applying = false;
    if (gen != _flowGen) {
      return;
    }
    if (outcome == null || outcome.stateEnum != NetState.up) {
      _to(SetupHostedRefused(ssid: _hostedSsid(outcome), psk: _apPsk ?? ''));
      return;
    }
    _to(
      SetupHostedJoin(
        ssid: await _resolveHostedSsid(outcome),
        psk: _apPsk ?? '',
      ),
    );
  });

  /// "Join it for me" (§13.2.3) — the Android suggestion dialog via [joinAp].
  Future<void> joinHostedAp() => _run(() async {
    final st = _state;
    if (st is! SetupHostedJoin && st is! SetupHostedRefused) {
      return;
    }
    final ssid = st is SetupHostedJoin
        ? st.ssid
        : (st as SetupHostedRefused).ssid;
    final psk = st is SetupHostedJoin ? st.psk : (st as SetupHostedRefused).psk;
    final gen = _flowGen;
    _to(
      SetupApplying(phase: ApplyingPhase.joiningAp, hosted: true, ssid: ssid),
    );
    final joiner = joinAp;
    final ok = joiner == null ? true : await joiner(ssid, psk);
    if (gen != _flowGen) {
      return;
    }
    if (!ok) {
      _to(SetupHostedRefused(ssid: ssid, psk: psk));
      return;
    }
    await _finishHosted(gen, ssid, psk);
  });

  /// "I'll join it myself" (§13.2.3): the user joined in Wi-Fi settings; just
  /// verify and finish.
  Future<void> hostedJoinedManually() => _run(() async {
    final st = _state;
    if (st is! SetupHostedJoin && st is! SetupHostedRefused) {
      return;
    }
    final ssid = st is SetupHostedJoin
        ? st.ssid
        : (st as SetupHostedRefused).ssid;
    final psk = st is SetupHostedJoin ? st.psk : (st as SetupHostedRefused).psk;
    await _finishHosted(_flowGen, ssid, psk);
  });

  Future<void> _finishHosted(int gen, String ssid, String psk) async {
    _to(SetupApplying(phase: ApplyingPhase.checking, hosted: true, ssid: ssid));
    final url = await _verify(null);
    if (gen != _flowGen) {
      return;
    }
    if (url == null) {
      _to(const SetupUnreachable(ip: '192.168.4.1'));
      return;
    }
    _summary = _summary.copyWith(wifiSsid: ssid, hosted: true, apPsk: psk);
    _to(SetupNameAndUnits(suggestedName: _bridge?.name ?? ''));
  }

  /// Skip Wi-Fi (§13.2: every hop is skippable). Straight to name + units;
  /// [SetupDone] then shows Wi-Fi as "— not set up".
  Future<void> skipNetwork() => _run(() async {
    _to(SetupNameAndUnits(suggestedName: _bridge?.name ?? ''));
  });

  /// The `SmokeBridge-XXXX` SSID (§13.2.3): use the authoritative
  /// `net_status.ssid`; fall back to the bond's device id; never guess a MAC.
  /// Synchronous form for the failure paths (no network read to spare).
  String _hostedSsid(NetStatus? net) {
    final live = net?.ssid ?? '';
    if (live.isNotEmpty) {
      return live;
    }
    final id = _bridgeId;
    return id != null && id.isNotEmpty
        ? 'SmokeBridge-$id'
        : (_bridge?.name ?? '');
  }

  /// Success-path SSID: as [_hostedSsid], but reads `device_info` for the id
  /// when neither the live `net_status.ssid` nor a captured bond id is on hand
  /// (§13.2.3: "fall back to deviceInfo(); guess never").
  Future<String> _resolveHostedSsid(NetStatus? net) async {
    final sync = _hostedSsid(net);
    if (sync.isNotEmpty) {
      return sync;
    }
    try {
      final id = (await transport.deviceInfo()).id;
      if (id.isNotEmpty) {
        return 'SmokeBridge-$id';
      }
    } on Object {
      // fall through
    }
    return sync;
  }

  /// Attaches a `net_status` watcher. Called BEFORE the config write so a
  /// transition notified during the write is not missed — the wizard subscribed
  /// after and relied on the read fallback; watching across the transition is
  /// what §5.7's whole choreography is.
  ({Completer<NetStatus> settled, StreamSubscription<NetStatus> sub})
  _watchNet() {
    final settled = Completer<NetStatus>();
    final sub = transport.netStatus.listen((n) {
      final s = n.stateEnum;
      if ((s == NetState.up || s == NetState.failed) && !settled.isCompleted) {
        settled.complete(n);
      }
    });
    return (settled: settled, sub: sub);
  }

  /// Resolves the watcher against the budget, then falls back to a READ
  /// (`wizard.dart:475` BOARD-FOUND: an already-joined bridge emits no
  /// transition, so asking is the only way to learn the current state).
  Future<NetStatus?> _settleNet(int gen, Completer<NetStatus> settled) async {
    NetStatus? outcome;
    await Future.any([
      settled.future.then((n) => outcome = n),
      _delay(kHandoffBudget),
    ]);
    if (outcome == null) {
      try {
        final now = await transport.readNetStatus();
        final s = now.stateEnum;
        if (s == NetState.up || s == NetState.failed) {
          outcome = now;
        }
      } on Object {
        // unreadable: null means "nothing to go on but the budget"
      }
    }
    return gen == _flowGen ? outcome : null;
  }

  Future<String?> _verify(String? ipHint) async {
    String? url;
    await Future.any([
      verify(ipHint).then((u) => url = u),
      _delay(kHandoffBudget),
    ]);
    return url;
  }

  /// The dotted-quad from a `net_status`, or null when it carried none
  /// (0.0.0.0 means "not assigned", not "the address is zero") —
  /// `wizard.dart:536`.
  static String? _ipOf(NetStatus? n) {
    final ip = n?.ip;
    if (ip == null || ip.length != 4 || ip.every((o) => o == 0)) {
      return null;
    }
    return ip.join('.');
  }

  // ══ finish (§13.2.4) ═══════════════════════════════════════════════════

  /// Name + units submit (§13.2.4): the one place units are asked.
  Future<void> submitNameAndUnits(String name, {bool celsius = false}) =>
      _run(() async {
        _summary = _summary.copyWith(bridgeName: name, unitsCelsius: celsius);
        _to(SetupDone(_summary));
      });

  // ══ escape, link-loss, restart (§13.2.4) ═══════════════════════════════

  /// [SetupLinkLost] "Reconnect": re-establish BLE, then resume at the recorded
  /// stage. Adapter-off is surfaced as [SetupBluetoothOff], not a silent loop.
  Future<void> reconnect() => _run(() async {
    final resumeAt = _state is SetupLinkLost
        ? (_state as SetupLinkLost).resumeAt
        : currentStage;
    if (probe.adapterStateNow == SetupAdapterState.off) {
      _to(SetupBluetoothOff(resumeAt: resumeAt));
      return;
    }
    final bridge = _bridge;
    try {
      if (bridge != null &&
          client.connectionState != BleConnectionState.connected) {
        await client.connect(bridge.deviceId);
        await transport.start();
      }
    } on BleException {
      // Still down — leave the user on link-lost with reconnect-or-restart.
      _to(SetupLinkLost(resumeAt: resumeAt));
      return;
    }
    await _resume(resumeAt);
  });

  /// Abandon and restart from the top (§13.2.1) — bumps [_flowGen] so no
  /// in-flight loop can transition, and kicks a fresh scan rather than flashing
  /// an empty "No bridges" first (`wizard.dart:333` bug).
  Future<void> restart() async {
    _bridge = null;
    _bridgeId = null;
    _apPsk = null;
    _wifiFailCount = 0;
    _ackRetries = 0;
    _prewarm = const [];
    _summary = const SetupSummary();
    _flowGen++;
    _applying = false;
    _inFlight = false;
    _abort();
    unawaited(_connSub?.cancel());
    _connSub = null;
    try {
      await listen.cancel();
    } on Object {
      // best-effort
    }
    // Kick a fresh scan without awaiting it (a real scan stream never ends),
    // and without flashing an empty "No bridges" first (`wizard.dart:333`).
    // The synchronous head of [startScan] emits SetupScanning before we return.
    unawaited(startScan());
  }

  /// Cancel the in-flight operation and rest at the current hop's stable state
  /// (§13.2). Ungated, because it must interrupt a running loop.
  Future<void> cancel() async {
    _flowGen++;
    _applying = false;
    _inFlight = false;
    _abort();
    try {
      await listen.cancel();
    } on Object {
      // best-effort
    }
    try {
      await client.stopScan();
    } on Object {
      // best-effort
    }
    switch (currentStage) {
      case SetupStage.preflight:
        break;
      case SetupStage.findBridge:
      case SetupStage.pair:
        _to(const SetupScanning(scanning: false));
      case SetupStage.baseListen:
        _to(const SetupBaseIntro());
      case SetupStage.network:
      case SetupStage.applying:
        _to(
          SetupNetworkPick(
            networks: List.of(_prewarm),
            scanning: false,
            failureCount: _wifiFailCount,
          ),
        );
      case SetupStage.done:
        break;
    }
  }

  Future<void> dispose() async {
    _flowGen++;
    await _connSub?.cancel();
    await _adapterSub?.cancel();
    await _states.close();
  }
}

/// The internal outcome of one listen window (§13.2.2).
class _ListenResult {
  const _ListenResult.confirmed(this.snap)
    : confirmed = true,
      reason = null,
      garbled = 0;
  const _ListenResult.fail(this.reason, this.garbled)
    : confirmed = false,
      snap = null;
  final bool confirmed;
  final BasePairSnapshot? snap;
  final BaseSyncFailure? reason;
  final int garbled;
}
