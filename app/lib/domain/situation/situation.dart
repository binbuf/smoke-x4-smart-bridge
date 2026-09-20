/// **Reconciliation** — what the phone remembers, versus what is actually
/// there (design 16 §16.3).
///
/// The app has always had a connection *supervisor*: it reconnects, it races
/// lanes, it backs off. What it has never had is a layer that **reconciles** —
/// that compares what the phone remembers against what it can observe and what
/// the device says when reached, and turns the difference into a named
/// situation with a cause and a remedy.
///
/// Without it, `LaunchState` had four variants and **every mismatch in the
/// world collapsed into "Offline · retry 6"**. Observed on the bench: a bridge
/// was reflashed, came up hosting its own access point, and the app — which
/// knew its Bluetooth bond, its device id and its last address — sat on a retry
/// counter indefinitely, telling the user nothing and doing nothing. That is
/// the failure this library exists to end.
///
/// **Pure.** Facts in, one [Situation] out. No I/O, no Flutter, no plugins —
/// so every recovery path in the product is decidable at a desk, which is the
/// only way they get tested at all. The acting on it lives in
/// `features/shell/situation_resolver.dart`.
library;

import 'package:meta/meta.dart';

/// What kind of trouble, in priority order. **The order is the semantics**:
/// `SituationKind.values` is sorted most-blocking first, and the reconciler
/// returns the first that applies. One situation at a time, never a list — a
/// list of problems is a triage job handed to a tired person at 3 a.m.
enum SituationKind {
  /// The OS radio is off. Nothing else can be diagnosed through it.
  bluetoothOff,

  /// A permission the app needs is not granted.
  permissionMissing,

  /// Nothing has ever been set up on this phone.
  neverSetUp,

  /// The phone forgot, but the bridge did not: a bond or a visible AP names a
  /// bridge this phone has no record of. Adopting it is safe and automatic —
  /// the *device* is the one with the identity, and it still has it.
  phoneForgotBridge,

  /// The bridge could not reach the network it knew, so it is hosting its own.
  bridgeHostingOwnNetwork,

  /// It answers, but not where it used to.
  bridgeMovedAddress,

  /// It answers, and it is **not the bridge this phone was set up with**.
  /// The one situation that is never resolved automatically.
  bridgeWasReset,

  /// Reached, but it has never met a Smoke X base.
  bridgeNotPairedToBase,

  /// Reached, but its clock was never set, so cooks cannot be dated.
  deviceClockUnset,

  /// Reached, but too old for something the app needs.
  firmwareTooOld,

  /// Everything is remembered and nothing answers.
  bridgeOutOfRange,

  /// A cook is on screen for a bridge this phone no longer talks to.
  staleCook,

  /// Nothing to say.
  healthy,
}

/// Everything the reconciler is allowed to know. Every field is nullable and
/// **null means "not known yet"**, which is distinct from false — a bond we
/// have not checked for is not a bond that is absent, and treating them alike
/// is how an app tells someone their bridge was reset while it is booting.
@immutable
class SituationFacts {
  const SituationFacts({
    this.rememberedBridgeId,
    this.rememberedBaseUrl,
    this.rememberedBleDeviceId,
    this.lastSeenUnixMs,
    this.hasRunningCook = false,
    this.runningCookBridgeId,
    this.bluetoothOn,
    this.missingPermission,
    this.bondedBridgeName,
    this.visibleApSsid,
    this.reachedDeviceId,
    this.reachedAddress,
    this.reachedNetMode,
    this.reachedApSsid,
    this.pairedToBase,
    this.deviceClockValid,
    this.supportsFullHistory,
    this.nowUnixMs = 0,
  });

  // ── what the phone remembers ──────────────────────────────────────
  final String? rememberedBridgeId;
  final String? rememberedBaseUrl;
  final String? rememberedBleDeviceId;
  final int? lastSeenUnixMs;
  final bool hasRunningCook;

  /// The bridge the running cook was recorded against.
  ///
  /// **Not the same as [rememberedBridgeId].** They diverge for exactly one
  /// reason, and it is the reason [SituationKind.staleCook] exists: the user
  /// adopted a different bridge, so what the phone *remembers* moved on while
  /// the cook on screen did not. Comparing the remembered id instead — which
  /// is what this did first — made the guard a strict subset of
  /// [SituationKind.bridgeWasReset]'s, so it fired first every time and
  /// `staleCook` was unreachable in every possible input.
  final String? runningCookBridgeId;

  // ── what is observable right now ──────────────────────────────────
  final bool? bluetoothOn;

  /// A human name for the one missing permission, or null.
  final String? missingPermission;

  /// A bridge this phone is OS-bonded to, if any — the tell that the phone was
  /// reset but the pairing survived.
  final String? bondedBridgeName;

  /// A `SmokeBridge-*` access point in range, if any.
  final String? visibleApSsid;

  // ── what the device said when reached (all null if not reached) ───
  final String? reachedDeviceId;
  final String? reachedAddress;

  /// `'ap'` or `'sta'`.
  final String? reachedNetMode;

