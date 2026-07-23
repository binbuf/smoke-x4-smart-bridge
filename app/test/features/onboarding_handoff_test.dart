/// A8.3 — handoff verification and the recovery path: the M3 exit gate,
/// rehearsed entirely off the board (design 05 §5.7, 08 §8.4).
///
/// This is an INTEGRATION test in the sense that matters: the fake
/// peripheral drives a real [BleTransport], and the handoff's verification
/// step runs the real [ConnectionManager] race against a real
/// [HttpTransport]. Nothing between the wizard and `GET /status` is
/// stubbed — the only fakes are the two ends, the radio and the wire.
///
/// **Deviation from the task's letter, recorded rather than glossed:**
/// A8.3 says to wire the fake peripheral to a spawned `tools/sim`. That is
/// not runnable here. `tools/sim` is a member of the root Dart pub
/// workspace; the app is a standalone Flutter package, and CI's app job
/// only runs `flutter pub get` inside `app/`, so `dart run sim` would not
/// resolve in the environment this suite has to pass in. Spawning a
/// process from `flutter test` on Windows adds a second failure mode for
/// no extra coverage. What the sim would have contributed — a real HTTP
/// server answering `/status` — is contributed instead by the same
/// `HttpClientAdapter` seam the A5 suite verifies `HttpTransport` through,
/// so the code under test is identical and the transport is exercised for
/// real. `tools/sim` still earns its keep in the A5/A15 suites, where the
/// app package boundary is not in the way.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dto/records.g.dart';
import 'package:smoke_bridge/data/transport/ble_gatt.dart';
import 'package:smoke_bridge/data/transport/ble_transport.dart';
import 'package:smoke_bridge/data/transport/connection_manager.dart';
import 'package:smoke_bridge/data/transport/http_transport.dart';
import 'package:smoke_bridge/features/onboarding/wizard.dart';
import 'package:smoke_bridge/platform/network_binder.dart';

import '../data/fake_peripheral.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

WifiScanResult _ap(String ssid) =>
    WifiScanResult(rssi: -55, auth: 3, channel: 6, ssidRaw: _b(ssid));

NetStatus _net(NetState state, {NetMode mode = NetMode.sta}) => NetStatus(
  mode: mode.wire,
  state: state.wire,
  ip: state == NetState.up ? [192, 168, 1, 42] : [0, 0, 0, 0],
  ssidRaw: _b('Backyard'),
  hostRaw: _b('smokebridge'),
);

