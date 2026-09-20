/// A23.4 — the hop-2 payoff, hop-3 (Wi-Fi) and finish copy (design 13 §13.2.2,
/// §13.2.3, §13.2.4).
///
/// WHY this file exists separately from the hop-1 agent's `copy/setup_copy.dart`
/// and from `copy/base_sync_copy.dart`: the three copy files are owned by three
/// agents building in parallel, and one string source per owner is what keeps
/// the wave from write-conflicting on a single file (§13.4.1, "one named
/// reviewer reads every string in §13.5 aloud"). The hop-2 *gesture* and
/// *failure* lines already live in [BaseSyncCopy]; this file adds only what the
/// hop-2 *payoff*, all of hop 3, and the finish screens need, so no sentence is
/// duplicated across the two hop-2 files.
///
/// Every reason string here is 1:1 with a `SetupState` field the machine
/// produces (`WifiFailure`, `ApplyingPhase`), so a copy change never has to
/// touch the machine and a state can never render a sentence about the wrong
/// cause — which is failure #5 (13 §13.1), the collapse of six distinct causes
/// into "that password did not work", stated positively.
library;

import '../setup_machine.dart' show ApplyingPhase, WifiFailure;

/// Hop-2 payoff copy (§13.2.2). The gesture, listening and failure lines are in
/// [BaseSyncCopy]; only the confirmed-reading payoff is new here.
abstract final class BasePayoffCopy {
  const BasePayoffCopy._();

  /// `SetupBaseHeard` body — the real ~30 s wait, narrated not spun (§13.2.2).
  static const String heardBody =
      'This can take up to half a minute. Your Smoke X sends a reading about '
      'twice a minute — leave it be.';

  /// `SetupBaseConfirmed` headline (§13.2.2) — never a checkmark, a temperature.
  static const String confirmedHeadline = 'Your bridge is reading temperatures';

  /// The eyebrow above the payoff: `Smoke X · 3F91 · 4 probes`.
  static String confirmedEyebrow(String deviceId, int numProbes) {
    final id = deviceId.isEmpty ? 'your base' : deviceId;
    final probes = numProbes == 1 ? '1 probe' : '$numProbes probes';
    return 'Smoke X · $id · $probes';
  }

  /// Row label for probe [i] (0-based): probe 0 is the pit (§13.2.2 mock).
  static String probeLabel(int i) => i == 0 ? 'Pit' : 'Probe $i';

  static const String confirmedPrimary = 'Continue';

  /// `SetupBaseSkipped` — the non-punitive skip's next step (§13.2.2).
  static const String skippedHeadline = 'No thermometer for now';
  static const String skippedPrimary = 'Put it on Wi-Fi';
}

/// Hop-3 (Wi-Fi) copy (§13.2.3).
abstract final class SetupNetCopy {
  const SetupNetCopy._();

  // ── picker ──────────────────────────────────────────────────────────────
  // A25: Bluetooth is the default connection and already works by this point
  // in setup — Wi-Fi is an upgrade, not a requirement, and the copy says so.
  static const String pickTitle = 'Add Wi-Fi to your bridge?';

  /// Why this screen exists on a first run: Wi-Fi is an upgrade, not a
  /// requirement. A re-entry replaces this half with its own reason (§16.3)
  /// and keeps [pickBand], which is true either way.
  static const String pickReason =
      'Bluetooth is already set up — live temperatures work at the smoker '
      'right now. Wi-Fi adds full cook history, updates, and Home Assistant.';

  /// The one fact about the radio the user needs before they scan the list —
  /// held apart so it survives every rewording of the reason above it.
  static const String pickBand =
      "The bridge uses 2.4 GHz Wi-Fi; a 5 GHz-only network won't appear here.";

  static const String pickSubtitle = '$pickReason $pickBand';

  /// The Bluetooth-only forward action (A25): a first-class way to finish
  /// setup, never a buried "skip". Wi-Fi stays one tap away in Settings.
  static const String bleOnly = 'Use Bluetooth only for now';
  static const String scanning = 'Looking for networks…';
  static const String hiddenNetwork = 'Join a hidden network';

  /// The quiet tertiary hosted link at the bottom of the picker (§13.2.3).
  static const String hostedLink = 'No Wi-Fi where you cook?';
  static const String hostedLinkAction = 'Use the bridge’s own network';

  /// `auth == 5` — the one question the app must not ask (§13.2.3).
  static const String enterpriseDisabled =
      "Work and campus Wi-Fi isn't "
      'supported';

  // ── empty ─────────────────────────────────────────────────────────────
  static const String emptyTitle = "We couldn't find any networks";
  static const String emptySubtitle =
      'Nothing showed up nearby. You can have the bridge host its own network '
      'instead, or look again.';
  static const String emptyLookAgain = 'Look again';

