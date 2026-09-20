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

/// A fixed "now" so a freshness assertion is a statement about the ladder
/// rather than a race against how long the suite took to get here.
const int _fixedNow = 1770000000000;

DashboardSnapshot _seed({
  List<Alarm> alarms = const [],
  int? readingAgeS,
}) => DashboardSnapshot(
  probes: const [
    ProbeView(probe: 1, role: ProbeRole.pit, name: 'Pit', tempF10: 2250),
    ProbeView(probe: 2, role: ProbeRole.food, name: 'Brisket', tempF10: 1500),
    ProbeView(probe: 3, role: ProbeRole.food, name: 'Probe 3'),
    ProbeView(probe: 4, role: ProbeRole.unused, name: 'Probe 4'),
  ],
  link: LinkKind.http,
  alarms: alarms,
  // The ladder ages what reached *this phone*, so the seed states when the
  // reading landed rather than what the device said about its base station.
  readingAtUnixMs: readingAgeS == null ? null : _fixedNow - readingAgeS * 1000,
);

ShellSession _session({
  List<Alarm> alarms = const [],
  int? readingAgeS,
  LaunchState launch = const LaunchConnecting(),
}) => ShellSession.seeded(
  snapshot: _seed(alarms: alarms, readingAgeS: readingAgeS),
  launch: launch,
  now: () => _fixedNow,
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

  // ── the chrome stack (newapp §H.2) ──────────────────────────────────
  //
  // Three full-bleed strips stacked in arrival order was the shell's loudest
  // "competent Material app" tell. What is pinned below is the curation that
  // replaced it: one bezel, floating notices, an explicit rank, and the second
  // situation subordinated rather than shouted at the same weight.

  group('the chrome stack', () {
    testWidgets('the status bar is the only full-bleed element', (
      tester,
    ) async {
      await _sized(tester, const Size(400, 800));
      final session = _session(
        alarms: const [
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

      final bar = tester.getRect(find.byType(SystemStatusBar));
      final alarm = tester.getRect(find.byKey(const Key('alarm-bar')));
      expect(bar.left, 0);
      expect(bar.right, 400, reason: 'the bezel spans the window');
      expect(
        alarm.left,
        greaterThan(0),
        reason:
            'a notice floats in the gutter; a third edge-to-edge band is the '
            'thing this pass exists to remove',
      );
      expect(alarm.top, greaterThanOrEqualTo(bar.bottom));
    });

    testWidgets('an alarm outranks a failed refresh, and subordinates it', (
      tester,
    ) async {
      await _sized(tester, const Size(400, 800));
      final session = _session(
        launch: const LaunchOffline(),
        alarms: const [
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
      await tester.pump();
      // A seeded session has no supervisor to retry through, which is exactly
      // the shape of "the bridge is not there".
      await session.refresh();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      expect(find.byKey(const Key('refresh-banner')), findsOneWidget);
      final alarm = tester.getRect(find.byKey(const Key('alarm-bar')));
      final refresh = tester.getRect(find.byKey(const Key('refresh-banner')));
      expect(
        alarm.top,
        lessThan(refresh.top),
        reason:
            'the alarm is about the cook; a failed pull is about the app’s own '
            'plumbing, and the cook wins',
      );
      // Subordinated, not silenced: the cause survives, the paragraph does not.
      expect(find.byKey(const Key('refresh-banner-title')), findsOneWidget);
      expect(find.byKey(const Key('refresh-banner-detail')), findsNothing);
      expect(
        find.byKey(const Key('refresh-banner-dismiss')),
        findsNothing,
        reason: 'two ✕ on screen is a coin toss about which one you closed',
      );
    });

    testWidgets('alone, the refresh banner keeps its detail and its ✕', (
      tester,
    ) async {
      await _sized(tester, const Size(400, 800));
      final session = _session(launch: const LaunchOffline());
      addTearDown(session.dispose);

      await tester.pumpWidget(_host(session));
      await tester.pump();
      await session.refresh();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      expect(find.byKey(const Key('refresh-banner-detail')), findsOneWidget);
      expect(find.byKey(const Key('refresh-banner-dismiss')), findsOneWidget);
    });

    testWidgets('a healthy shell shows no chrome about health at all', (
      tester,
    ) async {
      await _sized(tester, const Size(400, 800));
      final session = _session();
      addTearDown(session.dispose);

      await tester.pumpWidget(_host(session));
      await tester.pump(const Duration(seconds: 1));

      // Both are mounted, so they can animate — and both are silent.
      expect(find.byType(AlarmBar), findsOneWidget);
      expect(tester.getSize(find.byType(AlarmBar)).height, 0);
      expect(find.byKey(const Key('alarm-bar')), findsNothing);
      expect(find.byKey(const Key('refresh-banner')), findsNothing);
    });

    testWidgets('stale readings get the word, not only a stopped dot', (
      tester,
    ) async {
      await _sized(tester, const Size(400, 800));
      // 5 minutes since the last packet: past aging, short of frozen.
      final session = _session(readingAgeS: 300);
      addTearDown(session.dispose);

      await tester.pumpWidget(_host(session));
      await tester.pump(const Duration(seconds: 1));

      // The dot ceasing to breathe IS the staleness signal — and it is
      // invisible in a still frame, in a screenshot, and to a screen reader.
      expect(find.text('Stale'), findsOneWidget);
      expect(
        find.text('No signal'),
        findsNothing,
        reason: 'stale is not frozen; the ladder has four rungs for a reason',
      );
    });

    testWidgets('a healthy stream says nothing about freshness', (
      tester,
    ) async {
      await _sized(tester, const Size(400, 800));
      final session = _session(readingAgeS: 10);
      addTearDown(session.dispose);

      await tester.pumpWidget(_host(session));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Stale'), findsNothing);
      expect(find.text('No signal'), findsNothing);
    });

    testWidgets('the transport chip announces itself as an actionable button', (
      tester,
    ) async {
      await _sized(tester, const Size(400, 800));
      final handle = tester.ensureSemantics();
      final session = _session(readingAgeS: 10);
      addTearDown(session.dispose);

      await tester.pumpWidget(_host(session));
      await tester.pump(const Duration(seconds: 1));

      final node = tester.getSemantics(find.byType(TransportChip));
      expect(node.label, contains('Wi-Fi'));
      expect(
        node.label,
        contains('receiving readings'),
        reason:
            'a link can be up while the stream is dead — "connected" would be '
            'the exact lie this app exists to catch',
      );
      expect(node.flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });

  testWidgets('with no snapshot the reader answers anyway, never a spinner', (
    tester,
  ) async {
    await _sized(tester, const Size(400, 800));
    final session = ShellSession.seeded(launch: const LaunchConnecting());
    addTearDown(session.dispose);

    await tester.pumpWidget(_host(session));
    await tester.pump();

    // §16.6 and §16.2: the reader renders its real layout on the first frame,
    // in every case. A full-screen spinner is the app declining to answer its
    // own question — and the shell must not reintroduce one above it either.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Live'), findsOneWidget);
    expect(find.byType(SystemStatusBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
