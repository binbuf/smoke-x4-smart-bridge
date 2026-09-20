/// **Reconciliation, acting** — the other half of `domain/situation/situation.dart`
/// (design 16 §16.3).
///
/// `situation.dart` is pure: facts in, one named [Situation] out. It decides
/// *what is wrong*. Nothing gathered the facts and nothing acted on them, so
/// the model was a diagnosis with no doctor — and the product went on
/// collapsing every mismatch in the world into "Offline · retry 6". This file
/// is the doctor:
///
///  1. **Gather.** Three columns, exactly as §16.3 draws them — what the phone
///     remembers ([BridgePrefs]), what is observable right now (the OS radio,
///     the permission, the surviving bond — a [SituationProbe]), and what the
///     device says when reached (a [SituationShell] over the live link).
///  2. **Reconcile.** One call to `reconcile()`. One situation, never a list.
///  3. **Act, then report.** Anything `automatic` happens *without asking* and
///     the copy switches to the **past tense**. A banner offering to do
///     something the app could simply have done is an app turning its own
///     problem into the user's decision.
///
/// **Identity is never automatic.** `bridgeWasReset` is the one situation this
/// class refuses to resolve itself: adopting a reset bridge silently would
/// attach a phone's history to a device that did not record it. It is exposed
/// as [adoptReachedBridge], for a human to invoke behind a cost sheet.
///
/// **Nothing is claimed that was not verified.** Every automatic remedy either
/// reads back (the clock), checks the link came up (adopt, join, retry), or is
/// a purely local write whose success is not in doubt (re-learning an address).
/// A remedy that could not be carried out leaves the *present-tense* situation
/// and its human action on screen rather than reporting a fix that did not
/// happen.
///
/// **Pure over its seams.** [SituationProbe] and [SituationShell] are narrow
/// interfaces; the whole recovery matrix — every [SituationKind], every
/// automatic act, every failure of one — runs in the host suite with no radio,
/// no socket and no channel.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/prefs/bridge_prefs.dart';
import '../../data/transport/bridge_transport.dart';
import '../../domain/situation/situation.dart';
import '../dashboard/dashboard_snapshot.dart';

/// A bridge this phone is still OS-bonded to, whatever the app remembers.
///
/// The tell that the *phone* was reset and the *device* was not: the pairing
/// lives in the OS bond table, which survives an app reinstall, a cleared data
/// directory and a restored backup.
@immutable
class BondedBridge {
  const BondedBridge({required this.deviceId, required this.name});

  /// The platform's handle (a MAC on Android) — what the BLE lane dials.
  final String deviceId;

  /// `SmokeBridge-8274`, or the handle when the OS reports no name.
  final String name;
}

/// Everything the reconciler needs from outside the app's own data.
///
/// Deliberately seven small questions rather than a plugin: the OS radio, the
/// one missing permission, the surviving bond, a hosted network in range, and
/// the three things the app can *do* about them. A fake implementing this
/// drives every OS-shaped branch with no phone.
abstract interface class SituationProbe {
  /// Is the Bluetooth radio on? **Null means not known yet**, which is not
  /// false — telling someone their radio is off while the plugin is still
  /// booting is exactly the class of lie §16.3 exists to end.
  Future<bool?> bluetoothOn();

  /// The one permission the app is missing, in the words the OS uses for it
  /// ("Nearby devices"), or null when nothing is missing or it cannot be told.
  Future<String?> missingPermission();

  /// A bridge this phone is bonded to at the OS level, or null.
  Future<BondedBridge?> bondedBridge();

  /// A `SmokeBridge-*` network in range, or null when none is visible **or
  /// this platform will not say**. Android will not name networks to an app
  /// that has not taken the location permission this one promised never to
  /// take (A6.6), so on device this is usually null and the hosted-network
  /// tell arrives from the device itself over Bluetooth instead.
  Future<String?> visibleApSsid();

  /// Join [ssid], scoping this app's traffic to it. False when the platform
  /// cannot (no binder, no credentials, the user declined).
  Future<bool> joinNetwork(String ssid, {String psk = ''});

  /// Open the OS Bluetooth settings. False when there is nothing to open.
  Future<bool> openBluetoothSettings();

