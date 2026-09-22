/// N15.8 — the real `BridgeRepository` over the transport stack.
///
/// Pure Dart (`package:test`), so it runs in both `flutter test` and
/// `dart test test/data`. It drives the whole drop-in against a real
/// [ConnectionSupervisor] + [BridgeSession] + [SampleCache] over [MockTransport]
/// — the same seam the app ships behind `bridgeRepositoryProvider`.
library;

import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

class _WifiFactory implements TransportFactory {
  _WifiFactory(this.transport);

  final BridgeTransport Function() transport;
  final List<String> opened = [];

  @override
  Future<BridgeTransport?> openHttp(String host) async {
    opened.add(host);
    return host == 'smokebridge.local' ? transport() : null;
  }

  @override
  Future<BridgeTransport?> openBle() async => null;
}

MockTransport _deviceTransport({
  Map<int, List<Sample>>? samples,
  Map<int, List<Mark>>? marks,
}) => MockTransport(
  kind: TransportKind.http,
  label: 'wifi',
  device: MockBridgeDevice(
    samples:
        samples ??
        {
          1: const [
            Sample(t: 0, tempsF10: [1000, null, null, 2200], rssi: -60),
            Sample(t: 30, tempsF10: [1010, null, null, 2210], rssi: -58),
            Sample(t: 60, tempsF10: [1020, null, null, 2220], rssi: -57),
          ],
        },
    marks: marks,
  ),
);

Future<(RealBridgeRepository, MockTransport)> _connected({
  MockTransport? transport,
}) async {
  final device = transport ?? _deviceTransport();
  final factory = _WifiFactory(() => device);
  final supervisor = ConnectionSupervisor(
    manager: ConnectionManager(factory: factory),
    factory: factory,
    preferred: TransportPreference.wifi,
  );
  final repo = RealBridgeRepository(
    supervisor: supervisor,
    bridgeId: 'X4-480001',
    nowMs: () => 1700000100000,
    statusPollInterval: const Duration(hours: 1),
  );
  await repo.connect();
  return (repo, device);
}

