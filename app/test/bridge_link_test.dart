import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/data/ble/ble_client.dart';
import 'package:smoke_bridge/data/ble/bridge_link.dart';
import 'package:smoke_bridge/data/ble/bridge_protocol.dart';
import 'package:smoke_bridge/domain/content.dart';
import 'package:smoke_bridge/features/live/live_screen.dart';
import 'package:smoke_bridge/theme/app_theme.dart';

import 'support/codecs.dart' as gen;
import 'support/fake_ble_client.dart';
import 'support/fake_bridge.dart';

final DateTime _now = DateTime.utc(2026, 10, 27, 12);

void main() {
  group('first connect', () {
    test('runs connect → info → MTU → bond → subscribe → live → set_time → '
        'recent sync end to end', () async {
      final harness = _Harness(
        bridge: FakeBridge(
          seq: 200,
          initialRecords: <gen.SampleRec>[
            _record(149, _now.subtract(const Duration(minutes: 20))),
            _record(150, _now.subtract(const Duration(minutes: 10))),
            _record(151, _now.subtract(const Duration(minutes: 5))),
          ],
        ),
      );
      addTearDown(harness.dispose);

      await harness.link.connectAndSecure(harness.device);

      final ops = harness.client.operations;
      int index(String prefix) =>
          ops.indexWhere((entry) => entry.startsWith(prefix));
      expect(index('connect:'), greaterThanOrEqualTo(0));
      expect(
        index('read:${gen.bleCharacteristicByName('info').uuid}'),
        greaterThan(index('connect:')),
      );
      expect(index('mtu:247'), greaterThan(index('read:')));
      expect(index('bond'), greaterThan(index('mtu:247')));
      expect(
        index('notify:${gen.bleCharacteristicByName('live').uuid}'),
        greaterThan(index('bond')),
      );
      expect(
        index('read:${gen.bleCharacteristicByName('live').uuid}'),
        greaterThan(index('notify:')),
      );
      expect(
        index('write:${gen.bleCharacteristicByName('control').uuid}'),
        greaterThan(index('read:${gen.bleCharacteristicByName('live').uuid}')),
      );

      // The passkey instruction precedes the OS bond.
      expect(harness.bondPrompts, 1);
      expect(harness.promptSawBond, isFalse);
      expect(ops.where((entry) => entry == 'bond'), hasLength(1));

      // set_time carries the phone's UTC milliseconds and a timezone offset.
      expect(harness.bridge.controlWrites, hasLength(1));
      expect(
        harness.bridge.controlWrites.single.op,
        gen.ControlOp.setTime.wire,
      );
      final body = harness.bridge.controlBodies.single;
      expect(unixMsOfSetTimeBody(body), _now.millisecondsSinceEpoch);
      expect(
        tzOffsetOfSetTimeBody(body),
        DateTime.now().timeZoneOffset.inMinutes,
      );
      expect(harness.link.lastSetTimeMs, _now.millisecondsSinceEpoch);
      expect(harness.link.negotiatedMtu, 247);

      // V0 recent sync is backward and keeps only the last 15 minutes.
      final sync = harness.bridge.syncRequests.single;
      expect(sync.direction, gen.SyncDirection.backward.wire);
      expect(harness.sink.batches.single.records.map((r) => r.seq), <int>[
        150,
        151,
      ]);
      expect(harness.controller.localMaxSeq, 151);
      expect(harness.link.phase, ConnectionPhase.live);
      expect(harness.controller.phase, ConnectionPhase.live);
      expect(harness.controller.syncState, SyncState.complete);
    });

    test('a valid stored bond skips the passkey prompt on reconnect', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await harness.link.connectAndSecure(harness.device);
      expect(harness.bondPrompts, 1);
      expect(harness.client.bondState, BleBondState.bonded);

      await harness.client.disconnect();
      await _waitFor(() => harness.clock.waits.isNotEmpty);
      await _waitFor(() => harness.controller.phase == ConnectionPhase.live);

      expect(
        harness.bondPrompts,
        1,
        reason: 'stored bond must not prompt again',
      );
      expect(
        harness.client.operations.where((entry) => entry == 'bond'),
        hasLength(1),
      );
    });

    test(
      'an unsecured link takes the bond path once, never a retry loop',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);

        await harness.link.connectAndSecure(harness.device);
        expect(
          harness.client.operations.where((entry) => entry == 'bond'),
          hasLength(1),
        );
        expect(harness.link.isSecured, isTrue);
      },
    );

    test('a failed bond is one named outcome, not a loop', () async {
      final harness = _Harness(forcedBondFailure: BleBondState.timeout);
      addTearDown(harness.dispose);

      await expectLater(
        harness.link.connectAndSecure(harness.device),
        throwsA(
          isA<BridgeLinkException>().having(
            (error) => error.failure,
            'failure',
            BridgeLinkFailure.bondFailed,
          ),
        ),
      );
      expect(
        harness.client.operations.where((entry) => entry == 'bond'),
        hasLength(1),
      );
      expect(harness.link.isSecured, isFalse);
    });
  });

  group('control queue', () {
    test(
      'waits 3 s for a matching result and never assumes ok from the write',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.link.connectAndSecure(harness.device);

        harness.bridge.dropControlResults = true;
        final first = harness.link.setTime(force: true);
        final second = harness.link.setTime(force: true);
        await Future<void>.delayed(Duration.zero);

        final controlWrites = harness.bridge.controlWrites;
        final timeOps = controlWrites
            .where((control) => control.op == gen.ControlOp.setTime.wire)
            .toList();
        expect(timeOps, hasLength(3), reason: 'first connect used one op_id');
        final ids = timeOps.map((control) => control.opId).toSet();
        expect(
          ids,
          hasLength(3),
          reason: 'an outstanding op_id is never reused',
        );

        final firstError = expectLater(
          first,
          throwsA(
            isA<BridgeLinkException>().having(
              (error) => error.failure,
              'failure',
              BridgeLinkFailure.controlTimeout,
            ),
          ),
        );
        final secondError = expectLater(
          second,
          throwsA(
            isA<BridgeLinkException>().having(
              (error) => error.failure,
              'failure',
              BridgeLinkFailure.controlTimeout,
            ),
          ),
        );
        harness.clock.fire(const Duration(seconds: 3));
        await firstError;
        await secondError;
      },
    );

    test(
      'branches on result status instead of the GATT write returning',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.link.connectAndSecure(harness.device);

        harness.bridge.forcedControlStatus = gen.ResultStatus.unsupported;
        final result = await harness.link.setTime(force: true);
        expect(result!.status, BridgeResultStatus.unsupported);
        expect(
          harness.link.lastSetTimeMs,
          _now.millisecondsSinceEpoch,
          reason: 'the first connect set the clock; a rejected op must not',
        );
      },
    );
  });

  group('reconnect', () {
    test(
      'a link drop recovers through backoff and syncs forward from local max',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.link.connectAndSecure(harness.device);
        expect(harness.controller.localMaxSeq, 102);

        harness.bridge
          ..addRecord(
            seq: 103,
            unixS:
                _now
                    .subtract(const Duration(minutes: 2))
                    .millisecondsSinceEpoch ~/
                1000,
          )
          ..addRecord(
            seq: 104,
            unixS:
                _now
                    .subtract(const Duration(minutes: 1))
                    .millisecondsSinceEpoch ~/
                1000,
          );
        harness.client.connectFailuresRemaining = 2;
        harness.sink.batches.clear();

        await harness.client.disconnect();
        await _waitFor(() => harness.clock.waits.length >= 3);
        expect(harness.clock.waits, <Duration>[
          const Duration(seconds: 1),
          const Duration(seconds: 2),
          const Duration(seconds: 4),
        ]);
        await _waitFor(() => harness.controller.phase == ConnectionPhase.live);
        final reconnectSyncs = harness.bridge.syncRequests.skip(1).toList();
        expect(reconnectSyncs, isNotEmpty);
        expect(
          reconnectSyncs.every(
            (request) => request.direction == gen.SyncDirection.forward.wire,
          ),
          isTrue,
          reason: 'a reconnect must not re-read the last 24 h',
        );
        expect(reconnectSyncs.first.cursorSeq, 102);
        expect(
          harness.sink.batches.last.records.map((record) => record.seq),
          containsAll(<int>[103, 104]),
        );
        expect(harness.link.phase, ConnectionPhase.live);
      },
    );

    test('all six failed attempts show the named unreachable state', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.link.connectAndSecure(harness.device);

      harness.client.connectFailuresRemaining = 6;
      await harness.client.disconnect();
      await _waitFor(() => harness.controller.phase == ConnectionPhase.failed);

      expect(harness.clock.waits, <Duration>[
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 4),
        const Duration(seconds: 8),
        const Duration(seconds: 15),
        const Duration(seconds: 30),
      ]);
      expect(harness.controller.connectionTitle, 'Can’t reach the Bridge');
    });

    test('pull-to-refresh cuts the reconnect wait short', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.link.connectAndSecure(harness.device);

      harness.clock.holdWaits = true;
      await harness.client.disconnect();
      await _waitFor(() => harness.link.isReconnecting);
      expect(harness.clock.heldWaits, 1);

      await harness.controller.refreshLink();
      await _waitFor(() => harness.controller.phase == ConnectionPhase.live);
      expect(harness.clock.waits, <Duration>[const Duration(seconds: 1)]);
    });

    test('app resume cuts the wait short too', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.link.connectAndSecure(harness.device);

      harness.clock.holdWaits = true;
      await harness.client.disconnect();
      await _waitFor(() => harness.link.isReconnecting);

      await harness.controller.onAppResume();
      await _waitFor(() => harness.controller.phase == ConnectionPhase.live);
      expect(harness.link.isReconnecting, isFalse);
    });
  });

  group('time sync', () {
    test(
      'sets the clock on first connect and on reconnect only when it drifts',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.link.connectAndSecure(harness.device);
        int setTimeCount() => harness.bridge.controlWrites
            .where((control) => control.op == gen.ControlOp.setTime.wire)
            .length;
        expect(setTimeCount(), 1);

        await harness.client.disconnect();
        await _waitFor(() => harness.clock.waits.isNotEmpty);
        await _waitFor(() => harness.controller.phase == ConnectionPhase.live);
        expect(
          setTimeCount(),
          1,
          reason: 'a healthy clock is not reset on reconnect',
        );

        // A five-second phone-clock jump is beyond the 2 s tolerance.
        harness.clock.now = harness.clock.now.add(const Duration(seconds: 5));
        await harness.client.disconnect();
        await _waitFor(() => harness.clock.waits.length >= 2);
        await _waitFor(() => harness.link.phase == ConnectionPhase.live);
        expect(setTimeCount(), 2);
      },
    );

    test('a bridge that lost its clock is set again on reconnect', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.link.connectAndSecure(harness.device);
      int setTimeCount() => harness.bridge.controlWrites
          .where((control) => control.op == gen.ControlOp.setTime.wire)
          .length;
      expect(setTimeCount(), 1);

      harness.bridge.clockValid = false;
      await harness.client.disconnect();
      await _waitFor(() => harness.clock.waits.isNotEmpty);
      await _waitFor(() => harness.controller.phase == ConnectionPhase.live);
      expect(setTimeCount(), 2);
    });
  });

  group('health watchdog', () {
    test('no notification for 110 s reads live and branches on age', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.link.connectAndSecure(harness.device);

      harness.bridge.ageS = 5;
      harness.clock.fire(const Duration(seconds: 110));
      await _waitFor(() => harness.controller.phase == ConnectionPhase.live);

      harness.bridge.ageS = 200;
      harness.clock.fire(const Duration(seconds: 110));
      await _waitFor(() => harness.controller.phase == ConnectionPhase.stale);
    });

    test('a read failure moves to reconnecting', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.link.connectAndSecure(harness.device);

      harness.clock.holdWaits = true;
      harness.client.readError = const BleException(BleFailure.gattError);
      harness.clock.fire(const Duration(seconds: 110));
      await _waitFor(
        () => harness.controller.phase == ConnectionPhase.reconnecting,
      );
      expect(harness.controller.phase, ConnectionPhase.reconnecting);
    });

    test(
      'any GATT disconnect reconnects even when the last sample was fresh',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.link.connectAndSecure(harness.device);
        harness.bridge.ageS = 1;

        harness.clock.holdWaits = true;
        await harness.client.disconnect();
        await _waitFor(
          () => harness.controller.phase == ConnectionPhase.reconnecting,
        );
        expect(harness.link.isReconnecting, isTrue);
      },
    );
  });

  testWidgets('the unreachable state offers Retry and Forget this phone', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.controller
      ..phase = ConnectionPhase.failed
      ..hasSavedBridge = true;

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: LiveScreen(controller: harness.controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('live.unreachable')), findsOneWidget);
    expect(find.text('Can’t reach the Bridge'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Forget this phone'), findsOneWidget);

    await tester.tap(find.byKey(const Key('live.unreachable.forget')));
    await tester.pump();
    expect(harness.controller.phase, ConnectionPhase.setup);
  });
}

