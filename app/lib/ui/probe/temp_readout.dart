/// The temperature, given presence — and given a measurable width (newapp
/// §H.2; design 16 §16.5).
///
/// Two jobs, both of which the reader needed and neither of which
/// [AnimatedTemp] should own.
///
/// **1. The series-hue underline.** §H.2 asks for *"a large, high-contrast
/// readout with a thin series-hue underline, on a near-black surface, tuned for
/// OLED and sunlight."* This is that: a 3 dp rule the exact width of the
/// number, in the probe's own hue. It is doing work, not decoration — on a card
/// with no swatch and no coloured word it is the only thing that says which
/// probe this number belongs to, and it is the one shape a series hue is
/// allowed to be (§16.5: stroke, arc, ≤12 dp dot, left rule). A detached probe
/// keeps the rule in `hairlineStrong`: the identity is still stated, and the
/// mark visibly is not carrying a reading.
///
/// **2. It can be measured before it is laid out.** [measure] returns the exact
/// width this readout will take. That is what lets a hero card honour *"the
/// temperature is never scaled to fit — the gauge is the flexible child"*
/// (§16.5) instead of wrapping the number in a `FittedBox` and hoping.
///
/// **The temperature does not take the OS text scale**, and that is deliberate.
/// It is already 96 pt — four times the largest body style in the app, and the
/// accessibility affordance for "readable across a dark yard" all by itself.
/// Multiplying it by 2 makes it 440 dp wide on a 360 dp phone, which is not a
/// bigger number, it is a missing one. Everything *around* it — names, phases,
/// sentences, buttons — scales normally, which is what a reader who set 200 %
/// actually asked for.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import 'animated_temp.dart';

class TempReadout extends StatelessWidget {
  const TempReadout({
    super.key,
    required this.tempF10,
    required this.celsius,
    required this.style,
    required this.unitStyle,
    required this.hue,
    required this.semanticName,
    this.underline = true,
    this.underlineHeight = 3,
  });

  final int? tempF10;
  final bool celsius;
  final TextStyle style;
  final TextStyle unitStyle;

  /// The probe's series hue — the underline, and nothing else.
  final Color hue;
  final String semanticName;

  final bool underline;
  final double underlineHeight;

  /// The width [TempReadout] will occupy for this value at this style, in
  /// logical pixels. Mirrors [AnimatedTemp]'s composition exactly: whole
  /// digits, a half-scale tenth, then the unit behind a 2 dp gap.
  static double measure({
    required int? tempF10,
    required bool celsius,
    required TextStyle style,
    required TextStyle unitStyle,
  }) {
    double widthOf(String text, TextStyle s) => (TextPainter(
      text: TextSpan(text: text, style: s),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout()).width;

    final unit = widthOf(celsius ? '°C' : '°F', unitStyle) + 2;
    if (tempF10 == null) {
      return widthOf(noValue, style) + unit;
    }
    final tenths = celsius
        ? (((tempF10 - 320) * 5) / 9).round()
        : tempF10.round();
    final abs = tenths.abs();
    final whole = '${tenths < 0 ? '-' : ''}${abs ~/ 10}';
    return widthOf(whole, style) +
        widthOf(
          '.${abs % 10}',
          style.copyWith(fontSize: (style.fontSize ?? 48) * 0.52),
        ) +
        unit;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final number = MediaQuery.withNoTextScaling(
      child: AnimatedTemp(
        tempF10: tempF10,
        celsius: celsius,
        style: style.copyWith(color: t.textHi),
        unitStyle: unitStyle,
        color: t.textHi,
        semanticName: semanticName,
      ),
    );
    final content = underline
        ? IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                number,
                const SizedBox(height: SmokeTokens.s2),
                Container(
                  height: underlineHeight,
                  decoration: BoxDecoration(
                    color: tempF10 == null ? t.hairlineStrong : hue,
                    borderRadius: BorderRadius.circular(underlineHeight / 2),
                  ),
                ),
              ],
            ),
          )
        : number;

    // **The render safety, and it is not the fitting policy.**
    //
    // "Never scale a temperature" is enforced *upstream*, by [measure]: a
    // caller works out what the number will take and spends what is left on
    // the gauge, shrinking it 84 → 56 dp and then moving it to its own line.
    // With the shipping metrics that leaves the number at a fixed 96 pt on
    // every supported width, which is the whole rule.
    //
    // This is what happens when a value arrives that no layout can survive —
    // a five-character negative °C, a metric-square test font, a caller that
    // hands this a 120 dp column. A 4 % shrink is a bad frame; a 14 px
    // overflow throw is a screen with no temperature on it at all, and this
    // app exists to prevent the second one.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: content,
    );
  }
}
