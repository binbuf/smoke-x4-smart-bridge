import 'package:flutter/material.dart';

import '../prototype/prototype_controller.dart';

/// Product app bar. The prototype theme switch and lab entry live in the
/// scenario lab, not here.
AppBar prototypeAppBar(
  BuildContext context,
  PrototypeController controller,
  String title, {
  List<Widget> actions = const [],
}) {
  return AppBar(
    title: Text(title),
    actions: [...actions, const SizedBox(width: 8)],
  );
}

class PrototypeThemeToggle extends StatelessWidget {
  const PrototypeThemeToggle({super.key, required this.controller});

  final PrototypeController controller;

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
      selected: {controller.themeMode},
      onSelectionChanged: (selection) =>
          controller.setThemeMode(selection.first),
    );
  }
}