gen.SampleRec _record(int seq, DateTime at) {
  return gen.SampleRec(
    seq: seq,
    unixS: at.millisecondsSinceEpoch ~/ 1000,
    temp: const <int>[2250, 1652, gen.tempDetached, 800],
    flags:
        gen.recordFlagProbe1Attached |
        gen.recordFlagProbe2Attached |
        gen.recordFlagClockValid,
  );
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 500; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('state did not settle');
}

class _Harness {
  _Harness({FakeBridge? bridge, BleBondState? forcedBondFailure})
    : clock = _TestClock() {
    this.bridge = bridge ?? FakeBridge();
    client = FakeBleClient(
      server: this.bridge,
      advertisements: <BleDevice>[this.bridge.advertisement()],
      forcedBondFailure: forcedBondFailure,
      connectDelay: Duration.zero,
      bondDelay: Duration.zero,
      scanInterval: Duration.zero,
    );
    device = this.bridge.advertisement();
    controller = BridgeController(bleClient: client, content: _EmptyContent())
      ..hasSavedBridge = true
      ..phase = ConnectionPhase.offline;
    link = controller.ensureLink(
      nowUtc: () => clock.now,
      elapsed: () => clock.elapsed,
      wait: clock.wait,
      schedule: clock.schedule,
      sink: sink,
      bondPrompt: () async {
        bondPrompts++;
        promptSawBond = client.operations.contains('bond');
        return true;
      },
    );
  }

