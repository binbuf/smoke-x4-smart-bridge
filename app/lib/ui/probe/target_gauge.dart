/// A19.6 — TargetGauge (design 14 §14.7.3, §14.6.6).
///
/// An 84×84 radial gauge with two modes and one payoff.
///
///  * **Sweep mode** (a food probe with a target): a solid arc filling toward
///    the target, tweened over `SmokeMotion.gauge`, with a radial *pull tick*
///    inside the ring at the pull temperature.
///  * **Band mode** (the pit, with a target band): a track, a tinted band
///    sector, and a current-value dot that goes `warning`/`critical` when the
///    reading leaves the band.
///
/// With neither a target nor a band, **it does not render** — there is never an
/// empty ring on screen (§14.7.3).
///
/// **Target reached is not a colour (§14.6.6).** When a food probe reaches its
/// target the ring sweeps past its 270° end to a full circle, thickens 8 → 10,
/// goes solid in the probe's own hue, and the centre glyph cross-fades to a
/// check. There is no green anywhere in this widget; the closed ring *is* the
/// signal, which is why a lit-lime chart line and "done" can never be confused.
/// The word still travels too — the caller's pill reads "Reached" and the
/// semantics say so — because a shape alone is as bad as a hue alone for a
/// screen reader.
///
/// **Band mode carries the same obligation, and the caller owes it.** Leaving
/// the band turns the band arc `warning` and the current-value dot `critical`,
/// and a status hue is only ever allowed to appear *with an icon and a word*
/// (§16.5). This widget has no room for either — an 84 dp dial that shrinks to
/// 56 — so [_semanticValue] speaks "above the band" to a screen reader and the
/// **caller must render the strip** that says it on the glass. `ProbeHeroCard`
/// does, from `InsightKind.band`; a new call site for band mode that does not
/// is a colour-rule break, not a styling choice.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/design.dart';

class TargetGauge extends StatelessWidget {
  const TargetGauge({
    super.key,
    required this.hue,
    required this.reached,
    this.tempF10,
    this.targetF10,
    this.startF10,
    this.pullF10,
    this.bandMinF10,
    this.bandMaxF10,
    this.size = 84,
    this.centerIcon,
  });

  final Color hue;
  final bool reached;
  final int? tempF10;
  final int? targetF10;

  /// Where the sweep starts from — usually the pit floor or ambient. Defaults
  /// to a sensible cool start so the arc is meaningful from the first reading.
  final int? startF10;
  final int? pullF10;
  final int? bandMinF10;
  final int? bandMaxF10;
  final double size;
  final IconData? centerIcon;

  bool get _band => bandMinF10 != null && bandMaxF10 != null;
  bool get _sweep => targetF10 != null && !_band;

  @override
  Widget build(BuildContext context) {
    if (!_band && !_sweep) {
      return const SizedBox.shrink();
    }
    final t = context.tokens;
    final motion = SmokeMotion.of(context);

    return Semantics(
      value: _semanticValue(),
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: _band
            ? CustomPaint(
                painter: _BandPainter(
                  hue: hue,
                  temp: tempF10,
                  min: bandMinF10!,
                  max: bandMaxF10!,
                  track: t.hairlineStrong,
                  warning: StatusPalette.warning,
                  critical: StatusPalette.critical,
                  glow: t.glowTight(hue),
                ),
                child: _center(context),
              )
            : TweenAnimationBuilder<double>(
                tween: Tween(end: _sweepFraction()),
                duration: motion.gauge,
                curve: motion.curve,
                builder: (context, frac, _) => CustomPaint(
                  painter: _SweepPainter(
                    hue: hue,
                    fraction: frac,
                    reached: reached,
                    pullFraction: _pullFraction(),
                    track: t.hairlineStrong,
                    cut: t.card,
                  ),
                  child: _center(context),
                ),
              ),
      ),
    );
  }

  Widget _center(BuildContext context) {
    final motion = SmokeMotion.of(context);
    final icon = reached ? Icons.check_rounded : centerIcon;
    if (icon == null) {
      return const SizedBox.shrink();
    }
    return Center(
      child: AnimatedSwitcher(
        duration: motion.standard,
        child: Icon(
          icon,
          key: ValueKey(reached),
          size: size * 0.28,
          color: reached ? hue : context.tokens.textMuted,
        ),
      ),
    );
  }

  double _sweepFraction() {
    final temp = tempF10;
    final target = targetF10;
    if (temp == null || target == null) {
      return 0;
    }
    final start = startF10 ?? (target - 1350).clamp(-400, target - 100);
    if (target <= start) {
      return reached ? 1 : 0;
    }
    return ((temp - start) / (target - start)).clamp(0.0, 1.0);
  }

  double? _pullFraction() {
    final pull = pullF10;
    final target = targetF10;
    if (pull == null || target == null) {
      return null;
    }
    final start = startF10 ?? (target - 1350).clamp(-400, target - 100);
    if (target <= start) {
      return null;
    }
    return ((pull - start) / (target - start)).clamp(0.0, 1.0);
  }

  String _semanticValue() {
    if (_band) {
      final temp = tempF10;
      if (temp == null) {
        return 'pit, no reading';
      }
      final below = temp < bandMinF10!;
      final above = temp > bandMaxF10!;
      final where = below
          ? 'below the band'
          : above
          ? 'above the band'
          : 'in the band';
      return 'pit ${(temp / 10).toStringAsFixed(1)} degrees, $where '
          '${(bandMinF10! / 10).round()} to ${(bandMaxF10! / 10).round()}';
    }
    if (reached) {
      return 'reached ${(targetF10! / 10).round()} degrees';
    }
    final pct = (_sweepFraction() * 100).round();
    final pull = pullF10;
    // The tick is a shape, so the word has to travel too — a screen reader gets
    // the pull point spoken, not "a mark at 78 %".
    final early = pull == null
        ? ''
        : ', pull early at ${(pull / 10).round()} degrees';
    return '$pct percent of the way to ${(targetF10! / 10).round()} degrees'
        '$early';
  }
}

