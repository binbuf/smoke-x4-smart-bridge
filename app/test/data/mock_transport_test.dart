/// A3.3 — a full 18-hour cook driven through MockTransport with no network
/// anywhere. The mock implements the same BridgeTransport surface the HTTP
/// and BLE transports will, so this suite is the template for testing all
/// three against `tools/sim`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/data/transport/mock_transport.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';

import 'records_parity_test.dart' show repoRoot;

void main() {
  final smk = File(
    '${repoRoot()}/protocol/fixtures/brisket-18h.smk',
  ).readAsBytesSync();
  final mrk = File(
    '${repoRoot()}/protocol/fixtures/brisket-18h.mrk',
  ).readAsBytesSync();

  MockTransport transport() => MockTransport.fromSmkBytes(smk, mrkBytes: mrk);

  test('capabilities: everything except OTA', () {
    final t = transport();
    expect(t.capabilities.liveState, isTrue);
    expect(t.capabilities.fullHistory, isTrue);
    expect(t.capabilities.ota, isFalse);
  });

  test('status() answers the dashboard header', () async {
    final s = await transport().status();
    expect(s.deviceId, '|abCDe');
    expect(s.paired, isTrue);
    expect(s.numProbes, 4);
    expect(s.uptimeS, greaterThan(17 * 3600));
  });

  test('sessions() lists the cook', () async {
    final sessions = await transport().sessions();
    expect(sessions, hasLength(1));
    expect(sessions.single.name, 'Brisket 18h (synthetic)');
  });

  test('samples() streams the full 18-hour cook in batches', () async {
    final t = transport();
    final batches = await t.samples(27).toList();
    final all = [for (final b in batches) ...b];
    expect(all.length, greaterThan(2000));
    expect(batches.length, greaterThan(1), reason: 'streamed, not one blob');
    // Monotonic, gap-preserving, detached-null-preserving.
    for (var i = 1; i < all.length; i++) {
      expect(all[i].t, greaterThan(all[i - 1].t));
    }
    expect(findGaps(all.map((s) => s.t)), isNotEmpty);
    expect(all.any((s) => s.tempsF10[3] == null), isTrue);
  });

  test('samples() honours from/to', () async {
    final t = transport();
    final all = [
      for (final b in await t.samples(27, fromT: 3600, toT: 7200).toList())
        ...b,
    ];
    expect(all.first.t, greaterThanOrEqualTo(3600));
    expect(all.last.t, lessThanOrEqualTo(7200));
  });

  test('an unknown session id fails like the API would', () {
    expect(() => transport().samples(999).toList(), throwsA(isA<StateError>()));
  });

  test('live() serves the trailing window instantly', () async {
    final live = await transport().live(window: const Duration(hours: 2));
    expect(live.t, greaterThan(17 * 3600));
    expect(live.recent, isNotEmpty);
    expect(live.recent.first.t, greaterThan(live.t - 2 * 3600 - 60));
    expect(live.unixMs, isNotNull);
  });

  test('events replays every sample then ends the session', () async {
    final t = transport();
    final events = await t.events.toList();
    final samples = events.whereType<BridgeSampleEvent>().toList();
    expect(samples.length, greaterThan(2000));
    final end = events.last;
    expect(end, isA<BridgeSessionEvent>());
    expect((end as BridgeSessionEvent).action, SessionAction.ended);

    // The exhaustive-switch guarantee (A3.1 done-when): this switch has no
    // default — adding a BridgeEvent variant without handling it here (and
    // everywhere else) fails analysis.
    var seen = 0;
    for (final e in events) {
      switch (e) {
        case BridgeSampleEvent():
          seen++;
        case BridgeAlarmEvent():
        case BridgeSessionEvent():
        case BridgeNetEvent():
        case BridgePowerEvent():
          break;
      }
    }
    expect(seen, samples.length);
  });

  test('control and configure are recorded for assertion', () async {
    final t = transport();
    await t.control(const ControlCommand.mark(kind: MarkKind.note));
    await t.control(const ControlCommand.sessionStop());
    await t.configure(const BridgeConfig(displayUnits: 'F'));
    expect(t.controlLog, hasLength(2));
    expect(t.controlLog.first, isA<MarkCommand>());
    expect(t.configureLog.single.displayUnits, 'F');
  });

  test('marks from the sibling .mrk are available', () {
    expect(transport().marks, hasLength(4));
  });
}
