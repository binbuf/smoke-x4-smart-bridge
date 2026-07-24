/// A9.5 — the launch flow (design 08 §8.4, 05 §5.7).
///
/// The composition root the placeholder home screen has stood in for
/// since A1.2. On launch: read the remembered bridge (A7.5), race every
/// lane (A7.1/A7.3, with A7.4's real discovery and A6.5's BLE fallback),
/// and land on the dashboard — or on the wizard when no bridge has ever
/// been provisioned.
///
/// **Offline is a first-class outcome, not an error.** The cache serves
/// every historical screen with the bridge unplugged; that has been the
/// acceptance test for the whole data layer since A4.4, and a launch that
/// shows an error page instead is a regression against it.
///
/// Everything platform-shaped arrives injected, so the whole state machine
/// runs in the host suite with no radio, no network and no channel.
library;

import 'dart:async';

import '../data/prefs/bridge_prefs.dart';
import '../data/transport/bridge_transport.dart';
import '../data/transport/connection_manager.dart';
import '../data/transport/discovery.dart';
import '../features/dashboard/dashboard_snapshot.dart';

sealed class LaunchState {
  const LaunchState();
}

/// No bridge has ever been provisioned — straight to the wizard.
class LaunchNeedsOnboarding extends LaunchState {
  const LaunchNeedsOnboarding();
}

class LaunchConnecting extends LaunchState {
  const LaunchConnecting({this.attempt = 0});
  final int attempt;
}

class LaunchConnected extends LaunchState {
  const LaunchConnected({
    required this.transport,
    required this.link,
    required this.address,
  });

  final BridgeTransport transport;
  final LinkKind link;

  /// Empty on the BLE lane — there is no address to speak to (A6.5).
  final String address;
}

/// Every lane failed. The cache still renders; that is the point.
class LaunchOffline extends LaunchState {
  const LaunchOffline();
}

/// Builds a transport for a winning base URL. Injected so the host suite
/// never opens a socket.
typedef TransportFactory = BridgeTransport Function(String baseUrl);

class AppConnection {
  AppConnection({
    required this.prefs,
    required this.transportFor,
    this.discovery,
    this.bleAttempt,
    this.probe,
    Delay? delay,
  }) : _delay = delay ?? _realDelay;

  final BridgePrefs prefs;
  final TransportFactory transportFor;
  final DiscoverySource? discovery;
  final BleAttempt? bleAttempt;

  /// Defaults to "build a transport for this URL and ask it for status".
  /// Injected so a test can decide which addresses answer.
  final ConnectionProbe? probe;
  final Delay _delay;

  final _states = StreamController<LaunchState>.broadcast();
  LaunchState _state = const LaunchConnecting();
  ConnectionManager? _manager;

  Stream<LaunchState> get states => _states.stream;
  LaunchState get state => _state;

  void _emit(LaunchState s) {
    _state = s;
    if (!_states.isClosed) {
      _states.add(s);
    }
  }

  /// The escape hatch (05 §5.8, 08 §8.4): a user-typed address pre-empts
  /// any race in flight. A12.3's manual-entry field calls this.
  void enterManual(String baseUrl) => _manager?.enterManual(baseUrl);

  Future<LaunchState> start({
    Duration raceTimeout = const Duration(seconds: 8),
  }) async {
    if (prefs.lastBaseUrl == null && bleAttempt == null) {
      // Nothing remembered and no radio to fall back on: this phone has
      // never met a bridge.
      _emit(const LaunchNeedsOnboarding());
      return _state;
    }
    _emit(const LaunchConnecting());
    return _race(raceTimeout: raceTimeout);
  }

  Future<LaunchState> _race({required Duration raceTimeout}) async {
    final mgr = ConnectionManager(
      cachedBaseUrl: prefs.lastBaseUrl,
      discovery: discovery,
      bleAttempt: bleAttempt,
      delay: _delay,
      probe: probe ?? _defaultProbe,
      // A7.5, finally wired: this is the callback that has been a no-op
      // at every production call site since A7.1.
      writeCache: (baseUrl) => prefs.recordConnection(baseUrl),
    );
    _manager = mgr;
    final outcome = await mgr.race(timeout: raceTimeout);
    switch (outcome) {
      case Connected(:final lane, :final baseUrl, :final transport):
        _emit(
          LaunchConnected(
            transport: transport ?? transportFor(baseUrl),
            link: lane == ConnectionLane.ble ? LinkKind.ble : LinkKind.http,
            address: baseUrl,
          ),
        );
      case Offline():
        _emit(const LaunchOffline());
    }
    return _state;
  }

  /// A dropped link re-RACES rather than redialling: the bridge may have
  /// changed mode or address while we were away (A7.3).
  Future<LaunchState> reconnect({
    int maxAttempts = 6,
    Duration raceTimeout = const Duration(seconds: 8),
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      _emit(LaunchConnecting(attempt: attempt));
      final s = await _race(raceTimeout: raceTimeout);
      if (s is LaunchConnected) {
        return s;
      }
      await _delay(backoffDelay(attempt));
    }
    _emit(const LaunchOffline());
    return _state;
  }

  Future<bool> _defaultProbe(String baseUrl) async {
    final t = transportFor(baseUrl);
    try {
      final s = await t.status();
      return s.deviceId.isNotEmpty;
    } on Object {
      return false;
    } finally {
      await t.close();
    }
  }

  Future<void> dispose() async {
    await _states.close();
  }

  static Future<void> _realDelay(Duration d) => Future<void>.delayed(d);
}
