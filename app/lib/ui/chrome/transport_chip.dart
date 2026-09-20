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
    this.onTap,
    this.liveLabel = 'connected',
    this.idleLabel = 'not connected',
  });

  final TransportState state;
  final String label;
  final bool live;

  // There is deliberately no `attempt` here any more.
  //
  // This chip used to render "Offline · retry 6" — the literal string 16 §16.3
  // opens by naming as the bug the whole reconciliation layer exists to kill.
  // A retry counter is a status code (§16.4 rule 4), it is the loudest chrome
  // in the app, and it tells a tired person nothing they can act on: the
  // number goes up whether the bridge is off, out of range, hosting its own
  // network, or was reflashed this morning.
  //
  // The chip states the link. The *cause* belongs to the situation banner,
  // which names it and says what is being done about it, and the lane-by-lane
  // detail belongs to Diagnostics (§F's "health chip + a Diagnostics page").

  final VoidCallback? onTap;

  /// What [live] *means* here, spoken. The default pair is about the link; the
  /// shell overrides it with "receiving readings" / "no readings arriving",
  /// because the dot tracks the stream, not the socket, and a link that is up
  /// while the stream is dead is the exact failure this app exists to catch.
  /// Screen readers get the distinction the animation was carrying alone.
  final String liveLabel;
  final String idleLabel;

  StatusRole get _role => switch (state) {
    TransportState.none => StatusRole.critical,
    TransportState.ble => StatusRole.info,
    TransportState.wifiAp => StatusRole.pit,
    TransportState.wifiSta => StatusRole.positive,
  };

  Color get _hue => state == TransportState.ble
      ? ProbePalette.hue(4)
      : StatusPalette.hue(_role);

  /// The floor for anything tappable. The chip is one of the two controls
  /// §14.10 names as *laid out* rather than themed, so it must assert its own
  /// target — and it does it by growing the hit box, not the pill: a 48 dp
  /// lozenge in a status bar would be a button pretending to be a readout.
  static const double _tapTarget = 48;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hue = _hue;

    final pill = Container(
      constraints: const BoxConstraints(minHeight: 32),
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
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SmokeType.label.copyWith(
                color: t.textHi,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: onTap != null,
      label: '$label, ${live ? liveLabel : idleLabel}',
      hint: onTap == null ? null : 'Opens connection options',
      excludeSemantics: true,
      child: onTap == null
          ? pill
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(SmokeTokens.radiusPill),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: _tapTarget),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: pill,
                ),
              ),
            ),
    );
  }
}
