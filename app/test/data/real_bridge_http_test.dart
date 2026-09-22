/// N15.8 exit-gate smoke — the real `BridgeRepository` over a **real HTTP
/// transport** against a loopback bridge ([FakeBridgeServer]).
///
/// `real_bridge_repository_test.dart` drives the drop-in over `MockTransport`
/// (deterministic, injectable); this file proves the same drop-in works when
/// every byte crosses a socket: status → sync → live → cache → subscribe, the
/// history list, a CSV export read back from drift, and the mid-cook link-loss
/// insight when the server disappears.
///
/// Pure Dart (`package:test`), so it runs in both `flutter test` and
/// `dart test test/data`. The manual entry point the bench uses is
/// `make sim` + `--dart-define=REAL_BRIDGE=true --dart-define=BRIDGE_HOST=…`.
library;

import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

import '../support/fake_bridge_server.dart';

/// Always hands the manager a transport pointed at the loopback server,
/// whatever lane (host) it is probing — the race itself is covered elsewhere.
class _LoopbackFactory implements TransportFactory {
  _LoopbackFactory(this.baseUrl);

  final String baseUrl;
  int opened = 0;

  @override
  Future<BridgeTransport?> openHttp(String host) async {
    opened++;
    return HttpTransport(
      baseUrl: baseUrl,
      timeout: const Duration(milliseconds: 500),
    );
  }

  @override
  Future<BridgeTransport?> openBle() async => null;
}

void main() {
  late FakeBridgeServer server;
  late RealBridgeRepository repo;

  setUp(() async {
    server = FakeBridgeServer();
    await server.start();
    final factory = _LoopbackFactory(server.baseUrl);
    final manager = ConnectionManager(
      factory: factory,
      manualBaseUrl: 'smokebridge.local',
      // No backoff: the link-loss test must not wait a real minute.
      backoff: const [],
      sleep: (_) async {},
    );
    final supervisor = ConnectionSupervisor(
      manager: manager,
      factory: factory,
      preferred: TransportPreference.wifi,
    );
    repo = RealBridgeRepository(
      supervisor: supervisor,
      bridgeId: 'X4-480001',
      nowMs: () => 1700000100000,
      statusPollInterval: const Duration(milliseconds: 50),
    );
  });

  tearDown(() async {
    await repo.dispose();
    await server.stop();
  });

  test('connects over real HTTP and builds the app snapshot', () async {
    await repo.connect();

    final s = repo.current;
    expect(s.connection.phase, ConnectionPhase.connected);
    expect(s.connection.primary, LinkPrimary.wifi);
    expect(s.connection.wifi.connected, isTrue);
    expect(s.cook.active, isTrue);
    expect(s.cook.name, 'Sim Cook');
    expect(s.pendingSession?.sessionId, '1');

    // The live feed came over `/live`, and the four jacks are present (I3).
    expect(s.probes, hasLength(4));
    final one = s.probes.firstWhere((p) => p.jack == ProbeJack.one);
    expect(one.tempF10, 1100);
  });

  test('syncs samples into the cache and exports the cook from it', () async {
    await repo.connect();

    expect(await repo.cache.sampleCount('X4-480001', 1), 3);
    expect(repo.history, hasLength(1));

    final csv = await repo.exportCookCsv('1');
    final lines = csv.trim().split('\n');
    expect(lines.first, cookCsvHeader);
    expect(lines.length, 4); // header + three samples
    expect(lines[1], startsWith('0,'));
  });

  test('a mark crosses the wire and lands in the snapshot', () async {
    await repo.connect();
    await repo.mark(kind: MarkKind.wrapped, text: 'wrap', jack: ProbeJack.one);

    expect(
      repo.current.marks.any(
        (m) => m.kind == MarkKind.wrapped && m.text == 'wrap',
      ),
      isTrue,
    );
    expect(
      server.requests.any((r) => r.$2 == '/api/v1/sessions/1/marks'),
      isTrue,
    );
  });

  test(
    'killing the server mid-cook raises the unreachable insight (I15)',
    () async {
      await repo.connect();
      expect(repo.current.cook.active, isTrue);

      await server.stop();
      // Let a backstop poll fail and the supervisor exhaust its lanes.
      await Future<void>.delayed(const Duration(seconds: 5));

      expect(
        repo.current.alarms.any((a) => a.ruleId == 'bridge_unreachable'),
        isTrue,
      );
      expect(repo.current.notice, contains('unreachable'));
    },
  );
}
