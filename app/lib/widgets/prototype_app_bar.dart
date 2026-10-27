import 'package:flutter/material.dart';

import '../app/bridge_controller.dart';

/// Product app bar. The prototype theme switch and lab entry live in the
/// scenario lab, not here.
AppBar prototypeAppBar(
  BuildContext context,
  BridgeController controller,
  String title, {
  List<Widget> actions = const [],
  bool highlightedTitle = true,
}) {
  final scheme = Theme.of(context).colorScheme;
  final text = Text(
    title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.2),
  );
  return AppBar(
    centerTitle: true,
    titleSpacing: 0,
    title: highlightedTitle
        ? Card(
            elevation: 0,
            margin: const EdgeInsets.symmetric(vertical: 8),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: text,
            ),
          )
        : text,
    actions: [...actions, const SizedBox(width: 8)],
  );
}

class PrototypeThemeToggle extends StatelessWidget {
  const PrototypeThemeToggle({super.key, required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ThemeMode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: ThemeMode.system,
          icon: Icon(Icons.brightness_auto_outlined, size: 18),
          label: Text('System'),
        ),
        ButtonSegment(
          value: ThemeMode.light,
          icon: Icon(Icons.light_mode_outlined, size: 18),
          label: Text('Light'),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          icon: Icon(Icons.dark_mode_outlined, size: 18),
          label: Text('Dark'),
        ),
      ],
      selected: {controller.themeMode}, // lab-only control; not product chrome
      onSelectionChanged: (selection) =>
          controller.setThemeMode(selection.first),
    );
  }
}
