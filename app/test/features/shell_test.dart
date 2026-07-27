/// A24.1 — the app shell: four tabs over one seeded session (design 13 §13.3).
///
/// The shell is driven here through a seeded [ShellSession] — no `AppEnv`, no
/// radio, no socket — so these assertions are about the shell's own behaviour:
/// the four tabs exist, switching selects a tab and reveals the shell chrome,
/// and the loudest unacked alarm raises an [AlarmBar] whose `Acknowledge` is one
/// tap away (§13.3.3). Fonts are loaded so the seeded Cook body measures the
/// metrics that ship.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/connection.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/features/shell/shell_session.dart';
import 'package:smoke_bridge/features/shell/system_status_bar.dart';
import 'package:smoke_bridge/ui/ui.dart';

import '../support/load_fonts.dart';

DashboardSnapshot _seed({List<Alarm> alarms = const []}) => DashboardSnapshot(
  probes: const [
    ProbeView(probe: 1, role: ProbeRole.pit, name: 'Pit', tempF10: 2250),
    ProbeView(probe: 2, role: ProbeRole.food, name: 'Brisket', tempF10: 1500),
    ProbeView(probe: 3, role: ProbeRole.food, name: 'Probe 3'),
    ProbeView(probe: 4, role: ProbeRole.unused, name: 'Probe 4'),
  ],
  link: LinkKind.http,
  alarms: alarms,
);

ShellSession _session({List<Alarm> alarms = const []}) => ShellSession.seeded(
  snapshot: _seed(alarms: alarms),
  launch: const LaunchConnecting(),
);

Widget _host(ShellSession session) => MaterialApp(
  theme: SmokeTheme.dark,
  home: AppShell(session: session),
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the four tabs are present', (tester) async {
    final session = _session();
    addTearDown(session.dispose);

    await tester.pumpWidget(_host(session));
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final tab in ['Cook', 'History', 'Alarms', 'Bridge']) {
      expect(find.text(tab), findsOneWidget, reason: 'nav tab "$tab"');
    }
  });

  testWidgets('switching selects the tab and reveals the shell chrome', (
    tester,
  ) async {
    final session = _session();
    addTearDown(session.dispose);

    await tester.pumpWidget(_host(session));
    await tester.pump();

    // Cook (tab 0) carries its own chrome inside CookView, so the shell does
    // not add its bar there.
    expect(find.byType(SystemStatusBar), findsNothing);

    await tester.tap(find.text('History'));
    // Not pumpAndSettle: the live TransportChip's PulseDot animates forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    // On a non-Cook tab the shell owns the chrome.
    expect(find.byType(SystemStatusBar), findsOneWidget);
  });

  testWidgets('the loudest unacked alarm raises an AlarmBar on the Cook tab', (
    tester,
  ) async {
    final session = _session(
      alarms: const [
        // A warning and a device-scope critical, both unacked: the critical is
        // louder and must be the one shown and acknowledged.
        Alarm(id: 7, rule: 'target_reached', probe: 2),
        Alarm(
          id: 9,
          rule: 'pit_crash',
          probe: 0,
          severity: AlarmSeverity.critical,
        ),
      ],
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(_host(session));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(AlarmBar), findsWidgets);
    expect(find.text('The fire is dying'), findsOneWidget);
    expect(find.text('Acknowledge'), findsOneWidget);

    // Acking routes through the shared session; with no bridge behind the
    // seeded session it is a safe no-op, not a throw.
    await tester.tap(find.text('Acknowledge'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no snapshot the Cook tab waits rather than throwing', (
    tester,
  ) async {
    final session = ShellSession.seeded(launch: const LaunchConnecting());
    addTearDown(session.dispose);

    await tester.pumpWidget(_host(session));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Cook'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