/// The wire end: answers `/status` only at the addresses in [reachable].
/// Everything else 404s, exactly as an unreachable bridge would.
class Wire implements HttpClientAdapter {
  final reachable = <String>{};
  final probed = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final base = '${options.uri.scheme}://${options.uri.host}';
    probed.add(base);
    if (!reachable.contains(base)) {
      return ResponseBody.fromString(
        '{"error":{"code":"not_found"}}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      '{"device":{"id":"A4F2","model":"heltec-v3","fw":"1.0.0"},'
      '"pairing":{"paired":true,"num_probes":4}}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The production verifier: race the ConnectionManager, and require a real
/// `/status` 200 through a real HttpTransport before declaring victory.
/// `net_status: up` means the radio associated — it does not mean this
/// phone can reach it, and that gap is the entire reason this step exists.
HandoffVerifier verifierOver(Wire wire) {
  return (ipHint) async {
    final mgr = ConnectionManager(
      // The address the bridge just reported over BLE — the lane that
      // actually works on a phone (see the wizard's HandoffVerifier doc).
      cachedBaseUrl: ipHint == null ? null : 'http://$ipHint',
      probe: (baseUrl) async {
        final dio = Dio(BaseOptions(baseUrl: baseUrl))
          ..httpClientAdapter = wire;
        final t = HttpTransport(baseUrl, dio: dio);
        try {
          final s = await t.status();
          return s.deviceId.isNotEmpty;
        } on Object {
          return false;
        } finally {
          await t.close();
        }
      },
      writeCache: (_) async {},
      // Hold the race's own backstop: an instantly-completing timeout
      // would race the probes (the M2 lesson, same as the A7 suite).
      delay: (_) => Completer<void>().future,
    );
    final outcome = await mgr.race();
    return outcome is Connected && outcome.lane != ConnectionLane.ble
        ? outcome.baseUrl
        : null;
  };
}

class _Clock {
  final asked = <Duration>[];
  final _gates = <Completer<void>>[];
  Future<void> call(Duration d) {
    asked.add(d);
    final c = Completer<void>();
    _gates.add(c);
    return c.future;
  }

  void fire() {
    for (final c in _gates) {
      if (!c.isCompleted) {
        c.complete();
      }
    }
    _gates.clear();
  }
}

class _Harness {
  _Harness({FakePeripheralConfig? config}) {
    fake = FakePeripheral(config: config);
    transport = BleTransport(fake);
    wizard = OnboardingWizard(
      transport: transport,
      client: fake,
      verify: verifierOver(wire),
      // A14.1's real binder double: joinAp must both join AND bind, or
      // the phone talks to 192.168.4.1 over cellular and nothing works.
      joinAp: (ssid, psk) async {
        try {
          await binder.joinAp(ssid, psk);
          return binder.state == BinderState.bound;
        } on Object {
          return false;
        }
      },
      nowMs: () => 1774051200000,
      delay: clock.call,
    );
  }

  final wire = Wire();
  final binder = FakeNetworkBinder();
  final clock = _Clock();
  late final FakePeripheral fake;
  late final BleTransport transport;
  late final OnboardingWizard wizard;

  Future<void> bondAndReachMode() async {
    await wizard.startScan();
    await wizard.select((wizard.state as WizardFind).found.single);
  }

  Future<void> dispose() async {
    await wizard.dispose();
    await transport.close();
    await binder.dispose();
  }
}

void main() {
  test('success: STA up, HTTP verified, wizard done', () async {
    final h = _Harness(
      config: FakePeripheralConfig(scanResults: [_ap('Backyard')]),
    );
    h.wire.reachable.add('http://192.168.1.42'); // the IP net_status gave
    await h.bondAndReachMode();
    await h.wizard.chooseMode(BridgeMode.joined);
    h.wizard.pickNetwork('Backyard');
    await h.wizard.submitCredentials('hunter2boo');

    expect(h.wizard.state, isA<WizardDone>());
    expect((h.wizard.state as WizardDone).baseUrl, isNotEmpty);
    // A real request was made before declaring victory.
    expect(h.wire.probed, isNotEmpty);
    await h.dispose();
  });

  test('wrong password → recover → succeed, hardware never touched', () async {
    // The M3 exit gate's second clause, end to end.
    final h = _Harness(
      config: FakePeripheralConfig(
        scanResults: [_ap('Backyard')],
        netStatusScript: [_net(NetState.connecting), _net(NetState.failed)],
      ),
    );
    h.wire.reachable.add('http://192.168.1.42');
    await h.bondAndReachMode();
    await h.wizard.chooseMode(BridgeMode.joined);
    h.wizard.pickNetwork('Backyard');
    await h.wizard.submitCredentials('WRONG');

    expect(h.wizard.state, isA<WizardRecover>());
    expect((h.wizard.state as WizardRecover).reason, RecoveryReason.wifiFailed);
    // Nothing was probed: `net_status: failed` short-circuits before the
    // HTTP step, so the user is told the real reason rather than a
    // generic "could not reach the bridge".
    expect(h.wire.probed, isEmpty);
    // The link that carries the fix is still up.
    expect(h.fake.connectionState, BleConnectionState.connected);

    // Correct it over that same link. No walk to the smoker.
    h.fake.config = h.fake.config.copyWith(netStatusScript: const []);
    await h.wizard.retryCredentials();
    expect(
      (h.wizard.state as WizardPickNetwork).error,
      contains('Incorrect password'),
    );
    h.wizard.pickNetwork('Backyard');
    await h.wizard.submitCredentials('hunter2boo');

    expect(h.wizard.state, isA<WizardDone>());
    expect(h.wire.probed, isNotEmpty);
    await h.dispose();
  });

  test('unreachable STA → revert to AP → verified on 192.168.4.1', () async {
    final h = _Harness(
      config: FakePeripheralConfig(scanResults: [_ap('Backyard')]),
    );
    // The bridge joins the network, but this phone cannot reach it —
    // guest network, client isolation, a different VLAN. Nothing answers.
    await h.bondAndReachMode();
    await h.wizard.chooseMode(BridgeMode.joined);
    h.wizard.pickNetwork('Backyard');
    await h.wizard.submitCredentials('hunter2boo');

    expect(h.wizard.state, isA<WizardRecover>());
    expect(
      (h.wizard.state as WizardRecover).reason,
      RecoveryReason.httpUnreachable,
    );
    expect(h.wire.probed, isNotEmpty, reason: 'we did try');

    // One wifi_config{mode: AP} write, then join the bridge's own network
    // with the PSK it just handed us.
    h.wire.reachable.add('http://192.168.4.1');
    await h.wizard.revertToHosting();

    expect(h.wizard.state, isA<WizardDone>());
    expect((h.wizard.state as WizardDone).mode, BridgeMode.hosted);
    expect((h.wizard.state as WizardDone).baseUrl, 'http://192.168.4.1');
    expect(h.wizard.apPsk, 'Gk7mR2xQpT');
    // And the phone is BOUND to that network, not merely joined — the
    // A14.1 trap: joined-but-unbound sends requests out over cellular.
    expect(h.binder.calls, contains('joinAp:SmokeBridge-A4F2'));
    expect(h.binder.state, BinderState.bound);
    await h.dispose();
  });

  test('the 20 s budget is what ends an unanswered handoff', () async {
    // A bridge that accepts the config and then goes quiet. Without the
    // budget this is a spinner forever; with it, it is the recovery
    // screen, which is a place the user can act from (§5.7).
    final h = _Harness(
      config: const FakePeripheralConfig(silentAfterConfig: true),
    );
    await h.bondAndReachMode();
    final pending = h.wizard.chooseMode(BridgeMode.hosted);
    await Future<void>.delayed(Duration.zero);
    expect(h.clock.asked, contains(kHandoffBudget));
    h.clock.fire();
    await pending;
    expect(h.wizard.state, isA<WizardRecover>());
    await h.dispose();
  });
}
