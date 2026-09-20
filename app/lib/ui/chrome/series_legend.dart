/// The chart's key — and the third identity channel made visible
/// (design 14 §14.10, newapp §H.2).
///
/// §H.2 asks for **colour-blind-safe multi-series**: *"series hues
/// distinguishable by luminance + a shape/label token, not hue alone — pair
/// each series with a glyph in the legend."* The palette has carried a stroke
/// pattern since A10.2, which survives a photocopy and the SSD1306 — but a
/// stroke pattern is unreadable at 12 dp, which is exactly the size a legend
/// entry, a probe-row swatch and a crosshair dot are drawn at. So the palette
/// now also carries a [SeriesGlyph], and this is where it is spent.
///
/// The measurement that makes this non-optional is in `series_palette.dart`:
/// P1 ember and P4 blue sit **0.018 apart in relative luminance**. Desaturate
/// the chart — monochrome print, a deuteranope, a phone in direct sun with the
/// screen washed out — and those two series are the same grey. Neither hue nor
/// luminance separates them. The glyph does, and the word beside it does.
///
/// Three channels per entry, in the order they degrade:
///
///  1. **glyph** — survives 12 dp, monochrome, and every form of CVD;
///  2. **stroke** — survives print and the OLED, needs ~40 dp to read;
///  3. **hue** — the fastest channel when it works, and the first to fail.
///
/// The semantics label names the glyph and the stroke and *then* the colour,
/// in that order, because that is the order they can be relied on.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

/// One legend entry's worth of identity. Values, not a `ProbeView` — this is
/// `ui/`, and a legend that knew about probes could not label a chart of
/// anything else.
@immutable
class SeriesLegendEntry {
  const SeriesLegendEntry({
    required this.name,
    required this.style,
    this.trailing,
    this.dimmed = false,
  });

  /// What the user calls this series. "Brisket flat", not "Probe 2".
  final String name;

  final ProbeStyle style;

  /// The value at the crosshair, or the peak, or nothing.
  final String? trailing;

  /// A detached or deselected series: still listed, in place, at reduced ink.
  /// It never leaves the legend — a series that vanishes when it is unplugged
  /// takes its identity with it and the remaining rows appear to change jack.
  final bool dimmed;
}

/// The glyph alone, at mark size. Also the swatch a probe row and a crosshair
/// dot should use, so one shape means one probe everywhere in the app.
class SeriesGlyphMark extends StatelessWidget {
  const SeriesGlyphMark({
    super.key,
    required this.style,
    this.size = 12,
    this.dimmed = false,
    this.color,
  });

  final ProbeStyle style;
  final double size;
  final bool dimmed;

  /// Ink for the glyph when it is **not** drawn on the chart's own surface.
  ///
  /// Exists for one caller and one reason: a mark knocked out of a disc that is
  /// already filled with its series hue (the chart's channel selector, 17
  /// §17.2/§17.5) cannot also be drawn *in* that hue — it would be invisible.
  /// Everywhere else this stays null and the hue is the ink, so "one shape
  /// means one probe everywhere in the app" survives the exception.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // A series hue as a ≤12 dp mark is exactly what the separation rule
    // permits, and the only thing it permits (§14.6.1).
    //
    // The dim level comes from the palette rather than from a literal here so
    // that a de-emphasised legend entry and the de-emphasised *stroke* it
    // stands for are provably the same ink (§17.3 D): the legend is the key to
    // the chart, and a key drawn at a different weight than the thing it keys
    // is worse than no key.
    return Icon(
      style.glyph.icon,
      size: size,
      color: color ?? (dimmed ? ProbePalette.dim(style.color) : style.color),
    );
  }
}

/// A wrapping row of entries. Wraps rather than scrolls: a key you have to
/// scroll is a key you do not read.
class SeriesLegend extends StatelessWidget {
  const SeriesLegend({super.key, required this.entries, this.onTap});

  final List<SeriesLegendEntry> entries;

  /// Tapping an entry isolates or restores that series. Null leaves the
  /// legend a readout — and then it is not a control, so it does not pretend
  /// to be one.
  final void Function(ProbeStyle style)? onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: SmokeTokens.s3,
      runSpacing: SmokeTokens.s2,
      children: [
        for (final e in entries)
          _Entry(
            key: Key('legend-${e.style.probe}'),
            entry: e,
            onTap: onTap == null ? null : () => onTap!(e.style),
          ),
      ],
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({super.key, required this.entry, this.onTap});

  final SeriesLegendEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final e = entry;
    final ink = e.dimmed ? t.textMuted : t.textHi;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SeriesGlyphMark(style: e.style, dimmed: e.dimmed),
        const SizedBox(width: SmokeTokens.s1),
        _StrokeSwatch(style: e.style, dimmed: e.dimmed),
        const SizedBox(width: SmokeTokens.s2),
        Text(
          e.name,
          style: SmokeType.bodySm.copyWith(color: ink, fontWeight: FontWeight.w600),
        ),
        if (e.trailing != null) ...[
          const SizedBox(width: SmokeTokens.s2),
          Text(
            e.trailing!,
            style: SmokeType.bodySm.copyWith(color: t.textBody),
          ),
        ],
      ],
    );

    return Semantics(
      button: onTap != null,
      // Glyph and stroke first, colour last: that is the order these channels
      // can be relied on, and the order a reader who cannot see the third one
      // needs them in.
      label:
          '${e.style.describe(e.name)}'
          '${e.trailing == null ? '' : ', ${e.trailing}'}'
          '${e.dimmed ? ', not shown' : ''}',
      excludeSemantics: true,
      child: onTap == null
          ? row
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(SmokeTokens.radiusChip),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: row,
                ),
              ),
            ),
    );
  }
}

/// A 20 dp sample of the series' actual stroke — solid, dashed, dotted or
/// dash-dot. Small, but it is the channel that survives a printout, and a
/// legend that shows only a colour swatch is a legend that lies about how the
/// chart is drawn.
class _StrokeSwatch extends StatelessWidget {
  const _StrokeSwatch({required this.style, required this.dimmed});

  final ProbeStyle style;
  final bool dimmed;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(20, 2),
    painter: _StrokePainter(
      color: dimmed ? ProbePalette.dim(style.color) : style.color,
      dash: style.dashArray,
      width: style.strokeWidth,
    ),
  );
}

class _StrokePainter extends CustomPainter {
  const _StrokePainter({
    required this.color,
    required this.dash,
    required this.width,
  });

  final Color color;
  final List<int>? dash;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    final pattern = dash;
    if (pattern == null || pattern.isEmpty) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    var x = 0.0;
    var i = 0;
    while (x < size.width) {
      final on = pattern[i % pattern.length].toDouble();
      final off = pattern[(i + 1) % pattern.length].toDouble();
      final end = (x + on).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x = end + off;
      i += 2;
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) =>
      old.color != color || old.dash != dash || old.width != width;
}
