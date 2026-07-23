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

  test('the corpus is present (8 storage + 12 BLE payload vectors)', () {
    expect(fixtures.length, 20);
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
