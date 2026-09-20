/// Vector portraits of the two devices setup talks about (design 17 §17.3 C,
/// 13 §13.2.1/§13.2.2).
///
/// WHY this file exists: the teardown in 17 §17.1 #4 names onboarding presence
/// as one of the four things the competitors have and we do not — *"`Meater-1`
/// and `Meater-3` sell the product on the setup screen. Our hop 1 is correct,
/// calm and empty: a rail, a title, a sentence, one device row."* A bench run
/// confirmed it: the first screen of the product is text on black. It has no
/// subject.
///
/// So hop 1 gets a subject, and it is the bridge itself.
///
/// **Vector, never a bundled photograph** — the same reasoning 17 §17.3 A gives
/// for the food glyphs, and one more that only applies here: the daylight
/// profile (14 §14.3.3) lifts the ink ramp and switches every glow off, and a
/// PNG cannot follow it. Everything below is painted from `context.tokens`, so
/// the bridge dims outdoors exactly as the rest of the screen does.
///
/// ## The colour channel this uses
///
/// 17 §17.2 opens a third channel — **identity** — alongside series and status,
/// for imagery that says *what a thing is* rather than *how it is going*. And
/// §17.5 sets how far it may be pushed: the colour discipline exists to stop a
/// hue lying about *live state*, so **where there is no live state the guard
/// has nothing to guard**. Onboarding has no session and no readings, so these
/// drawings are rich rather than austere — saturated ember, gradients, a rim
/// light, a lit pool under the board, gold pin headers.
///
/// Two things still hold, and they are why this is warm rather than loud:
///
/// * **no colour is the sole carrier of meaning** (§17.5, §H.2). A mood changes
///   the *glyph on the glass* and the *direction of the ripple*; it never
///   changes only the hue, so the four moods are told apart with the colour
///   removed.
/// * **green is not used to celebrate.** There is none in this file. A caller
///   that wants to claim a live link says so with a `positive` icon and a word
///   beside the picture (§16.5) — the drawing itself never claims it.
///
/// ## Motion
///
/// The ripple exists so the screen feels like it is *looking at something*.
/// Under `MediaQuery.disableAnimations` it stops and the rings render statically
/// at three fixed radii — the "broadcasting" idea survives, the movement does
/// not. The period comes from [SmokeMotion] and there is deliberately no
/// `Duration` literal anywhere in this file (14 §14.4.1).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/design.dart';

/// What the bridge is doing, expressed as the glyph on its OLED and the
/// direction of the ripple. **Never as a colour** — see the library doc.
enum BridgeMood {
  /// The phone is searching. Rings travel outward; the glass shows the
  /// "waiting for a phone" page.
  scanning,

  /// The bridge is listening for a Smoke X. Rings travel *inward* — something
  /// is arriving rather than being sent.
  listening,

  /// A pairing code is on the glass. Six cells, two groups of three, and
  /// **never a digit**: the passkey is generated on the device and this phone
  /// never learns it (§13.2.1), so this drawing is incapable of showing one.
  passkey,

  /// Bonded. A tick on the glass, a still halo, no ripple.
  linked,

  /// Powered and idle — the normal page, no ripple. Used where the subject is
  /// the device rather than an activity.
  ready,
}

/// The bridge: a Heltec-style board with its OLED lit.
///
/// Sizes itself to the smaller of [size] and whatever its parent allows, so a
/// caller can drop it into a bounded body slot at 200 % text scale without
/// measuring anything. Decorative by default — pass [semanticLabel] only where
/// the picture carries information the words around it do not.
class BridgeIllustration extends StatefulWidget {
  const BridgeIllustration({
    super.key,
    required this.mood,
    this.size = 168,
    this.semanticLabel,
  });

  final BridgeMood mood;

  /// The preferred edge of the square it draws into. Shrinks to fit.
  final double size;

  final String? semanticLabel;

  @override
  State<BridgeIllustration> createState() => _BridgeIllustrationState();
}