  final _TestClock clock;
  final _RecordingSink sink = _RecordingSink();
  late final FakeBridge bridge;
  late final FakeBleClient client;
  late final BridgeController controller;
  late final BridgeLink link;
  late final BleDevice device;
  int bondPrompts = 0;
  bool promptSawBond = false;

  Future<void> dispose() async {
    await link.dispose();
    controller.dispose();
    await client.dispose();
    await bridge.dispose();
  }
}

class _RecordingSink implements BridgeSyncSink {
  final List<BridgeSyncBatch> batches = <BridgeSyncBatch>[];

  @override
  Future<void> accept(BridgeSyncBatch batch) async {
    batches.add(batch);
  }
}

class _TestClock {
  DateTime now = _now;
  Duration elapsed = Duration.zero;
  bool holdWaits = false;
  final List<Duration> waits = <Duration>[];
  final List<_HeldWait> _held = <_HeldWait>[];
  final List<_Scheduled> scheduled = <_Scheduled>[];

  int get heldWaits => _held.length;

  Future<void> wait(Duration duration) {
    waits.add(duration);
    if (!holdWaits) {
      now = now.add(duration);
      elapsed += duration;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _held.add(_HeldWait(duration, completer));
    return completer.future;
  }

  BridgeLinkTimer schedule(Duration duration, void Function() action) {
    final entry = _Scheduled(duration, action);
    scheduled.add(entry);
    return _TestTimer(entry);
  }

  void fire(Duration duration) {
    for (final entry in scheduled) {
      if (entry.cancelled || entry.fired || entry.duration != duration) {
        continue;
      }
      entry.fired = true;
      entry.action();
    }
  }

  void releaseHeldWait() {
    if (_held.isEmpty) return;
    final held = _held.removeAt(0);
    now = now.add(held.duration);
    elapsed += held.duration;
    if (!held.completer.isCompleted) held.completer.complete();
  }
}

class _HeldWait {
  _HeldWait(this.duration, this.completer);

