/// N3.20 (part) — `PulseDot` and the shared pulse animation.
///
/// `lib/design/` is stateless by contract, so the *repeating* animation cannot
/// live in the dot itself. The app root owns one `AnimationController`, exposes
/// it through [SmokePulseScope], and every [PulseDot] in the tree reads it.
/// With no scope (tests, isolated previews) the dot renders static.
///
/// The pulse is the **staleness signal**: under reduced motion everything else
/// stops but the pulse keeps beating, because a still dot means "not live".
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Exposes the shared 0→1 pulse animation to [PulseDot].
class SmokePulseScope extends InheritedWidget {
  const SmokePulseScope({super.key, required this.pulse, required super.child});

  /// The repeating 0→1 animation, or null to render static.
  final Animation<double>? pulse;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SmokePulseScope>()?.pulse;

  @override
  bool updateShouldNotify(SmokePulseScope oldWidget) =>
      oldWidget.pulse != pulse;
}

/// The liveness state of a dot.
enum PulseState { live, warn, crit, idle }

/// A 7 dp liveness dot; hollow when not live.
class PulseDot extends StatelessWidget {
  const PulseDot({super.key, this.state = PulseState.live, this.size = 7});

  final PulseState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final idle = state == PulseState.idle;
    final color = switch (state) {
      PulseState.live => tokens.positive,
      PulseState.warn => tokens.warning,
      PulseState.crit => tokens.critical,
      PulseState.idle => Colors.transparent,
    };
    final glow = idle ? 0.0 : tokens.glow;

    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: idle ? Border.all(color: tokens.chromeDim, width: 1.5) : null,
        boxShadow: glow > 0
            ? <BoxShadow>[
                BoxShadow(
                  color: tokens.tint(
                    state == PulseState.crit
                        ? tokens.critical
                        : state == PulseState.warn
                        ? tokens.warning
                        : tokens.positive,
                    state == PulseState.crit ? 0.6 : 0.55,
                  ),
                  blurRadius: 6 * glow,
                ),
              ]
            : const <BoxShadow>[],
      ),
    );

    if (idle) {
      return Semantics(label: 'Not live', child: dot);
    }

    final pulse = SmokePulseScope.maybeOf(context);
    final labelled = Semantics(
      label: 'Live',
      child: pulse == null
          ? dot
          : FadeTransition(
              opacity: Tween<double>(begin: 1, end: 0.35).animate(pulse),
              child: dot,
            ),
    );
    return labelled;
  }
}