class _BridgeIllustrationState extends State<BridgeIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  /// Only two moods carry a travelling ripple; the rest are still pictures and
  /// must not hold a ticker open behind them.
  bool get _ripples =>
      widget.mood == BridgeMood.scanning ||
      widget.mood == BridgeMood.listening;

  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = SmokeMotion.of(context);
    // `pulseScales` is the one boolean the motion layer publishes for "the user
    // asked for less movement" (§14.4.1); `pulse` is the only period that is
    // never zeroed, which is exactly right for a loop that must not divide by
    // its own duration.
    _reduced = !motion.pulseScales;
    _c.duration = motion.pulse;
    _sync();
  }

  @override
  void didUpdateWidget(BridgeIllustration old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_ripples && !_reduced) {
      if (!_c.isAnimating) {
        _c.repeat();
      }
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final art = LayoutBuilder(
      builder: (context, c) {
        var d = widget.size;
        if (c.hasBoundedWidth) {
          d = math.min(d, c.maxWidth);
        }
        if (c.hasBoundedHeight) {
          d = math.min(d, c.maxHeight);
        }
        d = math.max(d, 0);
        return RepaintBoundary(
          child: SizedBox.square(
            dimension: d,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                painter: _BridgePainter(
                  mood: widget.mood,
                  tokens: tokens,
                  accent: StatusPalette.pit,
                  phase: _c.value,
                  reduced: _reduced,
                ),
                size: Size.square(d),
              ),
            ),
          ),
        );
      },
    );
    final label = widget.semanticLabel;
    return label == null
        ? ExcludeSemantics(child: art)
        : Semantics(label: label, excludeSemantics: true, child: art);
  }
}

/// The Smoke X base station, with its SYNC control lit.
///
/// Hop 2 asks the user to walk to a *second device* and hold a button on it
/// (§13.2.2). A screen that says so over an empty black field is asking someone
/// to go and find a control they have never looked for; drawing the unit is the
/// cheapest way to make the instruction land. Still — there is nothing to
/// animate here, so nothing is.
class BaseStationIllustration extends StatelessWidget {
  const BaseStationIllustration({
    super.key,
    this.size = 168,
    this.semanticLabel,
  });

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final art = LayoutBuilder(
      builder: (context, c) {
        var d = size;
        if (c.hasBoundedWidth) {
          d = math.min(d, c.maxWidth);
        }
        if (c.hasBoundedHeight) {
          d = math.min(d, c.maxHeight);
        }
        return RepaintBoundary(
          child: SizedBox.square(
            dimension: math.max(d, 0),
            child: CustomPaint(
              painter: _BasePainter(tokens: tokens, accent: StatusPalette.pit),
              size: Size.square(math.max(d, 0)),
            ),
          ),
        );
      },
    );
    final label = semanticLabel;
    return label == null
        ? ExcludeSemantics(child: art)
        : Semantics(label: label, excludeSemantics: true, child: art);
  }
}

// ══ the painters ═══════════════════════════════════════════════════════════
//
// Every dimension below is a fraction of the box edge, so one painter serves a
// 56 dp inline glyph and a 200 dp hero without a second set of numbers.

/// The ember these drawings are lit by — the same hue as the primary button and
/// series slot 1, which is the app's fire (§14.6.4).
Color get _ember => StatusPalette.pit;

/// The cool bounce on the underside of a body, so a shape reads as *lit from
/// above* rather than as a flat rectangle. Series slot 4's blue, borrowed as
/// identity: there is no series on screen here to confuse it with (§17.5).
Color get _bounce => ProbePalette.hue(4);

/// Copper. Pin headers and probe jacks are gold-plated on the real hardware,
/// and drawing them so is most of what makes a board read as a board.
const Color _copper = Color(0xFFE0A34A);

/// A blurred paint, or a plain one in the daylight profile where every glow is
/// off (§14.3.3). Returned rather than applied so the caller keeps its stroke
/// width and cap.
Paint _bloom(SmokeTokens t, Color c, double sigma, {double alpha = 1}) {
  final p = Paint()..color = c.withValues(alpha: alpha);
  if (t.glowsEnabled) {
    p.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
  }
  return p;
}

