/// A24.1 — SystemStatusBar (design 13 §13.5.7).
///
/// The fixed strip of chrome at the top of every non-Cook tab: a [TransportChip]
/// on the left saying how the bridge is reachable and whether the link is live,
/// and — on the right, each **absent when unknown, never `0%`** — the bridge
/// battery. RSSI and LoRa dBm are not yet on the [DashboardSnapshot], so they are
/// simply omitted rather than faked (§13.5.7's rule).
///
/// This is shell chrome, not a `ui/` primitive: it reads `context.tokens` and
/// composes the `ui/` [TransportChip]. It renders on a `surface` bar so it reads
/// as chrome and not as content.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../features/dashboard/dashboard_snapshot.dart';
import '../../ui/ui.dart';

class SystemStatusBar extends StatelessWidget {
  const SystemStatusBar({
    super.key,
    required this.link,
    required this.freshness,
    this.netMode,
    this.socPct,
    this.charging = false,
    this.batteryKnown = false,
    this.attempt,
    this.onTap,
  });

  final LinkKind link;
  final ProbeFreshness freshness;

  /// `'ap'` (hosting) or `'sta'` (joined) on Wi-Fi; null on BLE/offline. Lets
  /// the chip name *which* Wi-Fi mode rather than a generic "Wi-Fi".
  final String? netMode;

  /// Null / [batteryKnown] false means "this bridge cannot report a battery" —
  /// not "empty". A `0%` here would be a bug report against the hardware.
  final int? socPct;
  final bool charging;
  final bool batteryKnown;

  /// A background reconnect/upgrade attempt count, shown as the chip's subtext
  /// (e.g. "Bluetooth · retry 2" while climbing back onto Wi-Fi). Null when
  /// not retrying, so a healthy link reads clean.
  final int? attempt;

  /// Opens the connection sheet (05 §5.7): current transport, the fallback
  /// story, the preferred-transport choice, and the manual-address shortcut.
  final VoidCallback? onTap;

  TransportState get _state => switch (link) {
    LinkKind.http =>
      netMode == 'ap' ? TransportState.wifiAp : TransportState.wifiSta,
    LinkKind.ble => TransportState.ble,
    LinkKind.offline => TransportState.none,
  };

  String get _label => switch (link) {
    LinkKind.http => netMode == 'ap' ? 'Wi-Fi (hosted)' : 'Wi-Fi',
    LinkKind.ble => 'Bluetooth',
    LinkKind.offline => 'Offline',
  };

  /// The pulse dot animates only while readings are actually arriving; a dead
  /// link or a stale stream stops it (the chip's staleness signal). Mirrors
  /// `cook_view.dart:111`.
  bool get _live =>
      link != LinkKind.offline &&
      (freshness == ProbeFreshness.live || freshness == ProbeFreshness.aging);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SmokeTokens.s4,
            vertical: SmokeTokens.s2,
          ),
          child: Row(
            children: [
              TransportChip(
                state: _state,
                label: _label,
                live: _live,
                attempt: attempt,
                onTap: onTap,
              ),
              const Spacer(),
              if (batteryKnown && socPct != null) _battery(context, t),
            ],
          ),
        ),
      ),
    );
  }

  Widget _battery(BuildContext context, SmokeTokens t) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          charging
              ? Icons.battery_charging_full_rounded
              : Icons.battery_full_rounded,
          size: 16,
          color: t.textMuted,
        ),
        const SizedBox(width: SmokeTokens.s1),
        Text('$socPct%', style: SmokeType.label.copyWith(color: t.textMuted)),
      ],
    );
  }
}
