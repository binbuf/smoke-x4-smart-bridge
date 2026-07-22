/// Wire emission (T2.3): real files in the P1 layout — a 256 B header plus
/// N × 16 B CRC'd sample records, with marks in a sibling .mrk.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bridge_protocol/bridge_protocol.dart';

import 'thermal.dart';


/// A fully generated cook, ready to serialize.
class GeneratedCook {
  GeneratedCook({
    required this.header,
    required this.samples,
    required this.marks,
  });

  final SessionHeader header;
  final List<SampleRec> samples;
  final List<MarkRec> marks;

  Uint8List smkBytes() {
    final b = BytesBuilder();
    b.add(header.encode());
    for (final s in samples) {
      b.add(s.encode());
    }
    return b.toBytes();
  }

  Uint8List mrkBytes() {
    final b = BytesBuilder();
    for (final m in marks) {
      b.add(m.encode());
    }
    return b.toBytes();
  }

  void writeTo(String smkPath) {
    File(smkPath).writeAsBytesSync(smkBytes());
    final mrkPath = smkPath.replaceAll(RegExp(r'\.smk$'), '.mrk');
    if (marks.isNotEmpty) {
      File(mrkPath).writeAsBytesSync(mrkBytes());
    }
  }
}

/// A parsed .smk (+ optional sibling .mrk). The reader honours `hdr_len` and
/// `rec_len` from the header rather than assuming sizes — a future v2 record
/// stays readable.
class SmkFile {
  SmkFile({required this.header, required this.samples, required this.marks});

  final SessionHeader header;
  final List<SampleRec> samples;
  final List<MarkRec> marks;

  static SmkFile read(String smkPath) {
    final bytes = File(smkPath).readAsBytesSync();
    final smk = parse(bytes);
    final mrkPath = smkPath.replaceAll(RegExp(r'\.smk$'), '.mrk');
    final marks = <MarkRec>[];
    if (File(mrkPath).existsSync()) {
      final mb = File(mrkPath).readAsBytesSync();
      for (var off = 0; off + MarkRec.size <= mb.length; off += MarkRec.size) {
        marks.add(MarkRec.decode(mb, off));
      }
    }
    return SmkFile(header: smk.header, samples: smk.samples, marks: marks);
  }

  static SmkFile parse(Uint8List bytes) {
    final header = SessionHeader.decode(bytes);
    final samples = <SampleRec>[];
    final recLen = header.recLen;
    for (var off = header.hdrLen;
        off + recLen <= bytes.length;
        off += recLen) {
      // Stride by rec_len; parse the leading 16 bytes we understand.
      samples.add(SampleRec.decode(bytes, off));
    }
    return SmkFile(header: header, samples: samples, marks: const []);
  }
}

int _tenths(double f) => (f * 10).round().clamp(-5800, 5720);

/// Converts model output to wire records. Detached probes carry the sentinel,
/// never a number — the specific bug the reference has and we refuse to.
List<SampleRec> toSampleRecs(List<ModelSample> model) => [
      for (final m in model)
        SampleRec(
          t: m.tS,
          temp: [
            for (var i = 0; i < 4; i++)
              m.detached[i] ? tempDetached : _tenths(m.tempsF[i]),
          ],
          flags: m.sourceCelsius ? 1 << 6 : 0,
          rssi: m.rssi,
        ),
    ];

SessionHeader buildHeader({
  required int sessionId,
  required int sampleCount,
  required int markCount,
  required List<ProbeSpec> probes,
  required String name,
  int samplePeriodS = 30,
  bool clockValid = true,
  int startedUnixMs = 1774051200000, // fixed, deterministic (2026-03-20 UTC)
  List<int> targetsF10 = const [2250, 2030, 2030, 0],
}) {
  final probeNames = Uint8List(48);
  for (var i = 0; i < 4; i++) {
    probeNames.setRange(i * 12, (i + 1) * 12, utf8ToPadded(probes[i].name, 12));
  }
  return SessionHeader(
    numProbes: 4,
    flags: clockValid ? 1 : 0,
    sessionId: sessionId,
    startedUnixMs: clockValid ? startedUnixMs : 0,
    startedUptimeS: 92,
    samplePeriodS: samplePeriodS,
    sampleCount: sampleCount,
    markCount: markCount,
    deviceIdRaw: utf8ToPadded('|abCDe', 8),
    nameRaw: utf8ToPadded(name, 40),
    probeNameRaw: probeNames,
    probeRole: [for (final p in probes) p.role],
    probeTarget: targetsF10,
  );
}
