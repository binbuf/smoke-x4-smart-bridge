/// A24.10 — the Bridge tab's state model: the screen must always say which
/// state the bridge is in, and must never present stale details as live —
/// the board-found bug was a factory-reset bridge whose old id and IP still
/// read as current facts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/prefs/bridge_prefs.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/features/bridge/bridge_tab.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/features/shell/shell_session.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: SmokeTheme.dark, home: Scaffold(body: child));

DashboardSnapshot _snap(
  LinkKind link, {
  String? netMode,
  String address = '',
}) => DashboardSnapshot(
  probes: const [],
  link: link,
  netMode: netMode,
  address: address,
);

void main() {
  testWidgets('connected over Bluetooth says so, with no fake address', (
    tester,
  ) async {
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.ble));
    final prefs = InMemoryBridgePrefs(lastBaseUrl: 'http://10.0.0.7');
    await tester.pumpWidget(
      _wrap(BridgeTab(session: session, prefs: prefs)),
    );
    expect(find.text('Bluetooth'), findsOneWidget);
    // The remembered Wi-Fi address is NOT in use and must not read as if it
    // were — over BLE there is no address.
    expect(find.text('none — via Bluetooth'), findsOneWidget);
    expect(find.byKey(const Key('bridge-last-known')), findsNothing);
  });

  testWidgets('hosted Wi-Fi names the mode and the address', (tester) async {
    final session = ShellSession.seeded(
      snapshot: _snap(
        LinkKind.http,
        netMode: 'ap',
        address: 'http://192.168.4.1',
      ),
    );
    await tester.pumpWidget(_wrap(BridgeTab(session: session)));
    expect(find.text('Wi-Fi — hosted network'), findsOneWidget);
    expect(find.textContaining('192.168.4.1'), findsWidgets);
  });

  testWidgets('offline shows last-known framing and disables the verbs', (
    tester,
  ) async {
    // Tall surface so the danger zone (bottom of the list) is mounted.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.offline));
    final prefs = InMemoryBridgePrefs(
      lastBaseUrl: 'http://10.0.0.7',
      lastBridgeId: 'A4F2',
    );
    await tester.pumpWidget(
      _wrap(BridgeTab(session: session, prefs: prefs)),
    );
    expect(find.text('Not connected'), findsOneWidget);
    // Stale details are labelled as history, not presented as now.
    expect(find.byKey(const Key('bridge-last-known')), findsOneWidget);
    // The three verbs that need a link are disabled WITH their reason.
    expect(find.text('Needs a connection to the bridge.'), findsNWidgets(3));
  });

  testWidgets('a phone with no bridge gets one card and one action', (
    tester,
  ) async {
    final session = ShellSession.seeded(); // nothing connected, nothing known
    final prefs = InMemoryBridgePrefs();
    await tester.pumpWidget(
      _wrap(BridgeTab(session: session, prefs: prefs)),
    );
    expect(find.text('No bridge set up'), findsOneWidget);
    expect(find.byKey(const Key('bridge-set-up')), findsOneWidget);
    // No identity card full of dashes, no danger zone for a bridge that
    // does not exist.
    expect(find.text('YOUR BRIDGE'), findsNothing);
    expect(find.text('DANGER ZONE'), findsNothing);
  });
}