  // ── manual (hidden SSID) ──────────────────────────────────────────────
  static const String manualTitle = 'Join a hidden network';
  static const String manualSubtitle =
      "Type the exact network name — a hidden network won't show up in the "
      'list.';
  static const String manualSsidLabel = 'Network name';
  static const String manualSecurityLabel = 'Security';
  static const String manualPrimary = 'Continue';

  // ── password ──────────────────────────────────────────────────────────
  static const String passwordTitle = 'Enter the password';
  static String passwordSubtitle(String ssid) =>
      ssid.isEmpty ? 'for your network' : 'for $ssid';
  static const String passwordLabel = 'Wi-Fi password';
  static const String passwordPrimary = 'Connect';

  /// The live length rule stated before Connect enables (§13.2.3), so a
  /// too-short PSK is caught here rather than after two 20 s budgets.
  static String passwordHint(int auth) => switch (auth) {
    2 => 'A WEP key is 5 or 13 characters.',
    _ => 'A Wi-Fi password is at least 8 characters.',
  };

  /// Whether [psk] is a valid length for [auth] (WEP 5/13, WPA 8–63).
  static bool passwordValid(int auth, String psk) => switch (auth) {
    0 => true,
    2 => psk.length == 5 || psk.length == 13,
    _ => psk.length >= 8 && psk.length <= 63,
  };

  // ── applying (four narrated phases) ───────────────────────────────────
  /// The narrated line for one phase (§13.2.3). [ssid] fills the join line.
  static String applyingPhase(ApplyingPhase phase, String ssid, bool hosted) {
    final where = ssid.isEmpty ? 'your network' : ssid;
    return switch (phase) {
      ApplyingPhase.sent => 'Sent your network to the bridge',
      ApplyingPhase.joining =>
        hosted
            ? "Starting the bridge's own network"
            : 'The bridge is joining $where',
      ApplyingPhase.gettingAddress => 'Getting an address',
      ApplyingPhase.joiningAp => "Joining the bridge's network",
      ApplyingPhase.checking => 'Checking this phone can reach it',
    };
  }

  /// The ordered phase rows the screen ticks through, by path (§13.2.3).
  static List<ApplyingPhase> applyingSteps(bool hosted) => hosted
      ? const [
          ApplyingPhase.sent,
          ApplyingPhase.joining,
          ApplyingPhase.joiningAp,
          ApplyingPhase.checking,
        ]
      : const [
          ApplyingPhase.sent,
          ApplyingPhase.joining,
          ApplyingPhase.gettingAddress,
          ApplyingPhase.checking,
        ];

  static String applyingTitle(String ssid, bool hosted) => hosted
      ? "Setting up the bridge's network"
      : (ssid.isEmpty ? 'Putting it on Wi-Fi' : 'Putting $ssid on your bridge');

  static const String cancel = 'Cancel';

  // ── wifi failure, by reason byte (§13.2.3) ────────────────────────────
  /// Headline + body for a stated Wi-Fi failure — never "wrong password" for
  /// all six causes (§13.1 #5). 1:1 with [WifiFailure].
  static ({String headline, String body}) wifiFailure(
    WifiFailure reason,
    String ssid,
  ) {
    final where = ssid.isEmpty ? 'that network' : ssid;
    return switch (reason) {
      WifiFailure.wrongPassword => (
        headline: "That password didn't work",
        body: "Check it and try again — you don't need to touch the bridge.",
      ),
      WifiFailure.notFound => (
        headline: "The bridge couldn't find $where",
        body:
            'It may be a 5 GHz network — the bridge only sees 2.4 GHz. Or it '
            'is out of range of where the bridge is sitting.',
      ),
      WifiFailure.assocRefused => (
        headline: 'Your router turned the bridge away',
        body: 'Some routers block new devices, or filter by MAC address.',
      ),
      WifiFailure.noIp => (
        headline: 'The bridge joined but never got an address',
        body:
            "Your router didn't hand it one. Restarting the router usually "
            'fixes this.',
      ),
      WifiFailure.weakSignal => (
        headline: 'The signal is too weak where the bridge is',
        body:
            'It connected, then dropped. Move the bridge closer to your '
            'router.',
      ),
    };
  }

  /// The same six causes, one line each, for the banner above a prefilled
  /// password field. Here rather than on the machine so the short form and the
  /// full-screen form of a cause can never drift apart — and phrased as what
  /// happened, never as what the user got wrong (16 §16.4).
  static String wifiRetryBanner(WifiFailure reason, String ssid) {
    final where = ssid.isEmpty ? 'that network' : ssid;
    return switch (reason) {
      WifiFailure.wrongPassword => "That password didn't work for $where",
      WifiFailure.notFound => "The bridge couldn't find $where",
      WifiFailure.assocRefused => 'Your router turned the bridge away',
      WifiFailure.noIp => 'The bridge joined but never got an address',
      WifiFailure.weakSignal => 'The signal is too weak where the bridge is',
    };
  }

