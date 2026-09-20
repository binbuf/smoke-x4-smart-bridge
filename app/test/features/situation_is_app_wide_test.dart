/// The reconciliation layer belongs to the app, not to one tab (16 §16.3).
///
/// It used to be built inside `BridgeTab.initState`. Branches of a
/// `StatefulShellRoute` are not preloaded, so for anyone who opened the app and
/// stayed on the reader — which is *the* expected way to use a temperature
/// reader — the resolver was never constructed at all: no OS fact was gathered,
/// no automatic remedy ran, and `/live` fell back to a weaker reconciler that
/// could only diagnose. Every mismatch in the world still collapsed into
/// "Offline · retry 6", which is the sentence §16.3 opens by naming.
///
/// So what is pinned here is ownership and agreement:
///
///  * the reader states a situation the *resolver* produced, with the Device
///    tab never mounted;
///  * both screens read the same resolver, so §16.3's "`/device` — **the same
///    situation** as the lead card" is structurally true rather than a
///    coincidence of two engines agreeing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/connection.dart';
import 'package:smoke_bridge/data/prefs/bridge_prefs.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/domain/situation/situation.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/features/live/live_tab.dart';
import 'package:smoke_bridge/features/shell/shell_scope.dart';
import 'package:smoke_bridge/features/shell/shell_session.dart';
import 'package:smoke_bridge/features/shell/situation_resolver.dart';

import '../support/load_fonts.dart';

/// A phone with its radio switched off — situation #1, the commonest
/// real-world blocker, and one the reader could never surface before because
/// `liveSituation` is given no OS facts by design.
class _RadioOffProbe implements SituationProbe {
  @override
  Future<bool?> bluetoothOn() async => false;

  @override
  Future<String?> missingPermission() async => null;

  @override
  Future<BondedBridge?> bondedBridge() async => null;

  @override
  Future<String?> visibleApSsid() async => null;

  @override
  Future<bool> joinNetwork(String ssid, {String psk = ''}) async => false;

  @override
  Future<bool> openBluetoothSettings() async => true;

  @override
  Future<bool> requestMissingPermission() async => true;
}

class _StubShell implements SituationShell {
  @override
  DashboardSnapshot? snapshot;

  @override
  BridgeTransport? transport;

  @override
  bool hasRunningCook = false;

  @override
  Future<String?> runningCookBridgeId() async => null;

  @override
  Future<({String? mode, String? ssid})> netStatus() async =>
      (mode: null, ssid: null);

  @override
  Future<bool> retryNow() async => false;
}

DashboardSnapshot _cached() => const DashboardSnapshot(
  probes: [
    ProbeView(probe: 1, role: ProbeRole.pit, name: 'Pit', tempF10: 2250),
    ProbeView(probe: 2, role: ProbeRole.food, name: 'Brisket', tempF10: 1500),
    ProbeView(probe: 3, role: ProbeRole.unused, name: 'Probe 3'),
    ProbeView(probe: 4, role: ProbeRole.unused, name: 'Probe 4'),
  ],
  link: LinkKind.offline,
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the reader names a phone-side cause with Device never opened', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final resolver = SituationResolver(
      prefs: InMemoryBridgePrefs(
        lastBridgeId: 'SB-8274',
        lastBleDeviceId: 'AA:BB',
      ),
      probe: _RadioOffProbe(),
      shell: _StubShell(),
    );
    await resolver.evaluate();

    // The resolver did its job off-screen.
    expect(resolver.situation.kind, SituationKind.bluetoothOff);

    final session = ShellSession.seeded(
      snapshot: _cached(),
      launch: const LaunchOffline(),
      resolver: resolver,
    );
    addTearDown(session.dispose);

    // Only the reader is ever mounted. No BridgeTab, no Device branch.
    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeTheme.dark,
        home: ShellScope(
          session: session,
          activeIndex: 0,
          child: const Scaffold(body: LiveTab()),
        ),
      ),
    );
    await tester.pump();

    expect(
      session.situation.kind,
      SituationKind.bluetoothOff,
      reason: 'the shell owns the verdict, so every tab reads the same one',
    );
    expect(
      find.textContaining('Bluetooth is off'),
      findsWidgets,
      reason:
          'the reader must name the cause. Before the hoist this phone read '
          'as a bare "Offline" — the radio being off was invisible on the '
          'one screen the user actually lives on',
    );
    // And the temperatures are still there, above the fold, unveiled by the
    // banner — §16.6's "never covering them".
    expect(find.textContaining('225'), findsWidgets);
  });

  test('a session with no resolver still answers, and answers healthy', () {
    // A direct-mount test or the lab has no shell to borrow from. That must
    // degrade to "nothing to report", never to a crash.
    final session = ShellSession.seeded(snapshot: _cached());
    addTearDown(session.dispose);

    expect(session.situationResolver, isNull);
    expect(session.situation, Situation.ok);
  });
}
