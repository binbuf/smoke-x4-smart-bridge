/// The instrument-mode readout row (design 16 §16.5, §16.6; 17 §17.3 B).
///
/// Four of these, in jack order, are the answer to `/live`'s one question —
/// *"what is everything at, and can I trust it?"* — so this row is the densest
/// thing in the app and has the least room to waste.
///
/// ## What §17 changed, and why
///
/// The row was *swatch · name · state word · number · chevron*. §17.1's teardown
/// puts that beside TempPro's per-probe card — a numbered channel badge in the
/// channel's own colour, a meat chip, a large readout, `EST. TIME LEFT`, the
/// target — and beside FireBoard's per-channel High/Avg/Low, and concludes that
/// the gap is richness rather than craft. §17.3 B names the replacement, and
/// this is it:
///
///  * **the 4 dp left rule became a [JackBadge].** The rule was a correct mark
///    and an invisible one: four hairlines down the left edge of a dark list.
///    The badge says the same thing — *which jack* — in a form you can read
///    across a yard, and §17.2 sanctions it explicitly as an extension of the
///    series channel rather than a breach of it;
///  * **every row leads with a [FoodAvatar].** This is the identity channel, and
///    the single biggest reason the app now reads as cooking. The pit wears a
///    flame, an ambient probe a thermometer, a food probe whatever the cook or
///    its own name says it is — and a probe nobody has said anything about wears
///    cutlery, which is the honest picture of "unstated";
///  * **a second line carries the target and the estimate** where one exists.
///    That is `EST. TIME LEFT` from `TemProBBQ-1`, in this app's voice, on the
///    screen where it is actually useful.
///
/// ## The readout stepped down from `bigTemp` to `midTemp`, and it was measured
///
/// §14.7.1 assigned this row `bigTemp` (56 pt) when it held *swatch · name ·
/// number · chevron* and nothing competed with the number. §17.3 B roughly
/// doubled its content, and 56 pt does not survive that: `TempReadout.measure`
/// puts `254.2°F` at **158.6 dp of a 360 dp phone's 304 dp row**, which left
/// 95 dp for the name — rendered and looked at, that is `BRISKET …` beside a
/// number half the screen wide, with the chevron gone and no room for the
/// sparkline at any phone width.
///
/// At `midTemp` (34 pt) the same reading measures 88.6 dp, and the 70 dp that
/// buys is the difference between a row that works and one that truncates the
/// second-most-identifying thing on it. Three things make this safe rather than
/// a quiet erosion of §H.1:
///
///  * **the hero is untouched.** 96 pt on `ProbeHeroCard` is the app's
///    glanceable number and the thing §14.5.1 is written about. This row is the
///    *scan* surface, where four names, four numbers and four estimates have to
///    coexist above the fold on a 360 × 640 phone;
///  * **it is a token, not a fit.** §14.5.1 forbids `FittedBox` because a glyph
///    that changes height between frames reads as the layout breaking. This is
///    one fixed style, the same at every width and every value;
///  * 34 pt tabular is still 2.8× the largest label on the row, and every one
///    of the three reference apps gives the probe's **name** a line the number
///    does not crowd.
///
/// ## What it deliberately did **not** take
///
///  * **no role chip on a phone.** §17.3 B's anatomy names one, and it renders
///    from medium width up; at 360 dp the avatar already says *pit*, *ambient*
///    or *what is cooking*, and a `FOOD` pill beside a picture of a brisket is
///    the clutter the same section warns against.
///
/// ## The rules that did not move
///
/// **The number is `textHi` ink, never a hue** (§H.1 calls this the most
/// important rule in the app, and §17.4 names MEATER's magenta `133°` disc as
/// the one pattern that would break it outright). **Derived values are removed
/// when stale, not greyed** (§16.7) — that is [ProbeFreshness.showsDerived], and
/// it now governs the trend, the sparkline and the estimate on the second line;
/// the *target* survives, because a target is a setting and a setting does not
/// go stale. **A detached row renders in place** at 45 % opacity, showing `—`
/// and the word *unplugged*: the user needs to see that jack 3 is empty, not
/// have it vanish, and never, ever a `0`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/analysis/analysis.dart' show EtaRange, EtaUnavailable;
import '../../domain/entities/entities.dart' show ProbeRole;
import '../../features/dashboard/dashboard_snapshot.dart';
import 'food_avatar.dart';
import 'jack_badge.dart';
import 'probe_freshness.dart';
import 'probe_pills.dart';
import 'sparkline.dart';
import 'temp_readout.dart';