/// The lit pool a device sits in. Saturated on purpose — §17.5: no session, no
/// reading, nothing for a colour to misstate, and this is the single cheapest
/// thing that stops the screen reading as an outline on black.
void _paintPool(Canvas canvas, SmokeTokens t, Rect body, double s) {
  final pool = Rect.fromCenter(
    center: Offset(body.center.dx, body.bottom + s * 0.045),
    width: s * 1.0,
    height: s * 0.20,
  );
  canvas.drawOval(
    pool,
    Paint()
      ..shader = RadialGradient(
        colors: [
          _ember.withValues(alpha: t.glowsEnabled ? 0.22 : 0.12),
          _ember.withValues(alpha: 0.05),
          _ember.withValues(alpha: 0),
        ],
        stops: const [0, 0.55, 1],
      ).createShader(pool),
  );
}

/// The body of a device: a top-lit gradient slab with an ember rim on the
/// upper edge and a cool bounce along the lower one.
void _paintShell(Canvas canvas, SmokeTokens t, RRect rrect, double s) {
  final r = rrect.outerRect;
  canvas.drawRRect(
    rrect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [t.cardRaised, t.card, t.well],
        stops: const [0, 0.55, 1],
      ).createShader(r),
  );
  // The rim light. A 1 dp ember hairline along the top and a blue one along
  // the bottom is the whole depth cue — it costs nothing and it is what makes
  // the slab look like an object under a lamp.
  canvas.drawRRect(
    rrect,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.007
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _ember.withValues(alpha: 0.75),
          t.hairlineStrong,
          _bounce.withValues(alpha: 0.55),
        ],
        stops: const [0, 0.5, 1],
      ).createShader(r),
  );
}

class _BridgePainter extends CustomPainter {
  const _BridgePainter({
    required this.mood,
    required this.tokens,
    required this.accent,
    required this.phase,
    required this.reduced,
  });

  final BridgeMood mood;
  final SmokeTokens tokens;
  final Color accent;

  /// 0..1, one full ripple cycle.
  final double phase;
  final bool reduced;

  bool get _ripples =>
      mood == BridgeMood.scanning || mood == BridgeMood.listening;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (s <= 0) {
      return;
    }

    // The board. Landscape, because that is how it sits on a shelf beside the
    // smoker, and sized to *fill* its frame — a 90 dp object adrift in a 155 dp
    // box reads as a diagram, which is the opposite of presence. The ripple is
    // elliptical rather than circular for the same reason: hugging the board's
    // proportion buys the board another 20 % of the frame.
    final bw = s * 0.68;
    final bh = s * 0.34;
    final board = Rect.fromCenter(
      center: Offset(s / 2, s * 0.52),
      width: bw,
      height: bh,
    );
    final centre = board.center;

    if (_ripples) {
      _paintRipples(canvas, s, centre);
    } else {
      _paintHalo(canvas, s, centre);
    }

