/// A19.6 — ProbeCompactCard (design 14 §14.7.1).
///
/// The secondary food probes in guided mode: a `midTemp` readout with a 4 dp
/// progress rule bled into the footer instead of a full gauge. Half the height
/// of a hero card, two per row.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../features/dashboard/dashboard_snapshot.dart';
import '../surface/smoke_card.dart';
import 'animated_temp.dart';
import 'probe_freshness.dart';

class ProbeCompactCard extends StatelessWidget {
  const ProbeCompactCard({
    super.key,
    required this.view,
    required this.freshness,
    this.celsius = false,
    this.onTap,
  });

  final ProbeView view;
  final ProbeFreshness freshness;
  final bool celsius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hue = ProbePalette.hue(view.probe);
    return Opacity(
      opacity: freshness.ink,
      child: SmokeCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(
          SmokeTokens.s3,
          SmokeTokens.s3,
          SmokeTokens.s3,
          SmokeTokens.s2,
        ),
        footer: _progressRule(hue),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: hue, shape: BoxShape.circle),
                ),
                const SizedBox(width: SmokeTokens.s1),
                Expanded(
                  child: Text(
                    view.name.toUpperCase(),
                    style: SmokeType.label.copyWith(color: hue),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SmokeTokens.s1),
            AnimatedTemp(
              tempF10: view.tempF10,
              celsius: celsius,
              style: SmokeType.midTemp.copyWith(color: t.textHi),
              unitStyle: SmokeType.bodySm,
              color: t.textHi,
              semanticName: view.name,
            ),
            const SizedBox(height: SmokeTokens.s1),
            Text(
              view.targetF10 != null
                  ? 'Target ${formatSetpoint(view.targetF10, celsius: celsius)} · '
                        '${formatRate(view.rateFPerHr)}'
                  : formatRate(view.rateFPerHr),
              style: SmokeType.labelSm.copyWith(color: t.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressRule(Color hue) {
    final temp = view.tempF10;
    final target = view.targetF10;
    double frac = 0;
    if (temp != null && target != null && target > 320) {
      frac = ((temp - 320) / (target - 320)).clamp(0.0, 1.0);
    }
    return Padding(
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
}
