/// N3.27 — `StatGrid`, `StatMini` and `RecapRow`.
///
/// Small numeric tiles for the chart window stats and the cook recap. Values
/// are mono and tabular so a changing digit does not jitter the row. `planned`
/// and `actual` are always both shown in [RecapRow]; the point of a recap is
/// the comparison, so hiding one would defeat it.
library;

import 'package:flutter/material.dart';

import 'text.dart';
import 'tokens.dart';

/// One stat tile.
class StatMini extends StatelessWidget {
  const StatMini({super.key, required this.label, required this.value});

  final String label;
  final String value;

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
              fontSize: 10,
              letterSpacing: 0.5,
              color: tokens.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: SmokeText.monoValue.copyWith(color: tokens.textHi),
          ),
        ],
      ),
    );
  }
}

/// A stat spec for [StatGrid].
@immutable
class SmokeStat {
  const SmokeStat({required this.label, required this.value});

  final String label;
  final String value;
}

/// A grid of [StatMini]s.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.stats, this.columns = 3});

  final List<SmokeStat> stats;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final stat in stats)
          SizedBox(
            width:
                (MediaQuery.sizeOf(context).width -
                    tokens.density.pageGutter * 2 -
                    (columns - 1) * 8) /
                columns,
            child: StatMini(label: stat.label, value: stat.value),
          ),
      ],
    );
  }
}

/// A planned-vs-actual recap row.
class RecapRow extends StatelessWidget {
  const RecapRow({
    super.key,
    required this.label,
    required this.planned,
    required this.actual,
    this.showHeader = false,
    this.plannedLabel = 'Planned',
    this.actualLabel = 'Actual',
  });

  final String label;
  final String planned;
  final String actual;

  /// Renders the column header row above this one.
  final bool showHeader;
  final String plannedLabel;
  final String actualLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: SmokeText.sub.copyWith(color: tokens.textBody),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              planned,
              textAlign: TextAlign.right,
              style: SmokeText.monoSmall.copyWith(color: tokens.textMuted),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 70,
            child: Text(
              actual,
              textAlign: TextAlign.right,
              style: SmokeText.monoSmall.copyWith(color: tokens.textHi),
            ),
          ),
        ],
      ),
    );
    if (!showHeader) {
      return row;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Spacer(),
            SizedBox(
              width: 70,
              child: Text(
                plannedLabel,
                textAlign: TextAlign.right,
                style: SmokeText.labelSm.copyWith(
                  fontSize: 10,
                  letterSpacing: 0.5,
                  color: tokens.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 70,
              child: Text(
                actualLabel,
                textAlign: TextAlign.right,
                style: SmokeText.labelSm.copyWith(
                  fontSize: 10,
                  letterSpacing: 0.5,
                  color: tokens.textMuted,
                ),
              ),
            ),
          ],
        ),
        row,
      ],
    );
  }
}
