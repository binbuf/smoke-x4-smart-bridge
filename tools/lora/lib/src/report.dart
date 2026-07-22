/// The protocol-question report (design 02 §2.8): one capture in, direct
/// evidence on Q1/Q2/Q4/Q6/Q8 out, as committable markdown.
library;

import 'dart:math';

import 'capture.dart';

/// Field indices inside a state message (02 §2.2.3).
///
/// Field 3 was assumed to be `new_alarm` (an X2-era inference). The real X4
/// capture (x4-events-10min) shows it resting at `1` and moving to `2` around
/// alarm/menu activity — role unknown — while the *trailing* field is the one
/// that pulses `1` on each new alarm event.
const _idxField1 = 1;
const _idxUnits = 2;
const _idxHdr3 = 3;
const _probeFieldCount = 5;

class CaptureReport {
  CaptureReport(this.packets);

  final List<CapturedPacket> packets;

  List<CapturedPacket> get states => [
    for (final p in packets)
      if ((p.commaCount == 16 || p.commaCount == 26) &&
          p.source != CaptureSource.txAck)
        p,
  ];

  List<CapturedPacket> get syncs => [
    for (final p in packets)
      if (p.commaCount == 6) p,
  ];

  int _probeCount(CapturedPacket p) => p.commaCount == 26 ? 4 : 2;

  Map<String, int> countBy(String Function(CapturedPacket) key) {
    final out = <String, int>{};
    for (final p in packets) {
      out.update(key(p), (n) => n + 1, ifAbsent: () => 1);
    }
    return out;
  }

  /// Distinct values of state header field 1 (Q1) with counts.
  Map<String, int> field1Values() {
    final out = <String, int>{};
    for (final p in states) {
      out.update(p.fields[_idxField1], (n) => n + 1, ifAbsent: () => 1);
    }
    return out;
  }