  /// Prompt for the missing permission (or open app settings when the OS will
  /// no longer prompt). True when it is now granted.
  Future<bool> requestMissingPermission();
}

/// A probe that knows nothing and therefore claims nothing.
///
/// The default, and the right answer for a test, a desktop build, or any
/// context with no platform underneath: every observation is null — *unknown*,
/// never *absent* — so the reconciler falls through to what the phone
/// remembers and what the device says, which are the two columns that always
/// exist.
class UnknownSituationProbe implements SituationProbe {
  const UnknownSituationProbe();

  @override
  Future<bool?> bluetoothOn() async => null;

  @override
  Future<String?> missingPermission() async => null;

  @override
  Future<BondedBridge?> bondedBridge() async => null;

  @override
  Future<String?> visibleApSsid() async => null;

  @override
  Future<bool> joinNetwork(String ssid, {String psk = ''}) async => false;

  @override
  Future<bool> openBluetoothSettings() async => false;

  @override
  Future<bool> requestMissingPermission() async => false;
}

/// A probe that is still being built.
///
/// The real one reads the OS version off a channel before it can decide which
/// permission set applies, so it arrives one await after the screen does. This
/// stands in for it and answers **unknown** until it lands — which is exactly
/// the answer a screen should get while the phone is still being asked.
class DeferredSituationProbe implements SituationProbe {
  DeferredSituationProbe(Future<SituationProbe?> pending) {
    _ready = pending
        .then((p) => _real = p ?? const UnknownSituationProbe())
        .catchError((Object _) => _real = const UnknownSituationProbe());
  }

  SituationProbe _real = const UnknownSituationProbe();
  late final Future<SituationProbe> _ready;

  Future<SituationProbe> get _probe async {
    await _ready;
    return _real;
  }

  @override
  Future<bool?> bluetoothOn() async => (await _probe).bluetoothOn();

  @override
  Future<String?> missingPermission() async =>
      (await _probe).missingPermission();

  @override
  Future<BondedBridge?> bondedBridge() async => (await _probe).bondedBridge();

  @override
  Future<String?> visibleApSsid() async => (await _probe).visibleApSsid();

  @override
  Future<bool> joinNetwork(String ssid, {String psk = ''}) async =>
      (await _probe).joinNetwork(ssid, psk: psk);

  @override
  Future<bool> openBluetoothSettings() async =>
      (await _probe).openBluetoothSettings();

  @override
  Future<bool> requestMissingPermission() async =>
      (await _probe).requestMissingPermission();
}

/// What the reconciler needs from the live connection.
///
/// Five reads and one action, so the resolver never touches [ShellSession]
/// directly and the whole matrix is drivable from a fake. In the app,
/// [LiveSituationShell] adapts the shell's one session.
abstract interface class SituationShell {
  /// The latest projection, or null before anything connected.
  DashboardSnapshot? get snapshot;

  /// The active transport, or null when offline.
  BridgeTransport? get transport;

  /// Whether a cook annotation is running on this phone.
  bool get hasRunningCook;

  /// The bridge the running cook was recorded against, or null when there is
  /// no cook. Distinct from the remembered id — see
  /// [SituationFacts.runningCookBridgeId] for why that distinction is the
  /// whole reason [SituationKind.staleCook] exists.
  Future<String?> runningCookBridgeId();

  /// `'ap'` · `'sta'` · null.
  ///
  /// A separate read from [snapshot] because the snapshot only learns this on
  /// Wi-Fi — and the case that matters most is precisely the one where Wi-Fi
  /// is down: a bridge that failed to join your network, came up hosting its
  /// own, and is reachable **only over Bluetooth**. Asking the device is the
  /// only way to find that out, and it is the bench failure this whole layer
  /// was written for.
  /// Returns the mode **and** the network name in one frame, because the
  /// SSID is what lets the hosting copy *name* the network. The phone cannot
  /// name the access points around it without the location permission the
  /// manifest promises never to take (A6.6), so the device telling us is the
  /// whole mechanism.
  Future<({String? mode, String? ssid})> netStatus();

  /// Race every lane again, now. True when a link came up.
  Future<bool> retryNow();
}

