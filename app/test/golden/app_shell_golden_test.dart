/// N0.8 / N4 — the app shell at 390×844.
///
/// The golden describes the real chrome: status bar, Live app bar (transport
/// chip + bell), the destination body, the bottom nav and the debug dev-panel
/// button. The clock is pinned so the golden is deterministic.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/router.dart';
import 'package:smoke_bridge/app/smoke_app.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/data/repository/mock_bridge_repository.dart';
import 'package:smoke_bridge/features/live/live_page.dart';
import 'package:smoke_bridge/features/shell/shell.dart';

import 'golden.dart';

/// A fixed instant: the status clock, the scenario times and the stopwatch all
/// agree, so the Live destination's elapsed readouts are deterministic.
final DateTime _fixedNow = DateTime(2026, 9, 21, 9, 41);

void main() {
  testWidgets('the app shell at 390x844 matches its committed golden', (
    tester,
  ) async {
    await pumpForGolden(
      tester,
      ProviderScope(
        overrides: [
          shellPulseEnabledProvider.overrideWithValue(false),
          shellClockProvider.overrideWithValue(_fixedNow),
          liveNowProvider.overrideWithValue(_fixedNow),
          bridgeRepositoryProvider.overrideWith((ref) {
            final repo = MockBridgeRepository(
              nowMs: _fixedNow.millisecondsSinceEpoch,
            );
            ref.onDispose(repo.dispose);
            return repo;
          }),
        ],
        child: SmokeApp(router: createAppRouter()),
      ),
      // Written out even though it is `pumpForGolden`'s default: the phone
      // frame is the point of this golden (N0.8).
      // ignore: avoid_redundant_argument_values
      surface: const Size(390, 844),
    );

    expectGolden(tester, 'app_shell');
  });
}
