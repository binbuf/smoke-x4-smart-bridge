/// N15.3 — `BleTransport` against the fake bridge peripheral.
///
/// Pure Dart (`package:test`), so this runs in both `flutter test` and
/// `dart test test/data`. No radio, no phone, no board: the fake speaks the
/// generated codecs, so what is proven here is the contract — the binary
/// reassembly, the capability latch, the control correlation, and full history
/// over GATT.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:smoke_bridge/data/dto/records.g.dart' hide MarkKind, ProbeRole;
import 'package:smoke_bridge/data/transport/ble_gatt.dart';
import 'package:smoke_bridge/data/transport/ble_transport.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart'
    hide NetStatus;
import 'package:smoke_bridge/domain/domain.dart' show MarkKind;
import 'package:test/test.dart';

import '../support/fake_peripheral.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// A bonded, connected transport over the fake — the state every test below
/// starts from unless it is testing the way there.
Future<(BleTransport, FakePeripheral)> bonded({
  FakePeripheralConfig? config,
  FakeBridgeState? state,
}) async {
  final fake = FakePeripheral(config: config, state: state);
  await fake.connect('AA:BB:CC:DD:A4:F2');
  await fake.bond();
  await fake.requestMtu(247);
  final t = BleTransport(fake);
  await t.start();
  return (t, fake);
}

