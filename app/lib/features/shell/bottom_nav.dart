/// N4.2 — the bottom navigation.
///
/// Five fixed destinations (`.bottom-nav` / renderNav). The active item is
/// ink-highlighted with the ember cap; Live carries the unacked-alarm dot.
/// History and cook detail highlight Settings, exactly as the prototype does.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import 'shell_screen.dart';

/// One nav item's fixed metadata.
class ShellNavItem {
  const ShellNavItem({
    required this.screen,
    required this.label,
    required this.glyph,
  });

  final ShellScreen screen;
  final String label;
  final SmokeGlyph glyph;
}

/// The five destinations, in prototype order.
const List<ShellNavItem> kShellNavItems = <ShellNavItem>[
  ShellNavItem(
    screen: ShellScreen.live,
    label: 'Live',
    glyph: SmokeGlyph.activity,
  ),
  ShellNavItem(
    screen: ShellScreen.temps,
    label: 'Temps',
    glyph: SmokeGlyph.thermometer,
  ),
  ShellNavItem(
    screen: ShellScreen.timeline,
    label: 'Timeline',
    glyph: SmokeGlyph.list,
  ),
  ShellNavItem(
    screen: ShellScreen.graph,
    label: 'Graph',
    glyph: SmokeGlyph.chart,
  ),
  ShellNavItem(
    screen: ShellScreen.settings,
    label: 'Settings',
    glyph: SmokeGlyph.sliders,
  ),
];

/// The five-item bottom navigation bar.
class ShellBottomNav extends StatelessWidget {
  const ShellBottomNav({
    super.key,
    required this.current,
    required this.unackedAlarms,
    required this.onSelect,
  });

  /// The current surface; History/Cook detail highlight Settings.
  final ShellScreen current;

  /// Unacked alarms; when non-zero Live gets the dot.
  final int unackedAlarms;

  final ValueChanged<ShellScreen> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final active = current.navDestination;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: <Widget>[
              for (final item in kShellNavItems)
                Expanded(
                  child: _NavItem(
                    item: item,
                    selected: item.screen == active,
                    showDot:
                        item.screen == ShellScreen.live && unackedAlarms > 0,
                    onTap: () => onSelect(item.screen),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.showDot,
    required this.onTap,
  });

  final ShellNavItem item;
  final bool selected;
  final bool showDot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final color = selected ? tokens.textHi : tokens.textMuted;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        key: ValueKey<String>('shell-nav-${item.screen.name}'),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                SmokeIcon(item.glyph, size: 22, color: color),
                if (showDot)
                  Positioned(
                    top: -2,
                    right: -4,
                    child: Container(
                      key: const ValueKey<String>('shell-nav-live-dot'),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: tokens.critical,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: SmokeText.labelSm.copyWith(
                fontSize: 10.5,
                letterSpacing: 0.1,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
