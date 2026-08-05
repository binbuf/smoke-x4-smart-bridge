import 'dart:io';
import 'dart:typed_data';

import 'package:bridge_protocol/bridge_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Parses the shared golden vectors in protocol/fixtures/records/ and asserts
/// the values the .expected files declare — the same files the C host tests
/// parse, so a C/Dart divergence shows up as a red test on one side.
void main() {
  final dir = Directory(p.join(_repoRoot(), 'protocol', 'fixtures', 'records'));
  final fixtures =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.hex'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('fixture corpus is present', () {
    expect(fixtures, isNotEmpty);
  });

  test('crc primitives match their published check values', () {
    final check = Uint8List.fromList('123456789'.codeUnits);
    expect(crc16CcittFalse(check), 0x29B1);
    expect(crc32IsoHdlc(check), 0xCBF43926);
  });

  for (final hexFile in fixtures) {
    final name = p.basenameWithoutExtension(hexFile.path);
    final expected = _readExpected(
      File(hexFile.path.replaceAll(RegExp(r'\.hex$'), '.expected')),
    );
    final bytes = _readHex(hexFile);

    test(name, () {
      switch (expected['kind']) {
        case 'sample':
          final s = SampleRec.decode(bytes);
          expect(s.crcOk, expected['crc_ok'] == '1');
          expect(s.t, int.parse(expected['t']!));
          for (var i = 0; i < 4; i++) {
            expect(s.temp[i], int.parse(expected['temp$i']!));
            final expectNull = expected['temp${i}_null'] == '1';
            expect(
              s.tempOrNull(i) == null,
              expectNull,
              reason: 'temp$i null-ness',
            );
            if (expectNull) {
              // The load-bearing rule: a sentinel must never surface as a number.
              expect(s.tempNullable[i], isNull);
            }
          }
          expect(s.flags, int.parse(expected['flags']!));
          expect(s.p1Alarm, expected['flag_p1_alarm'] == '1');
          expect(s.p2Alarm, expected['flag_p2_alarm'] == '1');
          expect(s.p3Alarm, expected['flag_p3_alarm'] == '1');
          expect(s.p4Alarm, expected['flag_p4_alarm'] == '1');
          expect(s.billows, expected['flag_billows'] == '1');
          expect(s.newAlarm, expected['flag_new_alarm'] == '1');
          expect(s.sourceCelsius, expected['flag_source_celsius'] == '1');
          expect(s.rssi, int.parse(expected['rssi']!));
          expect(s.encode(), bytes, reason: 'byte-identical round-trip');

        case 'header':
          final h = SessionHeader.decode(bytes);
          expect(h.crcOk, expected['crc_ok'] == '1');
          expect(h.magicOk, expected['magic_ok'] == '1');
          expect(h.version, int.parse(expected['version']!));
          expect(h.hdrLen, int.parse(expected['hdr_len']!));
          expect(h.recLen, int.parse(expected['rec_len']!));
          expect(h.numProbes, int.parse(expected['num_probes']!));
          expect(h.clockValid, expected['flag_clock_valid'] == '1');
          expect(h.closed, expected['flag_closed'] == '1');
          expect(h.pinned, expected['flag_pinned'] == '1');
          expect(h.sourceCelsius, expected['flag_source_celsius'] == '1');
          expect(h.sessionId, int.parse(expected['session_id']!));
          expect(h.startedUnixMs, int.parse(expected['started_unix_ms']!));
          expect(h.endedUnixMs, int.parse(expected['ended_unix_ms']!));
          expect(h.startedUptimeS, int.parse(expected['started_uptime_s']!));
          expect(h.samplePeriodS, int.parse(expected['sample_period_s']!));
          expect(h.sampleCount, int.parse(expected['sample_count']!));
          expect(h.deviceId, expected['device_id']);
          expect(h.name, expected['name']);
          for (var i = 0; i < 4; i++) {
            expect(h.probeName[i], expected['probe_name$i'] ?? '');
            expect(h.probeRole[i], int.parse(expected['probe_role$i']!));
            expect(h.probeTarget[i], int.parse(expected['probe_target$i']!));
          }
          expect(h.markCount, int.parse(expected['mark_count']!));
          expect(h.encode(), bytes, reason: 'byte-identical round-trip');

        case 'mark':
          final m = MarkRec.decode(bytes);
          expect(m.crcOk, expected['crc_ok'] == '1');
          expect(m.t, int.parse(expected['t']!));
          expect(m.kind, int.parse(expected['mark_kind']!));
          expect(m.probe, int.parse(expected['probe']!));
          expect(m.text, expected['text']);
          expect(m.encode(), bytes, reason: 'byte-identical round-trip');

        // ── BLE payloads (P3.2) ──────────────────────────────────────
        case 'device_info':
          final d = DeviceInfo.decode(bytes);
          expect(d.ver, int.parse(expected['ver']!));
          expect(d.api, int.parse(expected['api']!));
          expect(d.probes, int.parse(expected['probes']!));
          expect(d.caps, int.parse(expected['caps']!));
          expect(d.wifiAp, expected['cap_wifi_ap'] == '1');
          expect(d.wifiSta, expected['cap_wifi_sta'] == '1');
          expect(d.wifiEnterprise, expected['cap_wifi_enterprise'] == '1');
          expect(d.historyPreview, expected['cap_history_preview'] == '1');
          expect(d.ota, expected['cap_ota'] == '1');
          expect(d.battery, expected['cap_battery'] == '1');
          expect(d.id, expected['id']);
          expect(d.model, expected['model']);
          expect(d.fw, expected['fw']);
          expect(d.encode(), bytes, reason: 'byte-identical round-trip');

        case 'wifi_scan_ctrl':
          final c = WifiScanCtrl.decode(bytes);
          expect(c.ver, int.parse(expected['ver']!));
          expect(c.cmd, int.parse(expected['cmd']!));
          expect(c.cmdEnum, isNotNull, reason: 'cmd must name a scan_cmd');
          expect(c.encode(), bytes, reason: 'byte-identical round-trip');

        case 'live_state':
          final s = LiveState.decode(bytes);
          expect(bytes, hasLength(16), reason: '16 ≤ 20: survives MTU 23');
          expect(s.ver, int.parse(expected['ver']!));
          expect(s.flags, int.parse(expected['flags']!));
          expect(s.paired, expected['flag_paired'] == '1');
          expect(s.sessionActive, expected['flag_session_active'] == '1');
          expect(s.billows, expected['flag_billows'] == '1');
          expect(s.alarmActive, expected['flag_alarm_active'] == '1');
          expect(s.clockValid, expected['flag_clock_valid'] == '1');
          for (var i = 0; i < 4; i++) {
            expect(s.temp[i], int.parse(expected['temp$i']!));
            final expectNull = expected['temp${i}_null'] == '1';
            expect(s.tempOrNull(i) == null, expectNull);
            if (expectNull) {
              expect(s.tempNullable[i], isNull);
            }
          }
          expect(s.socPct, int.parse(expected['soc_pct']!));
          expect(s.socPct == socUnknown, expected['soc_unknown'] == '1');
          expect(s.rssiLora, int.parse(expected['rssi_lora']!));
          expect(s.sessionT, int.parse(expected['session_t']!));
          expect(s.encode(), bytes, reason: 'byte-identical round-trip');

        case 'net_status':
          final s = NetStatus.unpack(bytes);
          expect(bytes.length, int.parse(expected['wire_len']!));
          expect(s.ver, int.parse(expected['ver']!));
          expect(s.mode, int.parse(expected['mode']!));
          expect(s.state, int.parse(expected['state']!));
          expect(s.wifiRssi, int.parse(expected['wifi_rssi']!));
          expect(s.ip.join('.'), expected['ip']);
          expect(s.ssid, expected['ssid']);
          expect(s.host, expected['host']);
          expect(s.pack(), bytes, reason: 'byte-identical round-trip');

        case 'wifi_scan_result':
          final r = WifiScanResult.unpack(bytes);
          expect(bytes.length, int.parse(expected['wire_len']!));
          expect(r.index, int.parse(expected['index']!));
          expect(r.total, int.parse(expected['total']!));
          expect(r.rssi, int.parse(expected['rssi']!));
          expect(r.auth, int.parse(expected['auth']!));
          expect(r.channel, int.parse(expected['channel']!));
          expect(r.ssid, expected['ssid']);
          expect(r.pack(), bytes, reason: 'byte-identical round-trip');

        case 'wifi_config':
          final c = WifiConfig.unpack(bytes);
          expect(bytes.length, int.parse(expected['wire_len']!));
          expect(c.mode, int.parse(expected['mode']!));
          expect(c.auth, int.parse(expected['auth']!));
          expect(c.ssid, expected['ssid']);
          expect(c.psk, expected['psk']);
          expect(c.user, expected['user']);
          expect(c.pack(), bytes, reason: 'byte-identical round-trip');

        case 'device_control':
          final c = DeviceControl.unpack(bytes);
          expect(bytes.length, int.parse(expected['wire_len']!));
          expect(c.op, int.parse(expected['op']!));
          expect(c.bodyRaw, hasLength(int.parse(expected['body_len']!)));
          if (c.opEnum == ControlOp.setTime) {
            final t = CtrlSetTime.decode(c.bodyRaw);
            expect(t.unixMs, int.parse(expected['unix_ms']!));
            expect(t.tzOffsetMin, int.parse(expected['tz_offset_min']!));
          }
          expect(c.pack(), bytes, reason: 'byte-identical round-trip');

        case 'result':
          final r = ResultFrame.unpack(bytes);
          expect(bytes.length, int.parse(expected['wire_len']!));
          expect(r.opEcho, int.parse(expected['op_echo']!));
          expect(r.status, int.parse(expected['status']!));
          expect(r.detail, expected['detail']);
          expect(r.pack(), bytes, reason: 'byte-identical round-trip');

        case 'history_preview':
          final h = HistoryPreview.unpack(bytes);
          expect(bytes.length, int.parse(expected['wire_len']!));
          expect(h.probeIndex, int.parse(expected['probe_index']!));
          expect(h.values, hasLength(int.parse(expected['count']!)));
          expect(h.values.length, lessThanOrEqualTo(120));
          expect(h.bucketMin, int.parse(expected['bucket_min']!));
          for (var i = 0; i < h.values.length; i++) {
            expect(h.values[i], int.parse(expected['v$i']!));
            expect(h.valuesNullable[i] == null, expected['v${i}_null'] == '1');
          }
          expect(h.pack(), bytes, reason: 'byte-identical round-trip');

        // ── v1.1: full history over BLE (§5.10–§5.11) ────────────────
        case 'history_ctrl':
          final c = HistoryCtrl.decode(bytes);
          expect(bytes.length, int.parse(expected['wire_len']!));
          expect(c.ver, int.parse(expected['ver']!));
          expect(c.req, int.parse(expected['req']!));
          expect(c.reqEnum, isNotNull, reason: 'req must name a history_req');
          expect(c.stride, int.parse(expected['stride']!));
          expect(c.sessionId, int.parse(expected['session_id']!));
          expect(c.fromT, int.parse(expected['from_t']!));
          expect(c.toT, int.parse(expected['to_t']!));
          expect(c.encode(), bytes, reason: 'byte-identical round-trip');

        case 'history_session':
          final s = HistorySession.decode(bytes);
          expect(bytes.length, int.parse(expected['wire_len']!));
          expect(s.sessionId, int.parse(expected['session_id']!));
          expect(s.startedUnixMs, int.parse(expected['started_unix_ms']!));
          expect(s.endedUnixMs, int.parse(expected['ended_unix_ms']!));
          expect(s.sampleCount, int.parse(expected['sample_count']!));
          expect(s.samplePeriodS, int.parse(expected['sample_period_s']!));
          expect(s.numProbes, int.parse(expected['num_probes']!));
          expect(s.flags, int.parse(expected['flags']!));
          expect(s.clockValid, expected['flag_clock_valid'] == '1');
          expect(s.closed, expected['flag_closed'] == '1');
          expect(s.pinned, expected['flag_pinned'] == '1');
          // 04 §4.6's auto-name is 26 BYTES — the em-dash costs three — so
          // the field is 28. A shrink must be a red test, not a clipped
          // cook name.
          expect(s.name, expected['name']);
          expect(s.encode(), bytes, reason: 'byte-identical round-trip');

        case 'history_data':
          final f = HistoryData.unpack(bytes);
          expect(bytes.length, int.parse(expected['wire_len']!));
          expect(f.ver, int.parse(expected['ver']!));
          expect(f.kind, int.parse(expected['data_kind']!));
          expect(f.kindEnum, isNotNull);
          expect(f.seq, int.parse(expected['seq']!));
          expect(f.flags, int.parse(expected['flags']!));
          expect(f.last, expected['last'] == '1');
          expect(f.count, int.parse(expected['count']!));
          expect(f.payloadRaw, hasLength(int.parse(expected['len']!)));
          // The 7-byte fixed prefix arrives whole in the first chunk even at
          // the 20-byte default MTU (§4) — what makes the total length
          // knowable from chunk one.
          expect(bytes.length - f.payloadRaw.length, 7);
          if (f.kindEnum == HistoryKind.samples) {
            expect(f.payloadRaw, hasLength(f.count * SampleRec.size));
            for (var i = 0; i < f.count; i++) {
              // Verbatim records: decoding one out of the frame payload
              // still verifies the CRC written to flash.
              final r = SampleRec.decode(f.payloadRaw, i * SampleRec.size);
              expect(r.crcOk, isTrue);
              expect(r.t, int.parse(expected['s${i}_t']!));
            }
            expect(
              SampleRec.decode(f.payloadRaw, SampleRec.size).tempOrNull(2),
              expected['s1_temp2_null'] == '1' ? isNull : isNotNull,
            );
          } else if (f.kindEnum == HistoryKind.end) {
            expect(f.count, 0);
            expect(f.payloadRaw, hasLength(1));
            expect(f.payloadRaw[0], int.parse(expected['status']!));
            expect(f.last, isTrue, reason: 'the terminator always sets last');
          }
          expect(f.pack(), bytes, reason: 'byte-identical round-trip');

        default:
          fail('unknown fixture kind ${expected['kind']}');
      }
    });
  }

  test('future-version header is read, not rejected', () {
    final bytes = _readHex(File(p.join(dir.path, 'header-future-version.hex')));
    final h = SessionHeader.decode(bytes);
    expect(h.version, 2);
    expect(h.recLen, 20, reason: 'readers must stride by rec_len');
    expect(h.crcOk, isTrue);
  });

  test('corrupt sample fails its CRC check', () {
    final bytes = _readHex(File(p.join(dir.path, 'sample-four-attached.hex')));
    bytes[5] ^= 0xFF; // flip a temp byte
    expect(SampleRec.decode(bytes).crcOk, isFalse);
  });
}

Uint8List _readHex(File f) {
  final bytes = <int>[];
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    for (final tok in t.split(RegExp(r'\s+'))) {
      bytes.add(int.parse(tok, radix: 16));
    }
  }
  return Uint8List.fromList(bytes);
}

Map<String, String> _readExpected(File f) {
  final map = <String, String>{};
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    map[t.substring(0, i)] = t.substring(i + 1);
  }
  return map;
}

String _repoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File(p.join(dir.path, 'protocol', 'records.yaml')).existsSync()) {
      return dir.path;
    }
    if (dir.parent.path == dir.path) throw StateError('repo root not found');
    dir = dir.parent;
  }
}
