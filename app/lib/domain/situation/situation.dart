/// N1.19 — reconciliation: what the phone remembers versus what is actually
/// there.
///
/// Pure facts in, one named [Situation] out. The **priority order is the
/// semantics**: a bridge cannot be found through a radio that is switched off,
/// so a missing permission is diagnosed before a missing bridge. Every field of
/// [SituationFacts] is nullable and **null means "not known yet"**, which is
/// distinct from false.
library;

import 'package:meta/meta.dart';

/// What kind of trouble, in priority order — `values` is sorted most-blocking
/// first and [reconcile] returns the first that applies.
enum SituationKind {
  /// The OS radio is off. Nothing else can be diagnosed through it.
  bluetoothOff,

  /// A permission the app needs is not granted.
  permissionMissing,

  /// Nothing has ever been set up on this phone.
  neverSetUp,

  /// The phone forgot, but the bridge did not. Adopting is safe and automatic.
  phoneForgotBridge,

  /// The bridge could not reach the network it knew, so it hosts its own.
  bridgeHostingOwnNetwork,

  /// It answers, but not where it used to.
  bridgeMovedAddress,

  /// It answers, and it is not the bridge this phone was set up with. The one
  /// situation never resolved automatically.
  bridgeWasReset,

  /// Reached, but it has never met a Smoke X base.
  bridgeNotPairedToBase,

  /// Reached, but its clock was never set, so cooks cannot be dated.
  deviceClockUnset,

  /// Reached, but too old for something the app needs.
  firmwareTooOld,

  /// Everything remembered and nothing answers.
  bridgeOutOfRange,

  /// A cook is on screen for a bridge this phone no longer talks to.
  staleCook,

  /// Nothing to say.
  healthy,
}

/// Everything the reconciler is allowed to know.
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

  /// The bridge the running cook was recorded against — not the same as
  /// [rememberedBridgeId], which is what makes [SituationKind.staleCook]
  /// reachable after an adoption.
  final String? runningCookBridgeId;

  // ── what is observable now ────────────────────────────────────────
  final bool? bluetoothOn;

  /// A human name for the one missing permission, or null.
  final String? missingPermission;

  /// A bridge this phone is OS-bonded to, if any.
  final String? bondedBridgeName;

  /// A `SmokeBridge-*` access point in range, if any.
  final String? visibleApSsid;

  // ── what the device said when reached (all null if not reached) ───
  final String? reachedDeviceId;
  final String? reachedAddress;

  /// `'ap'` or `'sta'`.
  final String? reachedNetMode;
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

  /// One or two sentences of consequence.
  final String detail;

  /// The single action, or empty when there is nothing for a human to do.
  final String actionLabel;

  /// The app can fix this itself, and reports in the past tense once it has.
  final bool automatic;

  /// Set once the app HAS fixed it, so the banner can say so and retire.
  final bool resolvedAutomatically;

  bool get isHealthy => kind == SituationKind.healthy;

  /// Whether this warrants interrupting the temperatures. `bridgeOutOfRange`
  /// deliberately does not: the transport chip already says offline.
  bool get showsBanner => !isHealthy && kind != SituationKind.bridgeOutOfRange;

  /// The same situation, fixed, said in the past tense.
  Situation resolved(String headline, {String detail = ''}) => Situation(
    kind: kind,
    headline: headline,
    detail: detail,
    automatic: automatic,
    resolvedAutomatically: true,
  );
}

/// Reconcile. Returns the single highest-priority situation.
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

  // 3–4. Identity: does this phone know a bridge at all?
  if (!f.remembersAnything) {
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

  // Identity, and it is NEVER automatic.
  final reachedId = f.reachedDeviceId;
  final rememberedId = f.rememberedBridgeId;
  if (reachedId != null && rememberedId != null && reachedId != rememberedId) {
    return Situation(
      kind: SituationKind.bridgeWasReset,
      headline: 'This is a different bridge',
      detail:
          'It answers to $reachedId; this phone was set up with '
          '$rememberedId. Your saved cooks stay on this phone either way.',
      actionLabel: 'Use this bridge instead',
    );
  }

  // Reachability: reached, but somewhere else than expected.
  if (f.reached) {
    if (f.reachedNetMode == 'ap') {
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

    // Usefulness: reached and correctly identified.
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

    // Stale cook: reachable only after an adoption.
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

  // Not reached, but we can SEE it hosting.
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

  // Remembered, and nothing answers.
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
