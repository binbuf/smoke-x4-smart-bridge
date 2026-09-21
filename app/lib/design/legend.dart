/// N3.28 — `SeriesLegend` and `LegendSwatch`.
///
/// Series identity is **hue + stroke pattern + glyph**, never hue alone
/// (research notes §9.3). The swatch draws the stroke pattern, and the entry
/// carries a glyph, so two probes are distinguishable in greyscale and to a
/// colour-blind reader. Tap-to-isolate dims every other entry.
///
/// This was unwired in the legacy app; N7's chart wires it here.
library;

import 'package:flutter/material.dart';

import 'icons.dart';
import 'text.dart';
import 'tokens.dart';

/// One series in the legend.
@immutable
class SeriesLegendEntry {
  const SeriesLegendEntry({
    required this.label,
    required this.color,
    this.value,
    this.dash,
    this.glyph,
    this.hidden = false,
  });

  final String label;

  /// The series mark colour.
  final Color color;

  /// The current value, if any.
  final String? value;

  /// The dash pattern (null = solid), in logical pixels.
  final List<double>? dash;

  /// A second identity channel beside hue.
  final SmokeGlyph? glyph;

  /// Hidden from the chart entirely.
  final bool hidden;
}

/// A stroke-pattern swatch.
class LegendSwatch extends StatelessWidget {
  const LegendSwatch({
    super.key,
    required this.color,
    this.dash,
    this.glyph,
    this.width = 18,
    this.height = 3,
  });

  final Color color;
  final List<double>? dash;
  final SmokeGlyph? glyph;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final line = CustomPaint(
      size: Size(width, height),
      painter: _StrokeSwatchPainter(color: color, dash: dash),
    );
    if (glyph == null) {
      return line;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SmokeIcon(glyph!, size: 12, color: color),
        const SizedBox(width: 4),
        line,
      ],
    );
  }
}

class _StrokeSwatchPainter extends CustomPainter {
  _StrokeSwatchPainter({required this.color, required this.dash});

  final Color color;
  final List<double>? dash;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (dash == null || dash!.isEmpty) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    var x = 0.0;
    var on = true;
    var i = 0;
    while (x < size.width) {
      final segment = dash![i % dash!.length];
      final end = (x + segment).clamp(0.0, size.width);
      if (on) {
        canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      }
      x = end;
      on = !on;
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _StrokeSwatchPainter old) =>
      old.color != color || old.dash != dash;
}

/// The chart key: swatch + name + value; tap to isolate.
class SeriesLegend extends StatelessWidget {
  const SeriesLegend({
    super.key,
    required this.entries,
    this.isolated,
    this.onIsolate,
  });

  final List<SeriesLegendEntry> entries;

  /// The isolated series label, or null for "show all".
  final String? isolated;

  /// Called with a label to isolate it, or null to clear the isolation.
  final ValueChanged<String?>? onIsolate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final entry in entries)
          _LegendItem(
            entry: entry,
            dimmed: isolated != null && isolated != entry.label,
            onTap: entry.hidden || onIsolate == null
                ? null
                : () =>
                      onIsolate!(isolated == entry.label ? null : entry.label),
          ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.entry,
    required this.dimmed,
    required this.onTap,
  });

  final SeriesLegendEntry entry;
  final bool dimmed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Opacity(
      opacity: entry.hidden ? 0.3 : (dimmed ? 0.42 : 1),
      child: Material(
        color: tokens.cardSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radii.pill),
          side: BorderSide(color: tokens.hairline),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(tokens.radii.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                LegendSwatch(
                  color: entry.color,
                  dash: entry.dash,
                  glyph: entry.glyph,
                ),
                const SizedBox(width: 6),
                Text(
                  entry.label,
                  style: SmokeText.labelSm.copyWith(
                    fontSize: 11.5,
                    color: tokens.textHi,
                  ),
                ),
                if (entry.value != null) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    entry.value!,
                    style: SmokeText.monoSmall.copyWith(color: tokens.textBody),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
