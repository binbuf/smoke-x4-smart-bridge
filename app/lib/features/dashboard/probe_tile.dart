/// A9.2 — the probe tiles (design 08 §8.6).
///
/// **The two numbers that matter are enormous.** You are reading this from
/// four feet away, in a dark yard, possibly through a screen door. The pit
/// and the primary food probe get the space; everything else collapses to
/// a compact tile. `SmokeTheme.headlineTemp` has been 88 pt since A1.2
/// precisely so this file uses it rather than inventing a size.
///
/// A detached probe renders `—` and the word *unplugged*. It never renders
/// a number, and it never disappears: a probe that vanishes from the grid
/// reads as an app bug, not as an unplugged jack.
library;

import 'package:flutter/material.dart';

import '../../app/palette.dart';
import '../../core/format.dart';
import '../../domain/analysis/analysis.dart';
import 'dashboard_snapshot.dart';

/// The big one: pit or the primary food probe.
class HeadlineProbeTile extends StatelessWidget {
  const HeadlineProbeTile({
    required this.view,
    this.celsius = false,
    super.key,
  });

  final ProbeView view;
  final bool celsius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = ProbePalette.styleFor(
      view.probe,
      theme.brightness,
      role: view.role,
    );
    return Container(
      key: Key('probe-tile-headline-${view.probe}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: style.color, width: 5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _TileLabel(view: view, style: style),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatTemp(view.tempF10, celsius: celsius),
                  style: theme.textTheme.displayLarge,
                  semanticsLabel: _semantics(view, celsius: celsius),
                ),
                if (view.attached) _TrendArrow(rate: view.rateFPerHr),
              ],
            ),
          ),
          if (!view.attached)
            Text(
              'unplugged',
              key: Key('probe-detached-${view.probe}'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          // A target on an unplugged probe is a number with nothing to
          // compare it to, and it puts a digit back on a tile whose whole
          // job is to say "no reading".
          if (view.attached && view.targetF10 != null)
            Text(
              'target ${formatTemp(view.targetF10, celsius: celsius)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (view.attached)
            Text(
              formatRate(view.rateFPerHr),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (view.eta != null && formatEta(view.eta).isNotEmpty)
            Text(
              formatEta(view.eta),
              key: Key('probe-eta-${view.probe}'),
              style: theme.textTheme.bodyMedium,
            ),
          if (view.stalled)
            _Flag(
              key: Key('probe-stall-${view.probe}'),
              icon: Icons.horizontal_rule,
              // §9.4: worth surfacing because it PREVENTS action.
              label: 'stalling — this is normal',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          if (view.alarm != null)
            _Flag(
              key: Key('probe-alarm-${view.probe}'),
              icon: AlarmPalette.iconOf(view.alarm!.severity),
              label: view.alarm!.acked
                  ? '${view.alarm!.rule} (acknowledged)'
                  : view.alarm!.rule,
              color: AlarmPalette.of(view.alarm!.severity),
            ),
          if (view.recent.length > 2) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 26,
              child: CustomPaint(
                painter: SparklinePainter(
                  points: view.recent,
                  color: style.color,
                ),
                size: Size.infinite,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The small one: everything not in a headline slot.
class CompactProbeTile extends StatelessWidget {
  const CompactProbeTile({required this.view, this.celsius = false, super.key});

  final ProbeView view;
  final bool celsius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = ProbePalette.styleFor(
      view.probe,
      theme.brightness,
      role: view.role,
    );
    return Container(
      key: Key('probe-tile-compact-${view.probe}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: style.color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _TileLabel(view: view, style: style, small: true),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatTemp(view.tempF10, celsius: celsius),
              style: theme.textTheme.displayMedium,
              semanticsLabel: _semantics(view, celsius: celsius),
            ),
          ),
          Text(
            view.attached ? formatRate(view.rateFPerHr) : 'unplugged',
            key: view.attached ? null : Key('probe-detached-${view.probe}'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TileLabel extends StatelessWidget {
  const _TileLabel({
    required this.view,
    required this.style,
    this.small = false,
  });

  final ProbeView view;
  final ProbeStyle style;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        // The colour-free half of the palette's identity channel (A10.2):
        // the same stroke the chart draws this probe with, so the tile and
        // the line are the same object even in monochrome.
        _StrokeSwatch(style: style),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            view.name.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style:
                (small
                        ? theme.textTheme.labelMedium
                        : theme.textTheme.labelLarge)
                    ?.copyWith(
                      letterSpacing: 2,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
          ),
        ),
      ],
    );
  }
}

/// Draws the probe's dash pattern as a short rule — the legend swatch
/// that still works on a photocopy, and the same language the OLED speaks.
class _StrokeSwatch extends StatelessWidget {
  const _StrokeSwatch({required this.style});
  final ProbeStyle style;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 18,
    height: 8,
    child: CustomPaint(painter: _StrokePainter(style)),
  );
}

class _StrokePainter extends CustomPainter {
  const _StrokePainter(this.style);
  final ProbeStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = style.color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    final dash = style.dashArray;
    if (dash == null) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    var x = 0.0;
    var i = 0;
    while (x < size.width) {
      final on = dash[i % dash.length].toDouble();
      final off = dash[(i + 1) % dash.length].toDouble();
      canvas.drawLine(
        Offset(x, y),
        Offset((x + on).clamp(0, size.width), y),
        paint,
      );
      x += on + off;
      i += 2;
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) => old.style.color != style.color;
}

class _TrendArrow extends StatelessWidget {
  const _TrendArrow({this.rate});
  final double? rate;

  @override
  Widget build(BuildContext context) {
    if (rate == null || rate!.abs() < 0.6) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Icon(
        rate! > 0 ? Icons.arrow_upward : Icons.arrow_downward,
        size: 28,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  const _Flag({
    required this.icon,
    required this.label,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        // Status never travels as colour alone — icon and word, always.
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}

/// The tile's sparkline. Deliberately not `fl_chart`: this is one path
/// with no axes, drawn 4–6 times per frame, and a full chart per tile is
/// how a dashboard starts dropping frames.
class SparklinePainter extends CustomPainter {
  const SparklinePainter({required this.points, required this.color});

  final List<ValuePoint> points;
  final Color color;

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
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(SparklinePainter old) =>
      old.points.length != points.length || old.color != color;
}

/// What a screen reader says. Written out rather than left to the default
/// so `—` is spoken as "unplugged" instead of as a dash.
String _semantics(ProbeView v, {bool celsius = false}) {
  if (!v.attached) {
    return '${v.name}, unplugged';
  }
  final trend = v.rateFPerHr == null || v.rateFPerHr!.abs() < 0.6
      ? 'steady'
      : v.rateFPerHr! > 0
      ? 'rising ${v.rateFPerHr!.toStringAsFixed(1)} per hour'
      : 'falling ${(-v.rateFPerHr!).toStringAsFixed(1)} per hour';
  final unit = celsius ? 'Celsius' : 'degrees';
  return '${v.name}, '
      '${((celsius ? f10ToC10(v.tempF10!) : v.tempF10!) / 10).round()} '
      '$unit, $trend';
}