  final Duration duration;
  final Completer<void> completer;
}

class _Scheduled {
  _Scheduled(this.duration, this.action);

  final Duration duration;
  final void Function() action;
  bool cancelled = false;
  bool fired = false;
}

class _TestTimer implements BridgeLinkTimer {
  _TestTimer(this.entry);

  final _Scheduled entry;

  @override
  void cancel() => entry.cancelled = true;
}

class _EmptyContent implements BridgeContent {
  @override
  List<double?> get probeTemps => const <double?>[null, null, null, null];

  @override
  DateTime get now => _now;

  @override
  HistoryWindow get historyWindow =>
      HistoryWindow(start: now.subtract(const Duration(hours: 1)), end: now);

  @override
  int get bridgeRecords => 0;

  @override
  int get bridgeCapacity => 0;

  @override
  int get phoneRecords => 0;

  @override
  String get savedDataRange => '—';

  @override
  String get savedDataSize => '0 B';

  @override
  List<ChartPoint> sparkline(int probe, {required bool hasData}) =>
      const <ChartPoint>[];

  @override
  HistoryFixture history(
    HistoryRange range, {
    required bool empty,
    required bool oneProbe,
    required bool estimated,
    required bool missingFromBridge,
    required bool hasGap,
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    return HistoryFixture(
      start: now,
      end: now,
      series: const <ChartSeries>[],
      gapStart: now,
      gapEnd: now,
      gapReason: HistoryGapReason.noSignal,
      estimated: estimated,
      missingFromBridge: missingFromBridge,
    );
  }

  @override
  List<CookSession> cooks() => const <CookSession>[];
}
