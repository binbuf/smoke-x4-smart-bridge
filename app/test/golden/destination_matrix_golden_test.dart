/// N16.5 — every destination across the theme × density matrix.
///
/// This is the destination half of the N16.5 golden set: the seven surfaces the
/// shell can show (Live, Temps, Timeline, Graph, Settings, History and Cook
/// detail) each rendered in the three theme combinations and both densities the
/// design system defines. The three combinations are dark, light and the
/// daylight contrast profile, exactly as `design_gallery_golden_test.dart`
/// pins the primitives; the theme values themselves are pinned by
/// `tokens_test.dart`, not by these text descriptions.
///
/// Like every golden in this harness these are **text descriptions**, not
/// bitmaps: the matrix guards that no destination silently changes what it
/// says when the appearance changes (a dropped label, a control that only
/// renders in one density). The clocks and the snapshot are pinned so two runs
/// produce the same bytes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/data/repository/mock_bridge_repository.dart';
import 'package:smoke_bridge/data/repository/prefs_repository.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/features/graph/graph.dart';
import 'package:smoke_bridge/features/history/history.dart';
import 'package:smoke_bridge/features/live/live_page.dart';
import 'package:smoke_bridge/features/settings/settings.dart';
import 'package:smoke_bridge/features/shell/shell.dart';
import 'package:smoke_bridge/features/temps/temps.dart';
import 'package:smoke_bridge/features/timeline/timeline.dart';

import '../support/load_fonts.dart';
import 'golden.dart';

/// A fixed instant: the status clock and every screen clock agree.
final DateTime _fixedNow = DateTime(2026, 9, 21, 9, 41);

/// The cook the History list and Cook detail render (`history-card-c1`).
const String _cookId = 'c1';

typedef _Destination = ({String location, Widget child});

/// The seven surfaces `ShellScreen` models, with their routes.
final Map<String, _Destination> _destinations = <String, _Destination>{
  'live': (location: '/live', child: const LivePage()),
  'temps': (location: '/temps', child: const TempsPage()),
  'timeline': (location: '/timeline', child: const TimelinePage()),
  'graph': (location: '/graph', child: const GraphPage()),
  'settings': (location: '/settings', child: const SettingsPage()),
  'history': (location: '/settings/history', child: const HistoryPage()),
  'cook_detail': (
    location: '/settings/history/$_cookId',
    child: const CookDetailPage(id: _cookId),
  ),
};

final Map<String, (Brightness, SmokeProfile)> _combos =
    <String, (Brightness, SmokeProfile)>{
      'dark': (Brightness.dark, SmokeProfile.standard),
      'light': (Brightness.light, SmokeProfile.standard),
      'daylight': (Brightness.dark, SmokeProfile.daylight),
    };

final Map<String, SmokeDensity> _densities = <String, SmokeDensity>{
  'compact': SmokeDensity.compact,
  'comfortable': SmokeDensity.comfortable,
};

void main() {
  setUpAll(loadAppFonts);

  for (final destination in _destinations.entries) {
    for (final combo in _combos.entries) {
      for (final density in _densities.entries) {
        final name =
            'destination_${destination.key}_${combo.key}_${density.key}';
        testWidgets('$name matches its committed golden', (tester) async {
          final (brightness, profile) = combo.value;
          final prefs = MockPrefsRepository();
          addTearDown(prefs.dispose);
          final target = destination.value;

          await pumpForGolden(
            tester,
            ProviderScope(
              overrides: [
                shellPulseEnabledProvider.overrideWithValue(false),
                shellClockProvider.overrideWithValue(_fixedNow),
                liveNowProvider.overrideWithValue(_fixedNow),
                graphNowProvider.overrideWithValue(_fixedNow),
                timelineNowProvider.overrideWithValue(_fixedNow),
                historyNowProvider.overrideWithValue(_fixedNow),
                prefsProvider.overrideWithValue(prefs),
                bridgeRepositoryProvider.overrideWith((ref) {
                  final repo = MockBridgeRepository(
                    nowMs: _fixedNow.millisecondsSinceEpoch,
                  );
                  ref.onDispose(repo.dispose);
                  return repo;
                }),
              ],
              child: MaterialApp(
                theme: SmokeThemeData.build(
                  brightness: brightness,
                  profile: profile,
                  density: density.value,
                ),
                home: Scaffold(
                  body: AppShell(
                    location: target.location,
                    child: target.child,
                  ),
                ),
              ),
            ),
            // Written out even though it is `pumpForGolden`'s default: the phone
            // frame is the point of these goldens.
            // ignore: avoid_redundant_argument_values
            surface: const Size(390, 844),
          );

          expectGolden(tester, name);
        });
      }
    }
  }
}
