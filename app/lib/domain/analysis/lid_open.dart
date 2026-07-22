/// A2.5 — the lid-open detector (design 09 §9.4).
///
///   detect:  pit drops ≥ 25 °F within any 3-minute window
///   confirm: recovers ≥ 50 % of the drop within 20 min → it was a lid open
///            does not recover → escalate to `pit_crash`
///
/// Firing on *detection* is what starts the alarm grace window immediately;
/// confirming afterwards is what lets a genuine fire failure still escalate
/// 20 minutes later. Suppressing a real pit_crash is the expensive failure,
/// so both branches are tested.
library;

import 'dart:math';

sealed class LidEvent {
  const LidEvent(this.t);

  /// Seconds-into-session when the event fired.
  final int t;
}

/// The drop was seen — start the pit-alarm grace window NOW.
class LidOpenDetected extends LidEvent {
  const LidOpenDetected(super.t, this.dropF);
  final double dropF;
}

/// The pit recovered ≥ 50 % — it was a lid open after all.
class LidOpenConfirmed extends LidEvent {
  const LidOpenConfirmed(super.t);
}

/// No recovery within 20 minutes — the fire is dying.
class PitCrashEscalated extends LidEvent {
  const PitCrashEscalated(super.t);
}

const double lidDetectDropF = 25;
const int lidDetectWindowS = 180;
const double lidConfirmRecoveryFraction = 0.5;
const int lidConfirmWindowS = 1200;

class LidOpenDetector {
  final List<({int t, double f})> _recent = [];
  bool _active = false;
  double _reference = 0;
  double _lowPoint = 0;
  int _detectT = 0;

  /// Whether a detected drop is awaiting confirmation/escalation.
  bool get pending => _active;

  /// Feed pit samples in order; null (detached) samples are skipped.
  List<LidEvent> add(int t, double? pitF) {
    if (pitF == null) {
      return const [];
    }
    final events = <LidEvent>[];

    if (!_active) {
      _recent.removeWhere((p) => p.t < t - lidDetectWindowS);
      if (_recent.isNotEmpty) {
        final refMax = _recent.map((p) => p.f).reduce(max);
        final drop = refMax - pitF;
        if (drop >= lidDetectDropF) {
          _active = true;
          _reference = refMax;
          _lowPoint = pitF;
          _detectT = t;
          _recent.clear();
          events.add(LidOpenDetected(t, drop));
          return events;
        }
      }
      _recent.add((t: t, f: pitF));
    } else {
      _lowPoint = min(_lowPoint, pitF);
      final drop = _reference - _lowPoint;
      final recovered = pitF - _lowPoint;
      if (recovered >= drop * lidConfirmRecoveryFraction) {
        _active = false;
        events.add(LidOpenConfirmed(t));
      } else if (t - _detectT >= lidConfirmWindowS) {
        _active = false;
        events.add(PitCrashEscalated(t));
      }
    }
    return events;
  }
}