/// The production [SituationShell]: the shell's one live session.
///
/// Kept out of [SituationResolver] so the resolver imports neither the session
/// nor any transport implementation — the BLE-specific net-mode read lives
/// here, behind the interface, where it is the only place that has to know
/// which lane it is on.
class LiveSituationShell implements SituationShell {
  LiveSituationShell({
    required DashboardSnapshot? Function() snapshotOf,
    required BridgeTransport? Function() transportOf,
    required bool Function() runningCook,
    required Future<({String? mode, String? ssid})> Function() netStatusOf,
    required Future<bool> Function() onRetry,
    Future<String?> Function()? cookBridgeOf,
  }) : _snapshot = snapshotOf,
       _transport = transportOf,
       _running = runningCook,
       _netStatus = netStatusOf,
       _retry = onRetry,
       _cookBridge = cookBridgeOf;

  final DashboardSnapshot? Function() _snapshot;
  final BridgeTransport? Function() _transport;
  final bool Function() _running;
  final Future<({String? mode, String? ssid})> Function() _netStatus;
  final Future<bool> Function() _retry;
  final Future<String?> Function()? _cookBridge;

  @override
  DashboardSnapshot? get snapshot => _snapshot();

  @override
  BridgeTransport? get transport => _transport();

  @override
  bool get hasRunningCook => _running();

  @override
  Future<String?> runningCookBridgeId() async => _cookBridge?.call();

  @override
  Future<({String? mode, String? ssid})> netStatus() => _netStatus();

  @override
  Future<bool> retryNow() => _retry();
}

/// What a human can do about a situation, once the app has done what it can.
///
/// The resolver performs the two the OS lets it perform ([openBluetooth],
/// [grantPermission]) and the one that is a local write ([adoptBridge], behind
/// a cost sheet). The rest are destinations, and the screen owns those —
/// nothing here knows what a route is.
enum SituationAct {
  /// Nothing for a human to do. The app has it, or is still trying.
  none,

  /// OS: the Bluetooth settings screen.
  openBluetooth,

  /// OS: the permission prompt, or app settings once it will not prompt again.
  grantPermission,

  /// Guided setup, from the top.
  runSetup,

  /// Guided setup's hop 2 — introducing the bridge to the base station.
  pairBase,

  /// Identity. **Never automatic**: a cost sheet, then
  /// [SituationResolver.adoptReachedBridge].
  adoptBridge,

  /// The §E.3 mode-switch wizard.
  switchNetwork,

  /// The firmware page.
  updateFirmware,

  /// End the cook annotation this phone is carrying for another bridge.
  endCook,
}

/// The one act each situation offers, or [SituationAct.none].
SituationAct actFor(SituationKind kind) => switch (kind) {
  SituationKind.bluetoothOff => SituationAct.openBluetooth,
  SituationKind.permissionMissing => SituationAct.grantPermission,
  SituationKind.neverSetUp => SituationAct.runSetup,
  SituationKind.bridgeWasReset => SituationAct.adoptBridge,
  SituationKind.bridgeNotPairedToBase => SituationAct.pairBase,
  SituationKind.bridgeHostingOwnNetwork => SituationAct.switchNetwork,
  SituationKind.firmwareTooOld => SituationAct.updateFirmware,
  SituationKind.staleCook => SituationAct.endCook,
  // The app owns these outright: it re-learns the address, adopts the bridge
  // it is still bonded to, sets the clock, and keeps retrying. Offering a
  // button for any of them would be the app asking permission to do its job.
  SituationKind.phoneForgotBridge ||
  SituationKind.bridgeMovedAddress ||
  SituationKind.deviceClockUnset ||
  SituationKind.bridgeOutOfRange ||
  SituationKind.healthy => SituationAct.none,
};

/// Gathers the facts, reconciles them, and **acts on the ones it owns**.
///
/// A [ChangeNotifier] so a screen rebuilds as the picture resolves: gathering
/// is I/O (a status read, a bond lookup, a clock read-back) and the lead card
/// must not sit blank while it runs.
class SituationResolver extends ChangeNotifier {
  SituationResolver({
    required this.shell,
    this.prefs,
    this.probe = const UnknownSituationProbe(),
    int Function()? now,
  }) : _now = now ?? _wallClock;

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  /// The live connection, narrowed to five reads and one action.
  final SituationShell shell;

