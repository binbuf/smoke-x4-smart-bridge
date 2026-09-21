/// N4.4/N4.5 — the app-bar variants.
///
/// `appbarHtml()` in the prototype branches on `state.screen`:
///
/// * `live` — transport chip (left) + alerts bell (right);
/// * `temps`/`timeline`/`graph`/`settings` — title + sub (left) + bell;
/// * `history` — back, title + sub, plus, bell;
/// * `cookDetail` — back, title, bell.
///
/// All four are one widget here so a destination can never drift from the
/// prototype's chrome. The bell is [AlertsBell], shared with N11.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import 'alerts_bell.dart';
import 'shell_screen.dart';
import 'transport_status.dart';

/// A round chrome icon button (`.icon-btn`).
class ShellIconButton extends StatelessWidget {
  const ShellIconButton({
    super.key,
    required this.glyph,
    required this.label,
    this.onTap,
  });

  final SmokeGlyph glyph;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SmokeIcon(glyph, size: 22, color: tokens.textHi),
          ),
        ),
      ),
    );
  }
}

/// The app bar for the current [screen].
class ShellAppBar extends StatelessWidget {
  const ShellAppBar({
    super.key,
    required this.screen,
    required this.unackedAlarms,
    required this.transport,
    this.onAlerts,
    this.onBack,
    this.onStartCook,
    this.onConnection,
  });

  final ShellScreen screen;
  final int unackedAlarms;
  final TransportStatus transport;

  final VoidCallback? onAlerts;
  final VoidCallback? onBack;
  final VoidCallback? onStartCook;
  final VoidCallback? onConnection;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Row(
        children: <Widget>[
          if (screen.hasBack)
            ShellIconButton(
              key: const ValueKey<String>('shell-appbar-back'),
              glyph: SmokeGlyph.chevronLeft,
              label: 'Back',
              onTap: onBack,
            ),
          if (screen == ShellScreen.live)
            TransportChip(
              key: const ValueKey<String>('shell-transport-chip'),
              label: transport.label,
              phase: transport.phase,
              primary: transport.primary,
              btConnected: transport.btConnected,
              wifiConnected: transport.wifiConnected,
              wifiAp: transport.wifiAp,
              onTap: onConnection,
            )
          else
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    screen.title,
                    key: const ValueKey<String>('shell-appbar-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SmokeText.title.copyWith(color: tokens.textHi),
                  ),
                  if (screen.subtitle != null)
                    Text(
                      screen.subtitle!,
                      key: const ValueKey<String>('shell-appbar-sub'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SmokeText.sub.copyWith(color: tokens.textMuted),
                    ),
                ],
              ),
            ),
          const Spacer(),
          if (screen.hasPlus)
            ShellIconButton(
              key: const ValueKey<String>('shell-appbar-plus'),
              glyph: SmokeGlyph.plus,
              label: 'Start a cook',
              onTap: onStartCook,
            ),
          AlertsBell(count: unackedAlarms, onTap: onAlerts),
        ],
      ),
    );
  }
}
