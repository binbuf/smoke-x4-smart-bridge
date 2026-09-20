/// Haptics — the touch half of the motion system (newapp §H.2).
///
/// Motion has had five tokens since A19; touch has had scattered
/// `HapticFeedback.heavyImpact()` calls with no vocabulary behind them, which
/// means every buzz in the app felt the same and therefore meant nothing. §H.2
/// asks for the opposite: *"a light impact for advisory, a distinct pattern for
/// critical"*. This file is that vocabulary, and it is in `design/` for exactly
/// the reason [SmokeMotion] is — it is the single seam, so a widget never picks
/// an impact strength and the mapping is reviewable in one place.
///
/// ## The five intents
///
/// | intent | feels like | raised by |
/// | --- | --- | --- |
/// | [SmokeHaptic.selection] | a tick | a segmented chip, a range change |
/// | [SmokeHaptic.advisory] | one light tap | crossing a *pull* tick, entering a band |
/// | [SmokeHaptic.confirm] | one firm tap | a target reached, a write read back |
/// | [SmokeHaptic.warning] | one heavy tap | a stall, out of band, storage low |
/// | [SmokeHaptic.critical] | a tap **and** a buzz | a pit crash, the base lost |
///
/// Only [SmokeHaptic.critical] is two events, and that is the whole design: at
/// 3 a.m., through a coat pocket, amplitude is not a channel a person can read
/// but *texture* is. A thud followed immediately by a longer buzz is
/// identifiable without looking at the phone; a slightly-harder thud is not.
///
/// ## Why the pattern is not timed
///
/// The obvious implementation — `heavyImpact(); await Future.delayed(90ms);
/// heavyImpact();` — schedules a timer that outlives the frame. Every
/// `testWidgets` case that raises an alarm would then have to flush it or fail
/// on a pending timer, and a haptic that can fail a test is a haptic somebody
/// deletes. Two back-to-back platform calls give a genuinely distinct texture
/// with no timer, no async and no test tax. That is a deliberate trade and it
/// is recorded here so nobody "fixes" it later.
///
/// ## What this file does not do
///
/// It does not consult `MediaQuery.disableAnimations`. Reduced motion is a
/// request about the *screen*; a person who cannot use the animation is often
/// exactly the person relying on the buzz. The OS already owns the haptics
/// switch, and when it is off these calls are no-ops at the platform boundary.
library;

import 'package:flutter/services.dart';

import 'status_palette.dart';

/// What a buzz *means*. Widgets name the meaning; this file picks the feel.
enum SmokeHaptic {
  /// A tick under a discrete choice.
  selection,

  /// One light tap. The advisory edge — a pull tick crossed, a band entered.
  advisory,

  /// One firm tap. Something the user asked for has completed: a target
  /// reached (14 §14.6.6), a write verified by read-back.
  confirm,

  /// One heavy tap. Something needs attention but the cook is not in danger.
  warning,

  /// Tap **and** buzz. Reserved for the cook actually being at risk.
  critical,
}

abstract final class SmokeHaptics {
  /// Fire [h]. Fire-and-forget by design: a haptic that a caller has to await
  /// is a haptic that can delay a frame.
  static void fire(SmokeHaptic h) {
    switch (h) {
      case SmokeHaptic.selection:
        HapticFeedback.selectionClick();
      case SmokeHaptic.advisory:
        HapticFeedback.lightImpact();
      case SmokeHaptic.confirm:
        HapticFeedback.mediumImpact();
      case SmokeHaptic.warning:
        HapticFeedback.heavyImpact();
      case SmokeHaptic.critical:
        // The one two-event pattern in the app — see the library doc.
        HapticFeedback.heavyImpact();
        HapticFeedback.vibrate();
    }
  }

  /// The status role a piece of chrome is already drawn in, mapped to the
  /// intent it should feel like. Keeps the buzz and the border in agreement:
  /// if the banner is critical the phone says critical, with no second table
  /// to drift.
  ///
  /// `positive` and `pit` are deliberately silent. Green is transport health
  /// (§14.6.5) and a link coming back is not worth waking someone for; `pit`
  /// is an accent, not an event.
  static SmokeHaptic? forRole(StatusRole role) => switch (role) {
    StatusRole.critical => SmokeHaptic.critical,
    StatusRole.warning => SmokeHaptic.warning,
    StatusRole.info => SmokeHaptic.advisory,
    StatusRole.positive || StatusRole.pit => null,
  };

  /// Convenience for the role mapping above — silent roles simply do nothing.
  static void fireForRole(StatusRole role) {
    final h = forRole(role);
    if (h != null) {
      fire(h);
    }
  }

  /// A food probe has crossed its target and the gauge ring closes
  /// (§14.6.6, once per probe per target, re-armed on the device's
  /// `target_rearm_f10` hysteresis so an oscillating value does not buzz
  /// repeatedly — the *de-duplication is the caller's*, because only the
  /// caller knows the probe).
  static void targetReached() => fire(SmokeHaptic.confirm);

  /// A probe has crossed the pull tick, or a pit has re-entered its band.
  /// Advisory: the user may want to know, and is not being summoned.
  static void thresholdCrossed() => fire(SmokeHaptic.advisory);
}
