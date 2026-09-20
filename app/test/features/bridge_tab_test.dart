/// `/device` — the state ladder, the lead card, and the two-hop signal model.
///
/// The screen's contract (design 16 §16.6) is that **the lead card IS the
/// situation**, so most of what is asserted here is about which card leads and
/// what it says: a phone with no bridge gets one card and one action, an
/// unreachable bridge says when it was last seen rather than showing a page of
/// dashes, a radio that is off is named before the bridge is blamed for it, and
/// a fix the app made itself is reported in the past tense with nothing to tap.
///
/// A24.10's original rule still holds underneath all of it: the screen must
/// never present stale details as live — the board-found bug was a
/// factory-reset bridge whose old id and IP still read as current facts.
///
/// A26's signal rules are unchanged: each hop is labelled with the two ends it
/// actually spans, an unmeasurable hop says so in words instead of drawing
/// empty bars, and nothing renders at all while the link is down.
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
import 'package:smoke_bridge/features/shell/situation_resolver.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: SmokeTheme.dark,
  home: Scaffold(body: child),
);

DashboardSnapshot _snap(
  LinkKind link, {
  String? netMode,
  String address = '',
  int? socPct,
  bool batteryKnown = false,
}) => DashboardSnapshot(
  probes: const [],
  link: link,
  netMode: netMode,
  address: address,
  socPct: socPct,
  batteryKnown: batteryKnown,
);

/// Answers the reads this screen and its reconciler make, and nothing else.
class _StubTransport implements BridgeTransport {
  _StubTransport({
    this.signalValue = const LinkSignal(),
    this.failSignal = false,
    this.deviceId = 'A4F2',
    this.storageFreePct = 62,
    this.paired = true,
  });

  final LinkSignal signalValue;
  final bool failSignal;
  final String deviceId;
  final int storageFreePct;

  /// Whether the bridge has met a Smoke X base. True by default: this stub
  /// stands in for a working bridge, and `BridgeStatus`'s own default of
  /// false would put "hasn't met your Smoke X yet" on top of every test.
  final bool paired;
  int signalCalls = 0;

  @override
  BridgeCapabilities get capabilities =>
      const BridgeCapabilities(fullHistory: true);

  @override
  Future<BridgeStatus> status() async => BridgeStatus(
    deviceId: deviceId,
    fw: '1.0.0',
    storageFreePct: storageFreePct,
    paired: paired,
  );

  @override
  Future<LiveState> live({Duration window = const Duration(hours: 1)}) async =>
      const LiveState(
        t: 0,
        unixMs: 1750000000000,
        tempsF10: [null, null, null, null],
      );

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

/// A phone whose radio, permission and bond are whatever the test says.
class _Probe implements SituationProbe {
  _Probe({this.bluetooth, this.permission, this.bonded, this.ap});

  bool? bluetooth;
  String? permission;
  BondedBridge? bonded;
  String? ap;

  @override
  Future<bool?> bluetoothOn() async => bluetooth;
  @override
  Future<String?> missingPermission() async => permission;
  @override
  Future<BondedBridge?> bondedBridge() async => bonded;
  @override
  Future<String?> visibleApSsid() async => ap;
  @override
  Future<bool> joinNetwork(String ssid, {String psk = ''}) async => false;
  @override
  Future<bool> openBluetoothSettings() async => true;
  @override
  Future<bool> requestMissingPermission() async => false;
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  // ── which card leads (§16.6) ────────────────────────────────────────

  testWidgets('a phone with no bridge gets one card and one action', (
    tester,
  ) async {
    final session = ShellSession.seeded(); // nothing connected, nothing known
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: session,
          prefs: InMemoryBridgePrefs(),
          probe: _Probe(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('situation-card')), findsOneWidget);
    expect(find.text('No bridge set up yet'), findsOneWidget);
    expect(find.text('Set up a bridge'), findsOneWidget);
    // No identity card full of dashes, no reset section for a bridge that
    // does not exist, and no connection card for a link that never was.
    expect(find.text('YOUR BRIDGE'), findsNothing);
    expect(find.text('CONNECTION'), findsNothing);
    expect(find.text('RESET AND POWER'), findsNothing);
  });

