/// N3.24 — `MonoWell`.
///
/// The deepest surface (`--well`), mono type, tap-to-copy. It holds a passkey or
/// an AP PSK — a value the user reads off and types elsewhere, never a live
/// reading. Tap-to-copy is the whole interaction; [onCopy] fires after the
/// clipboard write so a caller can show a toast or fire a haptic.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'text.dart';
import 'tokens.dart';

class MonoWell extends StatelessWidget {
  const MonoWell({
    super.key,
    required this.value,
    this.small = false,
    this.onCopy,
  });

  final String value;

  /// The `.sm` variant: 15 pt, left aligned (an SSID or a URL).
  final bool small;

  /// Called after the value is written to the clipboard.
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final style = small
        ? SmokeText.monoSmall.copyWith(
            fontSize: 15,
            letterSpacing: 2,
            color: tokens.textHi,
          )
        : SmokeText.monoKey.copyWith(color: tokens.textHi);

    return Semantics(
      label: 'Copyable value',
      child: Material(
        color: tokens.well,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radii.control),
          side: BorderSide(color: tokens.hairlineStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.radii.control),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: value));
            onCopy?.call();
          },
          child: Container(
            width: double.infinity,
            padding: small
                ? const EdgeInsets.symmetric(horizontal: 13, vertical: 11)
                : const EdgeInsets.all(14),
            alignment: small ? Alignment.centerLeft : Alignment.center,
            child: Text(value, style: style),
          ),
        ),
      ),
    );
  }
}
