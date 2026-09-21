/// N5.7 — the "at a glance" summary strip.
///
/// Three tiles: Grate (or "No pit probe"), Hottest food, To target (+ ready
/// count). Absent is an em dash, never a zero (I3). The page passes the unit so
/// storage stays canonical.
library;

import 'package:flutter/material.dart';

import '../../data/content/catalog.dart';
import '../../data/model/cook_state.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import 'live_format.dart';

class LiveSummaryStrip extends StatelessWidget {
  const LiveSummaryStrip({
    super.key,
    required this.probes,
    required this.cook,
    required this.catalog,
    required this.unit,
  });

  final List<ProbeState> probes;
  final CookState cook;
  final CatalogTable catalog;
  final TempUnit unit;

  @override
  Widget build(BuildContext context) {
    final grate = _grate();
    final hottest = _hottest();
    final (done, toTarget) = _targetCounts();

    return Row(
      key: const ValueKey<String>('live-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: _SummaryTile(
            key: const ValueKey<String>('live-summary-grate'),
            label: 'Grate',
            value: grate == null ? '—' : fmtTemp0(grate.tempF10, unit),
            unit: grate == null ? null : unitLabel(unit),
            sub: _grateSub(grate),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryTile(
            key: const ValueKey<String>('live-summary-hottest'),
            label: 'Hottest food',
            value: hottest == null ? '—' : fmtTemp0(hottest.tempF10, unit),
            unit: hottest == null ? null : unitLabel(unit),
            sub: hottest == null
                ? 'None attached'
                : probeName(hottest, cook, catalog),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryTile(
            key: const ValueKey<String>('live-summary-to-target'),
            label: 'To target',
            value: '$toTarget',
            sub: done > 0 ? '$done ready' : 'none ready yet',
          ),
        ),
      ],
    );
  }

  ProbeState? _grate() {
    for (final probe in probes) {
      if (probe.role == ProbeRole.pit) {
        return probe;
      }
    }
    return null;
  }

  ProbeState? _hottest() {
    ProbeState? best;
    for (final probe in probes) {
      if (probe.role != ProbeRole.food || !probe.attached) {
        continue;
      }
      if (best == null || (probe.tempF10 ?? 0) > (best.tempF10 ?? 0)) {
        best = probe;
      }
    }
    return best;
  }

  (int done, int toTarget) _targetCounts() {
    var done = 0;
    var toTarget = 0;
    for (final probe in probes) {
      if (probe.role != ProbeRole.food || !probe.attached) {
        continue;
      }
      final target = probe.targetF10;
      final temp = probe.tempF10;
      if (target == null || temp == null) {
        continue;
      }
      if (temp >= target) {
        done++;
      } else {
        toTarget++;
      }
    }
    return (done, toTarget);
  }

  String _grateSub(ProbeState? grate) {
    if (grate == null || !grate.attached) {
      return 'No pit probe';
    }
    final min = cook.pitBandMinF10;
    final max = cook.pitBandMaxF10;
    if (min == null || max == null) {
      return 'No pit band';
    }
    return 'Pit band ${fmtTemp0(min, unit)}–${fmtTemp0(max, unit)}°';
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    super.key,
    required this.label,
    required this.value,
    required this.sub,
    this.unit,
  });

  final String label;
  final String value;
  final String sub;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: tokens.cardSubtle,
        borderRadius: BorderRadius.circular(tokens.radii.control),
        border: Border.all(color: tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: SmokeText.labelSm.copyWith(
              fontSize: 9.5,
              letterSpacing: 0.6,
              color: tokens.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SmokeText.cardTitle.copyWith(
                    fontSize: 20,
                    color: tokens.textHi,
                  ),
                ),
              ),
              if (unit != null) ...<Widget>[
                const SizedBox(width: 3),
                Text(
                  unit!,
                  style: SmokeText.labelSm.copyWith(
                    fontSize: 10.5,
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 1),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SmokeText.labelSm.copyWith(
              fontSize: 10.5,
              color: tokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
