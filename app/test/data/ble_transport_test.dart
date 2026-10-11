import 'dart:typed_data';

import 'package:smoke_bridge/data/ble/ble_transport.dart';
import 'package:smoke_bridge/data/ble/bridge_transport.dart';
import 'package:smoke_bridge/data/dto/records.g.dart';
import 'package:test/test.dart';

import '../support/fake_peripheral.dart';

/// Connect + bond a fake peripheral so encrypted characteristics are readable.
Future<BleTransport> _connected({
  FakePeripheralConfig? config,
  FakeBridgeState? state,
  int mtu = 247,
}) async {
  final fake = FakePeripheral(config: config, state: state);
  await fake.connect('AA:BB:CC:DD:AA:BB');
  await fake.bond();
  await fake.requestMtu(mtu);
  final transport = BleTransport(fake);
  await transport.start();
  return transport;
}

void main() {
  group('BleTransport live_state', () {
    test(
      'readLive decodes the 16-byte payload with sentinels as null',
      () async {
        final t = await _connected();
        final live = await t.readLive();
        expect(live.paired, isTrue);
        expect(live.tempsF10, [2431, 1632, null, null]);
        expect(live.socPct, isNull, reason: 'SOC_UNKNOWN decodes to null');
        await t.close();
      },
    );

    test('liveUpdates emits a snapshot on each notify', () async {
      final t = await _connected();
      final seen = <LiveSnapshot>[];
      final sub = t.liveUpdates.listen(seen.add);
      (t.client as FakePeripheral).pushSample(pitTempF10: 2550);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, hasLength(1));
      expect(seen.single.tempsF10.first, 2550);
      await t.close();
    });
  });

  group('BleTransport full history', () {
    test('sessions lists a recorded cook', () async {
      final state = FakeBridgeState();
      state.recordCook(hours: 2);
      final t = await _connected(state: state);
      final sessions = await t.sessions();
      expect(sessions, hasLength(1));
      expect(sessions.single.id, 0x1A);
      expect(sessions.single.sampleCount, 2 * 120);
      await t.close();
    });

    test(
      'samples streams every record and preserves the detached sentinel',
      () async {
        final state = FakeBridgeState();
        state.recordCook(hours: 2);
        final t = await _connected(state: state);

        final all = <int>[];
        var detachedNulls = 0;
        await for (final batch in t.samples(0x1A)) {
          for (final s in batch) {
            all.add(s.t);
            if (s.tempsF10[2] == null) {
              detachedNulls++;
            }
          }
        }
        expect(all, hasLength(2 * 120));
        expect(all.first, 0);
        expect(all.last, (2 * 120 - 1) * 30);
        expect(detachedNulls, all.length, reason: 'probe 3 never becomes 0');
        await t.close();
      },
    );

    test('fromT transfers only the tail (the delta-resync shape)', () async {
      final state = FakeBridgeState();
      state.recordCook(hours: 2);
      final t = await _connected(state: state);

      final ts = <int>[];
      await for (final batch in t.samples(0x1A, fromT: 1000)) {
        for (final s in batch) {
          ts.add(s.t);
        }
      }
      expect(ts, isNotEmpty);
      expect(ts.every((x) => x >= 1000), isTrue);
      expect(ts.length, lessThan(2 * 120));
      await t.close();
    });

    test('a non-ok end frame surfaces as a typed failure', () async {
      final state = FakeBridgeState();
      state.recordCook(hours: 1);
      final t = await _connected(
        state: state,
        config: const FakePeripheralConfig(historyStatus: ResultStatus.failed),
      );
      await expectLater(
        t.samples(0x1A).drain<void>(),
        throwsA(isA<TransportException>()),
      );
      await t.close();
    });

    test('a dropped frame is detected by the seq gap', () async {
      final state = FakeBridgeState();
      state.recordCook(hours: 2);
      final t = await _connected(
        state: state,
        config: const FakePeripheralConfig(historyDropFrame: 0),
      );
      await expectLater(
        t.samples(0x1A).drain<void>(),
        throwsA(isA<FormatException>()),
      );
      await t.close();
    });
  });

  group('NotificationReassembler', () {
    test('concatenates chunks until the fixed-prefix length is reached', () {
      Uint8List? whole;
      final asm = NotificationReassembler(
        (b) => b.length < 3 ? null : 3 + b[2],
      );
      // ver, kind, len=5 -> total 8 bytes, split 4/4.
      whole ??= asm.add(Uint8List.fromList([1, 2, 5, 9]));
      expect(whole, isNull);
      whole = asm.add(Uint8List.fromList([9, 9, 9, 9]));
      expect(whole, hasLength(8));
    });
  });

  group('BleTransport cook clock and link', () {
    test(
      'setCookClock declares the age and clamps to the OLED width',
      () async {
        final t = await _connected();
        final fake = t.client as FakePeripheral;

        await t.setCookClock(90);
        expect(fake.cookClockElapsedS, 90);

        // 100 hours is past 99:59; the write must not fail, the value caps.
        await t.setCookClock(360000);
        expect(fake.cookClockElapsedS, cookClockMaxS);

        await t.clearCookClock();
        expect(fake.cookClockElapsedS, isNull);
        await t.close();
      },
    );

    test('readRssi reads the phone-bridge hop', () async {
      final t = await _connected(config: const FakePeripheralConfig(rssi: -64));
      expect(await t.readRssi(), -64);
      await t.close();
    });
  });
}
