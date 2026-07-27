/// A19.5 — MonoWell and StatRow (design 14 §14.7).
///
/// `MonoWell` is the deepest surface in the app: `well` fill, a `glow(pit)`
/// border, `monoKey` type, tap-to-copy with a haptic. It renders the two
/// strings a user copies off one screen and types into another — the BLE
/// passkey and the AP password — so it gets the widest tracking and the darkest
/// ground, and it is one of only three things allowed to glow.
///
/// `StatRow` is the plain label/value pair used down the device pages.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/design.dart';

class MonoWell extends StatelessWidget {
  const MonoWell({
    super.key,
    required this.value,
    this.label,
    this.copyable = true,
  });

  final String value;
  final String? label;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: copyable
          ? () {
              Clipboard.setData(ClipboardData(text: value));
              HapticFeedback.selectionClick();
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(content: Text('Copied ${label ?? value}')),
              );
            }
          : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: SmokeTokens.s4,
          vertical: SmokeTokens.s3,
        ),
        decoration: BoxDecoration(
          color: t.well,
          borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
          border: Border.all(color: StatusPalette.pit.withValues(alpha: 0.35)),
          boxShadow: [?t.glow(StatusPalette.pit)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  label!.toUpperCase(),
                  style: SmokeType.labelSm.copyWith(color: t.textMuted),
                ),
              ),
            Text(
              value,
              style: SmokeType.monoKey.copyWith(color: t.textHi),
              textAlign: TextAlign.center,
            ),
            if (copyable)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy_rounded, size: 12, color: t.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      'tap to copy',
                      style: SmokeType.labelSm.copyWith(color: t.textMuted),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class StatRow extends StatelessWidget {
  const StatRow({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: SmokeType.body.copyWith(color: t.textMuted)),
          Text(
            value,
            style: (mono ? SmokeType.mono : SmokeType.body).copyWith(
              color: t.textHi,
            ),
          ),
        ],
      ),
    );
  }
}