  /// What this phone remembers. Null on a build with no store, where the
  /// remembered column is simply empty rather than wrong.
  final BridgePrefs? prefs;

  /// The observable middle column — the radio, the permission, the bond.
  final SituationProbe probe;

  final int Function() _now;

  /// How long a past-tense report stays on screen before a healthy
  /// reconciliation is allowed to retire it. Long enough to read at 3 a.m.,
  /// short enough that it is not still there next time the tab is opened.
  static const Duration reportHold = Duration(seconds: 8);

  /// The soonest another blind reconnect may be fired. The supervisor has its
  /// own backoff; this only stops a rebuild storm from queue-jumping it.
  static const Duration retryCooldown = Duration(seconds: 20);

  Situation _situation = Situation.ok;
  SituationFacts? _facts;
  bool _evaluating = false;
  bool _acting = false;
  bool _disposed = false;
  Future<Situation>? _inFlight;
  int _reportedAtMs = 0;
  int _lastRetryMs = 0;

  /// The SSIDs already offered to the platform this session. A join the phone
  /// refused must not be re-offered on every rebuild — that is a permission
  /// prompt storm, and it teaches people to tap "deny".
  final Set<String> _joinAttempted = <String>{};

  /// The current situation. [Situation.ok] until the first [evaluate].
  Situation get situation => _situation;

  /// The facts behind it. Null before the first [evaluate]; exposed because a
  /// reconciliation nobody can inspect is a reconciliation nobody can debug.
  SituationFacts? get facts => _facts;

  /// A gather is running. The screen keeps rendering the previous answer —
  /// a spinner where the explanation was is worse than an explanation that is
  /// a few seconds old.
  bool get evaluating => _evaluating;

  /// A remedy is running.
  bool get acting => _acting;

  /// What a human can do about the current situation.
  SituationAct get act => actFor(_situation.kind);

  /// Gather → reconcile → act → report. Never throws.
  ///
  /// Re-entrant: a second call while one is in flight joins the first rather
  /// than doubling every read.
  Future<Situation> evaluate() {
    final running = _inFlight;
    if (running != null) {
      return running;
    }
    final run = _evaluate();
    _inFlight = run;
    return run.whenComplete(() => _inFlight = null);
  }

  Future<Situation> _evaluate() async {
    _evaluating = true;
    _notify();
    try {
      final facts = await _gather();
      _facts = facts;
      var next = reconcile(facts);
      next = await _remedy(next, facts);
      _adopt(next);
      return _situation;
    } on Object {
      // A reconciliation that throws must not blank the screen. Whatever was
      // last true stays on it.
      return _situation;
    } finally {
      _evaluating = false;
      _notify();
    }
  }

  /// Replaces the current situation, except while a past-tense report is still
  /// being read and the new answer is merely "nothing is wrong".
  ///
  /// A real problem always wins: a congratulation left on screen over a bridge
  /// that has since gone away is the same lie as a stale temperature.
  void _adopt(Situation next) {
    if (_situation.resolvedAutomatically &&
        next.isHealthy &&
        _now() - _reportedAtMs < reportHold.inMilliseconds) {
      return;
    }
    _situation = next;
    if (next.resolvedAutomatically) {
      _reportedAtMs = _now();
    }
  }

  /// Drop a past-tense report early — the user has read it.
  void retireReport() {
    if (_situation.resolvedAutomatically) {
      _situation = Situation.ok;
      _reportedAtMs = 0;
      _notify();
    }
  }

  // ── 1. gather ────────────────────────────────────────────────────────

