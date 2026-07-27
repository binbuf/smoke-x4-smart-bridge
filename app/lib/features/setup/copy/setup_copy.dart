/// A23.3 — every user-facing string for hop 0 (preflight) and hop 1 (find +
/// pair) of guided setup (design 13 §13.2.0–§13.2.1).
///
/// WHY a copy file, and why it is separate from the screens: 13 §13.3.7 sets a
/// grade-6 reading-level gate and 14 §14.11 says `ui/` (and, by the same rule,
/// the projection screens over it) *owns no user-facing strings* — they take
/// them. Centralising the words here is what lets the reading-level gate run
/// over one file instead of fifteen widgets, and what stops the passkey screen
/// and the "we couldn't hear the code" failure from drifting apart. Every line
/// is the copy the design spec dictates (§13.2.0 checks 0–4, §13.2.1 scan / no-
/// bridges / passkey / the four bond outcomes), kept plain: no "GATT", no
/// "adapter", no "advertisement", no six-digit field the phone never sees.
library;

/// The hop-0/hop-1 strings, as `static const` so a golden or a reading-level
/// script reads them without constructing a widget. Interpolated lines are
/// `static` methods for the same reason.
abstract final class SetupCopy {
  // ── hop 0, check 2 — the permission primer (§13.2.0) ──────────────────
  // Not optional: the OS cannot tell a first denial from a permanent one until
  // it has prompted once, so this screen earns the prompt.
  static const String primerTitle = 'Smoke Bridge needs to find nearby devices';
  static const String primerBody =
      'Your phone uses Bluetooth to find your bridge and set it up. We never '
      'use it to know where you are, and we never search in the background.';
  static const String primerReassure1 = 'Only used to set up your bridge';
  static const String primerReassure2 = 'Never runs in the background';
  static const String primerReassure3 = 'Never used to find where you are';
  static const String primerPrimary = 'Continue';
  static const String primerNotNow = 'Not now';

  // ── hop 0, check 4 — Bluetooth is off (§13.2.0) ───────────────────────
  static const String btOffTitle = 'Turn on Bluetooth';
  static const String btOffBody =
      "Your phone's Bluetooth is off. The app needs it to find your bridge and "
      'set it up.';
  static const String btOffPrimary = 'Turn on Bluetooth';
  static const String btOffOpenSettings = 'Open Bluetooth settings';
  static const String btOffTurnedOn = 'I turned it on';

  // ── hop 0, check 0 — no Bluetooth hardware, terminal (§13.2.0) ─────────
  // A phone with no Bluetooth cannot learn the bridge's network name or
  // password any way but off the glass, so the honest screen is the
  // instruction and no button that leads nowhere.
  static const String unsupportedTitle =
      "This phone can't set up over Bluetooth";
  static const String unsupportedBody =
      "This phone doesn't have the Bluetooth the app needs. You can still set "
      'up your bridge by hand: read the network name and password from the '
      "bridge's screen, join that Wi-Fi network in your phone's settings, then "
      'come back.';

  // ── hop 0, check 3 — permission denied (§13.2.0) ──────────────────────
  static const String deniedTitle = 'Allow Bluetooth to continue';
  static const String deniedBody =
      'Smoke Bridge needs your OK to find nearby devices. It is only used to '
      'set up your bridge.';
  static const String deniedAllow = 'Allow';
  static const String deniedNotNow = 'Not now';

  // Permanent denial: the OS will never show the dialog again, so the only way
  // through is the app's own settings.
  static const String deniedPermanentTitle = 'Allow Bluetooth in Settings';
  static const String deniedPermanentBody =
      "Your phone won't ask again, so you'll need to turn it on yourself. Open "
      'Settings, find Smoke Bridge, and turn on Nearby devices.';
  static const String deniedOpenAppSettings = 'Open app settings';
  static const String deniedAllowed = "I've allowed it";

  // ── hop 0, check 1 — location services off, Android SDK <= 32 (§13.2.0) ─
  static const String locationTitle = 'Turn on location to find your bridge';
  static const String locationBody =
      'On this version of Android, a Bluetooth search needs location turned on. '
      'The app never uses where you are — Android just asks for it before it '
      'will search.';
  static const String locationOpenSettings = 'Open location settings';
  static const String locationTurnedOn = 'I turned it on';

  // ── hop 1 — the scan / find list (§13.2.1) ────────────────────────────
  static const String scanningTitle = 'Looking for your bridge';
  static const String scanningBody =
      "Make sure it's plugged in. The screen should be lit.";
  static const String scanningCancel = 'Cancel';

