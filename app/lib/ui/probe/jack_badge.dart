/// The numbered jack badge (design 17 §17.2, §17.3 B).
///
/// A 1–4 numeral in a disc filled with that probe's **series hue**, leading
/// every probe row and card. It replaces the 4 dp left rule as the primary
/// identity mark, and it is the cheapest identity win available — TempPro's
/// channel tab (`TemProBBQ-1`), which is the one thing on that screen worth
/// taking.
///
/// ## Why a series hue is allowed to fill this
///
/// §16.5 says a series hue is *"only ever a mark — a chart stroke, a gauge arc,
/// a ≤12 dp dot, a card's left rule. It never fills a large shape and it never
/// carries a word."* A 26 dp disc with a digit in it breaks the letter of both
/// clauses, so §17.2 sanctions it explicitly and narrowly:
///
/// > The hue *is* the probe's identity, and the numeral names the same thing the
/// > hue names — it is a legend, not a claim.
///
/// The distinction that keeps the rule intact: a series hue may not carry a word
/// *about how the cook is going*. "2" says which jack, which is what the hue
/// already said. Nothing here can be mistaken for an alarm, because an alarm is
/// a bordered slab with a sentence in it and this is a coin.
///
/// The badge is also the app's answer to a hardware fact: the OLED can only name
/// a probe by its number ([07 §7.2]), and the series palette is keyed to the
/// jack rather than the role for the same reason. Printing the number beside the
/// hue makes the phone and the device agree out loud.
///
/// ## The ink is measured, not chosen
///
/// See [IdentityPalette.inkOn]. There is no single ink that reads on all four
/// series hues; picking per hue lands every slot at ≥4.9:1, and hard-coding
/// white or black ships one unreadable jack in four.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

class JackBadge extends StatelessWidget {
  const JackBadge({super.key, required this.jack, this.size = 26});

  /// 1..4 — the physical jack.
  final int jack;

  /// The disc's diameter. 26 on a strip row, 22 on a hero header, 20 on a
  /// compact card — a hierarchy of the same mark rather than three marks.
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hue = ProbePalette.hue(jack);
    return ExcludeSemantics(
      // The readout beside this already announces the probe by name, and
      // "probe 2, Brisket flat, 163 degrees" is the same fact twice. The
      // numeral is a *visual* legend; the spoken legend is the name.
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(color: hue, shape: BoxShape.circle),
          // Unscaled, exactly as a temperature is (§14.5.1's reasoning applied
          // to a mark rather than to a number): the disc is a fixed-size legend,
          // and a numeral doubled by the OS text scale inside it clips instead
          // of informing. Everything around it — the name, the trend, the second
          // line — still scales, which is what a reader who set 200 % asked for.
          child: Center(
            child: MediaQuery.withNoTextScaling(
              child: Text(
                '$jack',
                style: SmokeType.labelSm.copyWith(
                  color: IdentityPalette.inkOn(
                    hue,
                    light: t.textHi,
                    dark: t.bg,
                  ),
                  fontSize: size * 0.46,
                  letterSpacing: 0,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
