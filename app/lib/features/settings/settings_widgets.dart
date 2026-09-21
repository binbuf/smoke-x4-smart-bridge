/// N13 — small shared widgets for the firmware, diagnostics and verb sheets.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

/// A label/value fact line (the prototype's `diagRow`). The value is mono so
/// ids and versions line up; a missing value is `—`, never `0` (I3).
class FactRow extends StatelessWidget {
  const FactRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: SmokeText.labelSm.copyWith(
                fontSize: 12.5,
                color: tokens.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: SmokeText.monoSmall.copyWith(
                fontSize: 12,
                color: tokens.textHi,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The flash-usage bar (the prototype's `.tt-progress`). A neutral bar; storage
/// is a measurement, not a status.
class StorageBar extends StatelessWidget {
  const StorageBar({super.key, required this.fraction});

  /// 0..1.
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final value = fraction.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radii.pill),
      child: Container(
        height: 6,
        color: tokens.cardRaised,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value,
          child: ColoredBox(color: tokens.p1),
        ),
      ),
    );
  }
}