    _paintPool(canvas, tokens, board, s);
    _paintAntenna(canvas, s, board);
    _paintBody(canvas, s, board);
    _paintPorts(canvas, s, board);
    _paintOled(canvas, s, board);
  }

  /// Concentric rings, three of them, evenly spaced through one period.
  /// `scanning` sends them out; `listening` brings them in — the only thing
  /// that tells the two states apart in the drawing, since neither may say it
  /// in colour.
  void _paintRipples(Canvas canvas, double s, Offset centre) {
    const rings = 3;
    const near = 0.385;
    const far = 0.495;
    // Elliptical, at the board's own proportion — a circle big enough to clear
    // a landscape board wastes the frame above and below it.
    const squash = 0.66;
    final inward = mood == BridgeMood.listening;

    Rect ovalAt(double rx) =>
        Rect.fromCenter(center: centre, width: rx * 2, height: rx * 2 * squash);

    // A saturated wash the rings travel through, so the radio reads as a field
    // and not as three hoops. §17.5: nothing here is claiming a temperature.
    final field = ovalAt(s * far);
    canvas.drawOval(
      field,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.03),
            accent.withValues(alpha: 0),
          ],
          stops: const [0, 0.7, 1],
        ).createShader(field),
    );

    for (var i = 0; i < rings; i++) {
      // Reduced motion: freeze the three rings at fixed radii. The picture
      // still reads as a radio, it just stops moving (§14.4.1).
      final f = reduced ? (i + 1) / (rings + 1) : (phase + i / rings) % 1.0;
      final travel = inward ? 1 - f : f;
      final rx = s * (near + (far - near) * travel);
      // Fade out as it leaves, fade in as it arrives — so a ring is always
      // faintest at the far edge and never terminates with a hard edge.
      final a = 0.75 * (inward ? travel : 1 - f);
      if (a <= 0.01) {
        continue;
      }
      canvas.drawOval(
        ovalAt(rx),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.011
          ..color = accent.withValues(alpha: a),
      );
    }
  }

  /// The still moods get a lit halo instead of a ring.
  ///
  /// `linked` gets a *burst*: this is the arrival, the one moment in hop 1 that
  /// has been earned, and §17.5 says a screen with no live reading on it may
  /// look like it. The halo is paired with the tick on the glass, so the
  /// meaning survives with the colour removed.
  void _paintHalo(Canvas canvas, double s, Offset centre) {
    final arrival = mood == BridgeMood.linked;
    final r = s * (arrival ? 0.50 : 0.42);
    // A still bridge is grounded by the pool under it; a second wash on top of
    // that reads as a stain rather than as light, so the idle halo is faint and
    // only the arrival is bright.
    final peak = arrival ? 0.36 : 0.07;
    final field = Rect.fromCenter(
      center: centre,
      width: r * 2,
      height: r * 2 * 0.72,
    );
    canvas.drawOval(
      field,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: tokens.glowsEnabled ? peak : peak * 0.5),
            accent.withValues(alpha: 0),
          ],
        ).createShader(field),
    );
    if (!arrival) {
      return;
    }
    // Eight short rays, so the burst is a *shape* and not only a wash — which
    // is §17.5's colour-blind clause honoured in the drawing itself.
    final ray = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.013
      ..color = accent.withValues(alpha: 0.6);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + math.pi / 8;
      final d = Offset(math.cos(a) * 0.5, math.sin(a) * 0.36);
      canvas.drawLine(centre + d * (s * 0.80), centre + d * (s * 0.99), ray);
    }
  }

  /// The stub aerial. Drawn *behind* the board so it reads as plugged into the
  /// far edge rather than lying on top of it.
  void _paintAntenna(Canvas canvas, double s, Rect board) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.014
      ..strokeCap = StrokeCap.round
      ..color = tokens.chromeDim;
    final root = Offset(board.right - s * 0.01, board.top + board.height * 0.3);
    final elbow = Offset(board.right + s * 0.05, root.dy);
    final tip = Offset(elbow.dx, board.top - s * 0.07);
    canvas.drawLine(root, elbow, stroke);
    canvas.drawLine(elbow, tip, stroke);
    // The tip is lit: it is the end the radio comes out of.
    if (tokens.glowsEnabled) {
      canvas.drawCircle(tip, s * 0.03, _bloom(tokens, accent, s * 0.02, alpha: 0.5));
    }
    canvas.drawCircle(tip, s * 0.015, Paint()..color = accent);
  }

  void _paintBody(Canvas canvas, double s, Rect board) {
    final rrect = RRect.fromRectAndRadius(board, Radius.circular(s * 0.035));
    _paintShell(canvas, tokens, rrect, s);

    // The radio module — a shielded can with a copper trace snaking out of it,
    // which is what actually occupies the half of the board the display does
    // not. Without it the right side is a blank slab and the whole thing reads
    // as a placeholder.
    final can = Rect.fromLTWH(
      board.left + board.width * 0.56,
      board.center.dy - board.height * 0.20,
      board.width * 0.30,
      board.height * 0.40,
    );
    final canR = RRect.fromRectAndRadius(can, Radius.circular(s * 0.008));
    canvas.drawRRect(
      canR,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tokens.textMuted, tokens.chromeDim],
        ).createShader(can),
    );
    canvas.drawRRect(
      canR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.004
        ..color = tokens.well.withValues(alpha: 0.6),
    );
    // The meander antenna trace on the PCB, in copper.
    final trace = Path()..moveTo(can.right, can.center.dy);
    final step = board.width * 0.028;
    var x = can.right;
    var up = true;
    for (var i = 0; i < 3; i++) {
      trace.lineTo(x + step, can.center.dy + (up ? -1 : 1) * board.height * 0.12);
      x += step;
      up = !up;
    }
    canvas.drawPath(
      trace,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.006
        ..color = _copper.withValues(alpha: 0.8),
    );

    // Pin headers along both long edges — the one detail that says "dev board"
    // rather than "generic gadget", and the reason they are copper rather than
    // grey is that they are copper.
    final pinW = s * 0.010;
    final pinH = s * 0.022;
    final pins = Paint()..color = _copper;
    for (var i = 0; i < 8; i++) {
      final px = board.left + board.width * (0.10 + 0.105 * i);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(px, board.top + s * 0.010, pinW, pinH),
          Radius.circular(pinW),
        ),
        pins,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(px, board.bottom - s * 0.010 - pinH, pinW, pinH),
          Radius.circular(pinW),
        ),
        pins,
      );
    }
  }

  /// The USB-C tongue on the near edge, and the power LED — both are how a
  /// user recognises the object they are holding.
  void _paintPorts(Canvas canvas, double s, Rect board) {
    final usbH = s * 0.05;
    final usb = Rect.fromLTWH(
      board.left - s * 0.018,
      board.center.dy - usbH / 2,
      s * 0.026,
      usbH,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(usb, Radius.circular(s * 0.012)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tokens.textMuted, tokens.chromeDim],
        ).createShader(usb),
    );

    final led = Offset(board.right - s * 0.045, board.bottom - s * 0.045);
    if (tokens.glowsEnabled) {
      canvas.drawCircle(led, s * 0.03, _bloom(tokens, accent, s * 0.025));
    }
    canvas.drawCircle(led, s * 0.012, Paint()..color = accent);
  }

  /// The little OLED, lit. The glass is `well` — the deepest surface, the one
  /// reserved for mono readouts — because that is literally what it is. What
  /// makes it read as *lit* rather than as a dark hole is the ember wash inside
  /// it and the bloom around the bezel.
  void _paintOled(Canvas canvas, double s, Rect board) {
    final glass = Rect.fromLTWH(
      board.left + board.width * 0.055,
      board.top + board.height * 0.20,
      board.width * 0.44,
      board.height * 0.60,
    );
    final rrect = RRect.fromRectAndRadius(glass, Radius.circular(s * 0.012));
    canvas.drawRRect(rrect, Paint()..color = tokens.well);
    // The emitted light of an OLED, pooling at the middle of the glass.
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: 0.28),
            accent.withValues(alpha: 0.05),
          ],
        ).createShader(glass),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.006
        ..color = accent.withValues(alpha: 0.7),
    );
    if (tokens.glowsEnabled) {
      canvas.drawRRect(
        rrect,
        _bloom(tokens, accent, s * 0.035, alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.014,
      );
    }

    canvas.save();
    canvas.clipRRect(rrect);
    switch (mood) {
      case BridgeMood.passkey:
        _paintCells(canvas, s, glass);
      case BridgeMood.linked:
        _paintTick(canvas, s, glass);
      case BridgeMood.scanning:
      case BridgeMood.listening:
      case BridgeMood.ready:
        _paintPage(canvas, s, glass);
    }
    canvas.restore();
  }

  /// The device's normal page: a header rule and two short value rows. It is a
  /// *wireframe*, deliberately — inventing legible text on the glass would be
  /// inventing a reading.
  void _paintPage(Canvas canvas, double s, Rect glass) {
    final ink = Paint()..color = accent;
    final faint = Paint()..color = accent.withValues(alpha: 0.55);
    final h = glass.height;
    final barH = h * 0.11;
    void bar(double topFrac, double widthFrac, Paint p) {
      final r = Rect.fromLTWH(
        glass.left + glass.width * 0.12,
        glass.top + h * topFrac,
        glass.width * 0.76 * widthFrac,
        barH,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(barH / 2)),
        p,
      );
    }

    bar(0.16, 0.62, ink);
    bar(0.44, 1.0, faint);
    bar(0.68, 0.78, faint);
  }

  /// Six cells, grouped `••• •••` — the shape of the passkey, never its value.
  /// [PasskeyDisplay] makes the same promise in type; this makes it in paint.
  void _paintCells(Canvas canvas, double s, Rect glass) {
    final r = glass.height * 0.09;
    final y = glass.center.dy;
    final gap = glass.width * 0.115;
    final groupGap = glass.width * 0.09;
    final total = gap * 5 + groupGap;
    var x = glass.center.dx - total / 2;
    final p = Paint()..color = accent;
    for (var i = 0; i < 6; i++) {
      canvas.drawCircle(Offset(x, y), r, p);
      x += gap + (i == 2 ? groupGap : 0);
    }
  }

  void _paintTick(Canvas canvas, double s, Rect glass) {
    final w = glass.width * 0.34;
    final c = glass.center;
    final path = Path()
      ..moveTo(c.dx - w * 0.55, c.dy)
      ..lineTo(c.dx - w * 0.12, c.dy + w * 0.42)
      ..lineTo(c.dx + w * 0.6, c.dy - w * 0.42);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.016
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(_BridgePainter old) =>
      old.mood != mood ||
      old.tokens != tokens ||
      old.accent != accent ||
      old.reduced != reduced ||
      old.phase != phase;
}

