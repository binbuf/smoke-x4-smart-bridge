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
