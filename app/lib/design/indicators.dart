/// N3.21 — `Sparkline`, `TargetGauge` and `PhaseTrack`.
///
/// All three draw with a `CustomPainter` over plain numbers.
///
/// * [Sparkline] — a tiny straight-segment recent line.
/// * [TargetGauge] — an 84 dp sweep or band. **Reaching the target closes the
///   ring and says `DONE`; it never turns green.** Green is transport health
///   only, so the gauge uses the series mark colour throughout.
/// * [PhaseTrack] — a four-segment progression. Position is encoded by height
///   and ink, not by hue, so it reads without colour.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'text.dart';
import 'tokens.dart';

/// A tiny recent-values line.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.width = 52,
    this.height = 22,
  });

  final List<double> values;

  /// A series mark colour.
  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(width: width, height: height);
    }
    return CustomPaint(
      size: Size(width, height),
      painter: _SparklinePainter(values: values, color: color),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = values.first;
    var hi = values.first;
    for (final v in values) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    final span = (hi - lo) == 0 ? 1.0 : hi - lo;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * (size.width - 4) + 2;
      final y = size.height - 3 - ((values[i] - lo) / span) * (size.height - 6);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values || old.color != color;
}

/// An 84 dp radial gauge: a sweep to a target, or a pit band.
class TargetGauge extends StatelessWidget {
  const TargetGauge({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    this.target,
    this.bandMin,
    this.bandMax,
    this.center,
    this.caption,
    this.diameter,
  });

  final double value;
  final double min;
  final double max;

  /// The series mark colour.
  final Color color;

  /// The target crossing (a tick and, when reached, a closed ring).
  final double? target;
  final double? bandMin;
  final double? bandMax;

  /// The centre readout.
  final String? center;
  final String? caption;

  /// Overrides the default 84 dp (the reflow ladder drops it entirely).
  final double? diameter;

  /// Whether a reading has reached its target. "Target reached" closes the
  /// ring and says `DONE`; it is never expressed as a colour.
  static bool isReached(double value, double? target) =>
      target != null && value >= target;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final size = diameter ?? SmokeTextScale.gaugeBase;
    final reached = isReached(value, target);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            size: Size.square(size),
            painter: _GaugePainter(
              value: value,
              min: min,
              max: max,
              color: color,
              track: tokens.hairlineStrong,
              target: target,
              bandMin: bandMin,
              bandMax: bandMax,
              reached: reached,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (center != null)
                Text(
                  center!,
                  style: SmokeText.gaugeValue.copyWith(color: tokens.textHi),
                ),
              if (caption != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    caption!,
                    style: SmokeText.labelSm.copyWith(
                      fontSize: 9.5,
                      letterSpacing: 0.6,
                      color: tokens.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.track,
    required this.target,
    required this.bandMin,
    required this.bandMax,
    required this.reached,
  });

  final double value;
  final double min;
  final double max;
  final Color color;
  final Color track;
  final double? target;
  final double? bandMin;
  final double? bandMax;
  final bool reached;

  double _frac(double v) => ((v - min) / (max - min)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final centre = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final circle = Rect.fromCircle(center: centre, radius: radius);

    canvas.drawArc(
      circle,
      -math.pi / 2,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke,
    );

    if (bandMin != null && bandMax != null) {
      final f0 = _frac(bandMin!);
      final f1 = _frac(bandMax!);
      canvas.drawArc(
        circle,
        -math.pi / 2 + f0 * math.pi * 2,
        (f1 - f0) * math.pi * 2,
        false,
        Paint()
          ..color = color.withValues(alpha: 0.14)
          ..strokeWidth = 9
          ..style = PaintingStyle.stroke,
      );
    }

    final sweep = _frac(value);
    canvas.drawArc(
      circle,
      -math.pi / 2,
      sweep * math.pi * 2,
      false,
      Paint()
        ..color = color
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    if (target != null) {
      final tf = _frac(target!);
      final angle = -math.pi / 2 + tf * math.pi * 2;
      final tick = centre + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(
        tick,
        reached ? 5 : 3.5,
        Paint()..color = reached ? color : track,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value ||
      old.color != color ||
      old.target != target ||
      old.reached != reached;
}

/// A four-segment phase progression, positioned by height not hue.
class PhaseTrack extends StatelessWidget {
  const PhaseTrack({
    super.key,
    required this.phases,
    required this.currentIndex,
  });

  final List<String> phases;

  /// The active phase; anything at or below it is done.
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (var i = 0; i < phases.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    height: 6 + i * 4.0,
                    decoration: BoxDecoration(
                      color: i <= currentIndex
                          ? tokens.textHi
                          : tokens.hairlineStrong,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    phases[i],
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: SmokeText.labelSm.copyWith(
                      fontSize: 9.5,
                      color: i == currentIndex
                          ? tokens.textHi
                          : tokens.textMuted,
                      fontWeight: i == currentIndex
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
