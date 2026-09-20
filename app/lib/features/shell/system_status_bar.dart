/// A24.1 — SystemStatusBar (design 13 §13.5.7, newapp §H.2).
///
/// The one strip of chrome that is on screen on **every** tab, in every state,
/// forever. Everything else above the content — the alarm, a failed refresh, a
/// named situation — comes and goes; this does not. So it is the app's bezel,
/// and the §H.2 pass treats it as one:
///
///  * it is the **only** full-bleed element in the chrome stack, and it wears
///    the single hairline seam that separates instrument from content. The
///    banners beneath it float on `bg` as inset slabs. Three edge-to-edge
///    bands stacked read as an accident; a bezel plus notices reads as a
///    decision, and that is the entire difference;
///  * it carries the safe-area inset **for the whole stack**, which also fixes
///    a real bug: a refresh banner mounted above it used to render under the
///    notch;
///  * every readout on it is **absent when unknown, never `0%`** (§13.5.7).
///
/// ## The freshness word
///
/// The chip's [PulseDot] stopping is the staleness signal, and a signal made
/// only of motion is invisible to a screen reader and to anyone glancing at a
/// still frame — §14.10's *"status never rests on hue"* has the same shape.
/// So when the link is up but the readings have gone stale, the bar says the
/// word: **Stale** past 90 s, **No signal** past the frozen boundary. Live and
/// aging say nothing at all, because a healthy screen must read clean.
///
/// Green is transport health and nothing else, so the freshness pill is
/// `warning` and `critical` — never a green "fresh" badge, which would be a
/// second thing on screen claiming to mean connected.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../features/dashboard/dashboard_snapshot.dart';
import '../../ui/ui.dart';

/// Below this the bridge's battery stops being a readout and becomes a
/// warning: at 3 a.m. nobody is looking for a number, they need to be told.
const int _batteryLowPct = 15;

class SystemStatusBar extends StatelessWidget {
  const SystemStatusBar({
    super.key,
    required this.link,
    required this.freshness,
    this.netMode,
    this.socPct,
    this.charging = false,
    this.batteryKnown = false,
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

  /// The word the stopped dot cannot say. Null while the stream is healthy —
  /// and null when the link is already down, because "Offline · Stale" is two
  /// chips saying one thing.
  (String, StatusRole)? get _staleness {
    if (link == LinkKind.offline) {
      return null;
    }
    return switch (freshness) {
      ProbeFreshness.live || ProbeFreshness.aging => null,
      ProbeFreshness.stale => ('Stale', StatusRole.warning),
      ProbeFreshness.frozen => ('No signal', StatusRole.critical),
      ProbeFreshness.unknown => ('No readings yet', StatusRole.warning),
    };
  }

  /// The bar is **not** one merged semantics node, deliberately. Merging it
  /// would read the whole state in one breath and, in the same move, bury the
  /// only tappable thing on it — the chip that opens the connection sheet. So
  /// each element carries its own label and TalkBack sweeps them in reading
  /// order: how we reach the bridge (and it is a button), whether readings are
  /// arriving, then the battery.
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final stale = _staleness;

    return Material(
      color: t.surface,
      child: DecoratedBox(
        // The seam. One hairline in the whole chrome stack, and it is here,
        // because this is the edge of the instrument.
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.hairlineStrong)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            // s1 vertical, because the chip already carries a 48 dp tap
            // target: the bar lands at ~56 dp, Material's own app-bar height,
            // so the bezel reads as one deliberate bar rather than as a strip
            // somebody padded by eye.
            padding: const EdgeInsets.fromLTRB(
              SmokeTokens.s3,
              SmokeTokens.s1,
              SmokeTokens.s3,
              SmokeTokens.s1,
            ),
            child: Row(
              children: [
                Flexible(
                  child: TransportChip(
                    state: _state,
                    label: _label,
                    live: _live,
                    // "Connected" is not what the dot means: a link can be up
                    // while the stream has died, which is the exact failure
                    // this app exists to catch.
                    liveLabel: 'receiving readings',
                    idleLabel: link == LinkKind.offline
                        ? 'not connected'
                        : 'no readings arriving',
                    onTap: onTap,
                  ),
                ),
                // A cross-fade rather than a pop: the readings going stale is
                // the single most important thing this bar ever says, and a
                // chip that simply materialises reads as a rendering glitch.
                // `quick` is zero under reduced motion, and an
                // `AnimatedSwitcher` at zero is an instant swap, which is the
                // correct behaviour rather than a crash.
                AnimatedSwitcher(
                  duration: SmokeMotion.of(context).quick,
                  child: stale == null
                      ? const SizedBox(key: ValueKey(false))
                      : Padding(
                          key: ValueKey(stale.$1),
                          padding: const EdgeInsets.only(left: SmokeTokens.s2),
                          child: _StatusPill(
                            role: stale.$2,
                            icon: Icons.history_toggle_off_rounded,
                            label: stale.$1,
                          ),
                        ),
                ),
                const Spacer(),
                if (batteryKnown && socPct != null) _battery(t, socPct!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _battery(SmokeTokens t, int pct) {
    final icon = charging
        ? Icons.battery_charging_full_rounded
        : Icons.battery_full_rounded;
    // A low battery is chrome that has to be noticed, so it takes the status
    // treatment the rule prescribes: fill, border, icon **and** a value. A
    // healthy battery is a readout and stays a readout.
    if (!charging && pct <= _batteryLowPct) {
      return _StatusPill(
        role: StatusRole.warning,
        icon: Icons.battery_alert_rounded,
        label: '$pct%',
        semantics: 'Bridge battery low, $pct percent',
      );
    }
    return Semantics(
      label: 'Bridge battery $pct percent${charging ? ', charging' : ''}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: t.textMuted),
          const SizedBox(width: SmokeTokens.s1),
          Text('$pct%', style: SmokeType.label.copyWith(color: t.textMuted)),
        ],
      ),
    );
  }
}

/// A status hue drawn the only way it is allowed to be: 12–16 % fill, 22–35 %
/// border, an icon **and** a word, text at `textHi` (§14.6.1, §14.6.5). Same
/// pill geometry as [TransportChip], so the bar reads as one row of chips
/// rather than as a chip plus some decoration.
class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.role,
    required this.icon,
    required this.label,
    this.semantics,
  });

  final StatusRole role;
  final IconData icon;
  final String label;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hue = StatusPalette.hue(role);
    return Semantics(
      label: semantics ?? label,
      excludeSemantics: true,
      child: Container(
        // Same lozenge as the transport chip — one pill geometry on the bar,
        // so it reads as a row of chips and not as a chip plus decoration.
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: StatusPalette.fill(role),
          borderRadius: BorderRadius.circular(SmokeTokens.radiusPill),
          border: Border.all(color: StatusPalette.border(role)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: hue),
            const SizedBox(width: SmokeTokens.s1),
            Text(
              label,
              style: SmokeType.label.copyWith(
                color: t.textHi,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
