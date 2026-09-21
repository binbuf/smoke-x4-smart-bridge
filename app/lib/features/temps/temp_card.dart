/// N6.2–N6.4 — the big per-probe card.
///
/// Jack badge, name, a large numeral (whole + tenths + unit), a trend chip and
/// the freshness word; the STALL/DONE/Grate flags and a progress rule against
/// the target; then the meta grid.
///
/// Invariants encoded here:
/// * **I3** — an absent reading renders `—`, never `0`.
/// * **I4** — the trend chip is removed (shows the flat `stale` chip) when the
///   reading is not current; the ETA does the same in [tempMetaCells].
/// * **Target reached** closes the progress rule and says `DONE`; it is never a
///   colour.
library;

import 'package:flutter/material.dart';

import '../../data/content/catalog.dart';
import '../../data/model/cook_state.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import '../live/live_format.dart';
import 'temps_format.dart';

/// One attached probe, up close.
class TempCard extends StatelessWidget {
  const TempCard({
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
    final canShow = probe.freshness.showsDerived;
    final parts = tempParts(live ? probe.tempF10 : null, unit);
    final target = isGrate
        ? (cook.grateTargetF10 ?? probe.targetF10)
        : probe.targetF10;
    final temp = probe.tempF10;
    final showProgress = live && target != null;
    final progress = (showProgress && temp != null)
        ? (temp / target).clamp(0.0, 1.0)
        : 0.0;
    final done = live && target != null && temp != null && temp >= target;
    final stalled = probe.stalled && canShow;
    final trend = trendFor(canShow ? probe.trendFPerHr : null);

    return SmokeCard(
      key: ValueKey<String>('temps-card-${probe.jack.n}'),
      accent: live ? tokens.series(probe.jack.n) : null,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              JackBadge(jack: probe.jack.n, detached: !live),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  probeName(probe, cook, catalog),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SmokeText.cardTitle.copyWith(color: tokens.textHi),
                ),
              ),
              if (stalled) const _CardFlag(label: 'STALL', warn: true),
              if (stalled && done) const SizedBox(width: 4),
              if (done) const _CardFlag(label: 'DONE'),
              if (isGrate) ...<Widget>[
                if (stalled || done) const SizedBox(width: 4),
                const _CardFlag(label: 'GRATE'),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: parts.num,
                    children: <InlineSpan>[
                      if (parts.dec.isNotEmpty)
                        TextSpan(
                          text: parts.dec,
                          style: const TextStyle(fontSize: 26),
                        ),
                      if (parts.unit.isNotEmpty)
                        TextSpan(
                          text: parts.unit,
                          style: TextStyle(
                            fontSize: 15,
                            color: tokens.textMuted,
                          ),
                        ),
                    ],
                  ),
                  key: ValueKey<String>('temps-temp-${probe.jack.n}'),
                  maxLines: 1,
                  style: SmokeText.tempXl.copyWith(color: tokens.textHi),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TrendChip(direction: trend.direction, label: trend.label),
                  const SizedBox(height: 4),
                  Text(
                    probeFreshnessWord(probe.freshness),
                    key: ValueKey<String>('temps-fresh-${probe.jack.n}'),
                    style: SmokeText.labelSm.copyWith(
                      fontSize: 10.5,
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (showProgress) ...<Widget>[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(tokens.radii.pill),
              child: Container(
                key: ValueKey<String>('temps-progress-${probe.jack.n}'),
                height: 4,
                color: tokens.well,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: ColoredBox(color: tokens.series(probe.jack.n)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _MetaGrid(
            jack: probe.jack.n,
            cells: tempMetaCells(
              probe: probe,
              cook: cook,
              unit: unit,
              isGrate: isGrate,
            ),
          ),
        ],
      ),
    );
  }
}

/// The STALL/DONE/Grate tag.
class _CardFlag extends StatelessWidget {
  const _CardFlag({required this.label, this.warn = false});

  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final hue = warn ? tokens.warning : tokens.textHi;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

/// A three-column meta grid that chunks any number of cells into rows.
class _MetaGrid extends StatelessWidget {
  const _MetaGrid({required this.jack, required this.cells});

  final int jack;
  final List<TempMetaCell> cells;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 3) {
      final slice = cells.sublist(i, (i + 3).clamp(0, cells.length));
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (var j = 0; j < 3; j++) ...<Widget>[
                if (j > 0) const SizedBox(width: 8),
                Expanded(
                  child: j < slice.length
                      ? _MetaCell(jack: jack, cell: slice[j])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      key: ValueKey<String>('temps-meta-$jack'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }
}

class _MetaCell extends StatelessWidget {
  const _MetaCell({required this.jack, required this.cell});

  final int jack;
  final TempMetaCell cell;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          cell.label.toUpperCase(),
          style: SmokeText.labelSm.copyWith(
            fontSize: 9.5,
            letterSpacing: 0.5,
            color: tokens.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          cell.value,
          key: ValueKey<String>('temps-meta-${_slug(cell.label)}-$jack'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SmokeText.monoValue.copyWith(
            fontSize: 13,
            color: tokens.textHi,
          ),
        ),
      ],
    );
  }
}

String _slug(String label) => label.toLowerCase().replaceAll(' ', '-');
