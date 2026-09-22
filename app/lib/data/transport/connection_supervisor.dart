/// N15.6 — the connection supervisor.
///
/// BLE leads → Wi-Fi upgrades in the background → BLE is held warm → silent
/// failover → climb back. Exactly one transport is **active** (carrying data)
/// at a time; a warm BLE link is open but idle, ready to take over in a
/// heartbeat (I9).
///
/// The supervisor owns transport lifecycle. `BridgeSession` owns what flows
/// over the winner.
library;

import 'dart:async';

import 'bridge_transport.dart';
import 'connection_manager.dart';

/// The user's transport preference. `auto` prefers Wi-Fi when it is there but
/// never at the cost of a working BLE link.
enum TransportPreference { auto, wifi, ble }

class SupervisorState {
  const SupervisorState({
    required this.activeKind,
    required this.activeLabel,
    required this.bleWarm,
    required this.upgrading,
  });

  final TransportKind? activeKind;
  final String? activeLabel;

  /// A BLE link is open and idle, ready for failover.
  final bool bleWarm;

  /// A background Wi-Fi upgrade is in flight.
  final bool upgrading;

  bool get connected => activeKind != null;
}

/// N15.6 — the exactly-one-active transport owner.
class ConnectionSupervisor {
  ConnectionSupervisor({
    required this.manager,
    required this.factory,
    this.preferred = TransportPreference.auto,
    this.holdBle = true,
    this.probeTimeout = const Duration(seconds: 4),
  });

  final ConnectionManager manager;
  final TransportFactory factory;
  final TransportPreference preferred;

  /// Keep BLE open while Wi-Fi carries data, so failover is instant.
  final bool holdBle;
  final Duration probeTimeout;

  BridgeTransport? _active;
  BridgeTransport? _warmBle;
  bool _upgrading = false;
  bool _disposed = false;

  final StreamController<SupervisorState> _stateController =
      StreamController<SupervisorState>.broadcast();

  BridgeTransport? get active => _active;
  bool get bleWarm => _warmBle != null;
  Stream<SupervisorState> get state => _stateController.stream;

  SupervisorState get current => SupervisorState(
    activeKind: _active?.kind,
    activeLabel: _active?.label,
    bleWarm: _warmBle != null,
    upgrading: _upgrading,
  );

  void _emit() {
    if (!_stateController.isClosed) {
      _stateController.add(current);
    }
  }

  /// Bring the link up.
  ///
  /// `ble` preference or `auto` starts on BLE (it pairs without a network);
  /// `wifi` goes straight to the HTTP lanes. `auto` then tries to upgrade to
  /// Wi-Fi and keeps BLE warm.
  Future<BridgeTransport?> start({bool upgrade = true}) async {
    if (preferred == TransportPreference.wifi) {
      _active = await manager.connect();
      _emit();
      if (_active != null) {
        return _active;
      }
    }
    if (preferred != TransportPreference.wifi) {
      final ble = await _openBle();
      if (ble != null) {
        _active = ble;
        _emit();
        if (preferred == TransportPreference.auto && upgrade) {
          await upgradeToWifi();
        }
        return _active;
      }
    }
    // No BLE (or Wi-Fi-preferred): fall back to the HTTP race.
    _active = await manager.connect();
    _emit();
    return _active;
  }

  Future<BridgeTransport?> _openBle() async {
    final ble = await factory.openBle();
    if (ble == null) {
      return null;
    }
    try {
      await ble.status().timeout(probeTimeout);
      return ble;
    } catch (_) {
      await ble.close();
      return null;
    }
  }

  /// Try to promote a Wi-Fi transport above the active BLE one. Returns true
  /// when it did. The old BLE transport is kept warm unless [holdBle] is off.
  Future<bool> upgradeToWifi() async {
    if (_disposed) {
      return false;
    }
    if (_active?.kind == TransportKind.http) {
      return false;
    }
    _upgrading = true;
    _emit();
    BridgeTransport? winner;
    try {
      winner = await manager.raceOnce(includeBle: false);
      if (winner != null) {
        final previous = _active;
        _active = winner;
        if (previous != null && previous.kind == TransportKind.ble) {
          if (holdBle) {
            _warmBle = previous;
          } else {
            await previous.close();
          }
        }
      }
    } finally {
      _upgrading = false;
      _emit();
    }
    return winner != null;
  }

  /// A cheap liveness check: a real `status()` read, not a socket flag.
  Future<bool> verifyActive() async {
    final active = _active;
    if (active == null) {
      return false;
    }
    try {
      await active.status().timeout(probeTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The active link failed. Fall back to the warm BLE link, else climb back
  /// through the HTTP lanes. Returns the new active transport, or null.
  Future<BridgeTransport?> failover() async {
    final failed = _active;
    _active = null;
    if (failed != null) {
      await failed.close();
    }
    if (_warmBle != null) {
      final ble = _warmBle;
      _warmBle = null;
      try {
        await ble!.status().timeout(probeTimeout);
        _active = ble;
        _emit();
        return _active;
      } catch (_) {
        await ble!.close();
      }
    }
    if (preferred != TransportPreference.wifi) {
      final ble = await _openBle();
      if (ble != null) {
        _active = ble;
        _emit();
        return _active;
      }
    }
    _active = await manager.connect();
    _emit();
    return _active;
  }

  /// Drop everything (the bridge keeps recording — I2).
  Future<void> disconnect() async {
    final active = _active;
    final warm = _warmBle;
    _active = null;
    _warmBle = null;
    _emit();
    await active?.close();
    if (warm != null && warm != active) {
      await warm.close();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _stateController.close();
  }

  /// The real HTTP factory helper: a supervisor over real transports.
  static ConnectionSupervisor http({
    required ConnectionManager manager,
    TransportPreference preferred = TransportPreference.auto,
    bool holdBle = true,
  }) => ConnectionSupervisor(
    manager: manager,
    factory: manager.factory,
    preferred: preferred,
    holdBle: holdBle,
  );
}

/// Convenience: build the default HTTP-only supervisor for a host.
///
/// [bleOpener] is the N15.3 seam: when the platform build supplies an opener,
/// `auto` leads on BLE and upgrades to Wi-Fi in the background. Without one the
/// BLE lane is simply a miss.
ConnectionSupervisor httpSupervisor({
  required String host,
  int? port,
  String? token,
  Future<BridgeTransport?> Function()? bleOpener,
  TransportPreference preferred = TransportPreference.auto,
}) {
  final factory = HttpTransportFactory(
    port: port,
    token: token,
    bleOpener: bleOpener,
  );
  final manager = ConnectionManager(factory: factory, manualBaseUrl: host);
  return ConnectionSupervisor(
    manager: manager,
    factory: factory,
    preferred: preferred,
  );
}