class _BasePainter extends CustomPainter {
  const _BasePainter({required this.tokens, required this.accent});

  final SmokeTokens tokens;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (s <= 0) {
      return;
    }
    final body = Rect.fromCenter(
      center: Offset(s / 2, s * 0.48),
      width: s * 0.54,
      height: s * 0.74,
    );
    final rrect = RRect.fromRectAndRadius(body, Radius.circular(s * 0.06));

    _paintPool(canvas, tokens, body, s);
    _paintShell(canvas, tokens, rrect, s);

    // The display, showing two channel rows, lit.
    final glass = Rect.fromLTWH(
      body.left + s * 0.05,
      body.top + s * 0.06,
      body.width - s * 0.10,
      body.height * 0.40,
    );
    final gr = RRect.fromRectAndRadius(glass, Radius.circular(s * 0.02));
    canvas.drawRRect(gr, Paint()..color = tokens.well);
    canvas.drawRRect(
      gr,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0.04),
          ],
        ).createShader(glass),
    );
    canvas.drawRRect(
      gr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.005
        ..color = accent.withValues(alpha: 0.6),
    );
    final rowH = glass.height * 0.16;
    for (var i = 0; i < 2; i++) {
      final r = Rect.fromLTWH(
        glass.left + glass.width * 0.14,
        glass.top + glass.height * (0.22 + 0.34 * i),
        glass.width * (i == 0 ? 0.62 : 0.44),
        rowH,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(rowH / 2)),
        Paint()..color = accent.withValues(alpha: i == 0 ? 1 : 0.55),
      );
    }

    // The SYNC control — the one thing the eye should land on, because the
    // whole screen is an instruction to hold it (§13.2.2). Filled ember, not a
    // tinted outline: §17.5 permits a saturated fill where there is no live
    // reading to misstate, and the word is printed on the pill beneath the
    // drawing, so the colour is never the only thing naming this control.
    final btnW = body.width * 0.5;
    final btnH = s * 0.055;
    final btn = Rect.fromCenter(
      center: Offset(body.center.dx, body.bottom - s * 0.14),
      width: btnW,
      height: btnH,
    );
    final br = RRect.fromRectAndRadius(btn, Radius.circular(btnH / 2));
    if (tokens.glowsEnabled) {
      canvas.drawRRect(br, _bloom(tokens, accent, s * 0.04, alpha: 0.7));
    }
    canvas.drawRRect(
      br,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent, accent.withValues(alpha: 0.72)],
        ).createShader(btn),
    );
    // A pressed-in highlight along the top of the cap.
    canvas.drawLine(
      Offset(btn.left + btnH * 0.6, btn.top + btnH * 0.22),
      Offset(btn.right - btnH * 0.6, btn.top + btnH * 0.22),
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = s * 0.006
        ..color = Colors.white.withValues(alpha: 0.35),
    );

    // Four probe jacks along the bottom edge — the detail that says which box
    // this is, since the X4 is the one with four of them. Copper, like the
    // sockets are; they are told apart by *position*, never by hue, so no
    // series colour goes anywhere near them.
    for (var i = 0; i < 4; i++) {
      final c = Offset(
        body.left + body.width * (0.2 + 0.2 * i),
        body.bottom - s * 0.032,
      );
      canvas.drawCircle(c, s * 0.019, Paint()..color = tokens.well);
      canvas.drawCircle(
        c,
        s * 0.019,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.006
          ..color = _copper,
      );
    }
  }

  @override
  bool shouldRepaint(_BasePainter old) =>
      old.tokens != tokens || old.accent != accent;
}
