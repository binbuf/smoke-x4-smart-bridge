import 'package:flutter/material.dart';

import 'features/shell/app_shell.dart';
import 'prototype/prototype_controller.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const PrototypeApp());
}

/// The UI prototype entrypoint. It is intentionally a single app with a single
/// in-memory controller; there is no BLE, database, permission, or network code.
class PrototypeApp extends StatefulWidget {
  const PrototypeApp({super.key});

  @override
  State<PrototypeApp> createState() => _PrototypeAppState();
}

class _PrototypeAppState extends State<PrototypeApp> {
  late final PrototypeController _controller = PrototypeController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'Smoke X4 Smart Bridge',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: _controller.themeMode,
          home: AppShell(controller: _controller),
        );
      },
    );
  }
}
