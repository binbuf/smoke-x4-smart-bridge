/// A24.7 — the connection supervisor (design 05 §5.7, the A6.7 fix).
///
/// The premium connection story the single-transport [BridgeSession] cannot
/// tell on its own:
///
///   * **lead with Bluetooth** so data shows the instant the app opens
///     (a bonded reconnect beats a Wi-Fi handshake), then
///   * **upgrade to Wi-Fi** in the background for full history / config / OTA,
///   * **hold the BLE link as a warm standby** beside the active Wi-Fi one, and
///   * **fail over to it silently** when Wi-Fi drops mid-cook, then climb back
///     when it returns.
///
/// One transport is ever *active* — the session reads exactly one, whose
/// [BridgeCapabilities] honestly report any degradation — and the supervisor
/// keeps the second link warm and swaps which is active. A composite transport
/// that merged two streams would have to lie about its capabilities; this does
/// not.
///
/// It is pure over injected seams — an [AppConnection] for the Wi-Fi race and
/// the one BLE handle, a [Delay], and an optional connectivity stream — so the
/// whole machine runs in the host suite with no radio, socket or channel.
library;

import 'dart:async';

import '../data/transport/bridge_transport.dart';
import '../data/transport/connection_manager.dart' show Delay, backoffDelay;
import '../features/dashboard/dashboard_snapshot.dart';
import 'connection.dart';

/// The active link and the health context the header chip renders.
/// [transport] null means offline — the cache still renders every screen.
class LiveLink {
  const LiveLink({
    required this.transport,
    required this.link,
    required this.address,
    this.degraded = false,
    this.upgrading = false,
    this.attempt = 0,
    this.closePrevious = false,
  });

  final BridgeTransport? transport;
  final LinkKind link;

  /// Empty on BLE/offline.
  final String address;

  /// On BLE while Wi-Fi would be the richer path — drives "full history needs
  /// Wi-Fi" and the chip's degraded styling.
  final bool degraded;

  /// A background Wi-Fi (re)connect is running — the chip shows a retry count.
  final bool upgrading;
  final int attempt;

  /// Whether the transport being replaced by this one should be **closed** once
  /// the session has switched off it (a failover to a dead link, or a
  /// user-chosen switch away from Wi-Fi) — as opposed to the upgrade case,
  /// where the supervisor keeps the old BLE link warm as the standby.
  final bool closePrevious;

  bool get offline => transport == null;
}

class ConnectionSupervisor {
  ConnectionSupervisor({
    required this.connection,
    Delay? delay,
    Stream<void>? connectivityChanges,
    this.bootTimeout = const Duration(seconds: 8),
  }) : _delay = delay ?? _realDelay,
       _connectivity = connectivityChanges ?? const Stream<void>.empty();

  final AppConnection connection;
  final Delay _delay;
  final Stream<void> _connectivity;
  final Duration bootTimeout;

  final _links = StreamController<LiveLink>.broadcast();
  Stream<LiveLink> get links => _links.stream;

  /// Cuts a backoff wait short. Fed by [retryNow] — the user pulling to
  /// refresh means *now*, not "in eight seconds when the timer fires".
  final _kick = StreamController<void>.broadcast();
  Future<bool>? _retryInFlight;

  BridgeTransport? _active;
  LinkKind _activeLink = LinkKind.offline;
  String _activeAddress = '';
  BridgeTransport? _standbyBle;
  bool _degraded = false;
  bool _upgrading = false;
  int _attempt = 0;
  bool _upgradeRunning = false;
  bool _disposed = false;

  /// When the user prefers Bluetooth: lead with it and do NOT auto-climb back
  /// to Wi-Fi (they chose it for battery / mobility). Set at boot from the
  /// preference and updated live by [applyPreference].
  bool _stayOnBle = false;

  bool get _holdBle => connection.prefs.holdBleWhenOnWifi;

