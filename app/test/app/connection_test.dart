/// A9.5 — the launch flow.
///
/// Five outcomes, none of which needs a radio, a network or a platform
/// channel: never-provisioned, cached-and-reachable, cached-and-
/// unreachable, BLE-only, and a mid-session drop that reconnects.
///
/// The one that is easiest to get wrong is the third: **offline is a
/// first-class outcome, not an error.** The cache still serves every
/// historical screen, which has been the acceptance test for the data
/// layer since A4.4.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/connection.dart';
import 'package:smoke_bridge/data/prefs/bridge_prefs.dart';
import 'package:smoke_bridge/data/transport/connection_manager.dart';
import 'package:smoke_bridge/data/transport/discovery.dart';
import 'package:smoke_bridge/data/transport/mock_transport.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';

import '../data/records_parity_test.dart' show repoRoot;

class _FakeDiscovery implements DiscoverySource {
  _FakeDiscovery(this.bridges);
  final List<DiscoveredBridge> bridges;

  @override
  Stream<DiscoveredBridge> discover() => Stream.fromIterable(bridges);
}

/// Time, compressed 100x rather than removed.
///
/// The M2 race-test lesson, recorded in A6.5: a fake delay that completes
/// *instantly* makes the race's timeout backstop win before any probe has
/// answered, and every test then asserts against Offline. The timeout
/// must be held — just not for eight real seconds.
Future<void> _fastDelay(Duration d) =>
    Future<void>.delayed(Duration(milliseconds: d.inSeconds * 10));

