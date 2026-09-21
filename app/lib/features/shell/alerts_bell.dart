/// N4.4/N4.5 — the global alerts bell.
///
/// The bell is chrome that persists on every app-bar variant. Its badge is the
/// unacked-alarm count; tapping it opens the `alarms` overlay in the shell.
/// Filling behaviour (the alarms sheet itself) is N11.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

class AlertsBell extends StatelessWidget {
  const AlertsBell({super.key, required this.count, this.onTap});

  /// Unacked alarms. Zero hides the badge.
  final int count;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Semantics(
      button: true,
      label: count > 0 ? 'Alerts, $count unacknowledged' : 'Alerts',
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        child: InkWell(
          key: const ValueKey<String>('shell-alerts-bell'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                SmokeIcon(SmokeGlyph.bell, size: 22, color: tokens.textHi),
                if (count > 0)
                  Positioned(
                    top: -5,
                    right: -7,
                    child: Container(
                      key: const ValueKey<String>('shell-alert-badge'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(minWidth: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tokens.critical,
                        borderRadius: BorderRadius.circular(tokens.radii.pill),
                      ),
                      child: Text(
                        '$count',
                        style: SmokeText.labelSm.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: tokens.textHi,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
