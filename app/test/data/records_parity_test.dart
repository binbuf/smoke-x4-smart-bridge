/// A3.2 — the app's dto copy of the generated codec parses every shared
/// golden vector to the same values the C host tests assert. Same files,
/// same expectations: drift between the languages is a red test, not a
/// field returning null in the field.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dto/records.g.dart';

void main() {
  final dir = Directory('${repoRoot()}/protocol/fixtures/records');
  final fixtures =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.hex'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('the corpus is present (8 storage + 16 BLE payload vectors)', () {
    // v1.1 added four: the history request, a session entry, a mid-stream
    // samples frame, and the terminator (ble-gatt §5.10–§5.11).
    expect(fixtures.length, 24);
  });

  for (final hexFile in fixtures) {
    final name = hexFile.uri.pathSegments.last.replaceAll('.hex', '');
    test(name, () {
      final bytes = readHex(hexFile);
      final expected = readExpected(
        File(hexFile.path.replaceAll(RegExp(r'\.hex$'), '.expected')),
      );
      switch (expected['kind']) {
        case 'sample':
          final s = SampleRec.decode(bytes);
          expect(s.crcOk, expected['crc_ok'] == '1');
          expect(s.t, int.parse(expected['t']!));
          for (var i = 0; i < 4; i++) {
            expect(s.temp[i], int.parse(expected['temp$i']!));
            expect(s.tempOrNull(i) == null, expected['temp${i}_null'] == '1');
          }
          expect(s.rssi, int.parse(expected['rssi']!));
          expect(s.encode(), bytes);
        case 'header':
          final h = SessionHeader.decode(bytes);
          expect(h.crcOk, expected['crc_ok'] == '1');
          expect(h.magicOk, expected['magic_ok'] == '1');
          expect(h.version, int.parse(expected['version']!));
          expect(h.recLen, int.parse(expected['rec_len']!));
          expect(h.name, expected['name']);
          expect(h.deviceId, expected['device_id']);
          expect(h.encode(), bytes);
        case 'mark':
          final m = MarkRec.decode(bytes);
          expect(m.crcOk, expected['crc_ok'] == '1');
          expect(m.text, expected['text']);
          expect(m.encode(), bytes);
        // ── BLE payloads (P3.2) — the app's half of the drift guard ──
        case 'device_info':
          final d = DeviceInfo.decode(bytes);
          expect(d.caps, int.parse(expected['caps']!));
          expect(d.battery, expected['cap_battery'] == '1');
          expect(d.id, expected['id']);
          expect(d.model, expected['model']);
          expect(d.fw, expected['fw']);
          expect(d.encode(), bytes);
        case 'wifi_scan_ctrl':
          final c = WifiScanCtrl.decode(bytes);
          expect(c.cmd, int.parse(expected['cmd']!));
          expect(c.encode(), bytes);
        case 'live_state':
          final s = LiveState.decode(bytes);
          for (var i = 0; i < 4; i++) {
            expect(s.temp[i], int.parse(expected['temp$i']!));
            expect(s.tempOrNull(i) == null, expected['temp${i}_null'] == '1');
          }
          expect(s.socPct == socUnknown, expected['soc_unknown'] == '1');
          expect(s.sessionT, int.parse(expected['session_t']!));
          expect(s.encode(), bytes);
        case 'net_status':
          final s = NetStatus.unpack(bytes);
          expect(s.ip.join('.'), expected['ip']);
          expect(s.ssid, expected['ssid']);
          expect(s.host, expected['host']);
          expect(s.pack(), bytes);
        case 'wifi_scan_result':
          final r = WifiScanResult.unpack(bytes);
          expect(r.index, int.parse(expected['index']!));
          expect(r.total, int.parse(expected['total']!));
          expect(r.ssid, expected['ssid']);
          expect(r.pack(), bytes);
        case 'wifi_config':
          final c = WifiConfig.unpack(bytes);
          expect(c.ssid, expected['ssid']);
          expect(c.psk, expected['psk']);
          expect(c.pack(), bytes);
        case 'device_control':
          final c = DeviceControl.unpack(bytes);
          expect(c.op, int.parse(expected['op']!));
          expect(c.bodyRaw, hasLength(int.parse(expected['body_len']!)));
          expect(c.pack(), bytes);
        case 'result':
          final r = ResultFrame.unpack(bytes);
          expect(r.status, int.parse(expected['status']!));
          expect(r.detail, expected['detail']);
          expect(r.pack(), bytes);
        case 'history_preview':
          final h = HistoryPreview.unpack(bytes);
          expect(h.values, hasLength(int.parse(expected['count']!)));
          for (var i = 0; i < h.values.length; i++) {
            expect(h.valuesNullable[i] == null, expected['v${i}_null'] == '1');
          }
          expect(h.pack(), bytes);

        // ── v1.1: full history over BLE (§5.10–§5.11) ────────────────
        case 'history_ctrl':
          final c = HistoryCtrl.decode(bytes);
          expect(bytes, hasLength(HistoryCtrl.size));
          expect(c.reqEnum, isNotNull, reason: 'req must name a history_req');
          expect(c.stride, int.parse(expected['stride']!));
          expect(c.sessionId, int.parse(expected['session_id']!));
          expect(c.fromT, int.parse(expected['from_t']!));
          expect(c.toT, int.parse(expected['to_t']!));
          expect(c.encode(), bytes);

        case 'history_session':
          final s = HistorySession.decode(bytes);
          expect(bytes, hasLength(HistorySession.size));
          expect(s.sessionId, int.parse(expected['session_id']!));
          expect(s.startedUnixMs, int.parse(expected['started_unix_ms']!));
          expect(s.endedUnixMs, int.parse(expected['ended_unix_ms']!));
          expect(s.sampleCount, int.parse(expected['sample_count']!));
          expect(s.samplePeriodS, int.parse(expected['sample_period_s']!));
          expect(s.numProbes, int.parse(expected['num_probes']!));
          expect(s.clockValid, expected['flag_clock_valid'] == '1');
          expect(s.closed, expected['flag_closed'] == '1');
          expect(s.pinned, expected['flag_pinned'] == '1');
          // The em-dashed auto-name of 04 §4.6 is 26 BYTES. A 24-byte field
          // clipped it, which is why this one is 28 — held here so a future
          // shrink is a red test and not a truncated cook name.
          expect(s.name, expected['name']);
          expect(s.encode(), bytes);

        case 'history_data':
          final f = HistoryData.unpack(bytes);
          expect(f.kindEnum, isNotNull);
          expect(f.seq, int.parse(expected['seq']!));
          expect(f.last, expected['last'] == '1');
          expect(f.count, int.parse(expected['count']!));
          expect(f.payloadRaw, hasLength(int.parse(expected['len']!)));
          // The 7-byte fixed prefix arrives whole in the first chunk even
          // at the 20-byte default MTU — the §4 guarantee the reassembler
          // reads the total length from.
          expect(bytes.length - f.payloadRaw.length, 7);
          if (f.kindEnum == HistoryKind.samples) {
            expect(f.payloadRaw, hasLength(f.count * SampleRec.size));
            for (var i = 0; i < f.count; i++) {
              // Records travel VERBATIM: one decoded straight out of the
              // frame payload still verifies its own CRC.
              final r = SampleRec.decode(f.payloadRaw, i * SampleRec.size);
              expect(r.crcOk, isTrue);
              expect(r.t, int.parse(expected['s${i}_t']!));
            }
            expect(
              SampleRec.decode(f.payloadRaw, SampleRec.size).tempOrNull(2),
              expected['s1_temp2_null'] == '1' ? isNull : isNotNull,
            );
          } else if (f.kindEnum == HistoryKind.end) {
            // The terminator is the only frame that reports a status.
            expect(f.count, 0);
            expect(f.payloadRaw, hasLength(1));
            expect(f.payloadRaw[0], int.parse(expected['status']!));
            expect(f.last, isTrue);
          }
          expect(f.pack(), bytes);
        default:
          fail('unknown kind ${expected['kind']}');
      }
    });
  }
}

String repoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/protocol/records.yaml').existsSync()) {
    if (dir.parent.path == dir.path) {
      throw StateError('repo root not found');
    }
    dir = dir.parent;
  }
  return dir.path;
}

Uint8List readHex(File f) {
  final bytes = <int>[];
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) {
      continue;
    }
    bytes.addAll(t.split(RegExp(r'\s+')).map((x) => int.parse(x, radix: 16)));
  }
  return Uint8List.fromList(bytes);
}

Map<String, String> readExpected(File f) {
  final map = <String, String>{};
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) {
      continue;
    }
    final i = t.indexOf('=');
    map[t.substring(0, i)] = t.substring(i + 1);
  }
  return map;
}
