/// A24.10 — the Bridge tab's state model: the screen must always say which
/// state the bridge is in, and must never present stale details as live —
/// the board-found bug was a factory-reset bridge whose old id and IP still
/// read as current facts.
///
/// A26 adds the signal rows, which extend the same rule to dBm: each hop is
/// labelled with the two ends it actually spans, an unmeasurable hop says so
/// in words instead of drawing empty bars, and nothing renders at all while
/// the link is down.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/prefs/bridge_prefs.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/bridge/bridge_tab.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/features/shell/shell_session.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: SmokeTheme.dark,
  home: Scaffold(body: child),
);

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

/// Answers the two reads this screen makes, and nothing else.
class _StubTransport implements BridgeTransport {
  _StubTransport({
    this.signalValue = const LinkSignal(),
    this.failSignal = false,
  });

  final LinkSignal signalValue;
  final bool failSignal;
  int signalCalls = 0;

  @override
  Future<BridgeStatus> status() async =>
      const BridgeStatus(deviceId: 'A4F2', fw: '1.0.0');

  @override
  Future<LinkSignal> signal() async {
    signalCalls++;
    if (failSignal) {
      throw StateError('unreachable');
    }
    return signalValue;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('connected over Bluetooth says so, with no fake address', (
    tester,
  ) async {
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.ble));
    final prefs = InMemoryBridgePrefs(lastBaseUrl: 'http://10.0.0.7');
    await tester.pumpWidget(_wrap(BridgeTab(session: session, prefs: prefs)));
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
    await tester.pumpWidget(_wrap(BridgeTab(session: session, prefs: prefs)));
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
    await tester.pumpWidget(_wrap(BridgeTab(session: session, prefs: prefs)));
    expect(find.text('No bridge set up'), findsOneWidget);
    expect(find.byKey(const Key('bridge-set-up')), findsOneWidget);
    // No identity card full of dashes, no danger zone for a bridge that
    // does not exist.
    expect(find.text('YOUR BRIDGE'), findsNothing);
    expect(find.text('DANGER ZONE'), findsNothing);
  });

  // ── A26: signal ─────────────────────────────────────────────────────

  testWidgets('Bluetooth shows the phone↔bridge hop it can actually measure', (
    tester,
  ) async {
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.ble));
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: session,
          prefs: InMemoryBridgePrefs(lastBridgeId: 'A4F2'),
          transport: _StubTransport(
            signalValue: const LinkSignal(
              linkDbm: -66,
              wifiDbm: -52,
              ssid: 'Backyard',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bridge-signal')), findsOneWidget);
    // The hop the user is standing in, named as such — not "signal: −66".
    expect(find.byKey(const Key('bridge-signal-ble')), findsOneWidget);
    expect(find.text('Phone to bridge'), findsOneWidget);
    expect(find.text('−66 dBm'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);

    // And the bridge's own uplink, which Bluetooth learns from net_status —
    // this is how you discover the bridge has drifted out of Wi-Fi range
    // while you are standing next to it.
    expect(find.byKey(const Key('bridge-signal-wifi')), findsOneWidget);
    expect(find.text('Bridge to Backyard'), findsOneWidget);
    expect(find.text('−52 dBm'), findsOneWidget);
  });

  testWidgets(
    'joined Wi-Fi names the hop it can measure and the one it cannot',
    (tester) async {
      final session = ShellSession.seeded(
        snapshot: _snap(
          LinkKind.http,
          netMode: 'sta',
          address: 'http://10.0.0.7',
        ),
      );
      await tester.pumpWidget(
        _wrap(
          BridgeTab(
            session: session,
            prefs: InMemoryBridgePrefs(lastBridgeId: 'A4F2'),
            transport: _StubTransport(
              signalValue: const LinkSignal(wifiDbm: -80, ssid: 'Backyard'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The phone's own Wi-Fi strength is behind a permission this app refuses
      // to take, so it is explained rather than drawn as empty bars.
      expect(find.byKey(const Key('bridge-signal-wifi-phone')), findsOneWidget);
      expect(find.byKey(const Key('bridge-signal-ble')), findsNothing);
      // The measurable hop, with the advice a weak link earns.
      expect(find.text('Bridge to Backyard'), findsOneWidget);
      expect(find.text('Weak'), findsOneWidget);
      expect(
        find.textContaining('Move it closer to the router'),
        findsOneWidget,
      );
    },
  );

  testWidgets('on the bridge’s own network neither end can measure the link', (
    tester,
  ) async {
    final session = ShellSession.seeded(
      snapshot: _snap(
        LinkKind.http,
        netMode: 'ap',
        address: 'http://192.168.4.1',
      ),
    );
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: session,
          prefs: InMemoryBridgePrefs(lastBridgeId: 'A4F2'),
          // AP mode: the firmware reports rssi 0 (no upstream AP), which must
          // never reach the screen as a reading.
          transport: _StubTransport(
            signalValue: const LinkSignal(
              ssid: 'SmokeBridge-A4F2',
              apClients: 1,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bridge-signal-hosted')), findsOneWidget);
    expect(find.textContaining('1 device'), findsOneWidget);
    // No bars, no dBm — there is nothing to measure and the screen says so.
    expect(find.byKey(const Key('bridge-signal-wifi')), findsNothing);
    expect(find.textContaining('dBm'), findsNothing);
  });

  testWidgets('offline shows no signal block at all', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.offline));
    final stub = _StubTransport(
      signalValue: const LinkSignal(wifiDbm: -52, ssid: 'Backyard'),
    );
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: session,
          prefs: InMemoryBridgePrefs(lastBaseUrl: 'http://10.0.0.7'),
          transport: stub,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A dBm from a link that is down is a fact about the past dressed up as
    // the present — the same class of bug as the stale IP this screen killed.
    expect(find.byKey(const Key('bridge-signal')), findsNothing);
    expect(find.textContaining('dBm'), findsNothing);
  });

  testWidgets('a signal read that fails drops the reading, keeps the page', (
    tester,
  ) async {
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.ble));
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: session,
          prefs: InMemoryBridgePrefs(lastBridgeId: 'A4F2'),
          transport: _StubTransport(failSignal: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The hop is still named — "we have not measured this" and "this link is
    // weak" must never look the same.
    expect(find.byKey(const Key('bridge-signal-ble')), findsOneWidget);
    expect(find.textContaining('dBm'), findsNothing);
    // And the rest of the device page is unharmed.
    expect(find.text('YOUR BRIDGE'), findsOneWidget);
  });

  testWidgets('a transport swap discards the previous link’s reading', (
    tester,
  ) async {
    final prefs = InMemoryBridgePrefs(lastBridgeId: 'A4F2');
    final stub = _StubTransport(signalValue: const LinkSignal(linkDbm: -66));

    Widget tab(ShellSession s) => _wrap(
      BridgeTab(session: s, prefs: prefs, transport: stub, active: false),
    );

    await tester.pumpWidget(
      tab(ShellSession.seeded(snapshot: _snap(LinkKind.ble))),
    );
    await tester.pumpAndSettle();
    expect(find.text('−66 dBm'), findsOneWidget);

    // The supervisor upgrades to Wi-Fi. −66 dBm was a measurement of the
    // Bluetooth radio; it says nothing at all about the Wi-Fi path, so it is
    // dropped rather than relabelled under the new heading.
    await tester.pumpWidget(
      tab(
        ShellSession.seeded(
          snapshot: _snap(
            LinkKind.http,
            netMode: 'sta',
            address: 'http://10.0.0.7',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('dBm'), findsNothing);
  });

  testWidgets('the signal poll runs only while the tab is the visible one', (
    tester,
  ) async {
    final stub = _StubTransport(signalValue: const LinkSignal(linkDbm: -60));
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.ble));

    Widget tab({required bool active}) =>
        _wrap(BridgeTab(session: session, transport: stub, active: active));

    await tester.pumpWidget(tab(active: false));
    await tester.pumpAndSettle();
    // initState always lands one reading — an empty meter on arrival would be
    // worse than one that is a few seconds old.
    final onMount = stub.signalCalls;
    expect(onMount, 1);

    // Twenty-one seconds behind another tab: no radio work at all.
    await tester.pump(const Duration(seconds: 21));
    expect(stub.signalCalls, onMount);

    // Brought to the front: refreshed immediately, then on the poll.
    await tester.pumpWidget(tab(active: true));
    await tester.pumpAndSettle();
    expect(stub.signalCalls, onMount + 1);
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(stub.signalCalls, onMount + 2);

    // Leaving stops it again, so the timer cannot outlive the tab.
    await tester.pumpWidget(tab(active: false));
    await tester.pumpAndSettle();
    final parked = stub.signalCalls;
    await tester.pump(const Duration(seconds: 21));
    expect(stub.signalCalls, parked);
  });

  testWidgets('pull-to-refresh asks the unit again', (tester) async {
    final stub = _StubTransport(signalValue: const LinkSignal(linkDbm: -60));
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.ble));
    await tester.pumpWidget(
      _wrap(BridgeTab(session: session, transport: stub, active: false)),
    );
    await tester.pumpAndSettle();
    final before = stub.signalCalls;

    await tester.fling(
      find.byKey(const Key('bridge-tab')),
      const Offset(0, 320),
      1000,
    );
    await tester.pumpAndSettle();

    expect(stub.signalCalls, greaterThan(before));
  });
}