  /// The current link, also readable synchronously by a late subscriber.
  LiveLink get current => LiveLink(
    transport: _active,
    link: _activeLink,
    address: _activeAddress,
    degraded: _degraded,
    upgrading: _upgrading,
    attempt: _attempt,
  );

  void _emit({bool closePrevious = false}) {
    if (!_links.isClosed) {
      _links.add(
        LiveLink(
          transport: _active,
          link: _activeLink,
          address: _activeAddress,
          degraded: _degraded,
          upgrading: _upgrading,
          attempt: _attempt,
          closePrevious: closePrevious,
        ),
      );
    }
  }

  /// Boot: open the one BLE handle and race Wi-Fi concurrently, then settle to
  /// the active/standby arrangement the preference asks for.
  Future<void> start() async {
    final preferred = connection.prefs.preferredTransport;
    _stayOnBle = preferred == PreferredTransport.ble;
    final bleF = connection.attemptBle();
    final httpF = connection.raceHttpUpgrade(timeout: bootTimeout);
    switch (preferred) {
      case PreferredTransport.wifi:
        await _startWifiFirst(httpF, bleF);
      case PreferredTransport.ble:
        await _startBleFirst(httpF, bleF);
      case PreferredTransport.auto:
        await _startAuto(httpF, bleF);
    }
  }

  /// auto: show whichever connects first (BLE is usually instant), then settle
  /// onto Wi-Fi with BLE as the warm standby.
  Future<void> _startAuto(
    Future<LaunchConnected?> httpF,
    Future<BridgeTransport?> bleF,
  ) async {
    var activeSet = false;

    final bleArrival = bleF.then((t) {
      if (t != null && !activeSet && !_disposed) {
        activeSet = true;
        _goActiveBle(t, degraded: true, upgrading: true);
      }
      return t;
    });

    final httpArrival = httpF.then((h) {
      if (h != null && !_disposed) {
        if (!activeSet) {
          activeSet = true;
          _goActiveHttp(h);
        } else if (_activeLink == LinkKind.ble) {
          _upgradeToHttp(h); // swap BLE → Wi-Fi, BLE becomes the standby
        } else {
          _closeQuietly(h.transport);
        }
      }
      return h;
    });

    final results = await Future.wait([bleArrival, httpArrival]);
    if (_disposed) {
      return;
    }
    final ble = results[0] as BridgeTransport?;

    if (!activeSet) {
      _goOffline();
      _startUpgradeLoop(); // keep trying to reach the bridge
      return;
    }
    if (_activeLink == LinkKind.http) {
      if (ble != null) {
        _setStandby(ble); // warm standby for instant failover
      }
    } else {
      _startUpgradeLoop(); // still on BLE — climb to Wi-Fi
    }
  }

  /// wifi: lead with Wi-Fi so there is no BLE→Wi-Fi flash at launch when the
  /// network is present; fall back to BLE only if Wi-Fi is unreachable.
  Future<void> _startWifiFirst(
    Future<LaunchConnected?> httpF,
    Future<BridgeTransport?> bleF,
  ) async {
    final http = await httpF;
    if (_disposed) {
      unawaited(bleF.then(_closeQuietly));
      if (http != null) {
        _closeQuietly(http.transport);
      }
      return;
    }
    if (http != null) {
      _goActiveHttp(http);
      final ble = await bleF;
      if (!_disposed && ble != null) {
        _setStandby(ble);
      } else if (ble != null) {
        _closeQuietly(ble);
      }
      return;
    }
    final ble = await bleF;
    if (_disposed) {
      if (ble != null) {
        _closeQuietly(ble);
      }
      return;
    }
    if (ble != null) {
      _goActiveBle(ble, degraded: true, upgrading: true);
    } else {
      _goOffline();
    }
    _startUpgradeLoop();
  }

