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
  final fixtures = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.hex'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('the corpus is present (5 samples + 2 headers + 1 mark)', () {
    expect(fixtures.length, 8);
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
