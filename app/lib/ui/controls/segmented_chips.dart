/// A19.5 — SegmentedChips (design 14 §14.7).
///
/// A single-select chip row on an inset track: chart windows, °F/°C, battery
/// saver, display timeout. It replaces the blind two-state toggles the old
/// settings screen used, where a switch could not say what its two positions
/// meant.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

class ChipOption<T> {
  const ChipOption(this.value, this.label);
  final T value;
  final String label;
}

class SegmentedChips<T> extends StatelessWidget {
  const SegmentedChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<ChipOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.cardSubtle,
        borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
        border: Border.all(color: t.hairline),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(o.value),
                child: AnimatedContainer(
                  duration: SmokeMotion.of(context).quick,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: o.value == value ? t.cardRaised : Colors.transparent,
                    borderRadius: BorderRadius.circular(SmokeTokens.radiusChip),
                  ),
                  child: Text(
                    o.label,
                    style: SmokeType.bodySm.copyWith(
                      color: o.value == value ? t.textHi : t.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