  /// ble: the user asked to lead with — and stay on — Bluetooth (battery /
  /// mostly-mobile). No auto-upgrade; a Wi-Fi win at boot is closed, and the
  /// connection sheet is where they switch. If BLE is unavailable, Wi-Fi still
  /// serves rather than leaving them offline.
  Future<void> _startBleFirst(
    Future<LaunchConnected?> httpF,
    Future<BridgeTransport?> bleF,
  ) async {
    final ble = await bleF;
    if (_disposed) {
      if (ble != null) {
        _closeQuietly(ble);
      }
      unawaited(
        httpF.then((h) => h == null ? null : _closeQuietly(h.transport)),
      );
      return;
    }
    if (ble != null) {
      _goActiveBle(ble, degraded: false, upgrading: false);
      // Staying on BLE: discard a Wi-Fi win rather than open a link we will
      // not use.
      unawaited(
        httpF.then((h) => h == null ? null : _closeQuietly(h.transport)),
      );
      return;
    }
    final http = await httpF;
    if (_disposed) {
      if (http != null) {
        _closeQuietly(http.transport);
      }
      return;
    }
    if (http != null) {
      _goActiveHttp(http);
    } else {
      _goOffline();
      _startUpgradeLoop();
    }
  }

  /// The active link's push stream failed and a status read confirmed the
  /// bridge is unreachable (from [BridgeSession.onLinkLost]). Swap to the warm
  /// BLE standby **synchronously** so readings never stop, then climb back to
  /// Wi-Fi. Only Wi-Fi can be "lost" this way — a BLE-active session that loses
  /// its link has nowhere warmer to go and recovers through the loop.
  void reportLinkLost() {
    if (_disposed || _activeLink != LinkKind.http) {
      return;
    }
    final standby = _standbyBle;
    if (standby != null) {
      _standbyBle = null;
      // The Wi-Fi link is dead — hand it to the session to close once it has
      // switched off it (closePrevious).
      _goActiveBle(
        standby,
        degraded: true,
        upgrading: !_stayOnBle,
        closePrevious: true,
      );
      _startUpgradeLoop();
    } else {
      // No warm standby (hold-BLE off, or it never came up). Drop to offline
      // and recover both radios.
      _goOffline(closePrevious: true);
      _startRecovery();
    }
  }

  /// A26 — "try now", the connect half of pull-to-refresh (13 §13.5.2).
  ///
  /// The background loop already retries on a backoff; this is the user
  /// saying *now*. Two things it does that the loop alone does not:
  ///
  ///   * it cuts the current backoff wait short, and
  ///   * it brings **Bluetooth** up as well — [_upgradeLoop] only ever races
  ///     Wi-Fi, so an offline phone whose one path back is a bonded BLE link
  ///     would pull forever and never reconnect.
  ///
  /// Answers whether a link is up when it finishes, because a gesture has to
  /// be able to report failure. Concurrent pulls share one attempt: pulling
  /// three times costs one round of radio work, not three.
  Future<bool> retryNow({Duration timeout = const Duration(seconds: 12)}) {
    if (_disposed) {
      return Future<bool>.value(false);
    }
    if (_active != null) {
      return Future<bool>.value(true);
    }
    return _retryInFlight ??= _retryOnce(timeout).whenComplete(() {
      _retryInFlight = null;
    });
  }

  Future<bool> _retryOnce(Duration timeout) async {
    // Subscribe BEFORE kicking anything off, so a link that comes up on the
    // very next microtask is not missed between the kick and the wait.
    final settled = _links.stream.firstWhere((l) => !l.offline);
    // Detached immediately: if the timeout below wins, this future is
    // abandoned and its "No element" on stream close must not surface as an
    // unhandled zone error (the same trap A24.11 fixed on the GATT results).
    unawaited(settled.then((_) {}, onError: (Object _) {}));
    _startUpgradeLoop();
    if (!_kick.isClosed) {
      _kick.add(null);
    }
    _startRecovery();
    try {
      await settled.timeout(timeout);
    } on Object {
      return false;
    }
    return !_disposed && _active != null;
  }

  void _goActiveHttp(LaunchConnected http, {bool closePrevious = false}) {
    _active = http.transport;
    _activeLink = LinkKind.http;
    _activeAddress = http.address;
    _degraded = false;
    _upgrading = false;
    _attempt = 0;
    _emit(closePrevious: closePrevious);
  }

