/// N0.7 — the placeholder route. N4 replaces this with the real shell.
library;

import 'package:flutter/material.dart';

import '../../design/theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Smoke X4',
          key: ValueKey<String>('home-title'),
          style: TextStyle(
            fontFamily: SmokeTheme.displayFont,
            fontSize: 32,
            color: SmokeTheme.textHi,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