  Future<SituationFacts> _gather() async {
    final remembered = prefs;
    final snapshot = shell.snapshot;
    final transport = shell.transport;
    final reachable = snapshot != null && snapshot.link != LinkKind.offline;

    // The observable column. Each read is independently fallible and a
    // failure means *unknown*, never a verdict.
    final bluetoothOn = await _quiet(probe.bluetoothOn);
    final permission = await _quiet(probe.missingPermission);
    final bonded = await _quiet(probe.bondedBridge);
    final visibleAp = await _quiet(probe.visibleApSsid);

    // The device column. Every field stays null unless the device said it.
    String? deviceId;
    bool? paired;
    bool? fullHistory;
    bool? clockValid;
    String? netMode;
    String? apSsid;
    if (reachable && transport != null) {
      final status = await _quiet(transport.status);
      if (status != null && status.deviceId.isNotEmpty) {
        deviceId = status.deviceId;
        paired = status.paired;
      }
      fullHistory = transport.capabilities.fullHistory;
      // Always ask the device, even when the snapshot already has a mode: the
      // SSID only ever comes from here, and naming the network is the whole
      // difference between a sentence and an instruction.
      final net = await _quiet(shell.netStatus);
      netMode = snapshot.netMode ?? net?.mode;
      apSsid = net?.ssid;
      clockValid = await _clockValid(transport, deviceId);
    }

    return SituationFacts(
      rememberedBridgeId: _blankToNull(remembered?.lastBridgeId),
      rememberedBaseUrl: _blankToNull(remembered?.lastBaseUrl),
      rememberedBleDeviceId: _blankToNull(remembered?.lastBleDeviceId),
      lastSeenUnixMs: remembered?.lastSeenUnixMs,
      hasRunningCook: shell.hasRunningCook,
      // Without this the `staleCook` guard could never be true: the field was
      // documented at length, tested, and never filled by any gatherer.
      runningCookBridgeId: shell.hasRunningCook
          ? await _quiet(shell.runningCookBridgeId)
          : null,
      bluetoothOn: bluetoothOn,
      missingPermission: permission,
      bondedBridgeName: bonded?.name,
      visibleApSsid: visibleAp,
      reachedDeviceId: deviceId,
      // Empty on the Bluetooth lane, where there is no address at all — and
      // `reconcile` skips the moved-address test on an empty one, so a
      // Bluetooth link can never be mistaken for a bridge that moved.
      reachedAddress: reachable ? snapshot.address : null,
      reachedNetMode: netMode,
      reachedApSsid: _blankToNull(apSsid),
      pairedToBase: paired,
      deviceClockValid: clockValid,
      supportsFullHistory: fullHistory,
      nowUnixMs: _now(),
    );
  }

  /// The device whose clock we have already seen set. A clock does not come
  /// unset on its own, so once it answers we stop spending a round trip on the
  /// question every time the tab rebuilds.
  String? _clockSeenSetFor;

  /// Whether the bridge knows the time.
  ///
  /// `LiveState.unixMs` is null exactly while `clock_valid` is unset (04 §4.4),
  /// which is the device's own answer rather than an inference. A read that
  /// fails returns **null, not false** — an unreachable bridge has not told us
  /// its clock is wrong, and setting a clock on that assumption would be the
  /// app acting on a guess.
  Future<bool?> _clockValid(BridgeTransport transport, String? deviceId) async {
    if (deviceId != null && deviceId == _clockSeenSetFor) {
      return true;
    }
    final live = await _quiet(
      () => transport.live(window: const Duration(minutes: 1)),
    );
    if (live == null) {
      return null;
    }
    final valid = live.unixMs != null;
    if (valid && deviceId != null) {
      _clockSeenSetFor = deviceId;
    }
    return valid;
  }

  // ── 2. act, then report ──────────────────────────────────────────────

  /// Performs the remedy for an automatic situation and rewrites it in the
  /// past tense. Returns [s] untouched for everything else.
  ///
  /// The switch is exhaustive on purpose: a new [SituationKind] cannot be
  /// added without a decision here about whether the app fixes it itself.
  Future<Situation> _remedy(Situation s, SituationFacts f) async {
    if (!s.automatic || _acting) {
      return s;
    }
    _acting = true;
    _notify();
    try {
      switch (s.kind) {
        case SituationKind.phoneForgotBridge:
          return await _adoptForgotten(s, f);
        case SituationKind.bridgeHostingOwnNetwork:
          return await _joinHosted(s, f);
        case SituationKind.bridgeMovedAddress:
          return await _relearnAddress(s, f);
        case SituationKind.deviceClockUnset:
          return await _setClock(s, f);
        case SituationKind.bridgeOutOfRange:
          return await _keepTrying(s, f);
        // Never automatic. Listed rather than defaulted so that adding a kind
        // is a decision someone has to make in this file.
        case SituationKind.bluetoothOff:
        case SituationKind.permissionMissing:
        case SituationKind.neverSetUp:
        case SituationKind.bridgeWasReset:
        case SituationKind.bridgeNotPairedToBase:
        case SituationKind.firmwareTooOld:
        case SituationKind.staleCook:
        case SituationKind.healthy:
          return s;
      }
    } on Object {
      // A remedy that failed leaves the present-tense cause and its human
      // action on screen. Never a past-tense report of something that did not
      // happen.
      return s;
    } finally {
      _acting = false;
    }
  }

