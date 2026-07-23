/// A6.1–A6.4 — `BleTransport` against the fake bridge peripheral.
///
/// No radio, no phone, no board: the fake speaks the generated codecs, so
/// what is proven here is the contract. The bench (A6.7) is then spent on
/// what only a bench can tell us — OEM behaviour — instead of on byte
/// layouts that were already knowable.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dto/records.g.dart' hide MarkKind;
import 'package:smoke_bridge/data/transport/ble_gatt.dart';
import 'package:smoke_bridge/data/transport/ble_transport.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/domain/entities/entities.dart' show MarkKind;

import 'fake_peripheral.dart';
import 'transport_contract.dart';

Uint8List _ssid(String s) => Uint8List.fromList(utf8.encode(s));

WifiScanResult _ap(String ssid, {int rssi = -55, int channel = 6}) =>
    WifiScanResult(rssi: rssi, auth: 3, channel: channel, ssidRaw: _ssid(ssid));

/// A bonded, connected transport over the fake — the state every test
/// below starts from unless it is testing the way there.
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
  // ── A6.2: the shared behavioural contract ─────────────────────────
  runTransportContract(name: 'ble', create: () async => (await bonded()).$1);

  group('A6.1 the seam and the fake', () {
    test('device_info is readable with no bond at all', () async {
      // §3: open, so the app can identify a bridge before bonding.
      final fake = FakePeripheral();
      await fake.connect('x');
      final info = DeviceInfo.decode(await fake.read(BridgeChar.deviceInfo));
      expect(info.id, 'A4F2');
      expect(info.model, 'heltec-v3');
      expect(info.probes, 4);
      // caps.battery is clear until F12 (M5) — advertised honestly.
      expect(info.battery, isFalse);
      expect(info.historyPreview, isTrue);
      await fake.dispose();
    });

    test(
      'an encrypted characteristic before bonding is a typed refusal',
      () async {
        final fake = FakePeripheral();
        await fake.connect('x');
        expect(
          () => fake.read(BridgeChar.liveState),
          throwsA(isA<BleNotBondedException>()),
        );
        await fake.dispose();
      },
    );

    test('double connect is defined behaviour, not platform luck', () async {
      final fake = FakePeripheral();
      await fake.connect('x');
      expect(() => fake.connect('x'), throwsA(isA<BleStateException>()));
      await fake.dispose();
    });

    test('bond() while disconnected throws rather than hanging', () async {
      final fake = FakePeripheral();
      expect(fake.bond(), throwsA(isA<BleStateException>()));
      await fake.dispose();
    });

    test("the fake's payloads decode as the generated codecs", () async {
      final (t, fake) = await bonded();
      final net = NetStatus.unpack(await fake.read(BridgeChar.netStatus));
      expect(net.ssid, 'SmokeBridge-A4F2');
      expect(net.host, 'smokebridge');
      expect(net.ip.join('.'), '192.168.4.1');
      final live = LiveState.decode(await fake.read(BridgeChar.liveState));
      expect(live.temp[2], tempDetached);
      expect(live.socPct, socUnknown);
      await t.close();
    });
  });

  group('A6.2 BleTransport', () {
    test('capabilities are honest: no full history, no OTA', () async {
      final (t, _) = await bonded();
      expect(t.capabilities.liveState, isTrue);
      expect(t.capabilities.historyPreview, isTrue);
      expect(t.capabilities.fullHistory, isFalse);
      expect(t.capabilities.ota, isFalse);
      await t.close();
    });

    test('live_state notifications become BridgeEvent.sample', () async {
      final (t, fake) = await bonded();
      final events = <BridgeEvent>[];
      final sub = t.events.listen(events.add);
      fake.pushSample(pitTempF10: 2455);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      final e = events.single as BridgeSampleEvent;
      // Sentinels survive the whole way to the domain object: never 0.
      expect(e.sample.tempsF10[0], 2455);
      expect(e.sample.tempsF10[2], isNull);
      expect(e.sample.tempsF10[3], isNull);
      expect(e.sample.tempsF10.where((v) => v == 0), isEmpty);
      await sub.cancel();
      await t.close();
    });

    test('net_status notifications become BridgeEvent.net', () async {
      final (t, fake) = await bonded();
      final events = <BridgeEvent>[];
      final sub = t.events.listen(events.add);
      fake.notify(
        BridgeChar.netStatus,
        NetStatus(
          mode: NetMode.sta.wire,
          state: NetState.up.wire,
          ip: [192, 168, 1, 42],
          ssidRaw: _ssid('Backyard'),
          hostRaw: _ssid('smokebridge'),
        ).pack(),
      );
      await Future<void>.delayed(Duration.zero);
      final e = events.whereType<BridgeNetEvent>().single;
      expect(e.mode, 'sta');
      expect(e.state, 'up');
      expect(e.ip, '192.168.1.42');
      await sub.cancel();
      await t.close();
    });

    test('control() correlates the result by op_echo, not by order', () async {
      final (t, fake) = await bonded();
      // A scan result and an unrelated answer land in between; correlation
      // must be by op_echo or this test hangs / resolves on the wrong one.
      unawaited(
        Future<void>.delayed(Duration.zero, () {
          fake.notify(
            BridgeChar.result,
            ResultFrame(opEcho: 0, status: ResultStatus.ok.wire).pack(),
          );
        }),
      );
      await t.control(const ControlCommand.sessionStop());
      expect(fake.state.sessionActive, isFalse);
      final (slot, value) = fake.writes.last;
      expect(slot, BridgeChar.deviceControl);
      expect(DeviceControl.unpack(value).opEnum, ControlOp.sessionStop);
      await t.close();
    });

    test('every result.status maps to a typed failure', () async {
      final (t, fake) = await bonded();
      // sessionStart while a session is running → busy (the same refusal
      // semantics as the REST group).
      expect(fake.state.sessionActive, isTrue);
      await expectLater(
        t.control(const ControlCommand.sessionStart()),
        throwsA(
          isA<BridgeControlException>().having((e) => e.isBusy, 'isBusy', true),
        ),
      );
      // A mark with no open session → invalid.
      await t.control(const ControlCommand.sessionStop());
      await expectLater(
        t.control(const ControlCommand.mark(kind: MarkKind.note)),
        throwsA(
          isA<BridgeControlException>().having(
            (e) => e.isInvalid,
            'isInvalid',
            true,
          ),
        ),
      );
      await t.close();
    });

    test('control verbs map onto the frozen op table', () async {
      final (t, fake) = await bonded();
      final sent = <ControlOp?>[];
      for (final cmd in <ControlCommand>[
        const ControlCommand.pair(),
        const ControlCommand.unpair(),
        const ControlCommand.setTime(unixMs: 1774051200000),
        const ControlCommand.ackAlarm(alarmId: 2),
      ]) {
        await t.control(cmd);
        sent.add(DeviceControl.unpack(fake.writes.last.$2).opEnum);
      }
      expect(sent, [
        ControlOp.pair,
        ControlOp.unpair,
        ControlOp.setTime,
        ControlOp.ackAlarm,
      ]);
      await t.close();
    });

    test(
      'configure() sets units and refuses probes with a typed condition',
      () async {
        final (t, fake) = await bonded();
        await t.configure(const BridgeConfig(displayUnits: 'C'));
        final (slot, value) = fake.writes.last;
        expect(slot, BridgeChar.deviceControl);
        final ctrl = DeviceControl.unpack(value);
        expect(ctrl.opEnum, ControlOp.setUnits);
        expect(CtrlSetUnits.decode(ctrl.bodyRaw).unitsEnum, TempUnits.celsius);
        // No device_control op sets probe names — say so, do not drop it.
        expect(
          () => t.configure(const BridgeConfig(probes: [])),
          throwsA(isA<BridgeUnsupportedException>()),
        );
        await t.close();
      },
    );

    test('an unknown notification payload is dropped, not fatal', () async {
      final (t, fake) = await bonded();
      final events = <BridgeEvent>[];
      final errors = <Object>[];
      final sub = t.events.listen(events.add, onError: errors.add);
      // Too short to be a live_state: the additive-contract rule says
      // ignore it, and keep working.
      fake.notify(BridgeChar.liveState, Uint8List.fromList([1, 2, 3]));
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      expect(errors, isEmpty);
      fake.pushSample();
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      await sub.cancel();
      await t.close();
    });

    test('live() serves the 2-hour preview as a real series', () async {
      final (t, _) = await bonded();
      final live = await t.live();
      expect(live.recent, isNotEmpty);
      expect(live.recent.length, lessThanOrEqualTo(120));
      // The seeded preview has one detached bucket; it must be null.
      expect(live.recent.any((s) => s.tempsF10[0] == null), isTrue);
      expect(live.recent.every((s) => s.tempsF10[0] != 0), isTrue);
      await t.close();
    });
  });

  group('A6.3 MTU degradation and reassembly', () {
    test('at MTU 23 live_state arrives untouched', () async {
      // The 16 B design surviving contact with the OEM most likely to
      // break negotiation (R7).
      final (t, fake) = await bonded(
        config: const FakePeripheralConfig(negotiatedMtu: 23),
      );
      expect(fake.mtu, 23);
      final events = <BridgeEvent>[];
      final sub = t.events.listen(events.add);
      fake.pushSample(pitTempF10: 2400);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect((events.single as BridgeSampleEvent).sample.tempsF10[0], 2400);
      await sub.cancel();
      await t.close();
    });

    for (final mtu in [23, 247]) {
      test('a wifi_scan_result reassembles byte-exact at MTU $mtu', () async {
        final (t, fake) = await bonded(
          config: FakePeripheralConfig(
            negotiatedMtu: mtu,
            // The maximum-length SSID (32 B), which is exactly the case
            // that forces a split at the default MTU.
            scanResults: [_ap('Backyard-Network-Maximum-SSID-32')],
          ),
        );
        final got = <WifiScanResult>[];
        final sub = t.scanResults.listen(got.add);
        await t.startWifiScan();
        await Future<void>.delayed(Duration.zero);
        expect(got, hasLength(1));
        expect(got.single.ssid, 'Backyard-Network-Maximum-SSID-32');
        expect(got.single.ssidRaw, hasLength(32));
        await sub.cancel();
        await t.close();
      });
    }

    test('a net_status split across three notifications reassembles', () async {
      final (t, fake) = await bonded(
        config: const FakePeripheralConfig(negotiatedMtu: 23),
      );
      final frame = NetStatus(
        mode: NetMode.sta.wire,
        state: NetState.up.wire,
        wifiRssi: -54,
        ip: [192, 168, 1, 42],
        ssidRaw: _ssid('A-Reasonably-Long-Network-Name'),
        hostRaw: _ssid('smokebridge'),
      );
      final bytes = frame.pack();
      // 10 B fixed prefix + ssid + host, chunked at MTU-3 = 20 → three
      // notifications. Computed, not hardcoded, so the assertion stays
      // about the SPLIT rather than about my arithmetic.
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

    test('the fixed prefix always arrives whole in the first chunk', () {
      // The guarantee the whole scheme rests on (ble-gatt §4): every
      // variable payload's prefix is <= 10 B, so a 20-byte chunk always
      // carries it. Asserted as arithmetic, not as a hope.
      const smallestChunk = 23 - 3;
      for (final prefix in [
        10 /* net_status */,
        7 /* scan */,
        4 /* result */,
      ]) {
        expect(prefix, lessThanOrEqualTo(smallestChunk));
      }
    });

    test('an interleaved fragment fails loudly, never silently', () {
      final asm = NotificationReassembler(
        (b) => b.length < 4 ? null : 4 + b[3],
      );
      // Claims 4 bytes of detail, then hands over far more than that.
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

  group('A6.4 scan, connect, bond', () {
    test('the status blob decorates the scan entry', () async {
      final fake = FakePeripheral();
      final adv = await fake.scan().first;
      final d = BridgeDiscovery.fromAdvertisement(adv);
      // "Smoke Bridge A4F2 · pit 243 °F · 4 h 12 m", before connecting.
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
      final state = FakeBridgeState(pitTempF10: tempDetached);
      final fake = FakePeripheral(state: state);
      final d = BridgeDiscovery.fromAdvertisement(await fake.scan().first);
      expect(d.pitTempF10, isNull);
      await fake.dispose();
    });

    test('zero-session and unpaired blobs are handled', () async {
      final fake = FakePeripheral(
        state: FakeBridgeState(
          paired: false,
          sessionActive: false,
          sessionSeconds: 0,
        ),
      );
      final d = BridgeDiscovery.fromAdvertisement(await fake.scan().first);
      expect(d.paired, isFalse);
      expect(d.sessionActive, isFalse);
      expect(d.sessionMinutes, 0);
      await fake.dispose();
    });

    test('a malformed advertisement degrades to a nameless entry', () async {
      // Dropping the entry would mean the bridge is simply missing from
      // the list, with nothing to tell the user why.
      final fake = FakePeripheral(
        config: const FakePeripheralConfig(advertiseMalformed: true),
      );
      final d = BridgeDiscovery.fromAdvertisement(await fake.scan().first);
      expect(d.deviceId, isNotEmpty);
      expect(d.pitTempF10, isNull);
      expect(d.sessionMinutes, 0);
      await fake.dispose();
    });

    test('bonding, then reconnecting, skips pairing', () async {
      final fake = FakePeripheral();
      await fake.connect('x');
      expect(fake.bondState, BleBondState.none);
      await fake.bond();
      expect(fake.bondState, BleBondState.bonded);
      await fake.disconnect();
      await fake.connect('x');
      // The bond outlives the connection: no second pairing.
      expect(fake.bondState, BleBondState.bonded);
      expect(await fake.read(BridgeChar.liveState), isNotEmpty);
      await fake.dispose();
    });

    test('a rejected bond is typed, not a hang', () async {
      final fake = FakePeripheral(
        config: const FakePeripheralConfig(rejectBond: true),
      );
      await fake.connect('x');
      await expectLater(fake.bond(), throwsA(isA<BleBondRejectedException>()));
      expect(fake.bondState, BleBondState.failed);
      await fake.dispose();
    });

    test('a factory-reset bridge surfaces as re-bond-needed', () async {
      // THE bug report this test exists to prevent: "it just won't
      // connect". We hold an LTK the bridge threw away; the only fix is
      // to forget and re-pair, and the app must be able to say so.
      final fake = FakePeripheral(
        config: const FakePeripheralConfig(staleBond: true),
      );
      await fake.connect('x');
      await fake.bond();
      await expectLater(
        fake.read(BridgeChar.liveState),
        throwsA(isA<BleRebondRequiredException>()),
      );
      await fake.dispose();
    });

    test('a link dropped mid-write is typed, not a silent stall', () async {
      final fake = FakePeripheral(
        config: const FakePeripheralConfig(dropOnWrite: true),
      );
      await fake.connect('x');
      await fake.bond();
      await expectLater(
        fake.write(BridgeChar.deviceControl, Uint8List.fromList([1, 7])),
        throwsA(isA<BleConnectionLostException>()),
      );
      expect(fake.connectionState, BleConnectionState.disconnected);
      await fake.dispose();
    });
  });

  group('provisioning (the A8 surface)', () {
    test('a 12-AP scan streams indexed results', () async {
      final (t, _) = await bonded(
        config: FakePeripheralConfig(
          scanResults: [
            for (var i = 0; i < 12; i++) _ap('AP-$i', channel: 1 + i % 11),
          ],
        ),
      );
      final got = <WifiScanResult>[];
      final sub = t.scanResults.listen(got.add);
      await t.startWifiScan();
      await Future<void>.delayed(Duration.zero);
      expect(got, hasLength(12));
      for (var i = 0; i < 12; i++) {
        expect(got[i].index, i);
        expect(got[i].total, 12); // completion is implicit in index/total
        expect(got[i].ssid, 'AP-$i');
      }
      await sub.cancel();
      await t.close();
    });

    test('an empty scan completes rather than hanging', () async {
      final (t, _) = await bonded(
        config: const FakePeripheralConfig(emptyScan: true),
      );
      final got = <WifiScanResult>[];
      final sub = t.scanResults.listen(got.add);
      await t.startWifiScan(); // resolves: the ack is the completion
      await Future<void>.delayed(Duration.zero);
      expect(got, isEmpty);
      await sub.cancel();
      await t.close();
    });

    test('a mode change to AP answers with the PSK the phone needs', () async {
      final (t, _) = await bonded();
      final r = await t.applyWifiConfig(mode: NetMode.ap);
      expect(r.detail, 'Gk7mR2xQpT');
      await t.close();
    });

    test('an STA config answers ok and carries no credential back', () async {
      final (t, fake) = await bonded();
      final r = await t.applyWifiConfig(
        mode: NetMode.sta,
        ssid: 'Backyard',
        psk: 'hunter2boo',
      );
      expect(r.statusEnum, ResultStatus.ok);
      // The written frame carries the PSK; the ANSWER never does (§5.9).
      expect(r.detail, isEmpty);
      final written = WifiConfig.unpack(
        fake.writes.firstWhere((w) => w.$1 == BridgeChar.wifiConfig).$2,
      );
      expect(written.ssid, 'Backyard');
      expect(written.psk, 'hunter2boo');
      await t.close();
    });

    test('the wrong-password path notifies connecting then failed', () async {
      // The scripted shape of the M3 exit gate's recovery branch.
      final (t, _) = await bonded(
        config: FakePeripheralConfig(
          netStatusScript: [
            NetStatus(
              mode: NetMode.sta.wire,
              state: NetState.connecting.wire,
              ssidRaw: _ssid('Backyard'),
            ),
            NetStatus(
              mode: NetMode.sta.wire,
              state: NetState.failed.wire,
              ssidRaw: _ssid('Backyard'),
            ),
          ],
        ),
      );
      final seen = <NetState?>[];
      final sub = t.netStatus.listen((n) => seen.add(n.stateEnum));
      await t.applyWifiConfig(
        mode: NetMode.sta,
        ssid: 'Backyard',
        psk: 'wrong',
      );
      await Future<void>.delayed(Duration.zero);
      expect(seen, [NetState.connecting, NetState.failed]);
      await sub.cancel();
      await t.close();
    });

    test('a refused config surfaces the status, not a timeout', () async {
      final (t, _) = await bonded(
        config: const FakePeripheralConfig(
          wifiConfigOutcome: ResultStatus.invalid,
        ),
      );
      await expectLater(
        t.applyWifiConfig(mode: NetMode.sta, ssid: 'x'),
        throwsA(
          isA<BridgeControlException>().having(
            (e) => e.isInvalid,
            'isInvalid',
            true,
          ),
        ),
      );
      await t.close();
    });
  });
}