void main() {
  group('the seam and the codec', () {
    test('device_info is readable with no bond at all', () async {
      final fake = FakePeripheral();
      await fake.connect('x');
      final info = DeviceInfo.decode(await fake.read(BridgeChar.deviceInfo));
      expect(info.id, 'A4F2');
      expect(info.model, 'heltec-v3');
      expect(info.probes, 4);
      expect(info.historyPreview, isTrue);
      await fake.dispose();
    });

    test('capabilities derive full history from the device caps bit', () async {
      final (t, _) = await bonded();
      expect(t.capabilities.live, isTrue);
      expect(t.capabilities.historyPreview, isTrue);
      // A27 — derived from device_info caps b6, not declared.
      expect(t.capabilities.fullHistory, isTrue);
      expect(t.capabilities.ota, isFalse);
      await t.close();
    });

    test('an older bridge still reports no full history', () async {
      final (t, _) = await bonded(state: FakeBridgeState(caps: 0x0B));
      expect(t.capabilities.fullHistory, isFalse);
      expect(t.capabilities.historyPreview, isTrue);
      await t.close();
    });

    test('the status blob decorates the scan entry', () async {
      final fake = FakePeripheral();
      final adv = await fake.scan().first;
      final d = BridgeDiscovery.fromAdvertisement(adv);
      expect(d.name, 'SmokeBridge-A4F2');
      expect(d.pitTempF10, 2431);
      expect(d.sessionMinutes, 252); // 4 h 12 m
      expect(d.paired, isTrue);
      expect(d.sessionActive, isTrue);
      // No battery truth until F12: null, never a confident 0 %.
      expect(d.socPct, isNull);
      await fake.dispose();
    });

    test('a detached pit renders as null, never 0 °F', () async {
      final fake = FakePeripheral(
        state: FakeBridgeState(pitTempF10: tempDetached),
      );
      final d = BridgeDiscovery.fromAdvertisement(await fake.scan().first);
      expect(d.pitTempF10, isNull);
      await fake.dispose();
    });
  });

  group('notifications and reassembly', () {
    test('live_state notifications become sample events', () async {
      final (t, fake) = await bonded();
      final events = <TransportEvent>[];
      final sub = t.events().listen(events.add);
      fake.pushSample(pitTempF10: 2455);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      final sample = events.single.toSample();
      expect(sample.tempsF10[0], 2455);
      // Sentinels survive the whole way to the domain object: never 0.
      expect(sample.tempsF10[2], isNull);
      expect(sample.tempsF10[3], isNull);
      expect(sample.tempsF10.where((v) => v == 0), isEmpty);
      await sub.cancel();
      await t.close();
    });

    test('net_status notifications become net events', () async {
      final (t, fake) = await bonded();
      final events = <TransportEvent>[];
      final sub = t.events().listen(events.add);
      fake.notify(
        BridgeChar.netStatus,
        NetStatus(
          mode: NetMode.sta.wire,
          state: NetState.up.wire,
          ip: [192, 168, 1, 42],
          ssidRaw: _bytes('Backyard'),
          hostRaw: _bytes('smokebridge'),
        ).pack(),
      );
      await Future<void>.delayed(Duration.zero);
      final e = events.singleWhere((e) => e.type == 'net');
      expect(e.data['mode'], 'sta');
      expect(e.data['state'], 'up');
      expect(e.data['ip'], '192.168.1.42');
      await sub.cancel();
      await t.close();
    });

    test('a net_status split across three notifications reassembles', () async {
      final (t, fake) = await bonded(
        config: const FakePeripheralConfig(negotiatedMtu: 23),
      );
      final frame = NetStatus(
        mode: NetMode.sta.wire,
        state: NetState.up.wire,
        wifiRssi: -54,
        ip: [192, 168, 1, 42],
        ssidRaw: _bytes('A-Reasonably-Long-Network-Name'),
        hostRaw: _bytes('smokebridge'),
      );
      final bytes = frame.pack();
      // 10 B fixed prefix + ssid + host, chunked at MTU-3 = 20 → three
      // notifications. Computed, not hardcoded.
      expect(bytes.length, 10 + frame.ssid.length + frame.host.length);
      expect((bytes.length / 20).ceil(), 3);
      final got = <NetStatus>[];
      final sub = t.netStatus.listen(got.add);
      fake.notify(BridgeChar.netStatus, bytes);
      await Future<void>.delayed(Duration.zero);
      expect(got, hasLength(1));
      expect(got.single.pack(), bytes);
      expect(got.single.ssid, 'A-Reasonably-Long-Network-Name');
      await sub.cancel();
      await t.close();
    });

    test('an interleaved fragment fails loudly, never silently', () {
      final asm = NotificationReassembler(
        (b) => b.length < 4 ? null : 4 + b[3],
      );
      expect(asm.add(Uint8List.fromList([1, 0, 0, 4])), isNull);
      expect(
        () => asm.add(Uint8List.fromList([1, 2, 3, 4, 5, 6])),
        throwsA(isA<FormatException>()),
      );
      // And it recovers: the next well-formed frame parses.
      final ok = asm.add(Uint8List.fromList([1, 0, 0, 1, 9]));
      expect(ok, isNotNull);
      expect(ok!.length, 5);
    });
  });

  group('status and live', () {
    test('status maps identity, net, power and the open session', () async {
      final state = FakeBridgeState()..recordCook(hours: 1);
      final (t, _) = await bonded(state: state);
      final s = await t.status();
      expect(s.device.id, 'A4F2');
      expect(s.device.model, 'heltec-v3');
      expect(s.net.mode, 'ap');
      expect(s.net.ip, '192.168.4.1');
      expect(s.power.socPct, isNull, reason: 'socUnknown is absent, not 0');
      expect(s.pairing.numProbes, 4);
      // The open cook's id comes from the history session list.
      expect(s.session.active, isTrue);
      expect(s.session.id, 0x1A);
      expect(s.cookClock.set, isTrue);
      expect(s.cookClock.elapsedS, 15120);
      await t.close();
    });

    test('live() maps four probes and keeps detached null', () async {
      final (t, _) = await bonded();
      final live = await t.live();
      expect(live.probes, hasLength(4));
      expect(live.probes[0].tempF10, 2431);
      expect(live.probes[2].tempF10, isNull);
      expect(live.probes[2].attached, isFalse);
      expect(live.probes[0].attached, isTrue);
      await t.close();
    });
  });

  group('control', () {
    test('postMark correlates the result by op_echo', () async {
      final (t, fake) = await bonded();
      // An unrelated answer lands first; correlation must not pick it up.
      unawaited(
        Future<void>.delayed(
          Duration.zero,
          () => fake.notify(
            BridgeChar.result,
            ResultFrame(status: ResultStatus.ok.wire).pack(),
          ),
        ),
      );
      final mark = await t.postMark(
        0x1A,
        t: 120,
        kind: MarkKind.wrapped,
        text: 'wrapped',
      );
      expect(mark.t, 120);
      expect(mark.kind, MarkKind.wrapped);
      final (slot, value) = fake.writes.last;
      expect(slot, BridgeChar.deviceControl);
      final ctrl = DeviceControl.unpack(value);
      expect(ctrl.opEnum, ControlOp.mark);
      expect(CtrlMark.unpack(ctrl.bodyRaw).kindEnum?.name, 'wrapped');
      await t.close();
    });

    test('verbs map onto the frozen op table', () async {
      final (t, fake) = await bonded();
      final sent = <ControlOp?>[];
      for (final call in <Future<void> Function()>[
        t.pairSync,
        t.unpair,
        t.restart,
        t.powerOff,
        () => t.setTime(1774051200000),
        () => t.stopSession(0x1A),
      ]) {
        await call();
        sent.add(DeviceControl.unpack(fake.writes.last.$2).opEnum);
      }
      expect(sent, [
        ControlOp.pair,
        ControlOp.unpair,
        ControlOp.reboot,
        ControlOp.powerOff,
        ControlOp.setTime,
        ControlOp.sessionStop,
      ]);
      await t.close();
    });

    test('setCookClock sends the elapsed seconds', () async {
      final (t, fake) = await bonded();
      final clock = await t.setCookClock(startedUnixMs: 1);
      expect(clock.set, isTrue);
      final ctrl = DeviceControl.unpack(fake.writes.last.$2);
      expect(ctrl.opEnum, ControlOp.setCookClock);
      expect(CtrlSetCookClock.decode(ctrl.bodyRaw).elapsedS, greaterThan(0));
      final cleared = await t.clearCookClock();
      expect(cleared.set, isFalse);
      await t.close();
    });

    test('a refused control surfaces as a typed transport exception', () async {
      final (t, _) = await bonded();
      await t.stopSession(0x1A); // now idle
      await expectLater(
        t.postMark(0x1A, kind: MarkKind.note),
        throwsA(
          isA<TransportException>().having((e) => e.code, 'code', 'invalid'),
        ),
      );
      await t.close();
    });

    test('applyNetwork writes wifi_config and returns the AP PSK', () async {
      final (t, fake) = await bonded();
      final ap = await t.applyNetwork(mode: 'ap');
      expect(ap['psk'], 'Gk7mR2xQpT');
      final sta = await t.applyNetwork(
        mode: 'sta',
        ssid: 'Backyard',
        psk: 'hunter2boo',
      );
      expect(sta['detail'], isEmpty);
      final written = WifiConfig.unpack(
        fake.writes.lastWhere((w) => w.$1 == BridgeChar.wifiConfig).$2,
      );
      expect(written.ssid, 'Backyard');
      expect(written.psk, 'hunter2boo');
      await t.close();
    });

    test('Wi-Fi-only surfaces refuse with a typed unsupported', () async {
      final (t, _) = await bonded();
      expect(() => t.commitNetwork(), throwsA(isA<TransportUnsupported>()));
      expect(() => t.deviceConfig(), throwsA(isA<TransportUnsupported>()));
      expect(
        () => t.setDeviceConfig(const {}),
        throwsA(isA<TransportUnsupported>()),
      );
      expect(() => t.alarmConfig(), throwsA(isA<TransportUnsupported>()));
      expect(() => t.deleteSession(1), throwsA(isA<TransportUnsupported>()));
      expect(
        () => t.uploadOta(const Stream<List<int>>.empty()),
        throwsA(isA<TransportUnsupported>()),
      );
      await t.close();
    });
  });

  group('full history over BLE', () {
    test('twelve hours of an overnight cook arrive over Bluetooth', () async {
      final state = FakeBridgeState()..recordCook();
      final (t, _) = await bonded(state: state);
      final all = [for (final b in await t.samples(0x1A).toList()) ...b];
      expect(all, hasLength(1440), reason: '12 h at the 30 s cadence');
      expect(all.first.t, 0);
      expect(all.last.t, 1439 * 30);
      // THE invariant, surviving 1,440 records: detached is null, never 0.
      expect(all.every((s) => s.tempsF10[2] == null), isTrue);
      expect(all.every((s) => s.tempsF10[0] != null), isTrue);
      await t.close();
    });

    test('a range request fetches only the delta', () async {
      final state = FakeBridgeState()..recordCook(hours: 4);
      final (t, _) = await bonded(state: state);
      final all = [
        for (final b in await t.samples(0x1A, fromT: 3600).toList()) ...b,
      ];
      expect(all.first.t, 3600);
      expect(all, hasLength(360));
      expect(all.last.t, 479 * 30);
      await t.close();
    });

    test('the session list carries an open cook honestly', () async {
      final state = FakeBridgeState()..recordCook();
      final (t, _) = await bonded(state: state);
      final sessions = await t.sessions();
      expect(sessions, hasLength(1));
      final s = sessions.single;
      expect(s.id, 0x1A);
      expect(s.name, 'Cook — Sat 14 Mar, 06:12');
      expect(s.closed, isFalse);
      expect(s.endedUnixMs, isNull, reason: 'open: 0 must read as absent');
      expect(s.sampleCount, 1440);
      await t.close();
    });

    test('a failed history status throws rather than truncating', () async {
      final state = FakeBridgeState()..recordCook(hours: 2);
      final (t, _) = await bonded(
        state: state,
        config: const FakePeripheralConfig(historyStatus: ResultStatus.failed),
      );
      await expectLater(
        t.samples(0x1A).toList(),
        throwsA(isA<TransportException>()),
      );
      await t.close();
    });

    test('a dropped frame is caught by the seq chain', () async {
      final state = FakeBridgeState()..recordCook(hours: 2);
      final (t, _) = await bonded(
        state: state,
        config: const FakePeripheralConfig(historyDropFrame: 3),
      );
      await expectLater(
        t.samples(0x1A).toList(),
        throwsA(isA<FormatException>()),
      );
      await t.close();
    });

    test('busy is typed', () async {
      final state = FakeBridgeState()..recordCook(hours: 1);
      final (t, _) = await bonded(
        state: state,
        config: const FakePeripheralConfig(historyBusy: true),
      );
      await expectLater(
        t.samples(0x1A).toList(),
        throwsA(
          isA<TransportException>().having((e) => e.code, 'code', 'busy'),
        ),
      );
      await t.close();
    });

    test('marks stream over the same channel', () async {
      final state = FakeBridgeState()..recordCook(hours: 2);
      state.cookMarks[0x1A] = [
        MarkRec(t: 600, kind: 2, textRaw: utf8ToPadded('lid open', 24)),
        MarkRec(
          t: 1800,
          kind: 1,
          probe: 1,
          textRaw: utf8ToPadded('wrapped', 24),
        ),
      ];
      final (t, _) = await bonded(state: state);
      final marks = await t.marks(0x1A);
      expect(marks, hasLength(2));
      expect(marks.first.kind, MarkKind.lidOpen);
      expect(marks.last.kind, MarkKind.wrapped);
      expect(marks.last.text, 'wrapped');
      await t.close();
    });

    test('a v1.0 bridge keeps the live link working without history', () async {
      final (t, _) = await bonded(state: FakeBridgeState(caps: 0x0B));
      expect(await t.sessions(), isEmpty);
      expect(await t.marks(0x1A), isEmpty);
      await expectLater(
        t.samples(0x1A).toList(),
        throwsA(isA<TransportUnsupported>()),
      );
      await t.close();
    });

    test('two concurrent requests serialise instead of interleaving', () async {
      final state = FakeBridgeState()..recordCook(hours: 2);
      final (t, _) = await bonded(state: state);
      final results = await Future.wait([
        t.samples(0x1A).toList(),
        t.samples(0x1A).toList(),
      ]);
      for (final batches in results) {
        expect([for (final x in batches) ...x], hasLength(240));
      }
      await t.close();
    });
  });
}