  // The blob-line fallbacks, when the bridge advertised no live reading.
  static const String rowPairedIdle = 'paired, resting';
  static const String rowNotPaired = 'not paired with a Smoke X yet';

  // ── hop 1 — 10 s, nothing found (§13.2.1) ─────────────────────────────
  // A checklist of the bridge's own tells, ordered by how likely each is —
  // never a bare "check that it is on".
  static const String noBridgesTitle = "We can't see your bridge yet";
  static const String noBridgesCheck1 =
      'Is its screen lit? If not, hold the PRG button for 5 seconds.';
  static const String noBridgesCheck2 =
      'Are you within about 10 metres, in the same room?';
  static const String noBridgesCheck3 =
      'Did it just start up? Give it 10 more seconds.';
  static const String noBridgesLookAgain = 'Look again';
  static const String noBridgesManual =
      'My bridge is already set up — enter its address';

  // ── hop 1 — the already-provisioned fork (§13.2.1) ────────────────────
  static const String addPhoneTitle = 'This bridge is already set up';
  static const String addPhoneBody =
      "It's already on your Wi-Fi. Add this phone in a few seconds — there's no "
      'need to set up the network again.';
  static const String addPhonePrimary = 'Add this phone';
  static const String addPhoneOther = 'Set up a different bridge';

  // ── hop 1 — the passkey screen (§13.2.1) ──────────────────────────────
  // The highest-value screen in the app. It does not host a six-digit field;
  // it points at the bridge's own screen, because the code is generated on the
  // bridge and this phone never learns it.
  static const String pairTitle = 'Look at your bridge';
  static const String pairBody =
      'Your phone is about to ask for a 6-digit code. It is on the bridge screen'
      ' — type it from there, not from here.';
  static const String pairWaiting = "Waiting for your phone's pairing prompt…";
  static const String pairNoPrompt = "I don't see a prompt";
  static const String pairCancel = 'Cancel';
  static String connectingTo(String name) => 'Connecting to $name…';

  // ── hop 1 — 30 s, no OS prompt (§13.2.1) ──────────────────────────────
  static const String notSeenTitle = 'Still waiting for the prompt';
  static const String notSeenBody =
      'Some phones put the pairing request in the notification area instead of '
      'on the screen. Check there for a request to pair with your bridge.';
  static const String notSeenCheckNotifications = 'Check my notifications';
  static const String notSeenRetry = 'Try pairing again';

  // ── hop 1 — bond succeeded, the 3 s payoff (§13.2.1) ──────────────────
  static const String bondedTitle = 'Paired';
  static const String bondedBody =
      'Your phone and bridge are connected. Next, we will find your Smoke X '
      'base.';
  static const String bondedContinue = 'Continue';

  // ── hop 1 — bond outcome 1 of 4: wrong passkey (§13.2.1) ──────────────
  static const String wrongTitle = "That code didn't match";
  static const String wrongBody =
      "The 6-digit code you typed didn't match the one on the bridge screen. "
      "Let's get a fresh code and try once more.";
  static const String wrongRetry = 'Try again';
  static const String wrongStartOver = 'Start over';

  // ── hop 1 — bond outcome 2 of 4: the bridge was reset (§13.2.1) ───────
  static const String rebondTitle = 'This bridge was reset';
  static const String rebondBody =
      "It doesn't recognise this phone any more. Forget \"Smoke Bridge\" in "
      'your Bluetooth settings, then try again.';
  static const String rebondOpenSettings = 'Open Bluetooth settings';
  static const String rebondRetry = 'Try again';

  // ── hop 1 — bond outcome 3 of 4: all 3 bond slots full (§13.2.1) ──────
  static const String fullTitle = 'This bridge already has 3 phones';
  static const String fullBody =
      'A bridge can remember 3 phones at a time. Remove one on the bridge, or '
      'set up a different bridge.';
  static const String fullChooseOther = 'Choose a different bridge';
  static const String fullRemovePhone = 'Remove a phone';

  // ── hop 1 — bond outcome 4 of 4: not a bridge, terminal (§13.2.1) ─────
  // No retry button on a failure retrying can never fix — only "pick another".
  static const String notBridgeTitle = "That's not a Smoke Bridge";
  static const String notBridgeBody =
      "That device isn't a Smoke Bridge, or its software is too old to set up "
      'here. Pick a different one.';
  static const String notBridgeChoose = 'Choose a different device';
}
