/// A7.1/A7.3 — the ConnectionManager: the candidate race, manual-entry
/// pre-emption, reconnect backoff, and connectivity triggers (design 08
/// §8.4, 05 §5.8.5).
///
/// Pure logic over injected seams: candidate sources, the probe, the
/// clock, and the connectivity stream all arrive from outside. Production
/// wires the probe to `GET /status` via HttpTransport; tests wire fakes.
library;

import 'dart:async';

import 'bridge_transport.dart';
import 'discovery.dart';

/// Where a candidate address came from — the five §8.4 lanes.
enum ConnectionLane {
  manual, // user-typed IP: jumps the queue, always works
  cachedIp, // last-known address (~50 ms on the happy path)
  mdns, // _smokebridge._tcp browse
  mdnsName, // smokebridge.local
  apDefault, // 192.168.4.1 (the bridge's own AP)
  ble, // A6.5 — the fallback, tried only after every HTTP lane fails
}

class ConnectionCandidate {
  const ConnectionCandidate(this.baseUrl, this.lane);
  final String baseUrl;
  final ConnectionLane lane;
}

/// The race's outcome: connected via a lane, or offline-from-cache.
sealed class ConnectionOutcome {
  const ConnectionOutcome();
}

class Connected extends ConnectionOutcome {
  const Connected(this.baseUrl, this.lane, {this.transport});

  /// The HTTP base URL. **Empty for a BLE win** — there is no address to
  /// speak to; callers switch on [lane] or use [transport].
  final String baseUrl;
  final ConnectionLane lane;

  /// Non-null only on the BLE lane (A6.5): a live transport whose
  /// capabilities honestly report the degradation, which is what drives
  /// the chart's "full history needs Wi-Fi" notice rather than an error.
  final BridgeTransport? transport;

  bool get isDegraded => lane == ConnectionLane.ble;
}

class Offline extends ConnectionOutcome {
  const Offline();
}

/// True when the base URL answers `GET /status` with 200 (and, per §8.4,
/// the id matches when one is expected). Injected; must not throw.
typedef ConnectionProbe = Future<bool> Function(String baseUrl);

/// Persists a success so the next launch's cachedIp lane is warm.
typedef CacheWriter = Future<void> Function(String baseUrl);

/// Injected so tests drive time; production passes Future.delayed.
typedef Delay = Future<void> Function(Duration d);

/// A6.5 — the BLE lane. Returns a connected [BridgeTransport], or null if
/// BLE is unavailable (no bonded bridge in range, Bluetooth off, the user
/// never onboarded). Injected, so the race needs no radio in tests.
typedef BleAttempt = Future<BridgeTransport?> Function();

/// §8.4: 1, 2, 4, 8, 15, 30 s, capped at 30.
const backoffLadderS = [1, 2, 4, 8, 15, 30];

Duration backoffDelay(int attempt) {
  final i = attempt < 0
      ? 0
      : (attempt >= backoffLadderS.length
            ? backoffLadderS.length - 1
            : attempt);
  return Duration(seconds: backoffLadderS[i]);
}

class ConnectionManager {
  ConnectionManager({
    required this.probe,
    required this.writeCache,
    this.cachedBaseUrl,
    this.discovery,
    this.bleAttempt,
    Delay? delay,
    Stream<void>? connectivityChanges,
  }) : _delay = delay ?? _realDelay,
       _connectivity = connectivityChanges ?? const Stream.empty();

  final ConnectionProbe probe;
  final CacheWriter writeCache;
  final String? cachedBaseUrl;
  final DiscoverySource? discovery;

  /// Null when the app has no BLE lane to offer (never onboarded, or the
  /// user turned the persistent BLE link off — 05 §5.7).
  final BleAttempt? bleAttempt;
  final Delay _delay;
  final Stream<void> _connectivity;

  final _manual = Completer<ConnectionCandidate>();