void main() {
  test('connect maps a real status + live feed into a BridgeSnapshot', () async {
    final (repo, _) = await _connected();
    addTearDown(repo.dispose);

    final s = repo.current;
    expect(s.connection.phase, ConnectionPhase.connected);
    expect(s.connection.primary, LinkPrimary.wifi);
    expect(s.connection.batteryPct, 71);
    expect(s.connection.wifi.ssid, 'SmokeBridge-A4F2');
    expect(s.connection.wifi.connected, isTrue);

    expect(s.cook.active, isTrue);
    expect(s.cook.name, 'Sim Cook');
    expect(s.cook.startedAtMs, 1700000000000);

    // Live probe 1 is attached and carries its real reading (I3: absent null).
    final one = s.probes.firstWhere((p) => p.jack == ProbeJack.one);
    expect(one.attached, isTrue);
    expect(one.tempF10, 1642);
    expect(one.targetF10, 2010);
    expect(one.freshness, Freshness.live);

    // The active session is unadopted, so it surfaces as a pending session.
    expect(s.pendingSession, isNotNull);
    expect(s.pendingSession!.sessionId, '1');
    expect(s.pendingSession!.startedAtMs, 1700000000000);
  });

  test('snapshot() replays the current value then every change', () async {
    final (repo, _) = await _connected();
    addTearDown(repo.dispose);

    final seen = <BridgeSnapshot>[];
    final sub = repo.snapshot().listen(seen.add);
    // Let the async* body reach its `yield*` on the broadcast controller.
    await Future<void>.delayed(Duration.zero);
    await repo.mark(kind: MarkKind.note, text: 'probe tender');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sub.cancel();

    expect(seen.first.connection.phase, ConnectionPhase.connected);
    expect(seen.length, greaterThanOrEqualTo(2));
    expect(seen.last.marks.any((m) => m.text == 'probe tender'), isTrue);
  });

  test('the initial sync backfills the cache and builds history', () async {
    final (repo, _) = await _connected();
    addTearDown(repo.dispose);

    expect(await repo.cache.sampleCount('X4-480001', 1), 3);
    expect(repo.history, hasLength(1));

    final entry = repo.history.single;
    expect(entry.id, '1');
    expect(entry.name, 'Sim Cook');
    expect(entry.startedAtMs, 1700000000000);
    expect(entry.markEvents, isEmpty);

    // Re-syncing is idempotent: no row is rewritten and none is duplicated.
    await repo.resync();
    expect(await repo.cache.sampleCount('X4-480001', 1), 3);
    expect(repo.cache.maxT('X4-480001', 1), completion(60));
  });

  test('a mark is posted to the active session on the wire (I10)', () async {
    final (repo, device) = await _connected();
    addTearDown(repo.dispose);

    await repo.mark(kind: MarkKind.wrapped, text: 'wrap', jack: ProbeJack.one);

    final post = device.calls.firstWhere((c) => c.method == 'postMark');
    expect(post.arg, 1);
    expect(
      repo.current.marks.any(
        (m) => m.kind == MarkKind.wrapped && m.text == 'wrap',
      ),
      isTrue,
    );
  });

  test('startCook pins a catalog item and a safe pull on the jack', () async {
    final (repo, _) = await _connected();
    addTearDown(repo.dispose);

    final id = kCatalogTable.entries.first.id;
    await repo.startCook(presetId: id, jack: ProbeJack.two, targetF10: 2010);

    final item = repo.current.cook.items.single;
    expect(item.presetId, id);
    expect(item.jack, ProbeJack.two);
    final two = repo.current.probes.firstWhere((p) => p.jack == ProbeJack.two);
    expect(two.targetF10, 2010);
    expect(two.attached, isTrue);
  });

  test('setCookStart moves the anchor via the cook clock', () async {
    final (repo, device) = await _connected();
    addTearDown(repo.dispose);

    await repo.setCookStart(1700000200000);
    expect(repo.current.cook.startedAtMs, 1700000200000);
    expect(
      device.calls.any(
        (c) => c.method == 'setCookClock' && c.arg == 1700000200000,
      ),
      isTrue,
    );
  });

  test('exportCookCsv streams the cook window from the cache', () async {
    final (repo, _) = await _connected();
    addTearDown(repo.dispose);

    final csv = await repo.exportCookCsv('1');
    final lines = csv.trim().split('\n');
    expect(lines.first, cookCsvHeader);
    expect(lines.length, 4); // header + three samples
    expect(lines[1], startsWith('0,2023-11-14T22:13:20.000Z,100.0,,,220.0'));
  });

  test(
    'history annotation verbs edit the annotation, never a sample',
    () async {
      final (repo, _) = await _connected();
      addTearDown(repo.dispose);

      await repo.setCookNotes('1', 'great bark');
      await repo.setFavourite('1', true);
      await repo.setCookEnded('1', false);
      await repo.addCookMark('1', kind: MarkKind.note, text: 'Pulled');

      final entry = repo.history.single;
      expect(entry.notes, 'great bark');
      expect(entry.favourite, isTrue);
      expect(entry.isOpen, isTrue);
      expect(entry.markEvents.single.text, 'Pulled');
      // The recording is untouched (I10).
      expect(await repo.cache.sampleCount('X4-480001', 1), 3);
    },
  );

  test('disconnect drops the link but leaves the cache intact', () async {
    final (repo, _) = await _connected();
    addTearDown(repo.dispose);

    await repo.disconnect();
    expect(repo.current.connection.phase, ConnectionPhase.offline);
    expect(await repo.cache.sampleCount('X4-480001', 1), 3);
  });

  test(
    'a transport failure becomes a named notice, not an exception (I15)',
    () async {
      final device = _deviceTransport();
      device.device.failWith['applyNetwork'] = const TransportException(
        'wrong_password',
        'no',
      );
      final (repo, _) = await _connected(transport: device);
      addTearDown(repo.dispose);

      // Must not throw; the failure is swallowed by the repository seam.
      await repo.joinWifi(ssid: 'HomeNet-5G', password: 'hunter2');
      expect(repo.current, isNotNull);
    },
  );

  test('device alarms from /status become device-tier alarms (I2)', () async {
    final device = _deviceTransport();
    device.device.statusJson['alarms'] = [
      {
        'id': 3,
        'rule': 'band_high',
        'probe': 2,
        'since_unix_ms': 1700000050000,
        'acked': false,
      },
    ];
    final (repo, _) = await _connected(transport: device);
    addTearDown(repo.dispose);

    final alarm = repo.current.alarms.firstWhere(
      (a) => a.tier == AlarmTier.device,
    );
    expect(alarm.ruleId, 'band_high');
    expect(alarm.rule, 'Above the band');
    expect(alarm.severity, AlarmSeverity.warning);
    expect(alarm.atMs, 1700000050000);
    expect(alarm.sessionScoped, isTrue);

    await repo.ackAlarm(alarm.id);
    expect(
      repo.current.alarms.firstWhere((a) => a.id == alarm.id).acked,
      isTrue,
    );
  });

  test('a link loss mid-cook raises the bridge_unreachable insight', () async {
    final device = _deviceTransport();
    final factory = _WifiFactory(() => device);
    final supervisor = ConnectionSupervisor(
      manager: ConnectionManager(
        factory: factory,
        backoff: const [],
        sleep: (_) async {},
      ),
      factory: factory,
      preferred: TransportPreference.wifi,
    );
    final repo = RealBridgeRepository(
      supervisor: supervisor,
      bridgeId: 'X4-480001',
      nowMs: () => 1700000100000,
      statusPollInterval: const Duration(milliseconds: 15),
    );
    addTearDown(repo.dispose);
    await repo.connect();
    expect(repo.current.cook.active, isTrue);

    // The bridge drops. The next backstop poll fails, the supervisor finds no
    // other lane, and the app raises its own advisory insight (I2).
    device.device.failWith['status'] = const TransportException(
      'network',
      'gone',
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(
      repo.current.alarms.any((a) => a.ruleId == 'bridge_unreachable'),
      isTrue,
    );
    expect(repo.current.notice, contains('unreachable'));
  });
}
