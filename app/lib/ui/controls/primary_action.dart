/// A19.5 — PrimaryAction (design 14 §14.7, rail R1).
///
/// The only ember-filled button in the app, and **there is at most one per
/// screen.** That is rail R1 (13 §13.2): a screen with two filled buttons is a
/// screen that has failed to decide what the user should do next. A widget test
/// asserts the count; this widget is how it stays countable.
///
/// [busy] shows an inline spinner and disables the tap — the app-wide answer to
/// the double-tap class of bug, at the button level.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;

  /// Null disables the button. [busy] also disables it, but keeps the label.
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: StatusPalette.pit,
          foregroundColor: StatusPalette.onPit,
          disabledBackgroundColor: StatusPalette.pit.withValues(alpha: 0.4),
          minimumSize: const Size(64, 52),
          textStyle: SmokeType.title,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: StatusPalette.onPit,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 20),
            if (busy || icon != null) const SizedBox(width: SmokeTokens.s2),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
