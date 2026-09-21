/// N1.15 — the guided four-phase arc.
///
/// approaching → pullNow → resting → ready. Three honesty rules:
///
///  1. **The app never decides the meat came off the heat.** There is no sensor
///     for that — a cooling probe could be a pull, a lid, or a probe knocked
///     into the fire — so [CookPhaseState.pulledAtUnixMs] is a fact the *user*
///     supplies and the phase stays [CookPhase.pullNow] until they do.
///  2. The rest countdown is an **estimate from the cut's mass** and says so
///     ([CookPhaseState.estimated]).
///  3. If the probe stays in during the rest, the **sensor wins**.
///
/// Phase is a word, never a hue: green is transport health only.
library;

import 'presets.dart';

/// Where a food probe is in its guided cook.
enum CookPhase {
  /// Below the pull temperature, still climbing.
  approaching,

  /// At or past `target − carryover`. **Take it off the heat.**
  pullNow,

  /// Off the heat, coasting up on carryover.
  resting,

  /// Rested to target — done.
  ready;

  String get label => switch (this) {
    CookPhase.approaching => 'Approaching',
    CookPhase.pullNow => 'Pull now',
    CookPhase.resting => 'Resting',
    CookPhase.ready => 'Ready',
  };
}

/// The phase plus everything a gauge or notification needs to render it.
class CookPhaseState {
  const CookPhaseState({
    required this.phase,
    this.restRemainingS,
    this.restTotalS = 0,
    this.detail = '',
    this.estimated = false,
  });

  final CookPhase phase;

  /// Seconds left in the rest, or null outside [CookPhase.resting].
  final int? restRemainingS;

  /// The full rest this cut earns, seconds. 0 where none applies.
  final int restTotalS;

  /// One sentence under the pill. Never a bare number.
  final String detail;

  /// True when the phase came from the clock rather than a reading.
  final bool estimated;

  /// 0..1 through the rest, or null when not resting / no duration.
  double? get restProgress {
    final left = restRemainingS;
    if (left == null || restTotalS <= 0) {
      return null;
    }
    return ((restTotalS - left) / restTotalS).clamp(0.0, 1.0);
  }
}

/// Compute the phase for one food probe.
///
/// [tempF10] is the current reading (null = detached — the phase then holds
/// wherever it was). [pulledAtUnixMs] is when the user said they pulled it.
CookPhaseState cookPhaseFor({
  required int? tempF10,
  required int? targetF10,
  required int? pullF10,
  required int nowUnixMs,
  int? pulledAtUnixMs,
  int safetyRestS = 0,
}) {
  final target = targetF10;
  if (target == null) {
    return const CookPhaseState(
      phase: CookPhase.approaching,
      detail: 'No target set yet.',
    );
  }
  final pull = pullF10 ?? target;
  final carryover = target - pull;
  final restTotalS = restSecondsFor(
    carryoverF10: carryover,
    safetyRestS: safetyRestS,
  );

  if (pulledAtUnixMs != null) {
    // Rule 3: the sensor outranks the clock.
    if (tempF10 != null && tempF10 >= target) {
      return CookPhaseState(
        phase: CookPhase.ready,
        restTotalS: restTotalS,
        detail: 'Rested to target.',
      );
    }
    final elapsedS = ((nowUnixMs - pulledAtUnixMs) / 1000).round();
    final left = restTotalS - elapsedS;
    if (left > 0) {
      return CookPhaseState(
        phase: CookPhase.resting,
        restRemainingS: left,
        restTotalS: restTotalS,
        estimated: true,
        detail: carryover > 0
            ? 'Coasting up about ${(carryover / 10).round()}°F while it rests '
                  '— an estimate from the cut’s thickness.'
            : 'Resting. This cut does not carry over, so the timer is the '
                  'safe rest, not a temperature climb.',
      );
    }
    return CookPhaseState(
      phase: CookPhase.ready,
      restTotalS: restTotalS,
      estimated: tempF10 == null || tempF10 < target,
      detail: tempF10 != null && tempF10 < target
          ? 'Rest is over. It read ${(tempF10 / 10).toStringAsFixed(0)}°F, '
                'under the ${(target / 10).toStringAsFixed(0)}°F target — '
                'check it before serving.'
          : 'Rested and ready.',
    );
  }

  if (tempF10 != null && tempF10 >= pull) {
    return CookPhaseState(
      phase: CookPhase.pullNow,
      restTotalS: restTotalS,
      detail: carryover > 0
          ? 'Take it off the heat — it will coast up to '
                '${(target / 10).toStringAsFixed(0)}°F while it rests.'
          : 'It has reached ${(target / 10).toStringAsFixed(0)}°F.',
    );
  }

  return CookPhaseState(
    phase: CookPhase.approaching,
    restTotalS: restTotalS,
    detail: tempF10 == null
        ? 'Waiting for a reading from this probe.'
        : carryover > 0
        ? 'Pull at ${(pull / 10).toStringAsFixed(0)}°F, '
              '${(carryover / 10).round()}°F early.'
        : 'Target ${(target / 10).toStringAsFixed(0)}°F.',
  );
}
