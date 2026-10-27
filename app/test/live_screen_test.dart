import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/features/live/live_screen.dart';
import 'package:smoke_bridge/features/settings/bridge_details.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/theme/app_theme.dart';
import 'package:smoke_bridge/widgets/probe_sparkline.dart';

import 'support/fake_bridge_session.dart';

/// T34: every Live state in design 13 §13.4 is reachable through the fake and
/// renders the approved copy. The fake drives view state directly where the
/// scripted wire cannot express a clock age or cache availability.
void main() {
  Future<FakeBridgeSession> pumpLive(
    WidgetTester tester, {
    required void Function(FakeBridgeSession session) drive,
    bool shell = false,
  }) async {
    final session = FakeBridgeSession();
    addTearDown(session.dispose);
    drive(session);

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: shell
            ? AppShell(controller: session.controller)
            : Scaffold(body: LiveScreen(controller: session.controller)),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  Finder inProbe(int number, Finder matching) => find.descendant(
    of: find.byKey(Key('live.probe.$number')),
    matching: matching,
  );

  FakeBridgeSession healthy(FakeBridgeSession session) {
    session.driveLiveState(
      phase: ConnectionPhase.live,
      probeTemps: const <double?>[225.0, 165.2, null, 80.0],
      smokeXAge: const Duration(seconds: 12),
      smokeXStatus: SmokeXStatus.pairedLive,
      probeHealth: ProbeHealth.live,
      billowsAttachment: BillowsAttachment.attached,
      billowsSeenThisSession: true,
      offlineCache: true,
    );
    return session;
  }

  testWidgets('healthy shows the chain, four probes and a real sparkline', (
    tester,
  ) async {
    await pumpLive(tester, drive: healthy);

    expect(find.byKey(const Key('status.connection')), findsOneWidget);
    expect(find.text('App'), findsOneWidget);
    expect(find.text('Bridge'), findsOneWidget);
    expect(find.text('Smoke X4'), findsOneWidget);
    expect(find.text('Bridge connected · 2h 14m'), findsOneWidget);
    expect(find.text('Receiving readings · updated 12s ago'), findsOneWidget);
    for (var probe = 1; probe <= 4; probe++) {
      expect(find.byKey(Key('live.probe.$probe')), findsOneWidget);
      expect(find.text('P$probe'), findsOneWidget);
    }
    expect(find.byType(ProbeSparkline), findsNWidgets(4));
    expect(inProbe(1, find.text('1h · +4.8°F')), findsOneWidget);
    expect(inProbe(1, find.text('No history yet')), findsNothing);
    expect(inProbe(3, find.text('No history yet')), findsOneWidget);
    expect(inProbe(3, find.text('Not connected')), findsOneWidget);
    expect(find.text('Sync now'), findsNothing);
  });

  testWidgets('aging keeps the Bridge healthy and names the reading age', (
    tester,
  ) async {
    await pumpLive(
      tester,
      drive: (session) => healthy(session)
        ..driveLiveState(
          smokeXAge: const Duration(seconds: 62),
          probeHealth: ProbeHealth.aging,
        ),
    );

    expect(find.text('Bridge connected · 2h 14m'), findsOneWidget);
    expect(inProbe(1, find.text('Updated 62s ago')), findsOneWidget);
    expect(find.text('Receiving readings · updated 1m ago'), findsOneWidget);
  });

  testWidgets('stale X4 telemetry keeps the Bridge row connected', (
    tester,
  ) async {
    await pumpLive(
      tester,
      drive: (session) => healthy(session)
        ..driveLiveState(
          smokeXAge: const Duration(minutes: 4),
          probeHealth: ProbeHealth.stale,
        ),
    );

    expect(find.text('Bridge connected · 2h 14m'), findsOneWidget);
    expect(find.text('No readings for 4 min'), findsWidgets);
  });

  testWidgets('lost X4 signal shows the age and one troubleshooting notice', (
    tester,
  ) async {
    await pumpLive(
      tester,
      drive: (session) => healthy(session)
        ..driveLiveState(
          smokeXAge: const Duration(minutes: 14),
          smokeXStatus: SmokeXStatus.pairedLost,
          probeHealth: ProbeHealth.frozen,
        ),
    );

    expect(find.text('Smoke X4 signal lost · 14 min ago'), findsOneWidget);
    expect(find.text('No data from Smoke X4'), findsOneWidget);
    expect(find.text('Troubleshoot'), findsOneWidget);
  });

  testWidgets('an unpaired X4 gets a guided pairing action', (tester) async {
    await pumpLive(
      tester,
      drive: (session) => healthy(session)
        ..driveLiveState(
          smokeXStatus: SmokeXStatus.unpaired,
          probePresence: ProbePresence.none,
        ),
    );

    expect(find.byKey(const Key('live.smokeXUnpaired')), findsOneWidget);
    expect(find.text('Pair the Smoke X4'), findsOneWidget);
    expect(find.text('Show pairing steps'), findsOneWidget);
    expect(find.textContaining('no Smoke X4 is paired yet'), findsOneWidget);

    await tester.tap(find.text('Show pairing steps'));
    await tester.pumpAndSettle();
    expect(find.text('Put the Smoke X4 into SYNC mode.'), findsOneWidget);
    expect(find.textContaining('No reset is needed'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('a detached probe is a dash and Not connected, never zero', (
    tester,
  ) async {
    await pumpLive(tester, drive: healthy);

    expect(inProbe(3, find.text('—')), findsOneWidget);
    expect(inProbe(3, find.text('Not connected')), findsOneWidget);
    expect(inProbe(3, find.textContaining('0.0°F')), findsNothing);
    expect(find.byKey(const Key('live.probe.3')), findsOneWidget);
  });

  testWidgets('no probes keeps four tiles and shows one notice', (
    tester,
  ) async {
    await pumpLive(
      tester,
      drive: (session) =>
          healthy(session)..driveLiveState(probePresence: ProbePresence.none),
    );

    for (var probe = 1; probe <= 4; probe++) {
      expect(find.byKey(Key('live.probe.$probe')), findsOneWidget);
      expect(inProbe(probe, find.text('—')), findsOneWidget);
    }
    expect(find.text('No probes connected'), findsOneWidget);
    expect(find.text('Not connected'), findsNothing);
  });

  testWidgets('offline with cache keeps saved values and hides the signal', (
    tester,
  ) async {
    await pumpLive(
      tester,
      drive: (session) =>
          healthy(session)..driveLiveState(phase: ConnectionPhase.offline),
    );

    expect(
      find.text('Bridge disconnected · last connected 2 hr ago'),
      findsOneWidget,
    );
    expect(
      find.text('Showing saved readings · last reading 2 hr ago'),
      findsOneWidget,
    );
    expect(find.text('Fair'), findsNothing);
    expect(inProbe(1, find.text('225.0°F')), findsOneWidget);
    expect(find.text('Set temp (last known)'), findsOneWidget);
  });

  testWidgets('offline without cache never shows fixture values as current', (
    tester,
  ) async {
    await pumpLive(
      tester,
      drive: (session) => healthy(session)
        ..driveLiveState(phase: ConnectionPhase.offline, offlineCache: false),
    );

    expect(
      find.text('Bridge disconnected · nothing saved yet'),
      findsOneWidget,
    );
    expect(find.textContaining('Showing saved readings'), findsNothing);
    expect(inProbe(1, find.textContaining('225.0')), findsNothing);
    expect(inProbe(1, find.text('—')), findsOneWidget);
    expect(find.byKey(const Key('live.noCache')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('sync progress is its own card and names a slow connection', (
    tester,
  ) async {
    await pumpLive(
      tester,
      drive: (session) => healthy(session)
        ..driveLiveState(
          phase: ConnectionPhase.syncing,
          syncState: SyncState.recent,
          syncProgressPercent: 35,
          slowLink: true,
        ),
    );

    expect(find.byKey(const Key('live.sync')), findsOneWidget);
    expect(find.text('Syncing saved readings'), findsOneWidget);
    expect(find.text('Newest readings load first.'), findsOneWidget);
    expect(find.text('Slow connection'), findsOneWidget);

    final session = FakeBridgeSession();
    addTearDown(session.dispose);
    healthy(session);
    session.driveLiveState(
      phase: ConnectionPhase.syncing,
      syncState: SyncState.backfill,
      syncProgressPercent: 72,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: LiveScreen(controller: session.controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Loading saved readings'), findsOneWidget);
    expect(
      find.text(
        'Your latest readings are ready. Older readings continue in the background.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('sync failure is named and live readings keep updating', (
    tester,
  ) async {
    await pumpLive(
      tester,
      drive: (session) =>
          healthy(session)..driveLiveState(syncState: SyncState.error),
    );

    expect(find.text('History sync failed'), findsOneWidget);
    expect(find.text('Retry sync'), findsOneWidget);
    expect(find.text('Receiving readings · updated 12s ago'), findsOneWidget);
    expect(inProbe(1, find.text('225.0°F')), findsOneWidget);
  });

  testWidgets('Billows card needs detection and the observe capability', (
    tester,
  ) async {
    final session = await pumpLive(tester, drive: healthy);
    expect(find.byKey(const Key('live.billows')), findsOneWidget);
    expect(find.text('Billows'), findsOneWidget);
    expect(find.text('Set temp'), findsOneWidget);
    expect(find.text('Last detected'), findsOneWidget);
    expect(find.text('Set on the Smoke X4.'), findsOneWidget);
    expect(find.textContaining('Read-only'), findsNothing);

    session.driveLiveState(billowsObserve: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live.billows')), findsNothing);

    session.driveLiveState(
      billowsObserve: true,
      billowsAttachment: BillowsAttachment.unknown,
      billowsSeenThisSession: false,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live.billows')), findsNothing);
    expect(find.text('Billows not detected'), findsNothing);

    session.driveLiveState(
      billowsAttachment: BillowsAttachment.detached,
      billowsSeenThisSession: true,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live.billows')), findsNothing);
    expect(find.text('Billows not detected'), findsOneWidget);
    expect(find.text('View connection log'), findsOneWidget);
  });

  testWidgets('connection card opens Bridge details and a tile opens History', (
    tester,
  ) async {
    final session = await pumpLive(tester, drive: healthy, shell: true);

    await tester.tap(find.byKey(const Key('status.connection')));
    await tester.pumpAndSettle();
    expect(find.byType(BridgeDetailsScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('live.probe.2')));
    await tester.pumpAndSettle();

    expect(session.controller.tab, AppTab.history);
    expect(session.controller.historyProbe, 2);
    expect(session.controller.historyRange, HistoryRange.oneHour);
    expect(find.text('Summary'), findsOneWidget);
  });

  testWidgets('Live uses pull-to-refresh, never a Sync now action', (
    tester,
  ) async {
    await pumpLive(tester, drive: healthy, shell: true);

    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.text('Sync now'), findsNothing);
  });
}