  /// #4 — the phone forgot; the bridge did not. **The device holds the
  /// identity, and it still holds it**, so adopting it back is safe and needs
  /// no permission from anyone.
  Future<Situation> _adoptForgotten(Situation s, SituationFacts f) async {
    final name = f.bondedBridgeName ?? f.visibleApSsid ?? '';
    final bonded = await _quiet(probe.bondedBridge);
    final adopted = bonded != null && bonded.deviceId.isNotEmpty;
    if (adopted) {
      await prefs?.recordBleBridge(bonded.deviceId);
    }
    final up = await shell.retryNow();
    if (name.isEmpty || (!adopted && !up)) {
      // Nothing was written and nothing came up. The unresolved copy already
      // says the app is reconnecting to it, which is exactly what it is
      // doing — claiming more than that would be the failure this whole
      // layer exists to end, pointed the other way.
      return s;
    }
    return Situation(
      kind: s.kind,
      headline: up ? 'Reconnected to $name' : 'Remembered $name again',
      detail: up
          ? 'This phone had no record of it, but the two were still paired. '
                'It is back, and nothing was lost — the bridge recorded the '
                'whole time.'
          : 'This phone had no record of it, but the two are still paired, so '
                'the app has taken it back on. Still trying to reach it.',
      automatic: true,
      resolvedAutomatically: true,
    );
  }

  /// #5 — it could not reach the network it knew, so it made one.
  ///
  /// The automatic part is joining it. That needs a platform that will join a
  /// named network on this app's behalf **and** the key to it, and the app
  /// deliberately stores no Wi-Fi key (05 §5.9) — so on most phones the join
  /// cannot be made, and then the honest thing is to name the cause and offer
  /// the one action, not to report a fix that did not happen.
  ///
  /// Either way this ends the bench failure it was written for: a bridge
  /// hosting its own network, reachable over Bluetooth, is now a named
  /// situation instead of a retry counter.
  Future<Situation> _joinHosted(Situation s, SituationFacts f) async {
    final ssid = f.visibleApSsid ?? '';
    if (ssid.isEmpty || _joinAttempted.contains(ssid)) {
      return s;
    }
    _joinAttempted.add(ssid);
    final joined = await probe.joinNetwork(ssid);
    if (!joined) {
      return s;
    }
    final up = await shell.retryNow();
    if (!up) {
      return s;
    }
    return Situation(
      kind: s.kind,
      headline: 'Joined your bridge’s own network',
      detail:
          'It could not reach the network it knew, so it made one and this '
          'phone joined it. Nothing was lost — it recorded the whole time.',
      actionLabel: s.actionLabel,
      automatic: true,
      resolvedAutomatically: true,
    );
  }

  /// #6 — it answers, but not where it used to. A router handed it a new
  /// lease, or it moved between networks. Purely a local write: nothing about
  /// the device changes, so there is nothing to verify beyond the read that
  /// produced the address.
  Future<Situation> _relearnAddress(Situation s, SituationFacts f) async {
    final address = f.reachedAddress ?? '';
    if (address.isEmpty) {
      return s;
    }
    await prefs?.recordConnection(
      address,
      bridgeId: f.reachedDeviceId,
      atMs: f.nowUnixMs,
    );
    return Situation(
      kind: s.kind,
      headline: 'Learned your bridge’s new address',
      detail:
          'It is at ${_bare(address)} now, and the app has remembered that — '
          'the next launch will find it straight away.',
      automatic: true,
      resolvedAutomatically: true,
    );
  }

