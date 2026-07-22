import 'dart:io';
import 'dart:typed_data';

import 'package:bridge_protocol/bridge_protocol.dart';
import 'package:path/path.dart' as p;

/// Emits the shared golden vectors in protocol/fixtures/records/ (task P1.5).
///
/// Each fixture is a `<name>.hex` (hex bytes, `#` comments) plus a
/// `<name>.expected` (flat `key=value` lines) that the C host tests and the
/// Dart tests both parse, asserting identical values — the drift guard between
/// the two languages.
void main() {
  final dir = Directory(p.join(_repoRoot(), 'protocol', 'fixtures', 'records'))
    ..createSync(recursive: true);

  void write(
    String name,
    String comment,
    Uint8List bytes,
    Map<String, Object> expected,
  ) {
    final hex = StringBuffer('# $comment\n');
    for (var i = 0; i < bytes.length; i += 16) {
      hex.writeln(
        [
          for (var j = i; j < i + 16 && j < bytes.length; j++)
            bytes[j].toRadixString(16).padLeft(2, '0'),
        ].join(' '),
      );
    }
    File(p.join(dir.path, '$name.hex')).writeAsStringSync(hex.toString());
    final exp = StringBuffer('# $comment\n');
    expected.forEach((k, v) => exp.writeln('$k=$v'));
    File(p.join(dir.path, '$name.expected')).writeAsStringSync(exp.toString());
    stdout.writeln('wrote $name');
  }

  Map<String, Object> sampleExpect(SampleRec s) => {
    'kind': 'sample',
    'crc_ok': 1,
    't': s.t,
    for (var i = 0; i < 4; i++) 'temp$i': s.temp[i],
    for (var i = 0; i < 4; i++)
      'temp${i}_null': s.tempOrNull(i) == null ? 1 : 0,
    'flags': s.flags,
    'flag_p1_alarm': s.p1Alarm ? 1 : 0,
    'flag_p2_alarm': s.p2Alarm ? 1 : 0,
    'flag_p3_alarm': s.p3Alarm ? 1 : 0,
    'flag_p4_alarm': s.p4Alarm ? 1 : 0,
    'flag_billows': s.billows ? 1 : 0,
    'flag_new_alarm': s.newAlarm ? 1 : 0,
    'flag_source_celsius': s.sourceCelsius ? 1 : 0,
    'rssi': s.rssi,
  };

  final fourAttached = SampleRec(
    t: 43230,
    temp: [2431, 1632, 1594, 887],
    rssi: -71,
  );
  write(
    'sample-four-attached',
    'sample_rec: all four probes attached, no flags',
    fourAttached.encode(),
    sampleExpect(SampleRec.decode(fourAttached.encode())),
  );

  final oneDetached = SampleRec(
    t: 43260,
    temp: [2428, 1633, tempDetached, 887],
    rssi: -73,
  );
  write(
    'sample-one-detached',
    'sample_rec: probe 3 detached — must decode to null, never 0',
    oneDetached.encode(),
    sampleExpect(SampleRec.decode(oneDetached.encode())),
  );

  final allDetached = SampleRec(
    t: 90,
    temp: [tempDetached, tempDetached, tempDetached, tempDetached],
    rssi: -80,
  );
  write(
    'sample-all-detached',
    'sample_rec: every probe detached',
    allDetached.encode(),
    sampleExpect(SampleRec.decode(allDetached.encode())),
  );

  // 25.0 °C = 250 tenths-°C → F10 = 250 * 9 / 5 + 320 = 770 (canonical °F).
  final celsius = SampleRec(
    t: 600,
    temp: [770, 774, 778, 782],
    flags: 1 << 6, // source_celsius — provenance only, values already °F
    rssi: -68,
  );
  write(
    'sample-celsius-source',
    'sample_rec: source packet was °C; stored values already canonical °F',
    celsius.encode(),
    sampleExpect(SampleRec.decode(celsius.encode())),
  );

  final alarms = SampleRec(
    t: 55800,
    temp: [2503, 2035, 1610, 900],
    flags: (1 << 0) | (1 << 1) | (1 << 5), // p1_alarm, p2_alarm, new_alarm
    rssi: -65,
  );
  write(
    'sample-alarm-flags',
    'sample_rec: alarm enabled on probes 1+2, new_alarm set in this packet',
    alarms.encode(),
    sampleExpect(SampleRec.decode(alarms.encode())),
  );

  Map<String, Object> headerExpect(SessionHeader h) => {
    'kind': 'header',
    'crc_ok': 1,
    'magic_ok': h.magicOk ? 1 : 0,
    'version': h.version,
    'hdr_len': h.hdrLen,
    'rec_len': h.recLen,
    'num_probes': h.numProbes,
    'flag_clock_valid': h.clockValid ? 1 : 0,
    'flag_closed': h.closed ? 1 : 0,
    'flag_pinned': h.pinned ? 1 : 0,
    'flag_source_celsius': h.sourceCelsius ? 1 : 0,
    'session_id': h.sessionId,
    'started_unix_ms': h.startedUnixMs,
    'ended_unix_ms': h.endedUnixMs,
    'started_uptime_s': h.startedUptimeS,
    'sample_period_s': h.samplePeriodS,
    'sample_count': h.sampleCount,
    'device_id': h.deviceId,
    'name': h.name,
    for (var i = 0; i < 4; i++) 'probe_name$i': h.probeName[i],
    for (var i = 0; i < 4; i++) 'probe_role$i': h.probeRole[i],
    for (var i = 0; i < 4; i++) 'probe_target$i': h.probeTarget[i],
    'mark_count': h.markCount,
  };

  final noClock = SessionHeader(
    numProbes: 4,
    flags: 0, // clock_valid clear — started while the bridge had no time source
    sessionId: 27,
    startedUnixMs: 0,
    startedUptimeS: 413,
    samplePeriodS: 30,
    sampleCount: 0,
    deviceIdRaw: utf8ToPadded('|abCDe', 8),
    nameRaw: utf8ToPadded('Brisket', 40),
    probeNameRaw: _probeNames(['Pit', 'Point', 'Flat', 'Ambient']),
    probeRole: [1, 2, 2, 3],
    probeTarget: [2250, 2030, 2030, 0],
  );
  write(
    'header-clock-not-valid',
    'session_header: clock_valid clear; started_unix_ms 0 until back-patched',
    noClock.encode(),
    headerExpect(SessionHeader.decode(noClock.encode())),
  );

  // A future layout: version 2 with a 20-byte record. Readers must accept it
  // and stride by rec_len — reading, not rejecting, is the tested behaviour.
  final future = SessionHeader(
    version: 2,
    recLen: 20,
    numProbes: 4,
    flags: 1, // clock_valid
    sessionId: 99,
    startedUnixMs: 1774051200000,
    startedUptimeS: 12,
    samplePeriodS: 30,
    sampleCount: 3,
    deviceIdRaw: utf8ToPadded('|abCDe', 8),
    nameRaw: utf8ToPadded('Future v2', 40),
    probeNameRaw: _probeNames(['Pit', 'Food', '', '']),
    probeRole: [1, 2, 0, 0],
    probeTarget: [2250, 2030, 0, 0],
  );
  write(
    'header-future-version',
    'session_header: future version=2 rec_len=20 — read it, do not reject it',
    future.encode(),
    headerExpect(SessionHeader.decode(future.encode())),
  );

  final mark = MarkRec(
    t: 21600,
    kind: 1, // wrapped
    probe: 2,
    textRaw: utf8ToPadded('wrapped ✓ 完了', 24),
  );
  final decodedMark = MarkRec.decode(mark.encode());
  write(
    'mark-utf8',
    'mark_rec: multibyte UTF-8 text survives the fixed 24-byte field',
    mark.encode(),
    {
      'kind': 'mark',
      'crc_ok': 1,
      't': decodedMark.t,
      'mark_kind': decodedMark.kind,
      'probe': decodedMark.probe,
      'text': decodedMark.text,
    },
  );
}

Uint8List _probeNames(List<String> names) {
  final out = Uint8List(48);
  for (var i = 0; i < 4; i++) {
    out.setRange(i * 12, (i + 1) * 12, utf8ToPadded(names[i], 12));
  }
  return out;
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
