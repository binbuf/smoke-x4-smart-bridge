/// The root widget: theme, the connection scope, and the tab shell.
library;

import 'package:flutter/material.dart';

import '../data/local/drift_sample_cache.dart';
import '../design/theme.dart';
import 'bridge_controller.dart';
import 'bridge_scope.dart';
import 'home_shell.dart';

class SmokeBridgeApp extends StatefulWidget {
  const SmokeBridgeApp({super.key, required this.cache});

  final DriftSampleCache cache;

  @override
  State<SmokeBridgeApp> createState() => _SmokeBridgeAppState();
}

class _SmokeBridgeAppState extends State<SmokeBridgeApp> {
  late final BridgeController _controller = BridgeController(widget.cache);

  @override
  void initState() {
    super.initState();
    _controller.bootstrap();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BridgeScope(
      controller: _controller,
      child: MaterialApp(
        title: 'Smoke Bridge',
        debugShowCheckedModeBanner: false,
        theme: buildSmokeTheme(),
        home: const HomeShell(),
      ),
    );
  }
}
