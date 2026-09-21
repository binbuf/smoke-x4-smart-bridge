/// N3.29 — the haptic map.
///
/// Five kinds, and only five: `selection`, `advisory`, `confirm`, `warning`,
/// `critical`. **Critical is the only two-event pattern** — a heavy impact then
/// a vibration — so an urgent alarm is unmistakable through a pocket. `positive`
/// and `pit` are deliberately **silent**: reaching a target is not a reason to
/// buzz the phone, and the grate crossing a band is background information.
///
/// [SmokeHaptics.events] is the pure map (tested); [SmokeHaptics.fire] applies
/// it through the platform channel.
library;

import 'package:flutter/services.dart';

/// The five haptic kinds.
enum SmokeHaptic { selection, advisory, confirm, warning, critical }

/// Fires the platform haptics for a [SmokeHaptic].
abstract final class SmokeHaptics {
  const SmokeHaptics._();

  /// The platform events for a kind, in order. Critical has two.
  static List<String> events(SmokeHaptic kind) => switch (kind) {
    SmokeHaptic.selection => const <String>['selectionClick'],
    SmokeHaptic.advisory => const <String>['lightImpact'],
    SmokeHaptic.confirm => const <String>['mediumImpact'],
    SmokeHaptic.warning => const <String>['heavyImpact'],
    SmokeHaptic.critical => const <String>['heavyImpact', 'vibrate'],
  };

  /// Whether this kind is a two-event pattern.
  static bool isTwoEvent(SmokeHaptic kind) => events(kind).length == 2;

  /// Fire the haptics for [kind].
  ///
  /// Synchronous by design: haptics are fire-and-forget, and a synchronous
  /// signature keeps call sites out of the `unawaited_futures` trap.
  static void fire(SmokeHaptic kind) {
    for (final event in events(kind)) {
      switch (event) {
        case 'selectionClick':
          HapticFeedback.selectionClick();
        case 'lightImpact':
          HapticFeedback.lightImpact();
        case 'mediumImpact':
          HapticFeedback.mediumImpact();
        case 'heavyImpact':
          HapticFeedback.heavyImpact();
        case 'vibrate':
          HapticFeedback.vibrate();
      }
    }
  }
}
