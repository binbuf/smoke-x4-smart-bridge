import 'package:lora/lora.dart';
import 'package:test/test.dart';

/// A synthetic-but-faithful monitor log: ANSI colour, boot noise, app_lora
/// header+payload pairs, duplicate smoke_x lines, a sync + ACK exchange, a
/// °C flip, an alarm episode, a detach, a reset, and junk.
const sampleLog = '''
--- idf_monitor on COM7 115200 ---
ets Jul 29 2019 12:21:46
I (310) cpu_start: Pro cpu up.
\x1b[0;32mI (1200) app_lora: Starting LoRa Rx\x1b[0m
I (5000) smoke_x: Device is not paired, waiting for sync on 915
\x1b[0;32mI (9000) app_lora: Packet received - Size: 27 RSSI: -45, SNR: 10\x1b[0m
\x1b[0;32mI (9001) app_lora: 020001,|abCDe,160,32,69,54,\x1b[0m
I (9010) smoke_x: Received sync message: 020001,|abCDe,160,32,69,54,
I (9020) smoke_x: Frequency set to: 910 MHz
I (9030) smoke_x: Sending sync acknowledgement to transmitter: |abCDe,SUCCESS,
I (39000) app_lora: Packet received - Size: 87 RSSI: -71, SNR: 9
I (39001) app_lora: |abCDe,30,1,0,0,700,0,200,100,0,710,0,200,100,0,720,0,200,100,0,730,0,200,100,0,0,
I (39010) smoke_x: X4 DATA: |abCDe,30,1,0,0,700,0,200,100,0,710,0,200,100,0,720,0,200,100,0,730,0,200,100,0,0,
I (69000) app_lora: Packet received - Size: 87 RSSI: -72, SNR: 9
I (69001) app_lora: |abCDe,30,1,1,0,705,1,200,100,0,712,0,200,100,0,722,0,200,100,0,733,0,200,100,0,0,
I (99000) app_lora: Packet received - Size: 87 RSSI: -70, SNR: 8
I (99001) app_lora: |abCDe,30,1,1,0,707,1,200,100,0,713,0,200,100,0,724,0,200,100,0,735,0,200,100,0,0,
I (129000) app_lora: Packet received - Size: 87 RSSI: -74, SNR: 9
I (129001) app_lora: |abCDe,30,0,0,0,215,0,93,38,3,0,0,0,0,0,721,0,93,38,0,732,0,93,38,0,0,
I (159030) app_lora: Packet received - Size: 12 RSSI: -80, SNR: 4
I (159031) app_lora: junk with spaces not a payload
I (189000) app_lora: Packet received - Size: 40 RSSI: -66, SNR: 7
I (189001) app_lora: |abCDe,30,1,0,0,700,0,200,100,0,0,
I (189002) smoke_x: Received unrecognized message type: |abCDe,30,1,0,0,700,0,200,100,0,0,
ets Jul 29 2019 12:21:46
I (300) cpu_start: Pro cpu up.
I (8000) app_lora: Packet received - Size: 87 RSSI: -71, SNR: 9
I (8001) app_lora: |abCDe,30,1,0,0,708,0,200,100,0,714,0,200,100,0,725,0,200,100,0,736,0,200,100,0,0,
''';

void main() {
  final packets = parseMonitorLog(sampleLog);

  test('extracts payloads, skipping junk and non-payload lines', () {
    expect(packets, hasLength(8));
    expect(packets.any((p) => p.payload.contains(' ')), isFalse);
  });

  test('classifies by comma count', () {
    final classes = [for (final p in packets) p.messageClass];
    expect(classes, [
      'sync6',
      'ack2',
      'state26',
      'state26',
      'state26',
      'state26',
      'unknown11',
      'state26',
    ]);
  });

  test('binds RSSI/SNR from the app_lora header line', () {
    final sync = packets.first;
    expect(sync.rssi, -45);
    expect(sync.snr, 10);
    expect(packets[2].rssi, -71);
  });

  test('dedupes the smoke_x re-log of an app_lora payload', () {
    final x4 = packets.where(
      (p) => p.payload.startsWith('|abCDe,30,1,0,0,700,0,200,100,0,710'),
    );
    expect(x4, hasLength(1), reason: 'X4 DATA duplicate must collapse');
  });

  test('the transmitted ACK is captured and marked tx', () {
    final ack = packets.singleWhere((p) => p.messageClass == 'ack2');
    expect(ack.source, CaptureSource.txAck);
    expect(ack.payload, '|abCDe,SUCCESS,');
  });

  test('a reset starts a new boot segment', () {
    expect(packets.last.bootIndex, 1);
    expect(packets.first.bootIndex, 0);
  });

  test('loralog round-trips', () {
    final text = writeLoralog(packets, sourceLabel: 'test');
    final back = readLoralog(text);
    expect(back.length, packets.length);
    for (var i = 0; i < packets.length; i++) {
      expect(back[i].payload, packets[i].payload);
      expect(back[i].tMs, packets[i].tMs);
      expect(back[i].rssi, packets[i].rssi);
      expect(back[i].bootIndex, packets[i].bootIndex);
      expect(back[i].messageClass, packets[i].messageClass);
    }
  });

  group('report', () {
    final report = CaptureReport(packets);

    test('sync frequency decodes little-endian to 910.5 MHz', () {
      final sync = packets.first;
      expect(CaptureReport.syncFrequencyHz(sync), 910500000);
    });

    test('Q1: field1 values collected', () {
      expect(report.field1Values(), {'30': 5});
    });

    test('Q4: sees the detached probe state 3', () {
      final states = report.probeStateValues();
      expect(states.keys, containsAll(['0', '3']));
    });

    test('Q8: the alarm episode is one 2-packet run', () {
      expect(report.newAlarmRuns(), [2]);
    });

    test('units flip is visible', () {
      expect(report.unitsValues().keys, containsAll(['1', '0']));
    });

    test('intervals ignore boot boundaries', () {
      final iv = report.stateIntervalsMs();
      expect(iv.every((d) => d > 0), isTrue);
      expect(iv, isNotEmpty);
      expect(iv.first, 30000);
    });

    test('markdown carries the question verdicts and vectors', () {
      final md = report.markdown(sourceLabel: 'test');
      expect(md, contains('Never left `30`'));
      expect(md, contains('Q8'));
      expect(md, contains('910.5 MHz'));
      expect(md, contains('first sync6'));
      expect(md, contains('probe state `3`'));
      expect(md, contains('units °C'));
      expect(md, contains('field0=`020001`'));
    });
  });
}
