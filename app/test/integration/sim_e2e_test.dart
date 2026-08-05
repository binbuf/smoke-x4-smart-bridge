@Timeout(Duration(minutes: 5))
/// A15.4 — the MVP path, driven against a live `tools/sim`.
///
/// §8.9's claim, checked: the app is developable and testable against a
/// fake bridge replaying a recorded 18-hour cook, with no hardware
/// anywhere. What runs here is the **real** `HttpTransport`, the **real**
/// `SyncEngine`, the **real** repositories and the real screens — only the
/// bridge is fake, and it is fake by serving the actual API rather than by
/// being a stub.
///
/// ## Its relationship to CI, stated rather than discovered
///
/// `tools/sim` is a member of the root Dart pub workspace; `app/` is a
/// standalone Flutter package, and CI's app job runs `flutter pub get`
/// only inside `app/`. So `dart run sim` cannot resolve there — the same
/// constraint A8.3 hit in M3 and recorded as a deviation.
///
/// This suite therefore **spawns the real sim when the workspace is
/// bootstrapped and skips with a stated reason when it is not.** Locally
/// (and on any runner that has run `dart pub get` at the repo root) it is
/// a full end-to-end run; in the app-only job it announces why it did not
/// run. A test that quietly does not run is worse than one that says why —
/// and the alternative, a second in-process fake of an API the sim already
/// implements, would be a second thing to keep true.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/bridge_session.dart';
import 'package:smoke_bridge/data/local/database.dart';
import 'package:smoke_bridge/data/repos/repositories.dart';
import 'package:smoke_bridge/data/repos/sync_engine.dart';
import 'package:smoke_bridge/data/transport/http_transport.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/features/chart/chart_viewport.dart';
import 'package:smoke_bridge/features/cook/cook_view.dart';
import 'package:smoke_bridge/features/dashboard/dashboard.dart';
import 'package:smoke_bridge/features/sessions/export.dart';
import 'package:smoke_bridge/features/sessions/sessions_screen.dart';
import 'package:smoke_bridge/ui/ui.dart';

import '../data/records_parity_test.dart' show repoRoot;

/// Ports the sim is started on. 8080 is occupied on the development
/// machine, so this suite never asks for it.
const int _basePort = 8137;

/// One running sim.
class _Sim {
  _Sim(this.process, this.port);
  final Process process;
  final int port;

  String get baseUrl => 'http://127.0.0.1:$port';

  Future<void> stop() async {
    process.kill();
    await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () => 0,
    );
  }
}

/// True when the root workspace has been resolved — i.e. `dart run sim`
/// can work at all.
bool get _workspaceReady =>
    File('${repoRoot()}/.dart_tool/package_config.json').existsSync() &&
    _dartExecutable() != null;

/// The `dart` binary, found on PATH.
///
/// `flutter test` runs inside `flutter_tester`, whose
/// `Platform.resolvedExecutable` is the engine binary rather than the SDK
/// — so the Dart SDK has to be located rather than assumed, and on
/// Windows a bare `Process.start('dart', …)` cannot find `dart.bat` at
/// all.
String? _dartExecutable() {
  final sep = Platform.pathSeparator;
  // A real executable, not a launcher script: Windows' CreateProcess
  // cannot run `dart.bat` directly, and the Flutter SDK ships only the
  // script on PATH — the binary itself lives under its cache.
  final candidates = Platform.isWindows
      ? ['dart.exe', 'cache${sep}dart-sdk${sep}bin${sep}dart.exe']
      : ['dart', 'cache/dart-sdk/bin/dart'];
  for (final dir in (Platform.environment['PATH'] ?? '').split(
    Platform.isWindows ? ';' : ':',
  )) {
    if (dir.isEmpty) {
      continue;
    }
    for (final name in candidates) {
      final f = File('$dir$sep$name');
      if (f.existsSync()) {
        return f.path;
      }
    }
  }
  return null;
}

Future<_Sim?> _startSim({
  required int port,
  String? cook,
  String? scenario,
  double speed = 2000,
}) async {
  final process = await Process.start(_dartExecutable()!, [
    'run',
    'sim',
    '--port',
    '$port',
    '--speed',
    '$speed',
    if (scenario != null) ...['--scenario', scenario],
    if (scenario == null) ...[
      '--cook',
      cook ?? 'protocol/fixtures/brisket-18h.smk',
    ],
  ], workingDirectory: repoRoot());
  final sim = _Sim(process, port);
  // Wait for it to answer rather than sleeping a magic number.
  final client = HttpClient();
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final req = await client.getUrl(
        Uri.parse('${sim.baseUrl}/api/v1/status'),
      );
      final res = await req.close();
      await res.drain<void>();
      if (res.statusCode == 200) {
        client.close();
        return sim;
      }
    } on Object {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
  client.close();
  await sim.stop();
  return null;
}

