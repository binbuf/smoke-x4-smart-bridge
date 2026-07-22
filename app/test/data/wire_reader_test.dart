/// A3.2 — the rec_len-honouring .smk reader over the real brisket fixture,
/// plus a synthetic future-version archive that must be READ, not rejected.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dto/records.g.dart' as dto;
import 'package:smoke_bridge/data/transport/wire_reader.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';

import 'records_parity_test.dart' show repoRoot;

void main() {
  final smkBytes = File(
    '${repoRoot()}/protocol/fixtures/brisket-18h.smk',
  ).readAsBytesSync();
  final mrkBytes = File(
    '${repoRoot()}/protocol/fixtures/brisket-18h.mrk',
  ).readAsBytesSync();

  group('brisket-18h.smk', () {
    final archive = SmkArchive.parse(smkBytes);

    test('header maps to a domain session', () {
      final session = archive.toSession();
      expect(session.id, 27);
      expect(session.name, 'Brisket 18h (synthetic)');
      expect(session.numProbes, 4);
      expect(session.startedUnixMs, isNotNull);
      expect(session.probes[0].role, ProbeRole.pit);
      expect(session.probes[1].name, 'Brisket');
      expect(session.probes[1].targetF10, 2030);
      expect(session.probes[3].role, ProbeRole.ambient);
      expect(session.probes[3].targetF10, isNull, reason: '0 = no target');
    });

    test('every record parses and the count matches the header', () {
      expect(archive.records.length, archive.header.sampleCount);
      expect(archive.records.length, greaterThan(2000));
    });

    test('detached probes come back null, never 0', () {
      final samples = archive.toSamples();
      final window = samples
          .where((s) => s.t >= 9 * 3600 && s.t < 9 * 3600 + 2400)
          .toList();
      expect(window, isNotEmpty);
      for (final s in window) {
        expect(s.tempsF10[3], isNull);
      }
      // And nowhere does a detached slot surface as zero.
      expect(samples.any((s) => s.tempsF10.contains(0)), isFalse);
    });

    test('the ~1% dropout is visible as gaps', () {
      final gaps = findGaps(archive.toSamples().map((s) => s.t));
      expect(gaps, isNotEmpty);
    });

    test('marks parse with kinds and text', () {
      final marks = marksFromBytes(mrkBytes);
      expect(marks.length, 4);
      expect(marks[0].kind, MarkKind.lidOpen);
      expect(marks[1].text, 'wrapped');
    });
  });

  group('forward compatibility', () {
    test('a future version=2, rec_len=20 archive is read, not rejected', () {
      // Build a v2 archive: same header layout, longer records whose
      // trailing 4 bytes are unknown-to-us extension data.
      final v1 = SmkArchive.parse(smkBytes);
      final h = v1.header;
      final futureHeader = dto.SessionHeader(
        version: 2,
        recLen: 20,
        numProbes: h.numProbes,
        flags: h.flags,
        sessionId: 99,
        startedUnixMs: h.startedUnixMs,
        startedUptimeS: h.startedUptimeS,
        samplePeriodS: h.samplePeriodS,
        sampleCount: 3,
        deviceIdRaw: h.deviceIdRaw,
        nameRaw: dto.utf8ToPadded('From the future', 40),
        probeNameRaw: h.probeNameRaw,
        probeRole: h.probeRole,
        probeTarget: h.probeTarget,
      );
      final b = BytesBuilder()..add(futureHeader.encode());
      for (var i = 0; i < 3; i++) {
        final rec = dto.SampleRec(
          t: 30 * (i + 1),
          temp: [2400 + i, 1500 + i, dto.tempDetached, 800],
          rssi: -70,
        );
        b.add(rec.encode());
        b.add([0xDE, 0xAD, 0xBE, 0xEF]); // v2 extension bytes we skip
      }

      final archive = SmkArchive.parse(Uint8List.fromList(b.toBytes()));
      expect(archive.header.version, 2);
      expect(archive.records.length, 3, reason: 'strided by rec_len=20');
      expect(archive.records[1].t, 60);
      expect(archive.records[2].temp[0], 2402);
      expect(archive.toSamples()[0].tempsF10[2], isNull);
    });

    test('a torn tail stops cleanly at the last valid record', () {
      final whole = SmkArchive.parse(smkBytes).records.length;
      final torn = Uint8List.fromList(smkBytes.sublist(0, smkBytes.length - 7));
      final archive = SmkArchive.parse(torn);
      expect(archive.records.length, whole - 1);
    });

    test('bad magic is rejected loudly', () {
      final corrupt = Uint8List.fromList(smkBytes);
      corrupt[0] = 0x58; // 'X'
      expect(() => SmkArchive.parse(corrupt), throwsFormatException);
    });
  });

  group('cookgen ↔ detector cross-check (T2.3)', () {
    test("the generated brisket's stall is detected by A2.4", () {
      final samples = SmkArchive.parse(smkBytes).toSamples();
      final detector = StallDetector();
      final stalledAt = <int>[];
      for (final s in samples) {
        final f10 = s.tempsF10[1]; // Brisket, the food probe
        if (detector.add(s.t, f10 == null ? null : f10 / 10.0)) {
          stalledAt.add(s.t);
        }
      }
      expect(
        stalledAt,
        isNotEmpty,
        reason:
            'the generator and the detector must agree about what a '
            'stall looks like',
      );
      // The scenario stalls from 5 h for ~3 h; detection needs the 30-min
      // sustain, so it lands inside the window.
      expect(stalledAt.first, greaterThan(5 * 3600));
      expect(stalledAt.first, lessThan(8 * 3600));
      // And it un-stalls after the breakout.
      expect(stalledAt.last, lessThan(10 * 3600));
    });
  });
}
