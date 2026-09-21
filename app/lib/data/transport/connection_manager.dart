/// N15.5 — the six-lane connection race.
///
/// The lanes, in priority order (research notes §7):
///
///   manual → cachedIp → mdns → mdnsName → apDefault → ble
///
/// A lane **wins only on a real `GET /status` 200**: opening a socket is not a
/// connection. Failed attempts are closed immediately so exactly one transport
/// survives the race. The whole pass retries with the documented backoff
/// (1/2/4/8/15/30 s) when no lane answers.
///
/// **Deviation:** the lanes are attempted in priority order rather than all at
/// once. The observable contract — a transport whose `status()` returned 200
/// wins — is identical, and the order makes the result deterministic, which is
/// what a real radio needs anyway (one attempt at a time avoids paying for
/// concurrent sockets to an address that is not there).
library;

import 'dart:async';

import 'bridge_transport.dart';
import 'http_transport.dart';

/// Where a lane came from. Used for copy and for persistence decisions.
enum ConnectionLaneKind { manual, cachedIp, mdns, mdnsName, apDefault, ble }

class ConnectionLane {
  const ConnectionLane({required this.kind, this.host});

  final ConnectionLaneKind kind;

  /// Null for the BLE lane (it has no host).
  final String? host;

  String get id =>
      kind == ConnectionLaneKind.ble ? 'ble' : '${kind.name}:${host ?? ''}';

  String get copy => switch (kind) {
    ConnectionLaneKind.manual => 'the address you entered',
    ConnectionLaneKind.cachedIp => 'the last known address',
    ConnectionLaneKind.mdns => 'smokebridge.local',
    ConnectionLaneKind.mdnsName => '${host ?? 'the bridge'}.local',
    ConnectionLaneKind.apDefault => 'the bridge hotspot (192.168.4.1)',
    ConnectionLaneKind.ble => 'Bluetooth',
  };
}

enum ConnectionAttemptOutcome { probing, won, failed }

class ConnectionAttempt {
  const ConnectionAttempt({
    required this.lane,
    required this.outcome,
    this.error,
  });

  final ConnectionLane lane;
  final ConnectionAttemptOutcome outcome;
  final Object? error;
}

/// Opens transports for the manager. A `null` return means the lane cannot be
/// built (e.g. no BLE radio); the manager treats it as a miss.
abstract interface class TransportFactory {
  Future<BridgeTransport?> openHttp(String host);
  Future<BridgeTransport?> openBle();
}

/// The production factory: real HTTP transports; BLE is supplied by the
/// platform build (null until the BLE transport lands — N15.3).
class HttpTransportFactory implements TransportFactory {
  HttpTransportFactory({
    this.port,
    this.token,
    this.scheme = 'http',
    this.timeout = const Duration(seconds: 6),
    this.bleOpener,
  });

  final int? port;
  final String? token;
  final String scheme;
  final Duration timeout;
  final Future<BridgeTransport?> Function()? bleOpener;

  @override
  Future<BridgeTransport?> openHttp(String host) async => HttpTransport(
    baseUrl: '$scheme://$host${port == null ? '' : ':$port'}',
    token: token,
    timeout: timeout,
  );

  @override
  Future<BridgeTransport?> openBle() async => bleOpener?.call();
}

/// The backoff schedule, exactly as documented.
const List<Duration> kConnectionBackoff = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 15),
  Duration(seconds: 30),
];

class ConnectionManager {
  ConnectionManager({
    required this.factory,
    String? manualBaseUrl,
    this.cachedIp,
    this.bridgeLocalName,
    this.apDefaultHost = '192.168.4.1',
    this.statusTimeout = const Duration(seconds: 4),
    this.backoff = kConnectionBackoff,
    this.nowMs,
    this.sleep,
  }) : manualHost = _hostOf(manualBaseUrl);

  final TransportFactory factory;

  /// The user-entered URL/host, if any (lane 1).
  final String? manualHost;

  /// The last IP that worked (lane 2).
  final String? cachedIp;

  /// `SmokeBridge-A4F2` → lane 4 tries `SmokeBridge-A4F2.local`.
  final String? bridgeLocalName;

  final String apDefaultHost;
  final Duration statusTimeout;
  final List<Duration> backoff;
  final int Function()? nowMs;

