/// A24.9 — what a transport swap must never cost: data.
///
/// The full journey the field actually produces — Wi-Fi (either mode) →
/// Bluetooth fallback → Wi-Fi again — with the assertions that matter:
/// history survives every hop (the cache is the truth, not the link), and the
/// climb back onto Wi-Fi runs a *delta* sync from the cursor, not a refetch
/// and not a hole.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/bridge_session.dart';
import 'package:smoke_bridge/data/local/database.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';

/// A Wi-Fi-shaped transport: full history served from an in-memory list,
/// recording every `samples(fromT:)` so the delta cursor is assertable.
class _FakeWifi implements BridgeTransport {
  _FakeWifi(this.allSamples);

  final List<Sample> allSamples;
  final List<int> sampleRequests = [];
  final _events = StreamController<BridgeEvent>.broadcast();

  @override
  BridgeCapabilities get capabilities => const BridgeCapabilities(
    liveState: true,
    fullHistory: true,
    historyPreview: true,
    config: true,
  );

  @override
  Stream<BridgeEvent> get events => _events.stream;

  @override
  Future<BridgeStatus> status() async => const BridgeStatus(
    deviceId: 'DEV',
    sessionActive: true,
    activeSessionId: 1,
  );

  @override
  Future<LiveState> live({Duration window = const Duration(hours: 1)}) async =>
      LiveState(
        t: allSamples.isEmpty ? 0 : allSamples.last.t,
        tempsF10: const [2250, null, null, null],
      );

  @override
  Future<List<CookSession>> sessions() async => [
    CookSession(id: 1, name: 'Test cook', sampleCount: allSamples.length),
  ];

  @override
  Stream<List<Sample>> samples(
    int sessionId, {
    int fromT = 0,
    int? toT,
    int? bucketS,
  }) {
    sampleRequests.add(fromT);
    return Stream.value([
      for (final s in allSamples)
        if (s.t >= fromT) s,
    ]);
  }

  @override
  Future<void> close() async {
    await _events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// A Bluetooth-shaped transport: live only, no history, no session list.
class _FakeBle implements BridgeTransport {
  final _events = StreamController<BridgeEvent>.broadcast();

  @override
  BridgeCapabilities get capabilities =>
      const BridgeCapabilities(liveState: true, historyPreview: true);

  @override
  Stream<BridgeEvent> get events => _events.stream;

  @override
  Future<BridgeStatus> status() async =>
      const BridgeStatus(deviceId: 'DEV', sessionActive: true);

  @override
  Future<LiveState> live({Duration window = const Duration(hours: 1)}) async =>
      const LiveState(t: 300, tempsF10: [2251, null, null, null]);

  @override
  Future<void> close() async {
    await _events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Sample _s(int t) => Sample(t: t, tempsF10: [2000 + t, null, null, null]);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('Wi-Fi → BLE → Wi-Fi keeps history and delta-syncs the gap', () async {
    // 10 samples at t=0..270 on the bridge when the app first connects.
    final wifi = _FakeWifi([for (var t = 0; t < 300; t += 30) _s(t)]);
    final session = BridgeSession(
      db: db,
      transport: wifi,
      link: LinkKind.http,
      address: 'http://10.0.0.7',
      ownsTransport: false,
    );
    await session.start();
    expect(session.snapshot!.samples, hasLength(10));
    expect(wifi.sampleRequests, [0], reason: 'first sync is the full fetch');

    // Wi-Fi drops — the supervisor swaps to Bluetooth. History must not
    // shrink: the cache serves it even though BLE cannot.
    final ble = _FakeBle();
    await session.switchTransport(ble, link: LinkKind.ble);
    expect(session.snapshot!.link, LinkKind.ble);
    expect(session.snapshot!.fullHistory, isFalse);
    expect(
      session.snapshot!.samples.length,
      greaterThanOrEqualTo(10),
      reason: 'the BLE hop must not cost cached history',
    );

    // While on BLE the cook kept going: 5 more samples land on the bridge.
    wifi.allSamples.addAll([for (var t = 300; t < 450; t += 30) _s(t)]);

    // Wi-Fi returns — the climb back must fetch ONLY the gap (cursor =
    // cachedMax + 1 = 271), and the merged history must be complete.
    await session.switchTransport(
      wifi,
      link: LinkKind.http,
      address: 'http://10.0.0.7',
    );
    expect(session.snapshot!.link, LinkKind.http);
    expect(wifi.sampleRequests, hasLength(2));
    expect(
      wifi.sampleRequests.last,
      271,
      reason: 'the re-sync is a delta from the cursor, not a refetch',
    );
    expect(session.snapshot!.samples, hasLength(15));
    expect(session.snapshot!.fullHistory, isTrue);

    await session.dispose();
    await wifi.close();
    await ble.close();
  });

  test('a sample pushed during the BLE stint survives the re-sync', () async {
    final wifi = _FakeWifi([for (var t = 0; t < 300; t += 30) _s(t)]);
    final session = BridgeSession(
      db: db,
      transport: wifi,
      link: LinkKind.http,
      ownsTransport: false,
    );
    await session.start();

    final ble = _FakeBle();
    await session.switchTransport(ble, link: LinkKind.ble);

    // A live push over BLE lands in the cache (keyed idempotently).
    ble._events.add(BridgeEvent.sample(_s(300)));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // The bridge also has it; the re-sync must not duplicate or drop it.
    wifi.allSamples.add(_s(300));
    await session.switchTransport(wifi, link: LinkKind.http);
    final ts = session.snapshot!.samples.map((s) => s.t).toList();
    expect(ts, hasLength(ts.toSet().length), reason: 'no duplicate rows');
    expect(ts, contains(300));

    await session.dispose();
    await wifi.close();
    await ble.close();
  });
}