  /// #9 — it has no time of day, so cooks cannot be dated.
  ///
  /// **Verified by read-back** (§16.6): the write is not reported until the
  /// device says its clock is set. A `setTime` that was accepted and dropped
  /// looks exactly like one that worked, from the sending end.
  Future<Situation> _setClock(Situation s, SituationFacts f) async {
    final transport = shell.transport;
    if (transport == null) {
      return s;
    }
    await transport.control(ControlCommand.setTime(unixMs: _now()));
    final valid = await _clockValid(transport, f.reachedDeviceId);
    if (valid != true) {
      return s;
    }
    return Situation(
      kind: s.kind,
      headline: 'Set your bridge’s clock',
      detail:
          'It had no time of day, so cooks could not be dated. It has this '
          'phone’s clock now, and the readings it already took are still in '
          'order.',
      automatic: true,
      resolvedAutomatically: true,
    );
  }

  /// #11 — everything is remembered and nothing answers.
  ///
  /// The remedy is to keep trying, which is only worth *reporting* when it
  /// worked. A failed retry leaves the present-tense copy — and that copy
  /// carries `lastSeenUnixMs`, which is the whole difference between a state
  /// and information.
  Future<Situation> _keepTrying(Situation s, SituationFacts f) async {
    final now = _now();
    if (now - _lastRetryMs < retryCooldown.inMilliseconds) {
      return s;
    }
    _lastRetryMs = now;
    final up = await shell.retryNow();
    if (!up) {
      return s;
    }
    return Situation(
      kind: s.kind,
      headline: 'Reconnected to your bridge',
      detail: 'It is answering again. Nothing was lost while it was away.',
      automatic: true,
      resolvedAutomatically: true,
    );
  }

  // ── 3. the acts a human has to authorise ─────────────────────────────

  /// #7 — adopt the bridge that answered, as this phone's bridge.
  ///
  /// **The one thing this class will not do by itself.** Call it from behind a
  /// cost sheet: it rewrites which device this phone's future readings belong
  /// to. Saved cooks are untouched — they keep the id of the bridge that
  /// recorded them.
  Future<void> adoptReachedBridge() async {
    final f = _facts;
    final id = f?.reachedDeviceId;
    if (f == null || id == null) {
      return;
    }
    _acting = true;
    _notify();
    try {
      final address = f.reachedAddress ?? '';
      if (address.isNotEmpty) {
        await prefs?.recordConnection(address, bridgeId: id, atMs: _now());
      }
      final bonded = await _quiet(probe.bondedBridge);
      if (bonded != null && bonded.deviceId.isNotEmpty) {
        await prefs?.recordBleBridge(bonded.deviceId, bridgeId: id);
      }
    } on Object {
      // Nothing was adopted; the situation stands and the sheet can be
      // reopened. Silence here beats a crash on the device page.
    } finally {
      _acting = false;
      _notify();
    }
    await evaluate();
  }

  /// The two acts the OS owns. True when the world changed and the caller
  /// should re-evaluate.
  Future<bool> runOsAct() async {
    switch (act) {
      case SituationAct.openBluetooth:
        return probe.openBluetoothSettings();
      case SituationAct.grantPermission:
        return probe.requestMissingPermission();
      case SituationAct.none:
      case SituationAct.runSetup:
      case SituationAct.pairBase:
      case SituationAct.adoptBridge:
      case SituationAct.switchNetwork:
      case SituationAct.updateFirmware:
      case SituationAct.endCook:
        return false;
    }
  }

  // ── plumbing ─────────────────────────────────────────────────────────

  /// Runs [read] and turns any failure into "not known".
  static Future<T?> _quiet<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } on Object {
      return null;
    }
  }

  static String? _blankToNull(String? v) =>
      v == null || v.isEmpty ? null : v;

  /// `http://10.0.0.7/` → `10.0.0.7`. Copy names a place, never a URL scheme.
  static String _bare(String url) => url
      .replaceFirst(RegExp('^https?://'), '')
      .replaceFirst(RegExp(r'/$'), '');

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
