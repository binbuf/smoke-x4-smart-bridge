/// N12.12 — the cache-side CSV export.
///
/// The export is generated from what the phone already holds, so it works with
/// the bridge offline. The **format** is byte-compatible with the device's own
/// `format=csv` (`docs/design/06-device-api.md` §258):
///
/// ```
/// t_s,iso8601,p1_f,p2_f,p3_f,p4_f,billows,rssi
/// 0,2026-09-21T09:41:00.000Z,68.0,,,92.0,0,-60
/// ```
///
///  * a detached probe is an **empty field, never `0`** (I3);
///  * `iso8601` is empty when the session has no clock (I11);
///  * values are canonical tenths-°F, converted to whole °F only at this edge.
///
/// N15 streams the same rows from the drift cache; the header and field order
/// must not change.
library;

import 'dart:math' as math;

import '../../domain/domain.dart';
import '../model/history_entry.dart';

/// How many points the mock resamples a past cook into. The device records at a
/// 30 s cadence; the fixture only carries a summary, so this is a plausible
/// curve, not a claim about the real recording (N15 replaces it with the cache).
const int kHistorySampleCount = 60;

/// The device's CSV header, exactly.
const String cookCsvHeader = 't_s,iso8601,p1_f,p2_f,p3_f,p4_f,billows,rssi';

/// A deterministic curve for a past-cook fixture: rise, stall plateau, peak.
///
/// Ports the prototype's `histPoints` (`app.js` §6) so the detail chart has a
/// shape to draw until N15 feeds the real samples.
List<Sample> historySamples(HistoryEntry entry) {
  final n = kHistorySampleCount;
  final peak = entry.peakF10 / 10;
  final rand = _mulberry32(entry.id.length * 31 + 7);
  final jackIndex = (entry.jack - 1).clamp(0, 3);
  final out = <Sample>[];
  for (var i = 0; i <= n; i++) {
    final p = i / n;
    var v = 60 + (peak - 60) * math.pow(p, 0.6);
    if (p > 0.45 && p < 0.7) {
      v = 60 + (peak - 60) * math.pow(0.45, 0.6) + (p - 0.45) * 20;
    }
    v += (rand() - 0.5) * 3;
    if (v > peak) {
      v = peak;
    }
    if (v < 40) {
      v = 40;
    }
    final temps = <int?>[null, null, null, null];
    temps[jackIndex] = (v * 10).round();
    out.add(
      Sample(t: (p * entry.durationS).round(), tempsF10: temps, rssi: -60),
    );
  }
  final last = out.last;
  final temps = List<int?>.of(last.tempsF10);
  temps[jackIndex] = entry.peakF10;
  out[out.length - 1] = Sample(t: last.t, tempsF10: temps, rssi: last.rssi);
  return out;
}

/// The marks the detail screen shows for [entry]: the explicit rail when the
/// user has edited one, otherwise the prototype's derived milestones.
///
/// The derived rail is a display fallback, not a claim about the fixture: the
/// generated seeds carry only a mark *count*. N15 replaces it with the cache's
/// real `Marks` rows.
List<Mark> historyRail(HistoryEntry entry) => entry.markEvents.isEmpty
    ? <Mark>[
        const Mark(t: 0, kind: MarkKind.phaseChange, text: 'Cook started'),
        if (entry.wrapAtF10 != null)
          Mark(
            t: (entry.durationS * 0.5).round(),
            kind: MarkKind.wrapped,
            text: 'Wrapped',
          ),
        Mark(
          t: (entry.durationS * 0.85).round(),
          kind: MarkKind.note,
          text: 'Probe-tender',
        ),
        Mark(t: entry.durationS, kind: MarkKind.note, text: 'Pulled'),
      ]
    : entry.markEvents;

/// One CSV row per sample, in the device's field order.
String buildCookCsv({
  required List<Sample> samples,
  required int? sessionStartedUnixMs,
}) {
  final buffer = StringBuffer()..writeln(cookCsvHeader);
  for (final sample in samples) {
    final unixMs =
        sample.unixMs ??
        (sessionStartedUnixMs == null
            ? null
            : sessionStartedUnixMs + sample.t * 1000);
    buffer
      ..write(sample.t)
      ..write(',');
    if (unixMs != null) {
      buffer.write(iso8601Utc(unixMs));
    }
    for (var i = 0; i < 4; i++) {
      buffer.write(',');
      final f10 = i < sample.tempsF10.length ? sample.tempsF10[i] : null;
      if (f10 != null) {
        buffer.write((f10 / 10).toStringAsFixed(1));
      }
    }
    buffer
      ..write(',')
      ..write(sample.billows ? 1 : 0)
      ..write(',')
      ..write(sample.rssi)
      ..write('\n');
  }
  return buffer.toString();
}

/// `YYYY-MM-DDTHH:MM:SS.mmmZ`, the device's ISO-8601 spelling.
String iso8601Utc(int unixMs) =>
    DateTime.fromMillisecondsSinceEpoch(unixMs, isUtc: true).toIso8601String();

/// A port of the prototype's `mulberry32` PRNG, so the fixture curve is stable
/// across runs and platforms.
double Function() _mulberry32(int seed) {
  var a = seed & 0xFFFFFFFF;
  return () {
    a = (a + 0x6D2B79F5) & 0xFFFFFFFF;
    final t1 = _imul(a ^ (a >>> 15), 1 | a);
    final t2 = (t1 + _imul(t1 ^ (t1 >>> 7), 61 | t1)) & 0xFFFFFFFF;
    final t3 = (t2 ^ t1) & 0xFFFFFFFF;
    return ((t3 ^ (t3 >>> 14)) & 0xFFFFFFFF) / 4294967296;
  };
}

/// JS `Math.imul`: 32-bit multiply, kept unsigned here.
int _imul(int a, int b) {
  final aLo = a & 0xFFFF;
  final aHi = (a >>> 16) & 0xFFFF;
  final bLo = b & 0xFFFF;
  final bHi = (b >>> 16) & 0xFFFF;
  return (aLo * bLo + (((aHi * bLo + aLo * bHi) & 0xFFFF) << 16)) & 0xFFFFFFFF;
}
