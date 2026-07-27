/// A23.1 — hop 2 gesture copy and the three unmeasured timing constants
/// (design 13 §13.2.2).
///
/// WHY this file exists at all: three facts about the Smoke X sync handshake
/// are genuinely unmeasured, and all three are *timing* (§13.2.2). The design
/// mandate is that they live as named constants in ONE file with the
/// confidence marker in the comment, so that "if the bench says the window is
/// 15 s rather than 60, three constants change and no screen is redesigned."
/// This is that file. The listen budget is *derived*, never hard-coded, so a
/// bench correction to [kSyncWindowS] re-derives everything downstream.
///
/// Copy lives here too (the SYNC-hold gesture and the per-reason failure
/// lines) so the illustrated hop-2 screens and the machine's failure mapping
/// read from a single source and cannot drift from each other.
library;

import 'dart:math' as math;

/// The three unmeasured constants (§13.2.2), each with its confidence marker.
///
/// [K] verified · [I] inferred · [?] unknown — the marker convention from
/// 02 §2, carried through the design doc.
class BaseSyncTiming {
  const BaseSyncTiming._();

  /// **[?]** How long the base keeps its sync window open before giving up.
  /// Owner-reported gesture is "hold SYNC for a few seconds"; the *window*
  /// this opens on the base is unmeasured. Drives the derived [listenBudget]
  /// and the "did it register?" fallback timing. Default 60 s; the bench may
  /// say 15 s (§13.2.2) — change only this and re-run.
  static const int kSyncWindowS = 60;

  /// **[K]** Floor on the listen budget: long enough to cover fifteen 3 s
  /// beacons, short enough that a failed attempt does not feel abandoned
  /// (§13.2.2). Fifteen beacons × 3 s = 45 s.
  static const int kListenFloorS = 45;

  /// **[I]** Interval to the first *state* message after the SYNC ACK — one
  /// broadcast period, inferred at 30 s (§13.2.2). Once the base is `heard`,
  /// this is the watchdog: heard but no reading within [kHeardWaitS] is
  /// `timeout_no_state`, not `timeout_no_beacon`.
  static const int kHeardWaitS = 30;

  /// The overall listen budget, DERIVED not fixed (§13.2.2):
  /// `max(kListenFloorS, 2 × kSyncWindowS)`. A bench correction to
  /// [kSyncWindowS] flows through here automatically.
  static Duration get listenBudget =>
      Duration(seconds: math.max(kListenFloorS, 2 * kSyncWindowS));

  /// The heard-but-no-reading watchdog, as a [Duration].
  static Duration get heardWait => const Duration(seconds: kHeardWaitS);

  /// How often the machine re-reads the listen seam while a window is open.
  /// A poll, not a notify: `pair_status` (§13.8.2) does not exist in firmware
  /// yet, so 1 Hz local polling stands in for the real state-change notify.
  static const Duration pollInterval = Duration(seconds: 1);
}

/// The user-facing sentences for hop 2, in one place so the illustrated
/// screens and the machine's reason mapping cannot disagree (§13.2.2).
class BaseSyncCopy {
  const BaseSyncCopy._();

  /// `SetupBaseIntro` headline + gesture instruction.
  static const String introHeadline = "Now let's find your thermometer";
  static const String introGesture =
      'Press and hold SYNC on your Smoke X base for a few seconds, until its '
      'screen shows that it is syncing.';
  static const String introPrimary = "I've done it — start listening";
  static const String introSkip = "My base isn't here right now";

  /// `SetupBaseListening`.
  static const String listening = 'Listening for your Smoke X…';
  static const String listeningKeepClose =
      'Keep the base within about 30 metres of the bridge.';

  /// The `garbled > 0` sub-state — hearing something too faint to read.
  static const String garbledFaint =
      "We're hearing something, but it's too faint to read. Move the base "
      'closer.';

  /// `SetupBaseHeard` — the ~30 s narrated wait for the first reading.
  static String heard(String? deviceId) =>
      'Found it — Smoke X ${deviceId ?? ''}. Waiting for its first reading…';

  /// `SetupBaseSkipped` — the non-punitive skip's resumable card.
  static const String skippedCard =
      "Pair your Smoke X — the bridge can't read temperatures until you do.";

  /// Per-reason failure copy (§13.2.2 failure table). Headline shown on the
  /// phone; the machine picks the reason.
  static String failureHeadline(BaseSyncFailure reason) => switch (reason) {
    BaseSyncFailure.timeoutNoBeacon =>
      "We didn't hear your Smoke X. Its sync window may have closed.",
    BaseSyncFailure.timeoutNoState =>
      'We heard your Smoke X but it never sent a reading. Move it closer and '
          'try again.',
    BaseSyncFailure.garbled =>
      "There's a lot of radio noise here. Try moving the bridge away from the "
          "smoker's metal body, or closer to the base.",
    BaseSyncFailure.ackFailed =>
      "We couldn't answer your Smoke X. Trying again…",
  };
}

/// Why a listen window ended without a confirmed pairing (§13.2.2 · maps 1:1
/// to the firmware `pair_fail` enum §13.8.2). `ackFailed` is the only one the
/// machine handles by auto-retry rather than a user action.
enum BaseSyncFailure {
  /// Nothing decodable was ever heard within the budget.
  timeoutNoBeacon,

  /// The base was heard, but no reading arrived within [BaseSyncTiming.heardWait].
  timeoutNoState,

  /// The ACK back to the base failed (guard/tx). Auto-retried.
  ackFailed,

  /// Sustained noise: more than three garbled beacons.
  garbled,
}