  /// The network the device says it is on — the one it is *hosting* when
  /// [reachedNetMode] is `'ap'`.
  ///
  /// This is the device's own answer, read over whichever lane is up, and it
  /// is why [visibleApSsid] can stay null on principle: the phone would need
  /// the location permission to name the networks around it, and the bridge
  /// will simply tell us over Bluetooth. Naming the network is the difference
  /// between "your bridge is hosting its own network" and "your bridge is
  /// hosting *SmokeBridge-8274*" — the second one a person can act on from
  /// their Wi-Fi settings.
  final String? reachedApSsid;
  final bool? pairedToBase;
  final bool? deviceClockValid;
  final bool? supportsFullHistory;

  final int nowUnixMs;

  bool get reached => reachedDeviceId != null;
  bool get remembersAnything =>
      rememberedBridgeId != null ||
      rememberedBaseUrl != null ||
      rememberedBleDeviceId != null;
}

/// One named situation: what happened, what is being done, what the human can
/// do about it.
@immutable
class Situation {
  const Situation({
    required this.kind,
    required this.headline,
    this.detail = '',
    this.actionLabel = '',
    this.automatic = false,
    this.resolvedAutomatically = false,
  });

  static const Situation ok = Situation(
    kind: SituationKind.healthy,
    headline: '',
  );

  final SituationKind kind;

  /// What happened, in the user's terms. Never a mechanism, never a code.
  final String headline;

  /// One or two sentences of consequence. What it means for the cook.
  final String detail;

  /// The single action, or empty when there is nothing for a human to do.
  final String actionLabel;

  /// The app can fix this itself. **It does, and then reports in the past
  /// tense** — a banner offering to do something it could simply have done is
  /// an app making its problem into the user's decision.
  final bool automatic;

  /// Set once the app HAS fixed it, so the banner can say so and retire.
  final bool resolvedAutomatically;

  bool get isHealthy => kind == SituationKind.healthy;

  /// Whether this warrants interrupting the temperatures. `bridgeOutOfRange`
  /// deliberately does not: the transport chip already says offline, and a
  /// second banner saying the same thing is noise on the one screen that must
  /// stay readable.
  bool get showsBanner =>
      !isHealthy && kind != SituationKind.bridgeOutOfRange;

  /// The same situation, fixed, said in the past tense.
  ///
  /// [detail] defaults to **clearing** the original, because the original is
  /// present tense ("joining it now") and reads as a lie once the thing is
  /// done. `/device` wants the full explanation though (§16.6), so a caller
  /// that has past-tense detail passes it rather than rebuilding the whole
  /// value — which is what callers were doing while this dropped it.
  ///
  /// The action always clears: it has already been taken.
  Situation resolved(String headline, {String detail = ''}) => Situation(
    kind: kind,
    headline: headline,
    detail: detail,
    automatic: automatic,
    resolvedAutomatically: true,
  );
}