  testWidgets('an unreachable bridge leads with when it was last seen', (
    tester,
  ) async {
    _tall(tester);
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.offline));
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: session,
          prefs: InMemoryBridgePrefs(
            lastBaseUrl: 'http://10.0.0.7',
            lastBridgeId: 'A4F2',
            lastSeenUnixMs:
                DateTime.now().millisecondsSinceEpoch - 12 * 60 * 1000,
          ),
          probe: _Probe(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // "Can't reach it" is a state; "can't reach it, last seen 12 minutes ago"
    // is information (§16.3).
    expect(find.text('Can’t reach your bridge'), findsOneWidget);
    expect(find.textContaining('Last seen 12 minutes ago'), findsOneWidget);
    // The rest of the page is still there, framed as history rather than now.
    expect(find.byKey(const Key('bridge-last-known')), findsOneWidget);
  });

  testWidgets('Bluetooth off is named before the bridge is blamed', (
    tester,
  ) async {
    _tall(tester);
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.offline));
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: session,
          prefs: InMemoryBridgePrefs(lastBaseUrl: 'http://10.0.0.7'),
          probe: _Probe(bluetooth: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bluetooth is off'), findsOneWidget);
    expect(find.text('Turn on Bluetooth'), findsOneWidget);
    // One situation, never two — the unreachable bridge is a consequence of
    // this one, not a second thing to triage.
    expect(find.byKey(const Key('situation-card')), findsOneWidget);
    expect(find.text('Can’t reach your bridge'), findsNothing);
  });

  testWidgets('a missing permission leads the page and names itself', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: ShellSession.seeded(snapshot: _snap(LinkKind.offline)),
          prefs: InMemoryBridgePrefs(lastBaseUrl: 'http://10.0.0.7'),
          probe: _Probe(permission: 'Nearby devices'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nearby devices is off'), findsOneWidget);
    expect(find.text('Allow Nearby devices'), findsOneWidget);
  });

  testWidgets('a bridge that answers as somebody else is never adopted', (
    tester,
  ) async {
    _tall(tester);
    final prefs = InMemoryBridgePrefs(
      lastBaseUrl: 'http://10.0.0.7',
      lastBridgeId: 'A4F2',
    );
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: ShellSession.seeded(
            snapshot: _snap(
              LinkKind.http,
              netMode: 'sta',
              address: 'http://10.0.0.7',
            ),
          ),
          prefs: prefs,
          transport: _StubTransport(deviceId: 'B811'),
          probe: _Probe(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This is a different bridge'), findsOneWidget);
    // Identity is the one thing the app will not settle on its own — it asks,
    // and until it is answered the phone still believes in the bridge it knew.
    expect(find.text('Use this bridge instead'), findsOneWidget);
    expect(prefs.lastBridgeId, 'A4F2');
  });

  testWidgets('a bridge seen hosting its own network says so, in plain words', (
    tester,
  ) async {
    _tall(tester);
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.offline));
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: session,
          prefs: InMemoryBridgePrefs(
            lastBaseUrl: 'http://10.0.0.7',
            lastBridgeId: 'A4F2',
          ),
          probe: _Probe(ap: 'SmokeBridge-A4F2'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Your bridge is hosting its own network'),
      findsOneWidget,
    );
    // The cause, not the mechanism. Nothing on this screen says "mDNS".
    expect(find.textContaining('mDNS'), findsNothing);
    expect(find.textContaining('SoftAP'), findsNothing);
  });

  testWidgets('a bridge the phone forgot is adopted and reported, not offered', (
    tester,
  ) async {
    _tall(tester);
    final prefs = InMemoryBridgePrefs();
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: ShellSession.seeded(),
          prefs: prefs,
          probe: _Probe(
            bonded: const BondedBridge(
              deviceId: 'AA:BB:CC',
              name: 'SmokeBridge-8274',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Acted on without being asked…
    expect(prefs.lastBleDeviceId, 'AA:BB:CC');
    // …and reported in the past tense, with no button to press.
    expect(find.text('Remembered SmokeBridge-8274 again'), findsOneWidget);
    expect(find.byKey(const Key('situation-action')), findsNothing);
  });

  testWidgets('a bridge that has met no base station leads with that', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: ShellSession.seeded(
            snapshot: _snap(
              LinkKind.http,
              netMode: 'sta',
              address: 'http://10.0.0.7',
            ),
          ),
          prefs: InMemoryBridgePrefs(
            lastBaseUrl: 'http://10.0.0.7',
            lastBridgeId: 'A4F2',
          ),
          transport: _StubTransport(paired: false),
          probe: _Probe(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your bridge hasn’t met your Smoke X yet'), findsOneWidget);
    // It is working — it just has nothing to listen to. The remedy is a hand
    // on the base station, and the copy says so.
    expect(find.text('Pair the base station'), findsOneWidget);
  });

  testWidgets('a healthy bridge leads with the connection, not a banner', (
    tester,
  ) async {
    _tall(tester);
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
          prefs: InMemoryBridgePrefs(
            lastBaseUrl: 'http://10.0.0.7',
            lastBridgeId: 'A4F2',
          ),
          transport: _StubTransport(),
          probe: _Probe(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('situation-card')), findsNothing);
    expect(find.text('CONNECTION'), findsOneWidget);
  });

  // ── the connection statement (A24.10) ───────────────────────────────

  testWidgets('connected over Bluetooth says so, with no fake address', (
    tester,
  ) async {
    _tall(tester);
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.ble));
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: session,
          prefs: InMemoryBridgePrefs(
            lastBaseUrl: 'http://10.0.0.7',
            lastBridgeId: 'A4F2',
          ),
          transport: _StubTransport(),
          probe: _Probe(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('bridge-connection-title')))
          .data,
      'Bluetooth',
    );
    // The remembered Wi-Fi address is NOT in use and must not read as if it
    // were — over Bluetooth there is no address.
    expect(find.text('none — via Bluetooth'), findsOneWidget);
    expect(find.byKey(const Key('bridge-last-known')), findsNothing);
  });

  testWidgets('hosted Wi-Fi names the mode and the address', (tester) async {
    _tall(tester);
    final session = ShellSession.seeded(
      snapshot: _snap(
        LinkKind.http,
        netMode: 'ap',
        address: 'http://192.168.4.1',
      ),
    );
    await tester.pumpWidget(
      _wrap(BridgeTab(session: session, transport: _StubTransport(), probe: _Probe())),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('bridge-connection-title')))
          .data,
      'The bridge’s own network',
    );
    expect(find.textContaining('192.168.4.1'), findsWidgets);
  });

  testWidgets('offline shows last-known framing and disables the verbs', (
    tester,
  ) async {
    _tall(tester);
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.offline));
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: session,
          prefs: InMemoryBridgePrefs(
            lastBaseUrl: 'http://10.0.0.7',
            lastBridgeId: 'A4F2',
          ),
          probe: _Probe(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Stale details are labelled as history, not presented as now.
    expect(find.byKey(const Key('bridge-last-known')), findsOneWidget);
    // The three verbs that need a link are disabled WITH their reason.
    expect(find.text('Needs a connection to the bridge.'), findsNWidgets(3));
  });

  // ── absent is not zero (§16.4 #9) ───────────────────────────────────

  testWidgets('a bridge that cannot report a battery says so, never 0%', (
    tester,
  ) async {
    _tall(tester);
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
          transport: _StubTransport(),
          probe: _Probe(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bridge-battery-why')), findsOneWidget);
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('storage over Bluetooth is absent with its reason, never 0%', (
    tester,
  ) async {
    _tall(tester);
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.ble));
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: session,
          prefs: InMemoryBridgePrefs(lastBridgeId: 'A4F2'),
          // The Bluetooth lane leaves storageFreePct at 0 because it cannot
          // know it — a bare 0 would read as "the bridge is full".
          transport: _StubTransport(storageFreePct: 0),
          probe: _Probe(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bridge-storage-why')), findsOneWidget);
    expect(find.text('0% free'), findsNothing);
  });

  // ── §E.1: the three choices ─────────────────────────────────────────

  testWidgets('the three connection choices are always offered', (
    tester,
  ) async {
    _tall(tester);
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.ble));
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: session,
          prefs: InMemoryBridgePrefs(lastBridgeId: 'A4F2'),
          transport: _StubTransport(),
          probe: _Probe(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mode-bluetooth')), findsOneWidget);
    expect(find.byKey(const Key('mode-bridgeHosts')), findsOneWidget);
    expect(find.byKey(const Key('mode-joinsYours')), findsOneWidget);
    // Exactly one is marked as live, and it is the one the link says.
    expect(find.byKey(const Key('mode-in-use')), findsOneWidget);
  });

  testWidgets('choosing another network opens the rollback wizard', (
    tester,
  ) async {
    _tall(tester);
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.ble));
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: session,
          prefs: InMemoryBridgePrefs(lastBridgeId: 'A4F2'),
          transport: _StubTransport(),
          probe: _Probe(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mode-joinsYours')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('netmode-title')), findsOneWidget);
    // The consequence is stated before anything is sent, and it says the
    // switch undoes itself.
    expect(find.byKey(const Key('netmode-cost')), findsOneWidget);
  });

  // ── §16.7: it holds at every width and text scale ───────────────────

  testWidgets('it lays out at 360 dp and at 200% text', (tester) async {
    for (final width in <double>[360, 600, 840]) {
      for (final scale in <double>[1.0, 2.0]) {
        tester.view.physicalSize = Size(width, 3200);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: SmokeTheme.dark,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: BridgeTab(
                  session: ShellSession.seeded(
                    snapshot: _snap(
                      LinkKind.http,
                      netMode: 'sta',
                      address: 'http://10.0.0.7',
                    ),
                  ),
                  prefs: InMemoryBridgePrefs(
                    lastBaseUrl: 'http://10.0.0.7',
                    lastBridgeId: 'A4F2',
                  ),
                  transport: _StubTransport(),
                  probe: _Probe(),
                  active: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflowed at ${width}dp at ${scale}x text',
        );
      }
    }
    addTearDown(tester.view.reset);
  });

  // ── A26: signal ─────────────────────────────────────────────────────

  testWidgets('Bluetooth shows the phone↔bridge hop it can actually measure', (
    tester,
  ) async {
    _tall(tester);
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.ble));
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: session,
          prefs: InMemoryBridgePrefs(lastBridgeId: 'A4F2'),
          probe: _Probe(),
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
      _tall(tester);
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
            prefs: InMemoryBridgePrefs(
              lastBaseUrl: 'http://10.0.0.7',
              lastBridgeId: 'A4F2',
            ),
            probe: _Probe(),
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
    _tall(tester);
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
          probe: _Probe(),
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
    _tall(tester);
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
          probe: _Probe(),
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
    _tall(tester);
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.ble));
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: session,
          prefs: InMemoryBridgePrefs(lastBridgeId: 'A4F2'),
          transport: _StubTransport(failSignal: true),
          probe: _Probe(),
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
    _tall(tester);
    final prefs = InMemoryBridgePrefs(lastBridgeId: 'A4F2');
    final stub = _StubTransport(signalValue: const LinkSignal(linkDbm: -66));

    Widget tab(ShellSession s) => _wrap(
      BridgeTab(
        session: s,
        prefs: prefs,
        transport: stub,
        active: false,
        probe: _Probe(),
      ),
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
    _tall(tester);
    final stub = _StubTransport(signalValue: const LinkSignal(linkDbm: -60));
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.ble));

    Widget tab({required bool active}) => _wrap(
      BridgeTab(
        session: session,
        transport: stub,
        active: active,
        probe: _Probe(),
      ),
    );

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
    // Deliberately the default viewport: RefreshIndicator fires on an
    // overscroll of a quarter of the container's height, so a tall surface
    // would need a fling nobody makes.
    final stub = _StubTransport(signalValue: const LinkSignal(linkDbm: -60));
    final session = ShellSession.seeded(snapshot: _snap(LinkKind.ble));
    await tester.pumpWidget(
      _wrap(
        BridgeTab(
          session: session,
          transport: stub,
          active: false,
          probe: _Probe(),
        ),
      ),
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
