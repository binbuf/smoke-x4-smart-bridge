/// A19.6 — the sparkline (design 14 §14.8).
///
/// A tiny line of recent readings for a probe row. It draws **straight
/// segments, no smoothing and no area fill** (§14.8.1): a Bézier would
/// interpolate readings that were never taken and round off exactly the
/// lid-open spikes and pit crashes the chart exists to show.
///
/// Lives in `ui/` (not `features/`) so a component can use it without reaching
/// into a screen. Takes bare `(t, f)` points; the caller supplies the hue.
library;

import 'package:flutter/material.dart';

/// A recent-reading point: `t` seconds, `f` tenths-°F as a double.
typedef SparkPoint = ({int t, double f});

class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.points,
    required this.color,
    this.strokeWidth = 2,
  });

  final List<SparkPoint> points;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparkPainter(points, color, strokeWidth),
      size: Size.infinite,
    );
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter(this.points, this.color, this.strokeWidth);

  final List<SparkPoint> points;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.width <= 0) {
      return;
    }
    var lo = points.first.f;
    var hi = points.first.f;
    for (final p in points) {
      lo = p.f < lo ? p.f : lo;
      hi = p.f > hi ? p.f : hi;
    }
    final span = (hi - lo).abs() < 0.5 ? 1.0 : hi - lo;
    final t0 = points.first.t;
    final tSpan = points.last.t - t0 == 0 ? 1 : points.last.t - t0;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * (points[i].t - t0) / tSpan;
      final y = size.height * (1 - (points[i].f - lo) / span);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.points.length != points.length || old.color != color;
}
