/// A24.1 — the app shell: three tabs over one seeded session (design 13 §13.3,
/// newapp §B.2).
///
/// The shell is driven here through a seeded [ShellSession] — no `AppEnv`, no
/// radio, no socket — so these assertions are about the shell's own behaviour:
/// the three tabs exist, switching selects a tab and reveals the shell chrome,
/// and the loudest unacked alarm raises an [AlarmBar] whose `Acknowledge` is one
/// tap away (§13.3.3). Fonts are loaded so the seeded reader body measures the
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

/// The shell is adaptive now, so every test has to say which device it is
/// standing on — the default 800×600 test surface is a *medium* window and
/// renders the rail, not the bar. A phone is 400×800.
Future<void> _sized(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the three tabs are present on a phone', (tester) async {
    await _sized(tester, const Size(400, 800));
    final session = _session();
    addTearDown(session.dispose);

    await tester.pumpWidget(_host(session));
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    for (final tab in ['Live', 'Cooks', 'Device']) {
      expect(find.text(tab), findsOneWidget, reason: 'nav tab "$tab"');
    }
  });

  testWidgets('a medium window swaps the bar for a rail, same destinations', (
    tester,
  ) async {
    // An unfolded Pixel Fold, roughly.
    await _sized(tester, const Size(840, 1000));
    final session = _session();
    addTearDown(session.dispose);

    await tester.pumpWidget(_host(session));
    await tester.pump();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    // The destinations and their order do not change with the chrome — that
    // is what keeps this a layout change and not an IA change.
    for (final tab in ['Live', 'Cooks', 'Device']) {
      expect(find.text(tab), findsWidgets, reason: 'rail destination "$tab"');
    }
  });

  testWidgets('the shell owns one transport chip on every tab', (tester) async {
    await _sized(tester, const Size(400, 800));
    final session = _session();
    addTearDown(session.dispose);

    await tester.pumpWidget(_host(session));
    await tester.pump();

    // The reader used to be the exception — it drew its own chip inside CookView
    // while the other three got the shell's, so the indicator moved when you
    // changed tabs. There is exactly one, everywhere, now.
    expect(find.byType(SystemStatusBar), findsOneWidget);

    await tester.tap(find.text('Cooks'));
    // Not pumpAndSettle: the live TransportChip's PulseDot animates forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(find.byType(SystemStatusBar), findsOneWidget);
  });

  testWidgets('the loudest unacked alarm raises an AlarmBar on the reader', (
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

  testWidgets('with no snapshot the reader waits rather than throwing', (
    tester,
  ) async {
    final session = ShellSession.seeded(launch: const LaunchConnecting());
    addTearDown(session.dispose);

    await tester.pumpWidget(_host(session));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