class ProbeStripRow extends StatelessWidget {
  const ProbeStripRow({
    super.key,
    required this.view,
    required this.freshness,
    this.glyph,
    this.vivid = false,
    this.celsius = false,
    this.onTap,
  });

  final ProbeView view;

  /// How old the reading behind this row is. Derived marks — the sparkline, the
  /// rate and the estimate — are **removed** from `stale` down, never dimmed
  /// (§16.7).
  final ProbeFreshness freshness;

  /// What is on this jack (§17.3 A). Null resolves it from the probe's role and
  /// the name the user typed, which is all instrument mode has; a caller with a
  /// cook plan in hand passes the plan's answer, which is better.
  ///
  /// **It is not a function of state**, and nothing here may make it one — see
  /// [FoodAvatar].
  final FoodGlyph? glyph;

  /// §17.5's rich register. A property of the **screen**, not of this probe:
  /// true only on a reader where no jack is claiming a temperature. The caller
  /// owns that judgement because only the caller can see all four rows.
  final bool vivid;

  final bool celsius;
  final VoidCallback? onTap;

  /// The leading identity block: badge · gap · avatar · gap. Fixed, so the four
  /// rows' names, numbers and second lines all align down the list — which is
  /// most of why a dense list stays scannable.
  static const double _badge = 22;
  static const double _avatar = 26;
  static const double _lead = _badge + SmokeTokens.s1 + _avatar + SmokeTokens.s2;

  /// The widest the name column is worth, the narrowest a sparkline is worth
  /// drawing at, the width below which the role chip is clutter, and the
  /// narrowest the name may be squeezed to before the row starts dropping
  /// things to protect it.
  static const double _nameMax = 168;
  static const double _sparkMin = 56;
  static const double _rolePillMin = 150;
  static const double _nameFloor = 80;
  static const double _trendMin = 90;
  static const double _chevron = 24;

  /// The reading the number's column is sized for: three whole digits and a
  /// tenth, which the tabular figures make the widest any real value can be.
  /// The wire clamps to `-40.0 … 572.0` (`protocol/records.yaml`), so `-40.5`,
  /// `254.2` and `572.0` all measure identically and this stands in for all of
  /// them.
  static const int _referenceF10 = 2000;

  FoodGlyph get _glyph =>
      glyph ?? FoodGlyph.forProbe(role: view.role, name: view.name);

  /// `Target 203.0°F · ready in 2h – 2h 30m`, or null.
  ///
  /// Two halves under one guard each, because they age differently. The target
  /// is a **setting** — it is as true at four hours old as it was at zero — so
  /// it prints regardless of freshness. The estimate is **derived** and goes
  /// with the rest of the derived values the moment the reading behind it is no
  /// longer trustworthy (§16.7).
  ///
  /// A refusal prints its own sentence rather than being swallowed. §D.5 is
  /// explicit that a refusal is an answer: a probe whose estimate quietly
  /// vanished mid-cook is the disappearance §16.2 is written against, and
  /// *"No estimate while it is in a stall"* is a fact the reader can act on.
  String? _secondLine() {
    final target = view.targetF10;
    if (target == null || view.role == ProbeRole.pit) {
      return null;
    }
    final parts = <String>[
      'Target ${formatSetpoint(target, celsius: celsius)}',
      if (freshness.showsDerived && view.attached)
        switch (view.eta) {
          final EtaRange eta => 'ready in ${formatEtaSpan(eta)}',
          final EtaUnavailable eta => formatEtaRefusal(eta),
          null => '',
        }
      else
        '',
    ]..removeWhere((s) => s.isEmpty);
    return parts.join(' · ');
  }

