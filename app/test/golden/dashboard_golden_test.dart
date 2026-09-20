/// A15.2 — the reader pinned at every shape, in both themes.
///
/// The outline's list, and it is not negotiable: **no probes, all
/// detached, mid-gap, alarm active, 15 h of data, 54 days of data — each
/// in dark and in light.** Dark is first because dark-first is a product
/// requirement rather than a preference (§8.7); light is pinned too,
/// because "we have a light theme" is a claim that only survives if
/// something checks it.
///
/// The all-detached goldens are the ones that matter most: they are the
/// cheapest possible place to catch the day `—` becomes `0`.
///
/// **The subject moved.** These pinned `DashboardView`, the pre-shell screen
/// newapp §I.0 deleted — so the suite was guarding a widget nobody could
/// reach while the shipping reader ([CookView]) had no goldens at all. Same
/// six shapes, same two themes, now over the thing that actually renders.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/cook/cook_view.dart';
import 'package:smoke_bridge/features/dashboard/dashboard.dart';
import 'package:smoke_bridge/ui/ui.dart';

import '../support/shapes.dart';
import 'golden.dart';

Widget _dashboard(
  List<Sample> cook, {
  List<Alarm> alarms = const [],
  bool fullHistory = true,
}) {
  final snap = snapshotFor(
    cook,
    alarms: alarms,
    fullHistory: fullHistory,
    link: fullHistory ? LinkKind.http : LinkKind.ble,
  );
  return CookView(
    snapshot: snap,
    plan: null,
    freshness: ProbeFreshness.live,
  );
}

/// The six shapes, built once and shared by both themes.
final Map<String, Widget Function()> _shapes = {
  'no-probes': () => _dashboard(const []),
  'all-detached': () => _dashboard(allDetached(hours: 2)),
  'mid-gap': () =>
      _dashboard(withGap(syntheticCook(hours: 4), fromT: 3600, toT: 5400)),
  'alarm-active': () => _dashboard(
    syntheticCook(hours: 6),
    alarms: const [
      Alarm(
        id: 3,
        rule: 'target_reached',
        probe: 2,
        valueF10: 2031,
        severity: AlarmSeverity.critical,
      ),
    ],
  ),
  '15h': () => _dashboard(syntheticCook(hours: 15)),
  '54d': () => _dashboard(syntheticCook(hours: 54 * 24, periodS: 300)),
};

void main() {
  for (final brightness in Brightness.values) {
    // `daylight`, not `light`: the app has no Material light brightness.
    // The second profile is the direct-sun contrast one (14 §14.3.3) —
    // lifted ink, glows off, same surfaces.
    final theme = brightness == Brightness.dark ? 'dark' : 'daylight';
    group('dashboard · $theme', () {
      for (final entry in _shapes.entries) {
        testWidgets(entry.key, (tester) async {
          await pumpForGolden(tester, entry.value(), brightness: brightness);
          expectGolden(tester, 'dashboard-${entry.key}-$theme');
        });
      }
    });
  }

  testWidgets('the all-detached dashboard contains no temperature digit', (
    tester,
  ) async {
    // The M0 invariant, one last time, at the last layer before pixels.
    // Four empty jacks collapse to the explanation rather than to four
    // tiles reading 0 °F — and nothing on the screen is a temperature.
    await pumpForGolden(tester, _dashboard(allDetached(hours: 2)));
    final described = describeTree(tester);
    expect(described, isNot(contains('text "0°"')));
    expect(described, isNot(contains('degrees')));
  });

  testWidgets('the degraded dashboard says full history needs Wi-Fi', (
    tester,
  ) async {
    await pumpForGolden(
      tester,
      _dashboard(syntheticCook(hours: 2), fullHistory: false),
    );
    expectGolden(tester, 'dashboard-degraded-dark');
  });
}