/// Reconcile. Returns the single highest-priority situation.
///
/// The ordering is the whole design: a missing permission is diagnosed before a
/// missing bridge, because a bridge cannot be found through a radio that is
/// switched off, and telling someone their bridge is unreachable when the real
/// answer is "Bluetooth is off" sends them to the yard for nothing.
Situation reconcile(SituationFacts f) {
  // 1–2. The OS is in the way. Nothing below can be trusted through it.
  if (f.bluetoothOn == false) {
    return const Situation(
      kind: SituationKind.bluetoothOff,
      headline: 'Bluetooth is off',
      detail:
          'The app reaches your bridge over Bluetooth when Wi-Fi cannot. The '
          'bridge is still recording either way.',
      actionLabel: 'Turn on Bluetooth',
    );
  }
  final permission = f.missingPermission;
  if (permission != null && permission.isNotEmpty) {
    return Situation(
      kind: SituationKind.permissionMissing,
      headline: '$permission is off',
      detail:
          'The app needs it to reach your bridge. Your cooks are safe — the '
          'bridge records on its own.',
      actionLabel: 'Allow $permission',
    );
  }

  // 3–4. Does this phone know a bridge at all?
  if (!f.remembersAnything) {
    // The phone was reset but the pairing survived on the device side. Adopt
    // it: the DEVICE holds the identity, and it still holds it.
    final bonded = f.bondedBridgeName ?? f.visibleApSsid;
    if (bonded != null && bonded.isNotEmpty) {
      return Situation(
        kind: SituationKind.phoneForgotBridge,
        headline: 'Found $bonded',
        detail:
            'This phone has no record of it, but they are still paired. '
            'Reconnecting to it now.',
        automatic: true,
      );
    }
    return const Situation(
      kind: SituationKind.neverSetUp,
      headline: 'No bridge set up yet',
      detail: 'Set one up and it starts recording straight away.',
      actionLabel: 'Set up a bridge',
    );
  }

  // 7. Identity, and it is NEVER automatic. Adopting a reset bridge silently
  // would attach this phone's history to a device that did not record it.
  final reachedId = f.reachedDeviceId;
  final rememberedId = f.rememberedBridgeId;
  if (reachedId != null &&
      rememberedId != null &&
      reachedId != rememberedId) {
    return Situation(
      kind: SituationKind.bridgeWasReset,
      headline: 'This is a different bridge',
      detail:
          'It answers to $reachedId; this phone was set up with '
          '$rememberedId. Your saved cooks stay on this phone either way.',
      actionLabel: 'Use this bridge instead',
    );
  }

  // 5–6. Reached, but somewhere else than expected.
  if (f.reached) {
    if (f.reachedNetMode == 'ap') {
      // Name the network when the device told us what it is. "Your bridge is
      // hosting its own network" is a sentence; "…hosting SmokeBridge-8274"
      // is something you can go and act on from your Wi-Fi settings, which
      // matters because joining it is the one remedy the app cannot perform
      // for you — it holds no Wi-Fi key by design (05 §5.9).
      final ssid = f.reachedApSsid;
      return Situation(
        kind: SituationKind.bridgeHostingOwnNetwork,
        headline: ssid == null
            ? 'Your bridge is hosting its own network'
            : 'Your bridge is hosting $ssid',
        detail:
            'It could not reach the network it knew, so it made one. Nothing '
            'has been lost — it has been recording the whole time.',
        actionLabel: 'Put it back on your Wi-Fi',
        automatic: true,
      );
    }
    final address = f.reachedAddress;
    if (address != null &&
        f.rememberedBaseUrl != null &&
        address.isNotEmpty &&
        address != f.rememberedBaseUrl) {
      return Situation(
        kind: SituationKind.bridgeMovedAddress,
        headline: 'Your bridge moved',
        detail: 'It is at $address now. The app has remembered that.',
        automatic: true,
      );
    }
    // 8–10. Reached and correctly identified — now, is it useful?
    if (f.pairedToBase == false) {
      return const Situation(
        kind: SituationKind.bridgeNotPairedToBase,
        headline: 'Your bridge hasn’t met your Smoke X yet',
        detail:
            'It is working — it just has nothing to listen to. Hold SYNC on '
            'the base station and the two introduce themselves.',
        actionLabel: 'Pair the base station',
      );
    }
    if (f.deviceClockValid == false) {
      return const Situation(
        kind: SituationKind.deviceClockUnset,
        headline: 'Your bridge doesn’t know the time',
        detail:
            'Readings are still recorded and still in order — they just have '
            'no date yet. Setting it from this phone.',
        automatic: true,
      );
    }
    if (f.supportsFullHistory == false) {
      return const Situation(
        kind: SituationKind.firmwareTooOld,
        headline: 'This bridge can only send the last 2 hours over Bluetooth',
        detail:
            'A firmware update adds whole cooks over Bluetooth. Until then, '
            'connect over Wi-Fi for the full history.',
        actionLabel: 'Update the firmware',
      );
    }
    // 12. Reached, identified and healthy — but the cook on screen was
    // recorded against a DIFFERENT bridge. Reachable only after an adoption:
    // the remembered id moved to the new device and the cook did not follow.
    final cookBridge = f.runningCookBridgeId;
    if (f.hasRunningCook && cookBridge != null && cookBridge != reachedId) {
      return const Situation(
        kind: SituationKind.staleCook,
        headline: 'This cook was recorded on another bridge',
        detail:
            'Its targets cannot be checked against these readings. The cook '
            'itself is safe in your history either way.',
        actionLabel: 'End the cook',
      );
    }
    return Situation.ok;
  }

  // 5 (not reached). We cannot reach it, but we can SEE it hosting.
  final ap = f.visibleApSsid;
  if (ap != null && ap.isNotEmpty) {
    return Situation(
      kind: SituationKind.bridgeHostingOwnNetwork,
      headline: 'Your bridge is hosting its own network',
      detail:
          'It shows up as $ap. It could not reach your Wi-Fi, so it made its '
          'own — joining it now.',
      actionLabel: 'Join $ap',
      automatic: true,
    );
  }

  // 11. Remembered, and nothing answers. The chip already says offline, so
  // this one does not raise a banner — but it still carries the last-seen,
  // which is the difference between a state and information.
  return Situation(
    kind: SituationKind.bridgeOutOfRange,
    headline: 'Can’t reach your bridge',
    detail: _lastSeen(f),
    automatic: true,
  );
}

/// "Last seen 12 minutes ago" — never a bare "offline".
String _lastSeen(SituationFacts f) {
  final seen = f.lastSeenUnixMs;
  if (seen == null || f.nowUnixMs <= 0) {
    return 'It is still recording on its own. The app keeps trying.';
  }
  final ago = Duration(milliseconds: f.nowUnixMs - seen);
  final when = switch (ago.inSeconds) {
    < 90 => 'moments ago',
    < 3600 => '${ago.inMinutes} minutes ago',
    < 86400 => '${ago.inHours} hours ago',
    _ => '${ago.inDays} days ago',
  };
  return 'Last seen $when. It is still recording on its own, and the app '
      'keeps trying.';
}