  /// The role, or null when the name already says it.
  ///
  /// §16.5's row-subtitle rule — *"explains, never repeats the label"* — read
  /// as applying to a chip as much as to a line of prose. The pit is almost
  /// always called "Pit", and `PIT [PIT]` is the kind of small redundancy that
  /// makes a dense screen look unconsidered rather than informative.
  String? get _roleWord {
    final word = switch (view.role) {
      ProbeRole.pit => 'PIT',
      ProbeRole.food => 'FOOD',
      ProbeRole.ambient => 'AMBIENT',
      ProbeRole.unused => 'NOT USED',
    };
    return view.name.trim().toUpperCase() == word ? null : word;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hue = ProbePalette.hue(view.probe);
    final attached = view.attached;
    final derived = freshness.showsDerived;
    final second = _secondLine();

    return Opacity(
      opacity: attached ? 1.0 : 0.45,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SmokeTokens.s2),
          child: LayoutBuilder(
            builder: (context, c) {
              // **An explicit priority order, spent in width.**
              //
              // The row measures the number first — it is the content, it is
              // 158.6 dp of a 360 dp phone's 304 dp row, and §14.5.1 says it may
              // never give way — then spends what is left in a fixed order:
              // name, chevron, sparkline. Every child ends up with an exact
              // width, so the row cannot overflow at any scale. (A `Flexible`
              // name column beside an intrinsic temperature was the old answer,
              // and on a 360 dp phone it collapsed the name to 3.6 dp.)
              //
              // **The number's column is the same width on all four rows**,
              // measured from a canonical three-glyph reading rather than from
              // this row's own value. Two things fall out of that, and both are
              // why it is worth a second `TextPainter`: the four readouts
              // right-align into a column you can read down (tabular figures
              // are wasted if the boxes around them move), and the chevron
              // decision below comes out the same for every row. Measured per
              // row, a detached jack's narrow `—` bought itself a chevron its
              // attached neighbours could not afford, and one card showed two
              // rows with arrows and two without.
              final tempWidth = math.min(
                math.max(
                  TempReadout.measure(
                    tempF10: _referenceF10,
                    celsius: celsius,
                    style: SmokeType.midTemp,
                    unitStyle: SmokeType.bodySm,
                  ),
                  TempReadout.measure(
                    tempF10: view.tempF10,
                    celsius: celsius,
                    style: SmokeType.midTemp,
                    unitStyle: SmokeType.bodySm,
                  ),
                ),
                c.maxWidth * 0.55,
              );
              final free = math.max(0.0, c.maxWidth - _lead - tempWidth);

              // **The chevron is the first thing dropped**, and this is the
              // §17 change that paid for the avatar. It is pure affordance —
              // the row is an `InkWell` and ripples, and neither MEATER nor
              // TempPro draws one on a probe row — while the name is the second
              // most identifying thing on the line after the number. So below
              // [_nameFloor] the arrow goes and the name keeps the width. From
              // ~600 dp up there is room for both and it comes back.
              final showChevron = free - _chevron - SmokeTokens.s1 >= _nameFloor;
              final rest = showChevron
                  ? free - _chevron - SmokeTokens.s1
                  : free;
              final nameWidth = math.min(rest, _nameMax);
              final sparkWidth = rest - nameWidth;
              final showSpark =
                  attached &&
                  derived &&
                  view.recent.length >= 2 &&
                  sparkWidth >= _sparkMin;
              // The trend rides under the name; the second line is the target
              // and the estimate, and nothing else. Both were briefly on the
              // second line together, and rendered at 360 dp that put a 95 dp
              // chip in front of a 210 dp sentence in a 244 dp space —
              // `Target 203° · ready in 2h – 2…`, a duration ellipsised, which
              // is the one part of an estimate worth having.
              final showTrend =
                  attached &&
                  derived &&
                  view.rateFPerHr != null &&
                  nameWidth >= _trendMin;
              final role = nameWidth >= _rolePillMin ? _roleWord : null;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // §17.2's two sanctioned identity marks, together: which
                      // jack, and what is on it.
                      JackBadge(jack: view.probe, size: _badge),
                      const SizedBox(width: SmokeTokens.s1),
                      FoodAvatar(
                        glyph: _glyph,
                        size: _avatar,
                        vivid: vivid,
                        // The readout below announces the probe by name; a
                        // second identity word here is the same fact twice.
                        announce: false,
                      ),
                      const SizedBox(width: SmokeTokens.s2),
                      SizedBox(
                        width: nameWidth,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    view.name.toUpperCase(),
                                    // The hue is the badge; the word is ink.
                                    style: SmokeType.label.copyWith(
                                      color: t.textHi,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (role != null) ...[
                                  const SizedBox(width: SmokeTokens.s2),
                                  _RolePill(label: role),
                                ],
                              ],
                            ),
                            if (!attached) ...[
                              const SizedBox(height: 3),
                              Text(
                                'unplugged',
                                style: SmokeType.labelSm.copyWith(
                                  color: t.chromeDim,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ] else if (showTrend) ...[
                              const SizedBox(height: 3),
                              TrendChip(rateFPerHr: view.rateFPerHr),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(
                        width: sparkWidth,
                        child: showSpark
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: SmokeTokens.s2,
                                  ),
                                  // A bounded box, so IntrinsicHeight has
                                  // something finite to measure — `Size.infinite`
                                  // on a CustomPaint does not.
                                  child: SizedBox(
                                    height: 26,
                                    child: Sparkline(
                                      points: view.recent
                                          .map((p) => (t: p.t, f: p.f))
                                          .toList(growable: false),
                                      color: hue,
                                    ),
                                  ),
                                ),
                              )
                            : null,
                      ),
                      SizedBox(
                        width: tempWidth,
                        // Right, not centre: the four numbers form a column,
                        // and a `—` centred in its own box breaks it.
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TempReadout(
                            tempF10: view.tempF10,
                            celsius: celsius,
                            style: SmokeType.midTemp,
                            unitStyle: SmokeType.bodySm,
                            hue: hue,
                            semanticName: view.name,
                            // The badge already carries this row's identity; a
                            // second mark under every number would be four
                            // marks per row and no hierarchy at all.
                            underline: false,
                          ),
                        ),
                      ),
                      if (showChevron) ...[
                        const SizedBox(width: SmokeTokens.s1),
                        Center(
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: _chevron,
                            color: t.chromeDim,
                          ),
                        ),
                      ],
                    ],
                  ),
                  // §17.3 B's second line: the target, and what the estimator
                  // will say about it.
                  //
                  // Indented to the name column so the four rows read as a
                  // table rather than as four paragraphs, and full width from
                  // there — `Target 203° · No estimate while it is in a stall.`
                  // needs far more room than the name column has, and both
                  // halves are worth having.
                  if (second != null && attached)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: _lead,
                        top: SmokeTokens.s1,
                      ),
                      child: Text(
                        second,
                        style: SmokeType.bodySm.copyWith(color: t.textMuted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The role, as a pill, from medium width up.
///
/// TempPro's `MEAT ▶` chip exists because that card has no other role signal.
/// Ours does — the avatar — so this is the *secondary* channel rather than the
/// primary one, and it is the first thing dropped when the row runs out of
/// width. It is still worth having: "ambient" and "not used" are structural
/// facts a glyph states less precisely than a word.
class _RolePill extends StatelessWidget {
  const _RolePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
      decoration: BoxDecoration(
        color: t.cardSubtle,
        borderRadius: BorderRadius.circular(SmokeTokens.radiusChip),
        border: Border.all(color: t.hairline),
      ),
      child: Text(
        label,
        style: SmokeType.labelSm.copyWith(color: t.textMuted),
        maxLines: 1,
      ),
    );
  }
}
