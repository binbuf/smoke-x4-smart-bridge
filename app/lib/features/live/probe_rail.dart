/// N5.8/N5.11 — the compact probe rail.
///
/// Four tiles, jack badge, catalog name when a cook item is assigned, the temp
/// split, a sub line and DONE/STALL flags with a progress rule. **A detached
/// probe renders `—` + "Unplugged", never `0°` (I3)**, and derived values are
/// removed rather than greyed when the reading is not current (I4). Tapping a
/// tile opens the probe sheet (N6).
library;

import 'package:flutter/material.dart';

import '../../data/content/catalog.dart';
import '../../data/model/cook_state.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import 'live_format.dart';

class LiveProbeRail extends StatelessWidget {
  const LiveProbeRail({
    super.key,
    required this.probes,
    required this.cook,
    required this.catalog,
    required this.unit,
    this.onOpenProbe,
  });

  final List<ProbeState> probes;
  final CookState cook;
  final CatalogTable catalog;
  final TempUnit unit;
  final ValueChanged<ProbeState>? onOpenProbe;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey<String>('live-probe-rail'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final probe in probes)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SizedBox(
                width: 116,
                child: CompactProbeTile(
                  probe: probe,
                  cook: cook,
                  catalog: catalog,
                  unit: unit,
                  onTap: onOpenProbe == null ? null : () => onOpenProbe!(probe),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One compact probe tile.
class CompactProbeTile extends StatelessWidget {
  const CompactProbeTile({
    super.key,
    required this.probe,
    required this.cook,
    required this.catalog,
    required this.unit,
    this.onTap,
  });

  final ProbeState probe;
  final CookState cook;
  final CatalogTable catalog;
  final TempUnit unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final isGrate = probe.role == ProbeRole.pit;
    final live = isLiveProbe(probe);
    final parts = tempParts(live ? probe.tempF10 : null, unit);
    final target = isGrate
        ? (cook.grateTargetF10 ?? probe.targetF10)
        : probe.targetF10;
    final canShow = probe.freshness.showsDerived;
    final temp = probe.tempF10;
    final showBar = live && target != null && temp != null;
    final progress = showBar ? (temp / target).clamp(0.0, 1.0) : 0.0;
    final done = live && target != null && temp != null && temp >= target;
    final stalled = probe.stalled && canShow;

    return SmokeCard(
      key: ValueKey<String>('live-probe-${probe.jack.n}'),
      accent: tokens.series(probe.jack.n),
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 16,
            child: Row(
              children: <Widget>[
                if (stalled) const _Flag(label: 'STALL', warn: true),
                if (stalled && done) const SizedBox(width: 4),
                if (done) const _Flag(label: 'DONE'),
                if (isGrate) ...<Widget>[
                  if (stalled || done) const SizedBox(width: 4),
                  const _Flag(label: 'GRATE'),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              JackBadge(jack: probe.jack.n, detached: !live),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  probeName(probe, cook, catalog),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SmokeText.labelSm.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: tokens.textHi,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              text: parts.num,
              children: <InlineSpan>[
                if (parts.dec.isNotEmpty)
                  TextSpan(
                    text: parts.dec,
                    style: const TextStyle(fontSize: 13),
                  ),
                if (parts.unit.isNotEmpty)
                  TextSpan(
                    text: parts.unit,
                    style: TextStyle(fontSize: 11, color: tokens.textMuted),
                  ),
              ],
            ),
            key: ValueKey<String>('live-probe-temp-${probe.jack.n}'),
            maxLines: 1,
            style: SmokeText.tempMd.copyWith(color: tokens.textHi),
          ),
          const SizedBox(height: 3),
          Text(
            _sub(isGrate, live, canShow, target),
            key: ValueKey<String>('live-probe-sub-${probe.jack.n}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SmokeText.labelSm.copyWith(
              fontSize: 10.5,
              color: tokens.textMuted,
            ),
          ),
          if (showBar) ...<Widget>[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(tokens.radii.pill),
              child: Container(
                height: 3,
                color: tokens.well,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: ColoredBox(color: tokens.series(probe.jack.n)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _sub(bool isGrate, bool live, bool canShow, int? target) {
    if (!probe.attached) {
      return 'Unplugged';
    }
    if (probe.role == ProbeRole.unused) {
      return 'Unused';
    }
    if (isGrate) {
      final min = cook.pitBandMinF10;
      final max = cook.pitBandMaxF10;
      if (min == null || max == null) {
        return 'No pit band';
      }
      return 'Pit band ${fmtTemp0(min, unit)}–${fmtTemp0(max, unit)}°';
    }
    final eta = fmtEta(canShow ? probe.etaMin : null);
    if (eta != null) {
      return '$eta to pull';
    }
    if (target != null) {
      return 'Target ${fmtTemp0(target, unit)}°';
    }
    return 'No target';
  }
}

class _Flag extends StatelessWidget {
  const _Flag({required this.label, this.warn = false});

  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final hue = warn ? tokens.warning : tokens.textHi;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: warn ? tokens.tint(tokens.warning, 0.14) : tokens.cardRaised,
        borderRadius: BorderRadius.circular(tokens.radii.chip),
        border: Border.all(
          color: warn ? tokens.tint(tokens.warning, 0.35) : tokens.hairline,
        ),
      ),
      child: Text(
        label,
        style: SmokeText.labelSm.copyWith(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: hue,
        ),
      ),
    );
  }
}
