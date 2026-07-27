/// A26 — SignalBars: four rising bars, filled to [bars] (design 14 §14.7).
///
/// **Drawn in neutrals, not in a status hue.** §14.6.1's separation rule
/// reserves status hues for chrome that carries an icon *and* a word; a bar
/// glyph is neither, so colouring it green-to-red would both break the rule
/// and duplicate information the word beside it already carries. The bar
/// *count* is the signal; the word says how to read it.
///
/// Never zero bars: a link with no signal is a link that is down, which the
/// screen says in words rather than rendering as an empty meter on a
/// connection that is demonstrably working.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.bars, this.size = 16});

  /// 1..4. Clamped rather than asserted — a meter is not worth a crash.
  final int bars;

  /// The height of the tallest bar; the glyph is square-ish around it.
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final lit = bars.clamp(1, 4);
    // Four bars and three gaps have to add up to `size` exactly — a glyph
    // that overflows its own box by half a pixel is a yellow-and-black
    // stripe in every widget test that renders it.
    const barW = 0.18;
    final gap = size * (1 - barW * 4) / 3;
    return Semantics(
      label: '$lit of 4 bars',
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 4; i++) ...[
              if (i > 1) SizedBox(width: gap),
              Container(
                width: size * barW,
                height: size * (0.28 + 0.24 * (i - 1)),
                decoration: BoxDecoration(
                  color: i <= lit ? t.textHi : t.chromeDim,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
