/// N3.16 — `SmokeToggle`.
///
/// The prototype's `.toggle`: 42×25, ember when on. Built on Material's
/// `Switch` so it keeps platform semantics and keyboard/focus behaviour. A
/// disabled toggle states its reason (I5).
library;

import 'package:flutter/material.dart';

import 'text.dart';
import 'tokens.dart';

class SmokeToggle extends StatelessWidget {
  const SmokeToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.disabledReason,
  });

  final bool value;

  /// Null disables the toggle.
  final ValueChanged<bool>? onChanged;

  /// Why the toggle is disabled (I5).
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final enabled = onChanged != null;
    final control = Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: tokens.pit,
      activeTrackColor: tokens.tint(tokens.pit, 0.30),
      inactiveThumbColor: tokens.textMuted,
      inactiveTrackColor: tokens.cardRaised,
      trackOutlineColor: WidgetStatePropertyAll<Color>(tokens.hairlineStrong),
    );
    if (enabled || disabledReason == null) {
      return control;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        control,
        Text(
          disabledReason!,
          style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }
}