  /// The escape hatch (05 §5.8's promise): a user-typed address pre-empts
  /// any race in flight and is probed immediately, alone.
  void enterManual(String baseUrl) {
    if (!_manual.isCompleted) {
      _manual.complete(ConnectionCandidate(baseUrl, ConnectionLane.manual));
    }
  }

  /// One race: fan out every available lane, first successful probe wins.
  /// All lanes exhausted → Offline (deterministic); the timeout is only a
  /// backstop against lanes that hang.
  Future<ConnectionOutcome> race({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final winner = Completer<ConnectionOutcome>();

    // Manual entry watches from OUTSIDE the lane count: it pre-empts a
    // race in flight, and its failure reports directly — the escape
    // hatch must not share a failure mode with what it escapes from.
    unawaited(
      _manual.future.then((c) async {
        final ok = await _guardedProbe(c.baseUrl);
        if (winner.isCompleted) {
          return;
        }
        if (ok) {
          winner.complete(Connected(c.baseUrl, c.lane));
          await _guardedWriteCache(c.baseUrl);
        } else {
          winner.complete(const Offline());
        }
      }),
    );

    final lanes = _httpLanes();

    // A6.5: BLE is a FALLBACK, not a competitor. It engages only once
    // every HTTP lane has failed — a bridge reachable over Wi-Fi must
    // never be demoted to a degraded transport just because BLE answered
    // first. (Which it would: bonded reconnects are fast.)
    var pending = lanes.length;
    for (final f in lanes) {
      unawaited(
        f
            .then((candidate) async {
              if (candidate == null || winner.isCompleted) {
                return;
              }
              final ok = await _guardedProbe(candidate.baseUrl);
              if (ok && !winner.isCompleted) {
                winner.complete(Connected(candidate.baseUrl, candidate.lane));
                await _guardedWriteCache(candidate.baseUrl);
              }
            })
            .whenComplete(() {
              pending--;
              if (pending != 0 || winner.isCompleted) {
                return;
              }
              unawaited(
                _tryBle().then((outcome) {
                  if (!winner.isCompleted) {
                    winner.complete(outcome);
                  }
                }),
              );
            })
            // Stale-address hardening (A9.5): a synchronous throw from
            // building or closing a probe transport must not escape to the
            // zone as an uncaught error — it is just a lane that lost.
            .catchError((Object _) {}),
      );
    }

    unawaited(
      _delay(timeout).then((_) {
        if (!winner.isCompleted) {
          winner.complete(const Offline());
        }
      }),
    );
    return winner.future;
  }

  /// The Wi-Fi half of the race, with no BLE lane at all: the first HTTP
  /// lane to answer `GET /status` 200 wins, or `null` when every lane fails
  /// or the timeout fires. Manual entry still pre-empts.
  ///
  /// Two callers, both from [ConnectionSupervisor] (05 §5.7): the initial
  /// Wi-Fi attempt raced *beside* a single warm BLE link — so a bridge on
  /// Wi-Fi is never demoted, yet BLE shows data the instant it reconnects —
  /// and the background *upgrade* race that climbs back onto Wi-Fi after a
  /// failover. BLE is deliberately absent here because the supervisor owns
  /// the one BLE handle; racing it a second time would open a duplicate
  /// link only to discard it.
  Future<Connected?> raceHttpOnly({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final winner = Completer<Connected?>();

    unawaited(
      _manual.future.then((c) async {
        final ok = await _guardedProbe(c.baseUrl);
        if (winner.isCompleted) {
          return;
        }
        // The escape hatch ends the race whichever way it resolves.
        winner.complete(ok ? Connected(c.baseUrl, c.lane) : null);
        if (ok) {
          await _guardedWriteCache(c.baseUrl);
        }
      }),
    );

    final lanes = _httpLanes();
    var pending = lanes.length;
    for (final f in lanes) {
      unawaited(
        f
            .then((candidate) async {
              if (candidate == null || winner.isCompleted) {
                return;
              }
              final ok = await _guardedProbe(candidate.baseUrl);
              if (ok && !winner.isCompleted) {
                winner.complete(Connected(candidate.baseUrl, candidate.lane));
                await _guardedWriteCache(candidate.baseUrl);
              }
            })
            .whenComplete(() {
              pending--;
              if (pending == 0 && !winner.isCompleted) {
                winner.complete(null);
              }
            })
            .catchError((Object _) {}),
      );
    }

    unawaited(
      _delay(timeout).then((_) {
        if (!winner.isCompleted) {
          winner.complete(null);
        }
      }),
    );
    return winner.future;
  }

  /// The four HTTP candidate lanes, in the §8.4 order. Shared by [race] and
  /// [raceHttpOnly]. The discovery lane is guarded so a browse that throws
  /// or yields nothing degrades to "no candidate", never an escaped error.
  List<Future<ConnectionCandidate?>> _httpLanes() =>
      <Future<ConnectionCandidate?>>[
        if (cachedBaseUrl != null)
          Future.value(
            ConnectionCandidate(cachedBaseUrl!, ConnectionLane.cachedIp),
          ),
        if (discovery != null) _discoveryLane(),
        Future.value(
          const ConnectionCandidate(
            'http://smokebridge.local',
            ConnectionLane.mdnsName,
          ),
        ),
        Future.value(
          const ConnectionCandidate(
            'http://192.168.4.1',
            ConnectionLane.apDefault,
          ),
        ),
      ];

  Future<ConnectionCandidate?> _discoveryLane() async {
    try {
      return await discovery!
          .discover()
          .map((b) => ConnectionCandidate(b.baseUrl, ConnectionLane.mdns))
          .first;
    } on Object {
      // An empty browse (`.first` on no elements) or a channel error both
      // mean "mDNS found nothing" — a silent degrade, not a failure.
      return null;
    }
  }

  /// The injected [probe] "must not throw" by contract — but a stale cached
  /// address building a transport that throws synchronously (A9.5, the
  /// board-found `SocketException` after an AP→STA move) must be a lost
  /// lane, not an uncaught error. Belt to that brace.
  Future<bool> _guardedProbe(String baseUrl) async {
    try {
      return await probe(baseUrl);
    } on Object {
      return false;
    }
  }

  /// A cache write failing must never take down a race that already won.
  Future<void> _guardedWriteCache(String baseUrl) async {
    try {
      await writeCache(baseUrl);
    } on Object {
      // Losing the fast lane next launch is a slower start, not a bug.
    }
  }

  /// The BLE fallback. Never throws: an unavailable radio, an unbonded
  /// bridge, and a user who turned BLE off all mean the same thing to the
  /// race — no win, fall through to offline-from-cache.
  Future<ConnectionOutcome> _tryBle() async {
    final attempt = bleAttempt;
    if (attempt == null) {
      return const Offline();
    }
    try {
      final transport = await attempt();
      if (transport == null) {
        return const Offline();
      }
      // No writeCache: there is no address to remember, and overwriting
      // the cached IP with an empty string would break the next launch's
      // fastest lane.
      return Connected('', ConnectionLane.ble, transport: transport);
    } on Object {
      return const Offline();
    }
  }

  /// A7.3: re-race on a backoff ladder until connected. A connectivity
  /// change short-circuits the wait — walking back into Wi-Fi range
  /// reconnects without user action. A dropped WebSocket calls this (a
  /// re-RACE, not a redial: the bridge may have changed mode or address).
  Future<Connected> reconnect({
    Duration raceTimeout = const Duration(seconds: 8),
  }) async {
    var attempt = 0;
    while (true) {
      final outcome = await race(timeout: raceTimeout);
      if (outcome is Connected) {
        return outcome;
      }
      final kick = Completer<void>();
      final sub = _connectivity.listen((_) {
        if (!kick.isCompleted) {
          kick.complete();
        }
      });
      await Future.any<void>([_delay(backoffDelay(attempt)), kick.future]);
      await sub.cancel();
      attempt++;
    }
  }

  static Future<void> _realDelay(Duration d) => Future<void>.delayed(d);
}
