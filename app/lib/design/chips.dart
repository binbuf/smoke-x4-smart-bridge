/// N3.15 — `SegmentedChips` and `FilterChips`, both single-select.
///
/// `SegmentedChips` is the prototype's `.seg` pill (°F/°C, saver); `FilterChips`
/// is the `.seg-chips` wrap (ranges, categories). The selected state is an
/// ember **chrome** tint, never a series hue, and never the only signal — the
/// label is always present.
library;

import 'package:flutter/material.dart';

import 'icons.dart';
import 'text.dart';
import 'tokens.dart';

/// One option in a segmented row.
@immutable
class SmokeSegment<T> {
  const SmokeSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final SmokeGlyph? icon;
}

/// A single-select segmented control.
class SegmentedChips<T> extends StatelessWidget {
  const SegmentedChips({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final List<SmokeSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: tokens.cardSubtle,
          borderRadius: BorderRadius.circular(tokens.radii.pill),
          border: Border.all(color: tokens.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final segment in segments)
              _Segment(
                segment: segment,
                selected: segment.value == value,
                onTap: enabled && onChanged != null
                    ? () => onChanged!(segment.value)
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    super.key,
    required this.segment,
    required this.selected,
    required this.onTap,
  });

  final SmokeSegment<T> segment;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Material(
      color: selected ? tokens.cardRaised : Colors.transparent,
      borderRadius: BorderRadius.circular(tokens.radii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radii.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (segment.icon != null) ...<Widget>[
                SmokeIcon(
                  segment.icon!,
                  size: 14,
                  color: selected ? tokens.textHi : tokens.textMuted,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                segment.label,
                style: SmokeText.label.copyWith(
                  fontSize: 11.5,
                  color: selected ? tokens.textHi : tokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single-select row of chips.
class FilterChips<T> extends StatelessWidget {
  const FilterChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final List<SmokeSegment<T>> options;
  final T value;
  final ValueChanged<T>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final option in options)
            _Chip(
              option: option,
              selected: option.value == value,
              onTap: enabled && onChanged != null
                  ? () => onChanged!(option.value)
                  : null,
            ),
        ],
      ),
    );
  }
}

class _Chip<T> extends StatelessWidget {
  const _Chip({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SmokeSegment<T> option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Material(
      color: selected ? tokens.tint(tokens.pit, 0.15) : tokens.cardSubtle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radii.pill),
        side: BorderSide(
          color: selected ? tokens.tint(tokens.pit, 0.40) : tokens.hairline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radii.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (option.icon != null) ...<Widget>[
                SmokeIcon(
                  option.icon!,
                  size: 14,
                  color: selected ? tokens.textHi : tokens.textBody,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                option.label,
                style: SmokeText.label.copyWith(
                  fontSize: 12.5,
                  color: selected ? tokens.textHi : tokens.textBody,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