  /// Injection point so tests do not wait real backoff.
  final Future<void> Function(Duration)? sleep;

  final List<ConnectionAttempt> _attempts = [];
  final StreamController<ConnectionAttempt> _attemptController =
      StreamController<ConnectionAttempt>.broadcast();

  /// The race's attempt log (for the connect sheet's copy).
  List<ConnectionAttempt> get attempts => List.unmodifiable(_attempts);
  Stream<ConnectionAttempt> get attemptStream => _attemptController.stream;

  /// The lanes in priority order.
  List<ConnectionLane> get lanes => [
    if (manualHost != null && manualHost!.isNotEmpty)
      ConnectionLane(kind: ConnectionLaneKind.manual, host: manualHost),
    if (cachedIp != null && cachedIp!.isNotEmpty)
      ConnectionLane(kind: ConnectionLaneKind.cachedIp, host: cachedIp),
    const ConnectionLane(
      kind: ConnectionLaneKind.mdns,
      host: 'smokebridge.local',
    ),
    if (bridgeLocalName != null && bridgeLocalName!.isNotEmpty)
      ConnectionLane(
        kind: ConnectionLaneKind.mdnsName,
        host: '$bridgeLocalName.local',
      ),
    ConnectionLane(kind: ConnectionLaneKind.apDefault, host: apDefaultHost),
    const ConnectionLane(kind: ConnectionLaneKind.ble),
  ];

  Future<void> _record(ConnectionAttempt attempt) async {
    _attempts.add(attempt);
    if (!_attemptController.isClosed) {
      _attemptController.add(attempt);
    }
  }

  /// Runs the race once: returns the first transport whose `status()` answered,
  /// or null when every lane missed. [includeBle] lets a caller skip the BLE
  /// lane (e.g. when the phone's radio is known off).
  Future<BridgeTransport?> raceOnce({bool includeBle = true}) async {
    for (final lane in lanes) {
      if (lane.kind == ConnectionLaneKind.ble && !includeBle) {
        continue;
      }
      final transport = await _open(lane);
      if (transport == null) {
        await _record(
          ConnectionAttempt(
            lane: lane,
            outcome: ConnectionAttemptOutcome.failed,
          ),
        );
        continue;
      }
      await _record(
        ConnectionAttempt(
          lane: lane,
          outcome: ConnectionAttemptOutcome.probing,
        ),
      );
      try {
        await transport.status().timeout(statusTimeout);
        await _record(
          ConnectionAttempt(lane: lane, outcome: ConnectionAttemptOutcome.won),
        );
        return transport;
      } catch (e) {
        await transport.close();
        await _record(
          ConnectionAttempt(
            lane: lane,
            outcome: ConnectionAttemptOutcome.failed,
            error: e,
          ),
        );
      }
    }
    return null;
  }

  Future<BridgeTransport?> _open(ConnectionLane lane) async {
    try {
      return lane.kind == ConnectionLaneKind.ble
          ? await factory.openBle()
          : await factory.openHttp(lane.host!);
    } catch (_) {
      return null;
    }
  }

  /// Runs the race with backoff until a lane wins or [maxPasses] is spent.
  ///
  /// `maxPasses` defaults to `backoff.length + 1` (six spaced retries).
  Future<BridgeTransport?> connect({
    bool includeBle = true,
    int? maxPasses,
  }) async {
    _attempts.clear();
    final passes = maxPasses ?? backoff.length + 1;
    final sleeper = sleep ?? Future<void>.delayed;
    for (var pass = 0; pass < passes; pass++) {
      final winner = await raceOnce(includeBle: includeBle);
      if (winner != null) {
        return winner;
      }
      if (pass < passes - 1 && pass < backoff.length) {
        await sleeper(backoff[pass]);
      }
    }
    return null;
  }

  /// Release the attempt stream.
  Future<void> dispose() => _attemptController.close();

  static String? _hostOf(String? baseUrl) {
    if (baseUrl == null || baseUrl.trim().isEmpty) {
      return null;
    }
    var text = baseUrl.trim();
    if (!text.contains('://')) {
      text = 'http://$text';
    }
    final uri = Uri.tryParse(text);
    return uri?.host.isEmpty ?? true ? text : uri!.host;
  }
}
