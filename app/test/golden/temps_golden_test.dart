/// N6 — the Temps destination at 390×844.
///
/// The golden describes the real chrome at `/temps`: status bar, the Temps app
/// bar (title + sub), the header row, the four probe cards and the detached
/// section. Times and the snapshot are pinned so the description is
/// deterministic.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/data/repository/mock_bridge_repository.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/features/shell/shell.dart';
import 'package:smoke_bridge/features/temps/temps.dart';

import 'golden.dart';

/// A fixed instant: the status clock and the scenario times agree.
final DateTime _fixedNow = DateTime(2026, 9, 21, 9, 41);

void main() {
  testWidgets('the Temps destination at 390x844 matches its committed golden', (
    tester,
  ) async {
    await pumpForGolden(
      tester,
      ProviderScope(
        overrides: [
          shellPulseEnabledProvider.overrideWithValue(false),
          shellClockProvider.overrideWithValue(_fixedNow),
          bridgeRepositoryProvider.overrideWith((ref) {
            final repo = MockBridgeRepository(
              nowMs: _fixedNow.millisecondsSinceEpoch,
            );
            ref.onDispose(repo.dispose);
            return repo;
          }),
        ],
        child: MaterialApp(
          theme: SmokeThemeData.dark(),
          home: const Scaffold(
            body: AppShell(location: '/temps', child: TempsPage()),
          ),
        ),
      ),
      // Written out even though it is `pumpForGolden`'s default: the phone
      // frame is the point of this golden.
      // ignore: avoid_redundant_argument_values
      surface: const Size(390, 844),
    );

    expectGolden(tester, 'temps');
  });
}
