/// Re-entry copy — **why am I seeing setup again?** (design 16 §16.4, 13
/// §13.2.4).
///
/// Every sentence here exists to answer one question the old flow never
/// answered. A returning user dropped at "Looking for your bridge" has no way
/// to tell whether the app forgot them, whether the bridge broke, or whether
/// they mis-tapped — so they assume the worst, which is that nothing is saved.
/// These lines say what is already done, what is left, and what caused the
/// difference, in that order.
///
/// The §16.4 rules the file is written to, restated because they are the whole
/// point: say what happened, not what failed; name a cause the user could act
/// on or state plainly that the app is handling it; no jargon, no status codes;
/// sentence case; one idea per sentence; buttons are verbs that name the
/// outcome; **never blame the user**.
library;

import '../setup_entry.dart';

/// The sentences for each way back into setup.
abstract final class SetupResumeCopy {
  const SetupResumeCopy._();

  /// The bridge's name, or a phrase that reads as one. Never an id printed
  /// raw — §16.4 rule 3, and "SmokeBridge-A4F2" is not what anyone calls it.
  static String named(String name) =>
      name.trim().isEmpty ? 'your bridge' : name;

  // ── the re-link, while the Bluetooth link comes back up ───────────────
  // Shown instead of the passkey screen, because a bridge this phone is
  // already bonded to will never ask for a code — and promising one, then
  // never showing it, is the failure the passkey screen exists to prevent.

  static String relinkTitle(String name) => 'Reconnecting to ${named(name)}';

  /// One sentence of *why setup is open*, then one of *what is being done*.
  static String relinkBody(SetupResumeKind kind, String name) {
    final who = named(name);
    return switch (kind) {
      SetupResumeKind.adoptBridge =>
        'This phone lost its record of $who, but the two are still paired. '
            'Picking up from there — you will not need a code again.',
      SetupResumeKind.pairBase =>
        'Your phone and $who are already paired. The only thing left is your '
            'Smoke X.',
      SetupResumeKind.addNetwork =>
        'Your phone and $who are already paired. The only thing left is '
            'Wi-Fi.',
      SetupResumeKind.fresh ||
      SetupResumeKind.bridgeWasReset => 'Getting back in touch with $who.',
    };
  }

  /// The one control on the re-link screen. Setup has nothing to ask for
  /// while it reconnects, so the only honest action is to stop.
  static const String relinkCancel = 'Stop and start over';

  // ── the find list, when the phone is looking for a bridge it knows ────

  /// The scan subtitle when this phone is adopting a bridge it forgot.
  static const String adoptScanBody =
      'This phone has no record of it, but the pairing is still there. Once we '
      'find it, there is no code to type.';

  // ── hop 2, entered directly ───────────────────────────────────────────

  static const String pairBaseWhy =
      'Everything else is set up. Your bridge just has not met your Smoke X '
      'yet, so it has nothing to read.';

  // ── hop 3, entered directly ───────────────────────────────────────────

  /// The bridge has never been on Wi-Fi.
  static const String addNetworkWhy =
      'Bluetooth is already set up and working. Wi-Fi is the part that is not.';

  /// The bridge is on Wi-Fi and the user came back to change it.
  static const String changeNetworkWhy =
      'Your bridge is already set up. Pick a different network here, or leave '
      'it on the one it has.';

  // ── the bridge that came back as somebody else (§16.3 #7) ─────────────
  // The one situation the app must never resolve on its own. Adopting a reset
  // bridge silently would attach this phone's cooks to a device that did not
  // record them.

  static const String resetTitle = 'This bridge has been reset';

  /// Names both identities, because "a different bridge" with no evidence
  /// reads as the app being confused rather than the device having changed.
  static String resetBody({
    required String reachedId,
    required String rememberedId,
  }) {
    final ids = (reachedId.isEmpty || rememberedId.isEmpty)
        ? ''
        : ' It answers to $reachedId; this phone was set up with '
              '$rememberedId.';
    return 'It no longer recognises this phone, so setup has to start from the '
        'beginning.$ids Your saved cooks stay on this phone either way.';
  }

  static const String resetPrimary = 'Set it up as new';
  static const String resetLeave = 'Leave setup';
}
