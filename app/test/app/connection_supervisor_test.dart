/// A24.7 — the connection supervisor (05 §5.7, the A6.7 fix).
///
/// Five outcomes, none needing a radio or a socket: lead-with-BLE then upgrade
/// to Wi-Fi, degraded-BLE when Wi-Fi is down, the silent failover to the warm
/// standby and the climb back, and the two non-auto preferences (lead-with-
/// Wi-Fi, stay-on-Bluetooth).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/connection.dart';
import 'package:smoke_bridge/app/connection_supervisor.dart';
import 'package:smoke_bridge/data/prefs/bridge_prefs.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';

/// A transport the supervisor only ever holds and closes — it never reads
/// state off it (that is the session's job), so a close flag is all it needs.
class _FakeTransport implements BridgeTransport {
  _FakeTransport(this.tag);
  final String tag;
  bool closed = false;

  @override
  BridgeCapabilities get capabilities => BridgeCapabilities(
    fullHistory: tag == 'http',
    historyPreview: tag == 'ble',
  );

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Time, compressed rather than removed: the upgrade/backoff loop yields to the
/// event loop each iteration instead of busy-spinning.
Future<void> _fast(Duration _) =>
    Future<void>.delayed(const Duration(milliseconds: 1));

void main() {
  AppConnection makeConn({
    required bool wifiUp,
    _FakeTransport? ble,
    PreferredTransport preferred = PreferredTransport.auto,
    bool holdBle = true,
    Future<bool> Function(String)? probe,
  }) {
    final prefs = InMemoryBridgePrefs(
      lastBaseUrl: 'http://10.0.0.7',
      preferredTransport: preferred,
      holdBleWhenOnWifi: holdBle,
    );
    return AppConnection(
      prefs: prefs,
      transportFor: (_) => _FakeTransport('http'),
      probe: probe ?? (_) async => wifiUp,
      bleAttempt: ble == null ? null : () async => ble,
      delay: _fast,
    );
  }

  ConnectionSupervisor supervise(AppConnection conn) =>
      ConnectionSupervisor(connection: conn, delay: _fast);

  test(
    'auto, Wi-Fi up: leads with Bluetooth, then upgrades to Wi-Fi',
    () async {
      final ble = _FakeTransport('ble');
      final sup = supervise(makeConn(wifiUp: true, ble: ble));
      final links = <LiveLink>[];
      sup.links.listen(links.add);

      await sup.start();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Bluetooth showed first (instant data), Wi-Fi took over as the active
      // path, and the BLE link is kept warm rather than closed.
      expect(links.map((l) => l.link), contains(LinkKind.ble));
      expect(links.last.link, LinkKind.http);
      expect(links.last.degraded, isFalse);
      expect(ble.closed, isFalse);

      await sup.dispose();
    },
  );

  test('auto, Wi-Fi down: settles on a degraded Bluetooth link', () async {
    final ble = _FakeTransport('ble');
    final sup = supervise(makeConn(wifiUp: false, ble: ble));
    final links = <LiveLink>[];
    sup.links.listen(links.add);

    await sup.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final bleLinks = links.where((l) => l.link == LinkKind.ble).toList();
    expect(bleLinks, isNotEmpty);
    expect(bleLinks.last.degraded, isTrue);
    // It never falsely claims Wi-Fi.
    expect(links.every((l) => l.link != LinkKind.http), isTrue);

    await sup.dispose();
  });

  test(
    'failover: a Wi-Fi loss swaps to the warm standby, then climbs back',
    () async {
      final ble = _FakeTransport('ble');
      final sup = supervise(makeConn(wifiUp: true, ble: ble));
      final links = <LiveLink>[];
      sup.links.listen(links.add);

      await sup.start();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(links.last.link, LinkKind.http, reason: 'settled on Wi-Fi first');

      links.clear();
      sup.reportLinkLost();
      // The swap is synchronous+silent: the very next emitted link is Bluetooth.
      await Future<void>.delayed(Duration.zero);
      expect(links.first.link, LinkKind.ble);
      expect(links.first.degraded, isTrue);

      // Wi-Fi is still reachable, so the background upgrade climbs back onto it.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(links.last.link, LinkKind.http);
      expect(ble.closed, isFalse, reason: 'BLE returns to standby, not closed');

      await sup.dispose();
    },
  );

  test('preferred = Wi-Fi: leads with Wi-Fi, no Bluetooth flash', () async {
    final ble = _FakeTransport('ble');
    final sup = supervise(
      makeConn(wifiUp: true, ble: ble, preferred: PreferredTransport.wifi),
    );
    final links = <LiveLink>[];
    sup.links.listen(links.add);

    await sup.start();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    // The very first active link is Wi-Fi — BLE never became active.
    expect(links.first.link, LinkKind.http);
    expect(links.last.link, LinkKind.http);

    await sup.dispose();
  });

  test(
    'preferred = Bluetooth: leads with — and stays on — Bluetooth',
    () async {
      final ble = _FakeTransport('ble');
      final sup = supervise(
        makeConn(wifiUp: true, ble: ble, preferred: PreferredTransport.ble),
      );
      final links = <LiveLink>[];
      sup.links.listen(links.add);

      await sup.start();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Even though Wi-Fi was reachable, it never climbed off Bluetooth.
      expect(links.last.link, LinkKind.ble);
      expect(links.every((l) => l.link != LinkKind.http), isTrue);

      await sup.dispose();
    },
  );

  test('hold-BLE off: the standby is dropped once on Wi-Fi', () async {
    final ble = _FakeTransport('ble');
    final sup = supervise(makeConn(wifiUp: true, ble: ble, holdBle: false));
    final links = <LiveLink>[];
    sup.links.listen(links.add);

    await sup.start();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(links.last.link, LinkKind.http);
    // With backup off, the BLE link is not kept warm.
    expect(ble.closed, isTrue);

    await sup.dispose();
  });

  test('user picks Bluetooth on Wi-Fi: swaps down now, keeps it', () async {
    final ble = _FakeTransport('ble');
    final sup = supervise(makeConn(wifiUp: true, ble: ble));
    final links = <LiveLink>[];
    sup.links.listen(links.add);

    await sup.start();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(links.last.link, LinkKind.http, reason: 'settled on Wi-Fi first');

    links.clear();
    sup.applyPreference(PreferredTransport.ble);
    await Future<void>.delayed(Duration.zero);
    // Immediate swap to Bluetooth, and the dead Wi-Fi link is marked to close.
    expect(links.first.link, LinkKind.ble);
    expect(links.first.closePrevious, isTrue);

    // It stays on Bluetooth — no auto-climb behind the user's back.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(links.last.link, LinkKind.ble);

    await sup.dispose();
  });

  test('after Bluetooth, choosing Wi-Fi climbs back up', () async {
    final ble = _FakeTransport('ble');
    final sup = supervise(makeConn(wifiUp: true, ble: ble));
    final links = <LiveLink>[];
    sup.links.listen(links.add);

    await sup.start();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    sup.applyPreference(PreferredTransport.ble);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(links.last.link, LinkKind.ble);

    sup.applyPreference(PreferredTransport.wifi);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(links.last.link, LinkKind.http);

    await sup.dispose();
  });

  test('dispose closes the active transport', () async {
    final ble = _FakeTransport('ble');
    final sup = supervise(makeConn(wifiUp: false, ble: ble));
    sup.links.listen((_) {});
    await sup.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await sup.dispose();
    expect(ble.closed, isTrue);
  });

  // ── A26: retryNow — the connect half of pull-to-refresh ──────────────

  test(
    'retryNow on a healthy link answers yes without touching the radios',
    () async {
      final ble = _FakeTransport('ble');
      final sup = supervise(makeConn(wifiUp: true, ble: ble));
      sup.links.listen((_) {});
      await sup.start();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(await sup.retryNow(), isTrue);
      await sup.dispose();
    },
  );

  test('retryNow brings Bluetooth up — the upgrade loop only ever races '
      'Wi-Fi, so a BLE-only path back would never be found', () async {
    // The bridge is off: neither lane answers, so the boot lands offline.
    _FakeTransport? ble;
    final conn = AppConnection(
      prefs: InMemoryBridgePrefs(lastBaseUrl: 'http://10.0.0.7'),
      transportFor: (_) => _FakeTransport('http'),
      probe: (_) async => false, // Wi-Fi is down and stays down
      bleAttempt: () async => ble,
      delay: _fast,
    );
    final sup = ConnectionSupervisor(connection: conn, delay: _fast);
    final links = <LiveLink>[];
    sup.links.listen(links.add);

    await sup.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(links.last.offline, isTrue);

    // Someone switches the bridge back on. Bluetooth can answer now; Wi-Fi
    // still cannot — which is exactly the case the Wi-Fi-only climb misses.
    ble = _FakeTransport('ble');
    expect(await sup.retryNow(timeout: const Duration(seconds: 2)), isTrue);
    expect(links.last.link, LinkKind.ble);

    await sup.dispose();
  });

  test(
    'retryNow with nothing reachable answers no, and answers promptly',
    () async {
      final sup = supervise(makeConn(wifiUp: false));
      sup.links.listen((_) {});
      await sup.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // The gesture has to end. A pull that spins forever is worse than one
      // that reports failure.
      expect(
        await sup.retryNow(timeout: const Duration(milliseconds: 150)),
        isFalse,
      );
      await sup.dispose();
    },
  );

  test('overlapping retries share one round of radio work', () async {
    var bleAttempts = 0;
    final conn = AppConnection(
      prefs: InMemoryBridgePrefs(lastBaseUrl: 'http://10.0.0.7'),
      transportFor: (_) => _FakeTransport('http'),
      probe: (_) async => false,
      bleAttempt: () async {
        bleAttempts++;
        return null;
      },
      delay: _fast,
    );
    final sup = ConnectionSupervisor(connection: conn, delay: _fast);
    sup.links.listen((_) {});
    await sup.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final afterBoot = bleAttempts;

    const short = Duration(milliseconds: 150);
    final results = await Future.wait([
      sup.retryNow(timeout: short),
      sup.retryNow(timeout: short),
      sup.retryNow(timeout: short),
    ]);

    expect(results, everyElement(isFalse));
    // Three pulls, one attempt: a user drumming on the screen must not cost
    // three rounds of radio.
    expect(bleAttempts, afterBoot + 1);
    await sup.dispose();
  });
}
