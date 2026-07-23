/// A7.1/A7.3 — the ConnectionManager: the candidate race, manual-entry
/// pre-emption, reconnect backoff, and connectivity triggers (design 08
/// §8.4, 05 §5.8.5).
///
/// Pure logic over injected seams: candidate sources, the probe, the
/// clock, and the connectivity stream all arrive from outside. Production
/// wires the probe to `GET /status` via HttpTransport; tests wire fakes.
library;

import 'dart:async';

import 'discovery.dart';

/// Where a candidate address came from — the five §8.4 lanes.
enum ConnectionLane {
  manual, // user-typed IP: jumps the queue, always works
  cachedIp, // last-known address (~50 ms on the happy path)
  mdns, // _smokebridge._tcp browse
  mdnsName, // smokebridge.local
  apDefault, // 192.168.4.1 (the bridge's own AP)
  ble, // M3 — an honest stub reporting unavailable in M2
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
  const Connected(this.baseUrl, this.lane);
  final String baseUrl;
  final ConnectionLane lane;
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
    Delay? delay,
    Stream<void>? connectivityChanges,
  }) : _delay = delay ?? _realDelay,
       _connectivity = connectivityChanges ?? const Stream.empty();

  final ConnectionProbe probe;
  final CacheWriter writeCache;
  final String? cachedBaseUrl;
  final DiscoverySource? discovery;
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
        final ok = await probe(c.baseUrl);
        if (winner.isCompleted) {
          return;
        }
        if (ok) {
          winner.complete(Connected(c.baseUrl, c.lane));
          await writeCache(c.baseUrl);
        } else {
          winner.complete(const Offline());
        }
      }),
    );

    final lanes = <Future<ConnectionCandidate?>>[
      if (cachedBaseUrl != null)
        Future.value(
          ConnectionCandidate(cachedBaseUrl!, ConnectionLane.cachedIp),
        ),
      if (discovery != null)
        discovery!
            .discover()
            .map((b) => ConnectionCandidate(b.baseUrl, ConnectionLane.mdns))
            .first
            .then<ConnectionCandidate?>((c) => c)
            .catchError((Object _) => null),
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
      // BLE (M3): an honest stub — the lane exists, reports unavailable.
      Future.value(null),
    ];

    var pending = lanes.length;
    for (final f in lanes) {
      f
          .then((candidate) async {
            if (candidate == null || winner.isCompleted) {
              return;
            }
            final ok = await probe(candidate.baseUrl);
            if (ok && !winner.isCompleted) {
              winner.complete(Connected(candidate.baseUrl, candidate.lane));
              await writeCache(candidate.baseUrl);
            }
          })
          .whenComplete(() {
            pending--;
            if (pending == 0 && !winner.isCompleted) {
              winner.complete(const Offline());
            }
          });
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
