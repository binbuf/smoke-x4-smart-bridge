/// The secondary probes in guided mode (design 16 §16.5).
///
/// Two per row, half a hero card's weight: a `midTemp` readout with a 4 dp
/// progress rule bled into the footer instead of a full gauge.
///
/// Two rules it was breaking and now keeps:
///
///  * **The name is ink, not the series hue.** A hue is a mark and never a
///    word; the 8 dp dot is the mark.
///  * **Derived values are removed when stale, not greyed.** The rate and the
///    progress rule are both derived, and both used to keep drawing at four
///    hours old under nothing but an opacity change. The rule is now absent
///    below `aging`, and the subtitle falls back to the target — a *setting*,
///    which does not go stale — or to nothing at all.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../features/dashboard/dashboard_snapshot.dart';
import '../surface/smoke_card.dart';
import 'food_avatar.dart';
import 'jack_badge.dart';
import 'probe_freshness.dart';
import 'temp_readout.dart';
import '../state/stale_veil.dart';

class ProbeCompactCard extends StatelessWidget {
  const ProbeCompactCard({
    super.key,
    required this.view,
    required this.freshness,
    this.glyph,
    this.vivid = false,
    this.celsius = false,
    this.onTap,
  });

  final ProbeView view;
  final ProbeFreshness freshness;

  /// What is on this jack (17 §17.3 A). Null resolves it from the role and the
  /// name. Never a function of state.
  final FoodGlyph? glyph;

  /// §17.5's rich register — a property of the screen, not of this probe.
  final bool vivid;

  final bool celsius;
  final VoidCallback? onTap;

  FoodGlyph get _glyph =>
      glyph ?? FoodGlyph.forProbe(role: view.role, name: view.name);

  /// Progress from the pit floor to this probe's target, or null when there is
  /// no target to be a fraction of.
  double? get _progress {
    final temp = view.tempF10;
    final target = view.targetF10;
    if (temp == null || target == null || target <= 320) {
      return null;
    }
    return ((temp - 320) / (target - 320)).clamp(0.0, 1.0);
  }

  /// `Target 203.0° · +12°/hr`, thinned down as freshness drops. A target is a
  /// setting and survives staleness; a rate is derived and does not.
  String? get _subtitle {
    final target = view.targetF10 == null
        ? null
        : 'Target ${formatSetpoint(view.targetF10, celsius: celsius)}';
    final rate = freshness.showsDerived && view.rateFPerHr != null
        ? formatRate(view.rateFPerHr)
        : null;
    if (target != null && rate != null) {
      return '$target · $rate';
    }
    return target ?? rate;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hue = ProbePalette.hue(view.probe);
    final progress = freshness.showsDerived ? _progress : null;
    final subtitle = _subtitle;

    return Opacity(
      // A detached probe stays at 45% even inside a veil — that dim says
      // "unplugged", not "stale", and the two are different facts. The
      // freshness dim, though, is the veil's to apply; doing it here as well
      // multiplies the two.
      opacity: view.attached
          ? (veilAlreadyDims(context) ? 1.0 : freshness.ink)
          : 0.45,
      child: SmokeCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(
          SmokeTokens.s3,
          SmokeTokens.s3,
          SmokeTokens.s3,
          SmokeTokens.s3,
        ),
        footer: progress == null ? null : _progressRule(context, hue, progress),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // The same two identity marks the strip row and the hero lead
                // with, one step smaller (17 §17.3). Three sizes of one mark is
                // a hierarchy; three different marks would be a mess.
                JackBadge(jack: view.probe, size: 20),
                const SizedBox(width: SmokeTokens.s1),
                FoodAvatar(
                  glyph: _glyph,
                  size: 20,
                  vivid: vivid,
                  announce: false,
                ),
                const SizedBox(width: SmokeTokens.s2),
                Expanded(
                  child: Text(
                    view.name.toUpperCase(),
                    style: SmokeType.label.copyWith(color: t.textHi),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SmokeTokens.s2),
            TempReadout(
              tempF10: view.tempF10,
              celsius: celsius,
              style: SmokeType.midTemp,
              unitStyle: SmokeType.bodySm,
              hue: hue,
              semanticName: view.name,
              underline: false,
            ),
            const SizedBox(height: SmokeTokens.s1),
            Text(
              view.attached ? (subtitle ?? '') : 'unplugged',
              style: SmokeType.labelSm.copyWith(
                color: view.attached ? t.textMuted : t.chromeDim,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// A 4 dp rule bled to the card's bottom corners — a mark, at the one width
  /// a series hue is allowed to fill.
  Widget _progressRule(BuildContext context, Color hue, double frac) => Padding(
    padding: const EdgeInsets.only(top: SmokeTokens.s2),
    child: LayoutBuilder(
      builder: (context, c) => Stack(
        children: [
          Container(height: 4, color: context.tokens.hairlineStrong),
          Container(height: 4, width: c.maxWidth * frac, color: hue),
        ],
      ),
    ),
  );
}