// 270° of arc, opening down: from -225° (i.e. 135° past 12 o'clock CCW) sweeping
// clockwise. In canvas radians, 0 is 3 o'clock and positive is clockwise.
const double _start = math.pi * 0.75; // 135°, lower-left
const double _sweepArc = math.pi * 1.5; // 270°

class _SweepPainter extends CustomPainter {
  _SweepPainter({
    required this.hue,
    required this.fraction,
    required this.reached,
    required this.pullFraction,
    required this.track,
    required this.cut,
  });

  final Color hue;
  final double fraction;
  final bool reached;
  final double? pullFraction;
  final Color track;

  /// The surface behind the ring. The pull tick notches the ring by drawing a
  /// sliver of it, which is what makes the tick readable once the arc has swept
  /// past — the old tick was the same hue *on* the same hue and disappeared at
  /// exactly the moment it mattered.
  final Color cut;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = reached ? 10.0 : 8.0;
    final rect = Offset.zero & size;
    final inset = rect.deflate(stroke / 2 + 2);

    canvas.drawArc(
      inset,
      _start,
      _sweepArc,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = track,
    );

    final sweep = reached ? math.pi * 2 : _sweepArc * fraction;
    if (sweep > 0) {
      canvas.drawArc(
        reached ? rect.deflate(stroke / 2 + 2) : inset,
        _start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = hue,
      );
    }

    // ── the pull-early tick (§H.2: "a clearer pull-early tick") ──────
    //
    // *Pull early* is the single most actionable number in a guided cook — take
    // it off here and carryover finishes the job — and it was an 8 dp line at
    // 60 % alpha, drawn **inside** the ring in the same hue the ring fills
    // with. Now: a notch cut clean through the ring, and a full-alpha mark
    // crossing it. It reads whether the arc has passed it or not.
    final pf = pullFraction;
    if (pf != null && !reached) {
      final angle = _start + _sweepArc * pf;
      final c = inset.center;
      final r = inset.width / 2;
      final dir = Offset(math.cos(angle), math.sin(angle));

      // The notch: a 5°-wide sliver of the surface colour, one pixel wider
      // than the ring so no hue bleeds around its ends.
      const notch = math.pi / 36; // 5°
      canvas.drawArc(
        inset,
        angle - notch / 2,
        notch,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke + 2
          ..color = cut,
      );

      // The mark: crosses the ring and stands 3 dp proud of it on both sides,
      // so it is legible at the 56 dp the gauge shrinks to on a narrow phone.
      canvas.drawLine(
        c + dir * (r - stroke / 2 - 3),
        c + dir * (r + stroke / 2 + 3),
        Paint()
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = hue,
      );
    }
  }

  @override
  bool shouldRepaint(_SweepPainter old) =>
      old.fraction != fraction ||
      old.reached != reached ||
      old.pullFraction != pullFraction ||
      old.hue != hue ||
      old.cut != cut;
}

class _BandPainter extends CustomPainter {
  _BandPainter({
    required this.hue,
    required this.temp,
    required this.min,
    required this.max,
    required this.track,
    required this.warning,
    required this.critical,
    required this.glow,
  });

  final Color hue;
  final int? temp;
  final int min;
  final int max;
  final Color track;
  final Color warning;
  final Color critical;
  final BoxShadow? glow;

  // The band spans ±(max-min) around itself on the dial, so the band occupies
  // the middle third of the arc and there is room to read "below" and "above".
  static const double _span = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(6);
    final width = max - min;
    final lo = min - width;
    final hi = max + width;
    final range = (hi - lo).clamp(1, 1 << 30);

    double frac(int v) => ((v - lo) / range).clamp(0.0, 1.0);

    canvas.drawArc(
      rect,
      _start,
      _sweepArc,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = track,
    );

    final inBand = temp != null && temp! >= min && temp! <= max;
    canvas.drawArc(
      rect,
      _start + _sweepArc * frac(min),
      _sweepArc * (frac(max) - frac(min)),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = (inBand ? hue : warning).withValues(alpha: 0.85),
    );

    final v = temp;
    if (v != null) {
      final angle = _start + _sweepArc * frac(v);
      final c = rect.center;
      final r = rect.width / 2;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final dot = c + dir * r;
      final dotColor = inBand ? hue : critical;
      if (glow != null) {
        canvas.drawCircle(
          dot,
          7,
          Paint()
            ..color = dotColor.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawCircle(dot, 5, Paint()..color = dotColor);
    }
    // suppress unused-field lints on _span in case of future dial retuning
    assert(_span > 0);
  }

  @override
  bool shouldRepaint(_BandPainter old) =>
      old.temp != temp || old.min != min || old.max != max || old.hue != hue;
}