  static const String wifiRetry = 'Try again';
  static const String wifiRetryPassword = 'Try the password again';
  static const String useHosted = 'Use the bridge’s own network';

  // ── unreachable ───────────────────────────────────────────────────────
  static const String unreachableTitle =
      "The bridge is on your Wi-Fi, but this phone can't see it";
  static String unreachableSubtitle(String ip) {
    final at = ip.isEmpty ? '' : ' The bridge is at $ip.';
    return '$at Your phone might be on mobile data, on a guest network, or on a '
            'different Wi-Fi.'
        .trim();
  }

  static const String unreachableAddress = 'Bridge address';
  static const String unreachableRetry = 'My phone is on this network — retry';

  // ── factory reset over Bluetooth (A24.2) ──────────────────────────────
  static const String resetBridge = 'Reset this bridge instead';
  static const String resetConfirmTitle = 'Reset this bridge?';
  static const String resetConfirmBody =
      'This wipes the bridge over Bluetooth — its Wi-Fi setup, paired Smoke X, '
      'saved cooks, and every paired phone — and it restarts factory-fresh. '
      "You'll set it up again from scratch. This can't be undone.";
  static const String resetConfirm = 'Reset the bridge';
  static const String resetDoneTitle = 'The bridge is factory-fresh';
  static const String resetDoneSubtitle =
      'It restarted with nothing saved. To set it up again, forget '
      "'Smoke Bridge' in your phone's Bluetooth settings first, then start over.";
  static const String resetDoneStartOver = 'Set it up from scratch';

  // ── hosted join ───────────────────────────────────────────────────────
  static const String hostedTitle = "Join the bridge's own network";
  static const String hostedSubtitle =
      'Connect this phone to the network the bridge is hosting. It has no '
      'internet — that is expected.';
  static const String hostedRefusedTitle = "We couldn't join it for you";
  static const String hostedRefusedSubtitle =
      'Join the bridge’s network yourself in Wi-Fi settings, using these:';
  static const String hostedNetworkLabel = 'Network';
  static const String hostedPasswordLabel = 'Password';
  static const String hostedJoinForMe = 'Join it for me';
  static const String hostedJoinMyself =
      "I'll join it myself in Wi-Fi settings";
  static const String hostedJoinedAlready = "I've joined it myself";
  static const String hostedRetry = 'Try again';
}

/// Finish copy (§13.2.4).
abstract final class SetupFinishCopy {
  const SetupFinishCopy._();

  static const String nameTitle = 'What should we call it?';
  static const String nameSubtitle =
      'Naming it makes notifications and records legible — especially with two '
      'bridges in the house.';
  static const String nameLabel = 'Bridge name';
  static const String namePlaceholder = 'Backyard smoker';
  static const String unitsLabel = 'Show temperatures in';
  static const String finishPrimary = 'Finish setup';

  static String doneTitle(String name) =>
      name.trim().isEmpty ? 'Your bridge is ready' : '$name is ready';
  static const String doneBluetooth = 'Bluetooth';
  static const String doneSmokeX = 'Smoke X';
  static const String doneWifi = 'Wi-Fi';
  static const String donePaired = 'paired';
  static const String doneNotSetUp = '— not set up';
  static const String doneHosted = 'its own network';

  /// The Wi-Fi row when the cook chose Bluetooth only (A25) — a valid way to
  /// run, framed as the choice it was rather than a gap.
  static const String doneBleOnly = 'Bluetooth only · add Wi-Fi in Settings';
  static const String donePrimary = 'See my probes';

  static String doneBaseValue(String? deviceId, int numProbes) {
    if (deviceId == null || deviceId.isEmpty) {
      return doneNotSetUp;
    }
    final probes = numProbes == 1 ? '1 probe' : '$numProbes probes';
    return '$deviceId · $probes';
  }

  static String doneWifiValue({
    String? ssid,
    String? ip,
    required bool hosted,
  }) {
    if (ssid == null || ssid.isEmpty) {
      // No Wi-Fi at all = the Bluetooth-only choice (A25), not a gap.
      return hosted ? doneHosted : doneBleOnly;
    }
    if (hosted) {
      return '$ssid · hosted';
    }
    return ip == null || ip.isEmpty ? ssid : '$ssid · $ip';
  }

  // ── link lost / fault (cross-cutting, §13.2.0 / §13.2.3 / §13.5.1) ────
  static const String linkLostTitle = 'The connection dropped';
  static const String linkLostSubtitle =
      'We lost the Bluetooth link to your bridge. Move closer and reconnect, '
      'or start over.';
  static const String linkLostReconnect = 'Reconnect';
  static const String linkLostRestart = 'Start over';

  static const String faultTitle = 'Something went wrong';
  static const String faultSubtitle =
      'We hit an unexpected problem during setup. Nothing was harmed — you can '
      'start over.';
  static const String faultDetailLabel = 'Details';
  static const String faultRestart = 'Start over';
}
