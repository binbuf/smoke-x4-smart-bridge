/// A19.6 — TransportChip (design 14 §14.7).
///
/// The pill in the top-left of every screen that says how the bridge is
/// reachable and whether the link is live. It is the first of the two places
/// (the other is the chart footer) the app admits its transport — everywhere
/// else it just shows data or its absence.
///
/// The [PulseDot] does the liveness work: it animates while [live], goes hollow
/// and the label appends the age when not. **The dot stopping is the staleness
/// signal** — no colour flip needed.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import 'pulse_dot.dart';

enum TransportState { none, ble, wifiAp, wifiSta }

class TransportChip extends StatelessWidget {
  const TransportChip({
    super.key,
    required this.state,
    required this.label,
    required this.live,
    this.attempt,
    this.onTap,
  });

  final TransportState state;
  final String label;
  final bool live;

  /// Reconnect attempt number, shown as the chip's subtext while retrying.
  final int? attempt;
  final VoidCallback? onTap;

  StatusRole get _role => switch (state) {
    TransportState.none => StatusRole.critical,
    TransportState.ble => StatusRole.info,
    TransportState.wifiAp => StatusRole.pit,
    TransportState.wifiSta => StatusRole.positive,
  };

  Color get _hue => state == TransportState.ble
      ? ProbePalette.hue(4)
      : StatusPalette.hue(_role);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hue = _hue;
    return Semantics(
      button: onTap != null,
      label:
          '$label, ${live ? "connected" : "not connected"}'
          '${attempt != null ? ", retry $attempt" : ""}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SmokeTokens.radiusPill),
        child: Container(
          constraints: const BoxConstraints(minHeight: 28),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: hue.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(SmokeTokens.radiusPill),
            border: Border.all(color: hue.withValues(alpha: 0.30)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PulseDot(color: hue, live: live),
              const SizedBox(width: SmokeTokens.s2),
              Text(
                attempt != null ? '$label · retry $attempt' : label,
                style: SmokeType.label.copyWith(
                  color: t.textHi,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
