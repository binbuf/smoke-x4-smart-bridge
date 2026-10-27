import 'package:flutter/material.dart';

import 'lab_gate.dart';
import '../features/setup/setup_screen.dart';
import '../features/shell/app_shell.dart';
import '../theme/app_theme.dart';
import 'bridge_controller.dart';

/// The production app widget: the approved Material 3 shell, driven by
/// [BridgeController].
class SmokeBridgeApp extends StatefulWidget {
  const SmokeBridgeApp({
    super.key,
    required this.controller,
    this.enableExperimentalLab = experimentalLabEnabled,
  });

  final BridgeController controller;
  final bool enableExperimentalLab;

  @override
  State<SmokeBridgeApp> createState() => _SmokeBridgeAppState();
}

class _SmokeBridgeAppState extends State<SmokeBridgeApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On resume: health check + forward sync, or cut a reconnect wait short.
    // No background scanning or foreground service (06 §6.3).
    if (state == AppLifecycleState.resumed) {
      widget.controller.onAppResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final needsSetup =
            controller.phase == ConnectionPhase.setup ||
            !controller.hasSavedBridge;
        return MaterialApp(
          title: 'Smoke X4 Smart Bridge',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: controller.themeMode,
          home: needsSetup
              ? SetupScreen(controller: controller)
              : AppShell(
                  controller: controller,
                  enableExperimentalLab: widget.enableExperimentalLab,
                ),
        );
      },
    );
  }
}
