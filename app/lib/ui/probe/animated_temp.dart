/// A19.6 — AnimatedTemp (design 14 §14.5.1).
///
/// A temperature that tweens to a new reading over `SmokeMotion.value`. It
/// snaps to a **tenth** during the tween, so the digits step 163.4 → 163.7 →
/// 164.0 and never show `164.37` for a frame.
///
/// **A25 — the tenth is shown, subordinated.** The Smoke X reads to 0.1 °F and
/// so does the wire, so the app shows it too; but at headline size a full-height
/// `.8` would fight the number it belongs to. The decimal renders at roughly
/// half scale and baseline-aligned, so the eye still lands on the whole degrees
/// first and the tenth is there when you look for it.
///
/// The number is **never scaled to fit** (§14.5.1). It renders at a fixed
/// style, `maxLines: 1`, `softWrap: false`; the caller sizes the row for four
/// tabular glyphs and lets the gauge flex, not the number. That is why a probe
/// crossing 99 → 100 °F does not change glyph height between frames.
///
/// Null (detached) renders `—` and the unit, and carries the word *unplugged*
/// in its semantics — never a number, never a zero (the invariant this project
/// has held since M0).
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';

class AnimatedTemp extends StatelessWidget {
  const AnimatedTemp({
    super.key,
    required this.tempF10,
    required this.celsius,
    required this.style,
    required this.unitStyle,
    required this.color,
    required this.semanticName,
  });

  /// Tenths °F, or null for detached.
  final int? tempF10;
  final bool celsius;
  final TextStyle style;
  final TextStyle unitStyle;

  /// **Ink — never a series hue.** It paints the digits, the tenth and the
  /// unit, which is a word-sized shape at headline size, and §16.5 lets a
  /// series hue be a mark only: a stroke, an arc, a ≤12 dp dot, a left rule.
  /// `textHi` for a live reading, `textMuted` for a detached one. A caller that
  /// wants to say *which probe* this is spends the hue on something beside the
  /// number — [TempReadout]'s 3 dp underline, or a 12 dp dot in the row.
  final Color color;

  /// "Brisket flat" — spelled into the semantics label with the value.
  final String semanticName;

  String get _unit => celsius ? '°C' : '°F';

  @override
  Widget build(BuildContext context) {
    final motion = SmokeMotion.of(context);
    final value = tempF10;

    final unit = Padding(
      padding: const EdgeInsets.only(left: 2, top: 6),
      child: Text(_unit, style: unitStyle.copyWith(color: color)),
    );

    if (value == null) {
      return Semantics(
        label: '$semanticName, unplugged',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(noValue, style: style.copyWith(color: color), maxLines: 1),
            unit,
          ],
        ),
      );
    }

    final displayed = _tenths(value.toDouble());

    return Semantics(
      label:
          '$semanticName, ${_spoken(displayed)} degrees '
          '${celsius ? "Celsius" : "Fahrenheit"}',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.toDouble()),
        duration: motion.value,
        curve: motion.curve,
        builder: (context, v, _) {
          final shown = _tenths(v);
          final neg = shown < 0;
          final abs = shown.abs();
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${neg ? '-' : ''}${abs ~/ 10}',
                style: style.copyWith(color: color),
                maxLines: 1,
                softWrap: false,
              ),
              // Half-scale and baseline-aligned: present, never competing.
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '.${abs % 10}',
                  style: style.copyWith(
                    color: color,
                    fontSize: (style.fontSize ?? 48) * 0.52,
                  ),
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
              unit,
            ],
          );
        },
      ),
    );
  }

  /// The value in tenths of the DISPLAYED unit, rounded to one decimal.
  int _tenths(double f10) =>
      celsius ? (((f10 - 320) * 5) / 9).round() : f10.round();

  String _spoken(int tenths) {
    final neg = tenths < 0;
    final abs = tenths.abs();
    return '${neg ? '-' : ''}${abs ~/ 10}.${abs % 10}';
  }
}
