/// A23.2 — PasskeyDisplay (design 14 §14.7, screen spec 13 §13.2.1).
///
/// A vector reproduction of the bridge's OLED pairing overlay: six placeholder
/// glyphs grouped `••• •••` in `SmokeType.monoKey`, on the `well` surface, ringed
/// by `glow(pit)`. It is the prototype's `.pin-display` (`index.html:238-242`)
/// used *correctly*.
///
/// **The point is what it does NOT show.** §13.2.1: the illustration exists
/// *"not to display a code we know, but to show the user what to look for."* The
/// six-digit passkey is generated on the bridge, shown only on its OLED, and the
/// phone never learns it — so this widget must be **incapable** of rendering a
/// real code. It takes no `code` parameter; misuse is a compile error, not a
/// review note. What it draws are placeholder bullets, never digits.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

class PasskeyDisplay extends StatelessWidget {
  /// Deliberately parameterless. There is no `code` argument, by design — a
  /// passkey the phone should never possess cannot be handed to a widget that
  /// has nowhere to receive it.
  const PasskeyDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Three placeholder bullets, twice — the `418 302` grouping, with no digit
    // anywhere. `monoKey` carries the digit-cell spacing; the wider gap between
    // groups is the middle space.
    Widget group() => Text(
      '•••',
      style: SmokeType.monoKey.copyWith(color: StatusPalette.pit),
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SmokeTokens.s5,
        vertical: SmokeTokens.s4,
      ),
      decoration: BoxDecoration(
        color: t.well,
        borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
        border: Border.all(color: StatusPalette.pit.withValues(alpha: 0.35)),
        boxShadow: [?t.glow(StatusPalette.pit)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          group(),
          const SizedBox(width: SmokeTokens.s5),
          group(),
        ],
      ),
    );
  }
}
