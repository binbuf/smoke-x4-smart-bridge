/// The circular food avatar (design 17 §17.3 A, §17.5).
///
/// The single biggest thing this app was missing. Every competitor puts food on
/// the screen — TempPro a photograph on every probe card and profile row, MEATER
/// a bold circular animal glyph per protein, reused as the avatar on every
/// previous-cook row. We had none, anywhere, which is why the app read as an
/// instrument panel beside three apps that read as cooking.
///
/// ## The rule this obeys, and why it is allowed to look like this
///
/// A saturated circle is the shape §16.5 spends most of its words forbidding: a
/// series hue may never fill anything larger than 12 dp, and a status hue may
/// only appear as a 12–16 % wash behind an icon *and* a word. This is neither.
/// §17.2 names a third channel — **identity** — which may fill, may carry a
/// word, and is safe for exactly one reason:
///
/// > **It never encodes state.** The same brisket avatar renders whether the
/// > cook is perfect or ruined, live or four hours frozen, alarmed or quiet.
///
/// That invariance is the whole permission slip, so it is pinned by a test
/// (`test/design/identity_channel_test.dart`) rather than left to review. Two
/// consequences a future change must not talk itself out of:
///
///  * **no freshness input.** This widget takes a [FoodGlyph], a size and a
///    register. There is deliberately nothing here to make it go grey, and
///    adding one would turn an identity mark into a status mark;
///  * **no alarm input**, for the same reason. When a probe alarms, the alarm
///    bar says so in `critical` chrome with an icon and a word, and the food is
///    still the same food.
///
/// A [StaleVeil] above does desaturate this along with everything else it
/// covers. That is not an exception: the veil is a statement about *the
/// readings under it*, applied to a whole region, and exempting one circle from
/// it would make the region look partly live.
///
/// ## Two registers, and the moment between them (§17.5)
///
/// [vivid] is **not** a state input, and the distinction is worth being precise
/// about because it looks like one. It does not describe the probe, the cook or
/// the link — it describes **the surface**: whether anything on this screen is
/// currently claiming a temperature. Where nothing is, §16.5's guard has
/// nothing to guard and the rich register applies; where something is, the
/// disciplined one does. Two rows of the same brisket avatar, one on an empty
/// reader and one under a live 163 °F, differ because *the screens* differ.
///
/// The change between them is **tweened**, over `SmokeMotion.standard`, and
/// that is the point rather than a flourish: §17.5 asks for a cook starting to
/// be a designed moment in which the screen visibly *cools*. A hard swap would
/// read as a repaint bug; a 220 ms step-down reads as the app changing register
/// from *choosing* to *watching*. Under `disableAnimations` it collapses to
/// zero, like everything else.
///
/// ## Vector, not photographic
///
/// §17.4 rejects TempPro's photos outright — licensing, bundle size, and a photo
/// cannot be tinted for the daylight profile. Eight glyphs are hand-drawn paths
/// (`design/food_glyph.dart`), five are Material icons. Both render through the
/// same avatar so a row never has to know which kind it got.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

/// The glyph in its identity circle.
///
/// [size] is the circle's diameter. The glyph is drawn at 58 % of it, which is
/// the ratio Material uses inside a circular avatar and which keeps a horn or a
/// tail fin off the rim at 20 dp.
class FoodAvatar extends StatelessWidget {
  const FoodAvatar({
    super.key,
    required this.glyph,
    this.size = 34,
    this.vivid = false,
    this.announce = true,
  });

  final FoodGlyph glyph;
  final double size;

  /// **A property of the surface, not of the probe** (§17.5). True only where
  /// nothing on screen is claiming a temperature: the empty reader, the preset
  /// picker, a finished cook in the history list, anything pre-connection.
  ///
  /// Defaults false — the disciplined register — so a new call site has to
  /// *argue* for warmth rather than inherit it, which is the direction the
  /// mistake is cheapest in.
  final bool vivid;

  /// Whether to speak [FoodGlyph.label].
  ///
  /// True on a cook row, where the avatar is the first thing describing the
  /// cook. False on a probe row, where the readout already announces the
  /// probe's name and "brisket, Brisket flat, 163 degrees" is one word too
  /// many — a shape needs a name (14 §14.10), not a repetition.
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final motion = SmokeMotion.of(context);
    final icon = glyph.icon;

    // The two registers as endpoints of one tween. `TweenAnimationBuilder`
    // re-targets on rebuild, so flipping [vivid] animates from wherever the
    // colour currently is — which is what makes a cook starting a step-down
    // rather than a cut.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: vivid ? 1 : 0, end: vivid ? 1 : 0),
      duration: motion.standard,
      curve: motion.curve,
      builder: (context, warmth, _) {
        final fill = Color.lerp(
          IdentityPalette.of(glyph),
          IdentityPalette.vivid(glyph),
          warmth,
        )!;
        // Measured per fill rather than hard-coded, so the disciplined set gets
        // its near-white glyph and the rich set its near-black one from one
        // rule — and a retune of either cannot ship a glyph nobody can see.
        final ink = IdentityPalette.inkOn(fill, light: t.textHi, dark: t.bg);

        final circle = Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            // A hairline, because the disciplined hues sit only ~3.4:1 off
            // `card` and a rim is what keeps the disc a disc on an OLED at an
            // angle. Decorative by §14.3.1 rule 2 — never the only channel.
            border: Border.all(color: t.hairline),
          ),
          child: Center(
            child: icon != null
                ? Icon(icon, size: size * 0.56, color: ink)
                : CustomPaint(
                    size: Size.square(size * 0.58),
                    painter: _FoodGlyphPainter(glyph: glyph, ink: ink),
                  ),
          ),
        );

        return announce
            ? Semantics(
                label: glyph.label,
                excludeSemantics: true,
                child: circle,
              )
            : ExcludeSemantics(child: circle);
      },
    );
  }
}

/// Paints one of the eight hand-drawn silhouettes.
///
/// The path is authored in a [foodGlyphBox]-square space and scaled here, so
/// one geometry serves the 20 dp compact card and the 64 dp picker without a
/// second set of numbers to keep in sync.
class _FoodGlyphPainter extends CustomPainter {
  const _FoodGlyphPainter({required this.glyph, required this.ink});

  final FoodGlyph glyph;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final path = foodGlyphPath(glyph);
    if (path == null) {
      return;
    }
    final s = size.shortestSide / foodGlyphBox;
    canvas.save();
    canvas.scale(s, s);
    canvas.drawPath(path, Paint()..color = ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FoodGlyphPainter old) =>
      old.glyph != glyph || old.ink != ink;
}
