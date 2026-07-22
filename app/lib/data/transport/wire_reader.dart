/// A3.2 — binary record parsing on top of the generated codec.
///
/// The reader honours `hdr_len` and `rec_len` from the session header rather
/// than `sizeof` — that alone makes additive field growth
/// backward-compatible: a future v2 record is longer, and a v1 client reads
/// it by striding `rec_len` and parsing the leading bytes it understands.
library;

import 'dart:typed_data';

import '../../domain/entities/entities.dart';
import '../dto/records.g.dart' as dto;

/// A parsed `.smk` byte stream: the self-describing header plus its records.
class SmkArchive {
  SmkArchive({required this.header, required this.records});

  final dto.SessionHeader header;
  final List<dto.SampleRec> records;

  /// Parses [bytes]. A future `version` is READ, not rejected; records are
  /// strided by the header's `rec_len`. Throws [FormatException] only for
  /// structural impossibilities (too short, bad magic, zero rec_len).
  static SmkArchive parse(Uint8List bytes, {bool skipBadCrc = true}) {
    if (bytes.length < dto.SessionHeader.size) {
      throw const FormatException('smk: shorter than a session header');
    }
    final header = dto.SessionHeader.decode(bytes);
    if (!header.magicOk) {
      throw const FormatException('smk: bad magic');
    }
    final recLen = header.recLen;
    if (recLen < dto.SampleRec.size) {
      throw FormatException('smk: rec_len $recLen shorter than v1 record');
    }
    final records = <dto.SampleRec>[];
    for (var off = header.hdrLen; off + recLen <= bytes.length; off += recLen) {
      final rec = dto.SampleRec.decode(bytes, off);
      if (skipBadCrc && !rec.crcOk) {
        // A torn tail (04 §4.5) — stop at the first bad record.
        break;
      }
      records.add(rec);
    }
    return SmkArchive(header: header, records: records);
  }

  /// The session, as the domain sees it.
  CookSession toSession() {
    final h = header;
    return CookSession(
      id: h.sessionId,
      name: h.name,
      startedUnixMs: h.clockValid && h.startedUnixMs != 0
          ? h.startedUnixMs
          : null,
      endedUnixMs: h.closed && h.endedUnixMs != 0 ? h.endedUnixMs : null,
      samplePeriodS: h.samplePeriodS,
      sampleCount: h.sampleCount,
      numProbes: h.numProbes,
      probes: [
        for (var i = 0; i < 4; i++)
          Probe(
            n: i + 1,
            name: h.probeName[i],
            role: ProbeRole.values[h.probeRole[i].clamp(0, 3)],
            targetF10: h.probeTarget[i] == 0 ? null : h.probeTarget[i],
          ),
      ],
      closed: h.closed,
      pinned: h.pinned,
    );
  }

  /// Domain samples. Detached probes come back `null` — never a number.
  List<Sample> toSamples() => [for (final r in records) sampleFromRec(r)];
}

/// Maps one wire record to the domain. Exposed for stream parsing
/// (`format=bin` sync responses reuse it).
Sample sampleFromRec(dto.SampleRec r) => Sample(
  t: r.t,
  tempsF10: r.tempNullable,
  billows: r.billows,
  newAlarm: r.newAlarm,
  sourceCelsius: r.sourceCelsius,
  rssi: r.rssi,
);

/// Parses a bare record stream (a `format=bin` samples response), given the
/// `rec_len` learned from the session header.
List<Sample> samplesFromBin(
  Uint8List bytes, {
  int recLen = dto.SampleRec.size,
}) {
  final out = <Sample>[];
  for (var off = 0; off + recLen <= bytes.length; off += recLen) {
    final rec = dto.SampleRec.decode(bytes, off);
    if (rec.crcOk) {
      out.add(sampleFromRec(rec));
    }
  }
  return out;
}

/// Parses a `.mrk` byte stream.
List<Mark> marksFromBytes(Uint8List bytes) {
  final out = <Mark>[];
  for (
    var off = 0;
    off + dto.MarkRec.size <= bytes.length;
    off += dto.MarkRec.size
  ) {
    final rec = dto.MarkRec.decode(bytes, off);
    if (!rec.crcOk) {
      continue;
    }
    out.add(
      Mark(
        t: rec.t,
        kind: MarkKind.values[rec.kind.clamp(0, MarkKind.values.length - 1)],
        probe: rec.probe,
        text: rec.text,
      ),
    );
  }
  return out;
}