  /// Distinct probe `state` values (Q4) with counts.
  Map<String, int> probeStateValues() {
    final out = <String, int>{};
    for (final p in states) {
      for (var i = 0; i < _probeCount(p); i++) {
        final v = p.fields[4 + i * _probeFieldCount];
        out.update(v, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return out;
  }

  Map<String, int> unitsValues() {
    final out = <String, int>{};
    for (final p in states) {
      out.update(p.fields[_idxUnits], (n) => n + 1, ifAbsent: () => 1);
    }
    return out;
  }

  /// Distinct values of header field 3 — role unknown; see the index comment.
  Map<String, int> hdr3Values() {
    final out = <String, int>{};
    for (final p in states) {
      out.update(p.fields[_idxHdr3], (n) => n + 1, ifAbsent: () => 1);
    }
    return out;
  }

  Map<String, int> trailingValues() {
    final out = <String, int>{};
    for (final p in states) {
      out.update(p.fields.last, (n) => n + 1, ifAbsent: () => 1);
    }
    return out;
  }

  /// Maximal runs of consecutive state packets with the trailing `new_alarm`
  /// field set (Q8): run length 1 → edge-triggered; sustained runs → level.
  List<int> newAlarmRuns() {
    final runs = <int>[];
    var run = 0;
    for (final p in states) {
      final set = p.fields.last != '0';
      if (set) {
        run++;
      } else if (run > 0) {
        runs.add(run);
        run = 0;
      }
    }
    if (run > 0) {
      runs.add(run);
    }
    return runs;
  }

  /// Inter-packet intervals (ms) between consecutive state messages within
  /// one boot, ignoring spans that cross gaps a dropout would explain.
  List<int> stateIntervalsMs() {
    final out = <int>[];
    CapturedPacket? prev;
    for (final p in states) {
      if (prev != null && p.bootIndex == prev.bootIndex && p.tMs > prev.tMs) {
        out.add(p.tMs - prev.tMs);
      }
      prev = p;
    }
    return out;
  }

  /// Decodes a sync message's little-endian frequency bytes → Hz (02 §2.2.1).
  static int? syncFrequencyHz(CapturedPacket p) {
    if (p.commaCount != 6) {
      return null;
    }
    final f = p.fields;
    try {
      return int.parse(f[2]) |
          (int.parse(f[3]) << 8) |
          (int.parse(f[4]) << 16) |
          (int.parse(f[5]) << 24);
    } on FormatException {
      return null;
    }
  }

  String markdown({required String sourceLabel}) {
    final b = StringBuffer()
      ..writeln('# Capture report — $sourceLabel')
      ..writeln()
      ..writeln('| class | packets |')
      ..writeln('| --- | ---: |');
    countBy((p) => p.messageClass).forEach((k, v) {
      b.writeln('| $k | $v |');
    });

    final intervals = stateIntervalsMs();
    if (intervals.isNotEmpty) {
      final mean = intervals.reduce((a, c) => a + c) / intervals.length;
      b
        ..writeln()
        ..writeln('## Interval statistics (state messages)')
        ..writeln()
        ..writeln('- count: ${intervals.length}')
        ..writeln(
          '- min/mean/max ms: ${intervals.reduce(min)} / '
          '${mean.toStringAsFixed(0)} / ${intervals.reduce(max)}',
        )
        ..writeln(
          '- gaps > 45 s: '
          '${intervals.where((i) => i > 45000).length}',
        );
    }

    final rssis = [
      for (final p in packets)
        if (p.rssi != null) p.rssi!,
    ];
    if (rssis.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Link quality')
        ..writeln()
        ..writeln(
          '- RSSI min/mean/max dBm: ${rssis.reduce(min)} / '
          '${(rssis.reduce((a, c) => a + c) / rssis.length).toStringAsFixed(1)} / '
          '${rssis.reduce(max)}',
        );
    }

    b
      ..writeln()
      ..writeln('## Protocol questions (02 §2.8)')
      ..writeln();
    if (states.isNotEmpty) {
      b
        ..writeln(
          '- **Q1 / Q6** — state header field 1 values: '
          '${_fmt(field1Values())}. '
          '${field1Values().keys.length == 1 && field1Values().containsKey('30') ? 'Never left `30`.' : '**Left `30` — new evidence!**'}',
        )
        ..writeln(
          '- **Q4** — probe `state` values seen: '
          '${_fmt(probeStateValues())}'
          '${probeStateValues().keys.any((k) => k != '0' && k != '3') ? ' — **values beyond 0/3, new evidence!**' : ''}',
        )
        ..writeln('- units field values: ${_fmt(unitsValues())}')
        ..writeln(
          '- header field 3 values (role unknown; rests at `1`, moves to `2` '
          'around alarm/menu activity): ${_fmt(hdr3Values())}',
        );
      final runs = newAlarmRuns();
      if (runs.isEmpty) {
        b.writeln(
          '- **Q8** — trailing `new_alarm` field never fired in this '
          'capture: ${_fmt(trailingValues())}',
        );
      } else {
        b.writeln(
          '- **Q8** — trailing `new_alarm` field ${_fmt(trailingValues())}; '
          'episodes (consecutive packets): '
          '$runs → ${runs.every((r) => r <= 1)
              ? 'looks EDGE-triggered'
              : runs.any((r) => r > 2)
              ? 'looks LEVEL (sustained)'
              : 'ambiguous, keep capturing'}',
        );
      }
    } else {
      b.writeln('- no state messages in this capture');
    }
    for (final s in syncs) {
      final hz = syncFrequencyHz(s);
      b.writeln(
        '- **Q2 / Q6** — sync: field0=`${s.fields[0]}` '
        'device=`${s.fields[1]}`'
        '${hz != null ? ' frequency=${hz / 1e6} MHz' : ''}',
      );
    }

    // Curated vectors: the first packet of each class plus every packet
    // that carries a novel field value — ready to paste into 02 §2.3.
    b
      ..writeln()
      ..writeln('## Suggested vectors')
      ..writeln();
    final seenClass = <String>{};
    final seenNovel = <String>{};
    for (final p in packets) {
      final why = <String>[];
      if (seenClass.add(p.messageClass)) {
        why.add('first ${p.messageClass}');
      }
      if (p.commaCount == 16 || p.commaCount == 26) {
        for (var i = 0; i < _probeCount(p); i++) {
          final v = p.fields[4 + i * _probeFieldCount];
          if (v != '0' && seenNovel.add('probe_state=$v')) {
            why.add('probe state `$v`');
          }
        }
        final f1 = p.fields[_idxField1];
        if (f1 != '30' && seenNovel.add('field1=$f1')) {
          why.add('field1 `$f1`');
        }
        final h3 = p.fields[_idxHdr3];
        if (h3 != '1' && seenNovel.add('hdr3=$h3')) {
          why.add('hdr3 `$h3`');
        }
        if (p.fields.last != '0' && seenNovel.add('new_alarm')) {
          why.add('new_alarm set');
        }
        if (p.fields[_idxUnits] != '1' && seenNovel.add('celsius')) {
          why.add('units °C');
        }
      }
      if (why.isNotEmpty) {
        b.writeln('- `${p.payload}` — ${why.join(', ')}');
      }
    }
    return b.toString();
  }

  static String _fmt(Map<String, int> m) =>
      (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .map((e) => '`${e.key}`×${e.value}')
          .join(', ');
}