  void _goActiveBle(
    BridgeTransport ble, {
    required bool degraded,
    required bool upgrading,
    bool closePrevious = false,
  }) {
    _active = ble;
    _activeLink = LinkKind.ble;
    _activeAddress = '';
    _degraded = degraded;
    _upgrading = upgrading;
    _attempt = 0;
    _emit(closePrevious: closePrevious);
  }

  void _goOffline({bool closePrevious = false}) {
    _active = null;
    _activeLink = LinkKind.offline;
    _activeAddress = '';
    _degraded = false;
    _emit(closePrevious: closePrevious);
  }

  /// Promote a freshly-won Wi-Fi link to active; the BLE we were on becomes the
  /// warm standby (or is closed when hold-BLE is off).
  void _upgradeToHttp(LaunchConnected http) {
    final old = _active;
    final wasBle = _activeLink == LinkKind.ble;
    _active = http.transport;
    _activeLink = LinkKind.http;
    _activeAddress = http.address;
    _degraded = false;
    _upgrading = false;
    _attempt = 0;
    if (wasBle && old != null) {
      _setStandby(old);
    }
    _emit();
  }

  void _setStandby(BridgeTransport ble) {
    if (_holdBle) {
      if (_standbyBle != null && !identical(_standbyBle, ble)) {
        _closeQuietly(_standbyBle!);
      }
      _standbyBle = ble;
    } else {
      _standbyBle = null;
      _closeQuietly(ble);
    }
  }

  void _startUpgradeLoop() {
    if (_upgradeRunning || _disposed) {
      return;
    }
    // The user prefers Bluetooth: a live BLE link is the destination, not a
    // waypoint — don't climb to Wi-Fi behind their back. (Offline still tries
    // everything, so a total drop still recovers.)
    if (_stayOnBle && _activeLink == LinkKind.ble) {
      return;
    }
    _upgradeRunning = true;
    unawaited(_upgradeLoop());
  }

  /// The user chose a transport in the connection sheet. The written
  /// preference governs the next boot; this applies the safe, instant part
  /// live: choosing Wi-Fi/Auto climbs off BLE now, choosing Bluetooth stops
  /// the auto-climb so the next connect (or the current one, on its next drop)
  /// leads with BLE. Switching a healthy Wi-Fi link *down* to BLE is left to
  /// the next reconnect rather than torn down mid-cook.
  void applyPreference(PreferredTransport t) {
    if (_disposed) {
      return;
    }
    switch (t) {
      case PreferredTransport.wifi:
      case PreferredTransport.auto:
        _stayOnBle = false;
        if (_activeLink == LinkKind.ble) {
          _startUpgradeLoop();
        }
      case PreferredTransport.ble:
        _stayOnBle = true;
        // Respect an explicit "use Bluetooth now": swap down off Wi-Fi
        // immediately rather than waiting for the next drop. This is the
        // pocket-at-a-competition case — the user knows the network is about
        // to be useless and says so.
        if (_activeLink == LinkKind.http) {
          _switchToBleNow();
        }
    }
  }

  /// Move the active path to Bluetooth right now (05 §5.7). Uses the warm
  /// standby if there is one — instant — otherwise opens a BLE link first. The
  /// dead-weight Wi-Fi link is closed once the session switches off it.
  void _switchToBleNow() {
    final standby = _standbyBle;
    if (standby != null) {
      _standbyBle = null;
      _goActiveBle(
        standby,
        degraded: true,
        upgrading: false,
        closePrevious: true,
      );
      return;
    }
    unawaited(() async {
      final ble = await connection.attemptBle();
      if (_disposed || ble == null) {
        if (ble != null) {
          _closeQuietly(ble);
        }
        return;
      }
      if (_activeLink == LinkKind.http) {
        _goActiveBle(
          ble,
          degraded: true,
          upgrading: false,
          closePrevious: true,
        );
      } else {
        // The link changed under us while BLE was connecting — keep it warm.
        _setStandby(ble);
      }
    }());
  }

