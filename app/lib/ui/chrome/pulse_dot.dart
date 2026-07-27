/// A19.6 — PulseDot (design 14 §14.7).
///
/// A 7 dp liveness dot. **It animates only while [live].** The dot stopping is
/// the staleness signal, so under reduced motion it keeps the opacity fade and
/// drops only the scale (`SmokeMotionValues.pulseScales`) — the information is
/// in whether it breathes, and removing the breath removes the information.
///
/// When not live it goes hollow: a ring, not a filled dot, so "stale" reads at
/// a glance without a colour change.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

class PulseDot extends StatefulWidget {
  const PulseDot({
    super.key,
    required this.color,
    required this.live,
    this.size = 7,
  });

  final Color color;
  final bool live;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = SmokeMotion.of(context);
    if (widget.live) {
      _c.duration = motion.pulse;
      if (!_c.isAnimating) {
        _c.repeat(reverse: true);
      }
    } else {
      _c.stop();
      _c.value = 0;
    }

    if (!widget.live) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.color.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final tt = Curves.easeInOut.transform(_c.value);
        final opacity = 1.0 - 0.6 * tt;
        final scale = motion.pulseScales ? 1.0 + 0.3 * tt : 1.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: opacity),
              boxShadow: [?context.tokens.glowTight(widget.color)],
            ),
          ),
        );
      },
    );
  }
}
