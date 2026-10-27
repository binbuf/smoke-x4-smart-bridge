import 'package:flutter/material.dart';

import '../features/shell/app_shell.dart';
import '../theme/app_theme.dart';
import 'bridge_controller.dart';

/// The production app widget: the approved Material 3 shell, driven by
/// [BridgeController].
class SmokeBridgeApp extends StatelessWidget {
  const SmokeBridgeApp({super.key, required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'Smoke X4 Smart Bridge',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: controller.themeMode,
          home: AppShell(controller: controller),
        );
      },
    );
  }
}
