/// N0.7 — the root widget. The real shell arrives in N4; for now this is a
/// themed, single-route app that proves the package set and theming compile.
library;

import 'package:flutter/material.dart';

import '../design/theme.dart';
import 'router.dart';

class SmokeApp extends StatelessWidget {
  const SmokeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Smoke Bridge',
      debugShowCheckedModeBanner: false,
      theme: SmokeTheme.dark,
      darkTheme: SmokeTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
    );
  }
}