  /// The user toggled "keep Bluetooth as backup". Off drops the warm standby
  /// now (saving the bridge ~1–3 mA); on warms one when on Wi-Fi so the next
  /// drop still fails over instantly.
  void applyHoldBle(bool hold) {
    if (_disposed) {
      return;
    }
    if (!hold) {
      final standby = _standbyBle;
      _standbyBle = null;
      if (standby != null) {
        _closeQuietly(standby);
      }
    } else if (_activeLink == LinkKind.http && _standbyBle == null) {
      unawaited(_warmStandby());
    }
  }

  Future<void> _upgradeLoop() async {
    var attempt = 0;
    try {
      while (!_disposed && _activeLink != LinkKind.http) {
        _upgrading = true;
        _attempt = attempt;
        _emit();
        final http = await connection.raceHttpUpgrade();
        if (_disposed) {
          if (http != null) {
            _closeQuietly(http.transport);
          }
          return;
        }
        if (http != null) {
          if (_activeLink == LinkKind.ble) {
            _upgradeToHttp(http);
          } else {
            // Recovered from offline: go Wi-Fi, then warm a BLE standby so the
            // next drop fails over instantly.
            _goActiveHttp(http);
            unawaited(_warmStandby());
          }
          return;
        }
        attempt++;
        await _backoffWaitOrKick(attempt);
      }
    } finally {
      _upgradeRunning = false;
      if (!_disposed && _upgrading) {
        _upgrading = false;
        _emit();
      }
    }
  }

  /// After a Wi-Fi loss with no standby: bring BLE up for a live-but-degraded
  /// view, and keep climbing back to Wi-Fi.
  void _startRecovery() {
    unawaited(() async {
      final ble = await connection.attemptBle();
      if (_disposed) {
        if (ble != null) {
          _closeQuietly(ble);
        }
        return;
      }
      if (ble != null && _activeLink != LinkKind.http) {
        _goActiveBle(ble, degraded: true, upgrading: true);
      } else if (ble != null) {
        _setStandby(ble);
      }
      _startUpgradeLoop();
    }());
  }

  Future<void> _warmStandby() async {
    if (_disposed || !_holdBle || _standbyBle != null) {
      return;
    }
    final ble = await connection.attemptBle();
    if (_disposed || ble == null) {
      if (ble != null) {
        _closeQuietly(ble);
      }
      return;
    }
    if (_activeLink == LinkKind.http) {
      _setStandby(ble);
    } else {
      _closeQuietly(ble);
    }
  }

  Future<void> _backoffWaitOrKick(int attempt) async {
    final kick = Completer<void>();
    void wake(void _) {
      if (!kick.isCompleted) {
        kick.complete();
      }
    }

    // Two things cut the wait short: the phone's network changed under us,
    // and the user asked for it (retryNow).
    final subs = [_connectivity.listen(wake), _kick.stream.listen(wake)];
    await Future.any<void>([_delay(backoffDelay(attempt)), kick.future]);
    for (final s in subs) {
      await s.cancel();
    }
  }

  /// Fire-and-forget close for the many spots that discard a losing/dropped
  /// transport mid-flow and must not block on it.
  void _closeQuietly(BridgeTransport? t) {
    if (t == null) {
      return;
    }
    unawaited(_closeAwait(t));
  }

  Future<void> _closeAwait(BridgeTransport? t) async {
    if (t == null) {
      return;
    }
    try {
      await t.close();
    } on Object {
      // A transport that will not close is already gone.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    final active = _active;
    final standby = _standbyBle;
    _active = null;
    _standbyBle = null;
    // Await the closes so a caller that disposes and then inspects (or exits)
    // sees the sockets actually released.
    await _closeAwait(active);
    await _closeAwait(standby);
    await _kick.close();
    await _links.close();
  }

  static Future<void> _realDelay(Duration d) => Future<void>.delayed(d);
}