void main() {
  // `TestWidgetsFlutterBinding` installs an HttpOverrides that answers
  // every request with a 400 and never opens a socket — exactly right for
  // a widget test, and exactly wrong for the one suite whose whole point
  // is talking to a real server over the real transport. Dropping the
  // override restores dart:io, and therefore `dio`.
  HttpOverrides.global = null;

  if (!_workspaceReady) {
    test(
      'A15.4 — skipped: the root pub workspace is not resolved, so '
      '`dart run sim` cannot start (see this file\'s header)',
      () {},
      skip:
          'Run `dart pub get` at the repo root to enable the sim-backed '
          'end-to-end suite.',
    );
    return;
  }

  group('the MVP path against a live sim', () {
    late _Sim sim;
    late HttpTransport transport;
    late AppDatabase db;

    setUpAll(() async {
      HttpOverrides.global = null;
      final started = await _startSim(port: _basePort);
      expect(started, isNotNull, reason: 'the sim did not come up');
      sim = started!;
    });

    tearDownAll(() async => sim.stop());

    setUp(() {
      HttpOverrides.global = null;
      transport = HttpTransport(sim.baseUrl);
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await transport.close();
      await db.close();
    });

    test(
      'connect, sync 18 hours, and render the dashboard from cache',
      () async {
        final session = BridgeSession(
          db: db,
          transport: transport,
          link: LinkKind.http,
          address: sim.baseUrl,
        );
        await session.start();

        final snap = session.snapshot;
        expect(snap, isNotNull, reason: 'no snapshot after start()');
        expect(session.bridgeId, isNotEmpty);
        expect(snap!.samples.length, greaterThan(1000));
        // The invariant, on real API bytes rather than a fixture in memory.
        expect(snap.probes.where((p) => p.tempF10 == 0), isEmpty);
        expect(snap.headlinePit, isNotNull);

        await session.dispose();
      },
    );

    test('the chart decimates 18 hours without losing the ends', () async {
      await SyncEngine(db, transport).sync();
      final bridgeId = (await transport.status()).deviceId;
      final repo = SessionRepository(db, bridgeId: bridgeId);
      final sessions = await repo.sessions();
      final samples = await repo.samples(sessions.first.id);
      expect(samples.length, greaterThan(1000));

      final model = buildChartSeries(
        samples,
        fromT: samples.first.t,
        toT: samples.last.t,
        targetPoints: 400,
      );
      expect(model.series.first.points.length, lessThanOrEqualTo(400));
      expect(model.series.first.points.first.t, samples.first.t);
      expect(model.series.first.points.last.t, samples.last.t);
    });

    testWidgets('the dashboard and the session detail render live data', (
      tester,
    ) async {
      // Real I/O has to happen OUTSIDE the widget tester's fake clock:
      // an await on a socket inside the fake zone never completes, and
      // the test hangs until the harness kills it.
      final session = BridgeSession(
        db: db,
        transport: transport,
        link: LinkKind.http,
        address: sim.baseUrl,
      );
      await tester.runAsync(session.start);
      final snap = session.snapshot!;

      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CookView(
              snapshot: snap,
              plan: null,
              freshness: ProbeFreshness.live,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CookView), findsOneWidget);
      expect(tester.takeException(), isNull);

      final detail = await tester.runAsync(() async {
        final repo = session.sessions!;
        final cook = (await repo.sessions()).first;
        return (
          cook: cook,
          samples: await repo.samples(cook.id),
          marks: await repo.marks(cook.id),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionDetailView(
              session: detail!.cook,
              samples: detail.samples,
              marks: detail.marks,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('session-detail')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.runAsync(session.dispose);
    });

    test('the exported CSV is byte-identical to the device\'s own', () async {
      await SyncEngine(db, transport).sync();
      final bridgeId = (await transport.status()).deviceId;
      final repo = SessionRepository(db, bridgeId: bridgeId);
      final cook = (await repo.sessions()).first;
      final samples = await repo.samples(cook.id);

      final sink = InMemoryExportSink();
      final name = await exportSessionCsv(
        session: cook,
        samples: samples,
        sink: sink,
      );
      final ours = const LineSplitter().convert(sink.files[name]!);

      // The same range, straight from the sim's own csv writer.
      final client = HttpClient();
      final req = await client.getUrl(
        Uri.parse(
          '${sim.baseUrl}/api/v1/sessions/${cook.id}/samples'
          '?format=csv&from=${samples.first.t}&to=${samples.last.t}',
        ),
      );
      final res = await req.close();
      final theirs = const LineSplitter().convert(
        await res.transform(utf8.decoder).join(),
      );
      client.close();

      expect(ours.first, theirs.first, reason: 'header differs');
      // The device may have replayed further while we were talking to it;
      // compare the overlap, which is what "byte identical" has to mean
      // against a live replay.
      final n = ours.length < theirs.length ? ours.length : theirs.length;
      expect(n, greaterThan(100));
      for (var i = 0; i < n; i++) {
        expect(ours[i], theirs[i], reason: 'line $i differs');
      }
    });
  });

  group('the adverse scenarios — the S tier means these too', () {
    for (final (scenario, port) in [
      ('flaky', _basePort + 1),
      ('base-lost', _basePort + 2),
    ]) {
      test('$scenario syncs and renders without inventing data', () async {
        HttpOverrides.global = null;
        final sim = await _startSim(port: port, scenario: scenario);
        expect(sim, isNotNull, reason: 'the $scenario sim did not come up');
        final transport = HttpTransport(sim!.baseUrl);
        final db = AppDatabase(NativeDatabase.memory());
        try {
          final session = BridgeSession(
            db: db,
            transport: transport,
            link: LinkKind.http,
            address: sim.baseUrl,
          );
          await session.start();
          final snap = session.snapshot!;
          // Whatever the scenario did to the data, none of it may surface
          // as a temperature of zero.
          expect(snap.probes.where((p) => p.tempF10 == 0), isEmpty);
          if (scenario == 'flaky') {
            // Dropped packets are holes, and the chart must be able to
            // see them as holes.
            final model = buildChartSeries(
              snap.samples,
              fromT: 0,
              toT: 1 << 30,
            );
            expect(model.gaps, isNotEmpty);
          }
          await session.dispose();
        } finally {
          await transport.close();
          await db.close();
          await sim.stop();
        }
      });
    }
  });
}
