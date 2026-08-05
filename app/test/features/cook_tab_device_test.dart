/// The Cook tab on a real device geometry (design 13 §13.3, §13.3.8).
///
/// Written from a device session: the release build on a Pixel 10 Pro Fold
/// rendered the Cook body wrong under a live Bluetooth link. These pin the
/// exact geometry and link state it was in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/connection.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/live/live_tab.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/features/shell/shell_scope.dart';
import 'package:smoke_bridge/features/shell/shell_session.dart';

import '../support/load_fonts.dart';

/// What the bridge actually reports over Bluetooth: no address, no full
/// history, probes attached, and a couple of hours of samples.
DashboardSnapshot _bleSnapshot({List<Sample> samples = const []}) =>
    DashboardSnapshot(
      probes: const [
        ProbeView(probe: 1, role: ProbeRole.pit, name: 'Pit', tempF10: 2250),
        ProbeView(
          probe: 2,
          role: ProbeRole.food,
          name: 'Brisket',
          tempF10: 1500,
        ),
        ProbeView(probe: 3, role: ProbeRole.unused, name: 'Probe 3'),
        ProbeView(probe: 4, role: ProbeRole.unused, name: 'Probe 4'),
      ],
      link: LinkKind.ble,
      fullHistory: false,
      lastPacketSAgo: 3,
      samples: samples,
    );

List<Sample> _samples() => [
  for (var t = 0; t < 120; t++)
    Sample(t: t * 30, tempsF10: [2200 + t, 1200 + t * 2, null, null]),
];

Widget _host(ShellSession session) => MaterialApp(
  theme: SmokeTheme.dark,
  home: ShellScope(
    session: session,
    activeIndex: 0,
    child: const Scaffold(body: LiveTab()),
  ),
);

Future<void> _sized(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadAppFonts);

  // The Pixel 10 Pro Fold's cover display, in logical pixels.
  const coverDisplay = Size(411, 900);

  testWidgets('renders the instrument body over Bluetooth with no samples', (
    tester,
  ) async {
    await _sized(tester, coverDisplay);
    final session = ShellSession.seeded(
      snapshot: _bleSnapshot(),
      launch: const LaunchConnecting(),
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(_host(session));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    expect(tester.takeException(), isNull);
    expect(find.text('Live readings'), findsOneWidget);
    expect(find.text('Set up a cook'), findsOneWidget);
    // The shell owns the chip, so this must not draw a second one — but the
    // BLE capability line is this screen's own and stays.
    expect(find.textContaining('On Bluetooth'), findsOneWidget);
  });

  testWidgets('renders the chart under it once samples arrive', (tester) async {
    await _sized(tester, coverDisplay);
    final session = ShellSession.seeded(
      snapshot: _bleSnapshot(samples: _samples()),
      launch: const LaunchConnecting(),
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(_host(session));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    expect(tester.takeException(), isNull);
    expect(find.text('Live readings'), findsOneWidget);
  });

  testWidgets('the unfolded inner display uses the supporting pane', (
    tester,
  ) async {
    // The Fold opened: an expanded window.
    await _sized(tester, const Size(1000, 1030));
    final session = ShellSession.seeded(
      snapshot: _bleSnapshot(samples: _samples()),
      launch: const LaunchConnecting(),
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(_host(session));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    expect(tester.takeException(), isNull);
    expect(find.text('Live readings'), findsOneWidget);
  });

  testWidgets('no session renders a state, never a blank screen', (
    tester,
  ) async {
    await _sized(tester, coverDisplay);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LiveTab())));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SizedBox), findsWidgets);
    expect(find.text('No live session'), findsOneWidget);
  });
}
