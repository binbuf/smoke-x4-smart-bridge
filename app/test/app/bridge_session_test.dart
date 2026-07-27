/// A24.7 — the failover hooks BridgeSession grew for the supervisor:
/// the un-swallowed push-stream error (verify-then-fail-over) and the live
/// [BridgeSession.switchTransport] swap that never closes the old link.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/bridge_session.dart';
import 'package:smoke_bridge/data/local/database.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';

/// A transport whose push stream and status health the test drives directly.
class _ControllableTransport implements BridgeTransport {
  _ControllableTransport({this.deviceId = 'DEV1'});
  final String deviceId;

  /// Flip true to make the next status read fail — "the bridge is unreachable".
  bool failStatus = false;

  /// The same, for the live read pull-to-refresh leads with.
  bool failLive = false;

  /// Seconds into the session the unit will report next — "the bridge has a
  /// newer reading than the screen".
  int liveT = 0;
  bool closed = false;
  final _events = StreamController<BridgeEvent>.broadcast();

  void pushError(Object e) => _events.addError(e);

  @override
  BridgeCapabilities get capabilities =>
      const BridgeCapabilities(liveState: true, historyPreview: true);

  @override
  Stream<BridgeEvent> get events => _events.stream;

  @override
  Future<BridgeStatus> status() async {
    if (failStatus) {
      throw Exception('unreachable');
    }
    return BridgeStatus(deviceId: deviceId);
  }

  @override
  Future<LiveState> live({Duration window = const Duration(hours: 1)}) async {
    if (failLive) {
      throw Exception('unreachable');
    }
    return LiveState(t: liveT, tempsF10: const <int?>[]);
  }

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('a push error a status read confirms fires onLinkLost', () async {
    var lost = 0;
    final t = _ControllableTransport();
    final session = BridgeSession(
      db: db,
      transport: t,
      link: LinkKind.http,
      onLinkLost: () => lost++,
    );
    await session.start();

    t.failStatus = true; // the bridge is now unreachable
    t.pushError(StateError('stream closed'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(lost, 1);
    await session.dispose();
  });

  test('a push error the bridge survives does NOT fail over', () async {
    var lost = 0;
    final t = _ControllableTransport(); // status keeps answering
    final session = BridgeSession(
      db: db,
      transport: t,
      link: LinkKind.http,
      onLinkLost: () => lost++,
    );
    await session.start();

    t.pushError(StateError('stream closed'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // REST still works, so the push just hiccuped — no failover.
    expect(lost, 0);
    await session.dispose();
  });

  test(
    'with no onLinkLost a push error is simply swallowed (legacy)',
    () async {
      final t = _ControllableTransport();
      final session = BridgeSession(db: db, transport: t, link: LinkKind.http);
      await session.start();
      // Must not throw or fail the zone — the old behaviour.
      t.pushError(StateError('stream closed'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await session.dispose();
    },
  );

  test('switchTransport rebinds live and never closes the old link', () async {
    final a = _ControllableTransport(deviceId: 'A');
    final b = _ControllableTransport(deviceId: 'B');
    final session = BridgeSession(
      db: db,
      transport: a,
      link: LinkKind.http,
      ownsTransport: false,
    );
    final snaps = <DashboardSnapshot>[];
    session.snapshots.listen(snaps.add);
    await session.start();

    await session.switchTransport(b, link: LinkKind.ble);

    expect(session.transport, same(b));
    expect(session.link, LinkKind.ble);
    // The supervisor owns lifecycle — the swapped-out link stays warm.
    expect(a.closed, isFalse);
    // The screen re-rendered on the new link (let the broadcast flush).
    await Future<void>.delayed(Duration.zero);
    expect(snaps.last.link, LinkKind.ble);

    await session.dispose();
    // ownsTransport:false — dispose leaves the active transport alone too.
    expect(b.closed, isFalse);
  });

  test('switchTransport(closeOld: true) closes the discarded link', () async {
    final a = _ControllableTransport(deviceId: 'A');
    final b = _ControllableTransport(deviceId: 'B');
    final session = BridgeSession(
      db: db,
      transport: a,
      link: LinkKind.http,
      ownsTransport: false,
    );
    session.snapshots.listen((_) {});
    await session.start();

    // A user-chosen switch away from Wi-Fi (or a failover to a dead link)
    // discards the old transport — the session closes it after unbinding.
    await session.switchTransport(b, link: LinkKind.ble, closeOld: true);
    expect(session.transport, same(b));
    expect(a.closed, isTrue);

    await session.dispose();
  });

  // ── A26: refreshNow — the read behind pull-to-refresh ────────────────

  test('refreshNow gets a new value from the unit and emits it', () async {
    final t = _ControllableTransport();
    final session = BridgeSession(db: db, transport: t, link: LinkKind.http);
    await session.start();
    expect(session.snapshot!.elapsedS, 0);

    t.liveT = 900; // fifteen minutes have passed on the bridge
    await session.refreshNow();

    expect(session.snapshot!.elapsedS, 900);
    await session.dispose();
  });

  test(
    'refreshNow THROWS when the unit cannot be reached — a gesture that '
    'silently does nothing is how an app teaches people it is broken',
    () async {
      final t = _ControllableTransport()..failLive = true;
      final session = BridgeSession(db: db, transport: t, link: LinkKind.http);
      await session.start();

      await expectLater(session.refreshNow(), throwsA(isA<Exception>()));
      await session.dispose();
    },
  );

  test(
    'a stumbled status read does not discard a reading already in hand',
    () async {
      final t = _ControllableTransport();
      final session = BridgeSession(db: db, transport: t, link: LinkKind.http);
      await session.start();

      t.liveT = 900;
      t.failStatus = true; // alarms/battery go stale; the temperature does not
      await session.refreshNow();

      expect(session.snapshot!.elapsedS, 900);
      await session.dispose();
    },
  );
}
