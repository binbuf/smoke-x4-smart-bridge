/// A8 — the composition root for onboarding: the one place the real
/// radio, the real binder, and the real HTTP race are wired to the state
/// machine.
///
/// Everything it assembles is tested against fakes elsewhere; what lives
/// here is only the wiring, which is why it is a widget and not a library.
/// M4 replaces the entry point (the dashboard routes here when no bridge
/// has been provisioned) but not this composition.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/transport/ble_gatt_fbp.dart';
import '../../data/transport/ble_transport.dart';
import '../../data/transport/connection_manager.dart';
import '../../data/transport/http_transport.dart';
import '../../platform/network_binder.dart';
import 'onboarding_screens.dart';
import 'wizard.dart';

class OnboardingRoute extends StatefulWidget {
  const OnboardingRoute({super.key});

  @override
  State<OnboardingRoute> createState() => _OnboardingRouteState();
}

class _OnboardingRouteState extends State<OnboardingRoute> {
  late final FlutterBlueGattClient _client;
  late final BleTransport _transport;
  late final ChannelNetworkBinder _binder;
  late final OnboardingWizard _wizard;

  @override
  void initState() {
    super.initState();
    _client = FlutterBlueGattClient();
    _transport = BleTransport(_client);
    _binder = ChannelNetworkBinder();
    _wizard = OnboardingWizard(
      transport: _transport,
      client: _client,
      verify: _verifyOverHttp,
      joinAp: _joinAp,
    );
    unawaited(_wizard.startScan());
  }

  /// The §5.7 verification step: `net_status: up` means the radio
  /// associated, not that this phone can reach the bridge. Race the real
  /// ConnectionManager and require a real `/status` 200 — the BLE lane is
  /// excluded here on purpose, because "reachable over BLE" is what we
  /// are trying to graduate FROM.
  Future<String?> _verifyOverHttp(String? ipHint) async {
    if (kDebugMode) {
      debugPrint('VERIFY start hint=$ipHint');
    }
    final mgr = ConnectionManager(
      // The address the bridge just gave us over BLE goes in as the
      // known-address lane. Without it the race has only
      // `smokebridge.local` (which Android's resolver cannot answer) and
      // `192.168.4.1` (the AP we just left) — i.e. nothing.
      cachedBaseUrl: ipHint == null ? null : 'http://$ipHint',
      probe: (baseUrl) async {
        final t = HttpTransport(baseUrl);
        try {
          final s = await t.status();
          if (kDebugMode) {
            debugPrint('VERIFY $baseUrl -> OK id=${s.deviceId}');
          }
          return s.deviceId.isNotEmpty;
        } on Object catch (e) {
          if (kDebugMode) {
            debugPrint('VERIFY $baseUrl -> $e');
          }
          return false;
        } finally {
          await t.close();
        }
      },
      writeCache: (_) async {},
    );
    final outcome = await mgr.race();
    return outcome is Connected && outcome.lane != ConnectionLane.ble
        ? outcome.baseUrl
        : null;
  }

  /// A14.1's binder. The join must also BIND, or Android leaves the
  /// default route on cellular and every request to 192.168.4.1 vanishes
  /// (05 §5.8.1) — the trap the whole binder exists for.
  Future<bool> _joinAp(String ssid, String psk) async {
    try {
      await _binder.joinAp(ssid, psk);
      return _binder.state == BinderState.bound;
    } on Object {
      return false;
    }
  }

  @override
  void dispose() {
    unawaited(_wizard.dispose());
    unawaited(_transport.close());
    unawaited(_binder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Onboarding does NOT navigate itself. It used to jump home the
    // instant it finished, which meant the success screen existed for a
    // single frame and the user landed on a placeholder reading "Not
    // connected" — success and failure looked identical. The user leaves
    // when they say so.
    return OnboardingScreen(
      wizard: _wizard,
      onFinished: () {
        if (context.mounted) {
          context.go(AppRoutes.home);
        }
      },
    );
  }
}
