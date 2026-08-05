/// The guided four-phase progression (newapp §D.5).
///
/// MEATER walks approaching → remove from heat → rest → "Happy Eating!", and
/// Weber Connect does the same with a readiness countdown. This is the same
/// arc, built to survive a **~30 s sample cadence with possible LoRa packet
/// loss** — which is the reason it is a small pure function over values rather
/// than a physics model. §D.5's open decision was settled the same way: no
/// Combustion-style virtual core in v1, because a virtual core needs multi-point
/// sensing and this upstream is a single tip at 30 s.
///
/// **Three honesty rules, inherited from the ETA and not relaxed here:**
///
///  1. The app never decides the meat came off the heat. There is no sensor for
///     that — a food probe cooling could be a pull, a lid, or a probe knocked
///     into the fire — so [pulledAtUnixMs] is a fact the *user* supplies by
///     tapping, and until they do, the phase stays [CookPhase.pullNow] however
///     long that takes. Guessing here would move a brisket to "Ready" while it
///     was still on the smoker.
///  2. The rest countdown is an **estimate from the cut's mass**, and says so.
///     Carryover is not measurable from one interior point; ThermoWorks and
///     AmazingRibs both publish it as a range by thickness, so that is what
///     this returns.
///  3. If the probe stays in during the rest, the **sensor wins**. A reading
///     that has genuinely reached target ends the rest early rather than making
///     someone watch a timer that physics already finished.
///
/// Phase is rendered as a **mark**, never as a colour — green is transport
/// health, and "target reached" closes the ring rather than turning it green
/// (design 14 §14.6). This library returns words and numbers; it names no hue.
library;

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

  /// The pill's word. Deliberately imperative for the one phase that asks for
  /// an action and descriptive for the three that do not.
  String get label => switch (this) {
    CookPhase.approaching => 'Approaching',
    CookPhase.pullNow => 'Pull now',
    CookPhase.resting => 'Resting',
    CookPhase.ready => 'Ready',
  };
}

/// The phase, plus everything a gauge or a notification needs to render it.
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

  /// One sentence under the pill. Never jargon, and never a bare number.
  final String detail;

  /// True when the phase came from the clock rather than from a reading — the
  /// rest countdown. The UI must label it, per rule 2.
  final bool estimated;

  /// 0..1 through the rest, for the gauge's segmented arc. Null when not
  /// resting or when the rest has no duration to be a fraction of.
  double? get restProgress {
    final left = restRemainingS;
    if (left == null || restTotalS <= 0) {
      return null;
    }
    return ((restTotalS - left) / restTotalS).clamp(0.0, 1.0);
  }
}

/// How long a cut with this much carryover should rest, in seconds.
///
/// Derived from the carryover rather than from a second thickness field, so a
/// preset and a custom cook cannot disagree: the same mass that makes a roast
/// coast 8 °F is the mass that makes it want twenty minutes. [safetyRestS] is
/// the USDA floor (pork's three minutes) and is a **minimum**, never a maximum.
int restSecondsFor({required int carryoverF10, int safetyRestS = 0}) {
  final byMass = switch (carryoverF10) {
    <= 0 => 0,
    <= 20 => 5 * 60,
    <= 50 => 10 * 60,
    _ => 20 * 60,
  };
  return byMass > safetyRestS ? byMass : safetyRestS;
}

/// Compute the phase for one food probe.
///
/// [tempF10] is the current reading (null = detached — the phase then holds
/// wherever it was rather than falling back to "approaching", because a probe
/// pulled out during a rest is the normal case). [pulledAtUnixMs] is when the
/// user said they took it off the heat; null means they have not.
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
    // No target is not a phase — it is the "set a target" affordance (§D.3.2),
    // and pretending otherwise would put a progression on a cook that has none.
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
    // Rule 3: the sensor outranks the clock. A probe left in that has already
    // reached target is done, whatever the countdown says.
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
