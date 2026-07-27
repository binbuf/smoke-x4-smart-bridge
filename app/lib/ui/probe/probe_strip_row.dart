/// A19.6 — ProbeStripRow (design 14 §14.7.1).
///
/// The instrument-mode row: a probe as a 72 dp strip — swatch, name, sparkline,
/// big number, rate, chevron. This is the readout organ when there is no cook
/// plan: four equal rows in jack order, so the user is reading the instrument,
/// not a guided target.
///
/// **A detached row renders in place at 45% opacity**, showing `—` and the word
/// *unplugged* — the user needs to see that jack 3 is empty, not have it vanish.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../features/dashboard/dashboard_snapshot.dart';
import 'animated_temp.dart';
import 'probe_pills.dart';
import 'sparkline.dart';

class ProbeStripRow extends StatelessWidget {
  const ProbeStripRow({
    super.key,
    required this.view,
    this.celsius = false,
    this.onTap,
  });

  final ProbeView view;
  final bool celsius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hue = ProbePalette.hue(view.probe);
    final attached = view.attached;

    return Opacity(
      opacity: attached ? 1.0 : 0.45,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SmokeTokens.s2),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: hue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: SmokeTokens.s3),
                // A25: the reading now carries a tenth, which is widest in °C
                // on a 360 dp phone. The name column yields (it already
                // ellipsizes) rather than the row overflowing — the
                // temperature is the one thing here that must never be
                // clipped or scaled.
                Flexible(
                  child: SizedBox(
                    width: 104,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          view.name.toUpperCase(),
                          style: SmokeType.label.copyWith(color: t.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (attached)
                          TrendChip(rateFPerHr: view.rateFPerHr)
                        else
                          Text(
                            'unplugged',
                            style: SmokeType.labelSm.copyWith(
                              color: t.chromeDim,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: attached && view.recent.length >= 2
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SmokeTokens.s3,
                            vertical: SmokeTokens.s4,
                          ),
                          child: Sparkline(
                            points: view.recent
                                .map((p) => (t: p.t, f: p.f))
                                .toList(growable: false),
                            color: hue,
                          ),
                        )
                      : const SizedBox(),
                ),
                AnimatedTemp(
                  tempF10: view.tempF10,
                  celsius: celsius,
                  style: SmokeType.bigTemp.copyWith(color: t.textHi),
                  unitStyle: SmokeType.body,
                  color: t.textHi,
                  semanticName: view.name,
                ),
                const SizedBox(width: SmokeTokens.s1),
                Icon(Icons.chevron_right_rounded, color: t.chromeDim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
