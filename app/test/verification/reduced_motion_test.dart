/// N16.4 — reduced-motion verification.
///
/// Under reduced motion every motion token collapses to zero **except the
/// pulse**: the pulse stopping *is* the staleness signal (research notes §9.4).
/// This file pins the token contract, guards the source against a screen that
/// reaches for a raw token instead of the effective one, and proves the verb
/// sheet's step pace honours the setting.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/features/settings/settings.dart';

import '../support/load_fonts.dart';

/// A raw `SmokeMotion` token read that is not the pulse. The verb sheet used to
/// do this for its step pace; a screen must use the effective duration instead.
final RegExp _rawMotionToken = RegExp(
  r'const\s+SmokeMotion\(\)\.(?!pulse\b)\w+',
);

void main() {
  setUpAll(loadAppFonts);

  test('reduced motion zeroes every token but the pulse', () {
    const m = SmokeMotion(reducedMotion: true);
    for (final token in <Duration>[m.quick, m.standard, m.value, m.gauge]) {
      expect(m.effective(token), Duration.zero);
    }
    expect(m.effective(m.pulse), const Duration(seconds: 2));
  });

  test('no screen reaches for a raw SmokeMotion token', () {
    final hits = <String>[];
    final root = Directory('lib/features');
    for (final file
        in root
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_rawMotionToken.hasMatch(lines[i])) {
          hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      hits,
      isEmpty,
      reason:
          'Use SmokeMotion.of(context) and an *Effective duration so reduced '
          'motion is honoured. Offending lines:\n${hits.join('\n')}',
    );
  });

  testWidgets('the verb sheet runs instantly under reduced motion', (
    tester,
  ) async {
    final repo = MockBridgeRepository(nowMs: 1700000000000);
    final prefs = MockPrefsRepository();
    addTearDown(repo.dispose);
    addTearDown(prefs.dispose);
    await repo.checkForUpdates();

    tester.view
      ..physicalSize = const Size(500, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bridgeRepositoryProvider.overrideWithValue(repo),
          prefsProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          theme: SmokeThemeData.dark(reducedMotion: true),
          home: const Scaffold(
            body: VerbSheetBody(kind: 'ota', onDone: _noop),
          ),
        ),
      ),
    );

    // No `pump(700ms)` per step: the zeroed timers settle on their own.
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
  });
}

void _noop() {}