void main() {
  late MockTransport transport;

  setUp(() {
    transport = MockTransport.fromSmkBytes(
      File('${repoRoot()}/protocol/fixtures/brisket-18h.smk').readAsBytesSync(),
    );
  });

  AppConnection make({
    BridgePrefs? prefs,
    ConnectionProbe? probe,
    DiscoverySource? discovery,
    BleAttempt? bleAttempt,
  }) => AppConnection(
    prefs: prefs ?? InMemoryBridgePrefs(),
    transportFor: (_) => transport,
    probe: probe ?? (_) async => false,
    discovery: discovery,
    bleAttempt: bleAttempt,
    delay: _fastDelay,
  );

  test('never provisioned goes straight to the wizard', () async {
    final state = await make().start();
    expect(state, isA<LaunchNeedsOnboarding>());
  });

  test('never provisioned still onboards when a BLE radio exists', () async {
    // Board-found on the A8.4 sitting. The test above passes `bleAttempt:
    // null`, which is the one case production never has — `bootstrap.dart`
    // always wires a lane. So a fresh install raced, lost, and showed
    // "Cannot reach the bridge" with no way to add one; clearing app data
    // on the bench reproduced it every time.
    final state = await make(
      bleAttempt: () async => null, // radio present, nothing found
    ).start();
    expect(state, isA<LaunchNeedsOnboarding>());
  });

  test('a remembered bridge that is unreachable stays offline', () async {
    // The counterpart: onboarding must NOT swallow a known bridge simply
    // being off, or a user with a provisioned bridge gets sent back
    // through the wizard every time the grill is unplugged.
    final prefs = InMemoryBridgePrefs(lastBaseUrl: 'http://10.50.50.38');
    final state = await make(
      prefs: prefs,
      bleAttempt: () async => null,
    ).start();
    expect(state, isA<LaunchOffline>());
  });

  test('cached and reachable wins on the cached lane, first try', () async {
    final probed = <String>[];
    final prefs = InMemoryBridgePrefs(lastBaseUrl: 'http://10.50.50.38');
    final state = await make(
      prefs: prefs,
      probe: (url) async {
        probed.add(url);
        return url == 'http://10.50.50.38';
      },
    ).start();
    expect(state, isA<LaunchConnected>());
    final c = state as LaunchConnected;
    expect(c.link, LinkKind.http);
    expect(c.address, 'http://10.50.50.38');
    expect(probed.first, 'http://10.50.50.38');
  });

  test('a win writes the cache — the callback A7.1 left empty', () async {
    final prefs = InMemoryBridgePrefs(lastBaseUrl: 'http://10.50.50.38');
    await make(prefs: prefs, probe: (_) async => true).start();
    expect(prefs.lastBaseUrl, 'http://10.50.50.38');
    expect(prefs.lastSeenUnixMs, isNotNull);
  });

  test('discovery fills the lane A7.2 left empty', () async {
    final prefs = InMemoryBridgePrefs(lastBaseUrl: 'http://stale');
    final state = await make(
      prefs: prefs,
      discovery: _FakeDiscovery(const [
        DiscoveredBridge(host: '10.0.0.9', port: 80, id: '8274'),
      ]),
      probe: (url) async => url == 'http://10.0.0.9',
    ).start();
    expect((state as LaunchConnected).address, 'http://10.0.0.9');
    expect(prefs.lastBaseUrl, 'http://10.0.0.9');
  });

  test('cached and unreachable is offline, not an error', () async {
    final state = await make(
      prefs: InMemoryBridgePrefs(lastBaseUrl: 'http://10.50.50.38'),
      probe: (_) async => false,
    ).start();
    expect(state, isA<LaunchOffline>());
  });

  test('BLE-only wins the degraded lane, and leaves the cache alone', () async {
    final prefs = InMemoryBridgePrefs(lastBaseUrl: 'http://10.50.50.38');
    final state = await make(
      prefs: prefs,
      probe: (_) async => false,
      bleAttempt: () async => transport,
    ).start();
    final c = state as LaunchConnected;
    expect(c.link, LinkKind.ble);
    expect(c.address, isEmpty);
    // Blanking the cached IP would break the next launch's fastest lane.
    expect(prefs.lastBaseUrl, 'http://10.50.50.38');
  });

  test('a phone that has never met a bridge but has BLE still races', () async {
    final state = await make(
      probe: (_) async => false,
      bleAttempt: () async => transport,
    ).start();
    expect(state, isA<LaunchConnected>());
  });

  test('manual entry pre-empts the race in flight', () async {
    final connection = make(
      prefs: InMemoryBridgePrefs(lastBaseUrl: 'http://stale'),
      probe: (url) async {
        if (url == 'http://stale') {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return false;
        }
        return url == 'http://192.168.1.99';
      },
    );
    final race = connection.start();
    connection.enterManual('http://192.168.1.99');
    final state = await race;
    expect((state as LaunchConnected).address, 'http://192.168.1.99');
  });

  test('a mid-session drop re-races and reconnects', () async {
    var reachable = false;
    final connection = make(
      prefs: InMemoryBridgePrefs(lastBaseUrl: 'http://10.50.50.38'),
      probe: (_) async => reachable,
    );
    final seen = <LaunchState>[];
    connection.states.listen(seen.add);
    final future = connection.reconnect(maxAttempts: 4);
    // It comes back on the third attempt.
    Timer.run(() => reachable = true);
    final state = await future;
    expect(state, isA<LaunchConnected>());
    expect(seen.whereType<LaunchConnecting>(), isNotEmpty);
  });

  test(
    'reconnect gives up into offline rather than spinning forever',
    () async {
      final connection = make(
        prefs: InMemoryBridgePrefs(lastBaseUrl: 'http://10.50.50.38'),
        probe: (_) async => false,
      );
      expect(await connection.reconnect(maxAttempts: 2), isA<LaunchOffline>());
    },
  );

  test('the state stream mirrors what start() returned', () async {
    final connection = make(
      prefs: InMemoryBridgePrefs(lastBaseUrl: 'http://10.50.50.38'),
      probe: (_) async => true,
    );
    final seen = <LaunchState>[];
    connection.states.listen(seen.add);
    await connection.start();
    await Future<void>.delayed(Duration.zero);
    expect(seen.last, isA<LaunchConnected>());
    expect(connection.state, seen.last);
    await connection.dispose();
  });
}
