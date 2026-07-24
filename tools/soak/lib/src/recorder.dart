/// V3.2 — the recorder. Polls /status and /debug/tasks on a cadence,
/// appends one NDJSON line per sample to a file that survives the tool
/// being killed, and resumes from that file without losing or duplicating
/// a sample.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sample.dart';

/// A seam over HTTP, so the recorder is drivable against the sim and a
/// fake in tests without a real bridge.
typedef Fetch = Future<Map<String, Object?>> Function(String path);

class Recorder {
  Recorder({
    required this.fetch,
    required this.tracePath,
    this.reconnects = 0,
    this.wsDrops = 0,
  });

  final Fetch fetch;
  final String tracePath;
  int reconnects;
  int wsDrops;

  /// Reads the last `seq` already on disk so a resumed run continues the
  /// sequence rather than restarting it. Returns -1 for a fresh trace.
  int lastSeqOnDisk() {
    final f = File(tracePath);
    if (!f.existsSync()) return -1;
    var last = -1;
    for (final line in f.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      try {
        final j = jsonDecode(line) as Map<String, Object?>;
        final s = (j['seq'] as num?)?.toInt();
        if (s != null) last = s;
      } on FormatException {
        // A torn last line (killed mid-write) is not a lost sample: the
        // next append starts a fresh, whole line.
      }
    }
    return last;
  }

  /// One poll, folded into a [SoakSample] and appended atomically-enough
  /// (one write of one line with a trailing newline).
  Future<SoakSample> pollOnce(int seq) async {
    final status = await fetch('/api/v1/status');
    final tasks = await fetch('/api/v1/debug/tasks');

    final device = status['device'] as Map<String, Object?>? ?? const {};
    final radio = status['radio'] as Map<String, Object?>? ?? const {};
    final storage = status['storage'] as Map<String, Object?>? ?? const {};
    final session = status['session'] as Map<String, Object?>? ?? const {};
    final ota = status['ota'] as Map<String, Object?>? ?? const {};
    final alarms = status['alarms'] as List? ?? const [];
    final heap = tasks['heap'] as Map<String, Object?>? ?? const {};

    final sample = SoakSample(
      seq: seq,
      wallMs: DateTime.now().millisecondsSinceEpoch,
      uptimeS: (device['uptime_s'] as num?)?.toInt() ?? 0,
      freeHeap:
          (heap['free_b'] as num?)?.toInt() ??
          (device['free_heap'] as num?)?.toInt() ??
          0,
      minFreeHeap:
          (heap['min_free_b'] as num?)?.toInt() ??
          (device['min_free_heap'] as num?)?.toInt() ??
          0,
      largestFreeBlock: (heap['largest_free_block_b'] as num?)?.toInt() ?? 0,
      packetsOk: (radio['packets_ok'] as num?)?.toInt() ?? 0,
      packetsBad: (radio['packets_bad'] as num?)?.toInt() ?? 0,
      storageUsedB: (storage['used_b'] as num?)?.toInt() ?? 0,
      reconnects: reconnects,
      wsDrops: wsDrops,
      alarms: alarms.length,
      sessionActive: session['active'] == true,
      fw: (device['fw'] as String?) ?? '',
      gate: (ota['gate'] as String?) ?? '',
      tasks: [
        for (final t in (tasks['tasks'] as List? ?? const []))
          TaskRow.fromJson(t as Map<String, Object?>),
      ],
    );

    // Heal a torn final line: a kill mid-write leaves a partial line with
    // no newline, and appending straight onto it would merge two records
    // into one unparseable line — losing BOTH. A leading newline starts a
    // fresh line; readTrace then drops only the torn fragment.
    final f = File(tracePath);
    var prefix = '';
    if (f.existsSync()) {
      final len = f.lengthSync();
      if (len > 0) {
        final raf = f.openSync(mode: FileMode.read);
        raf.setPositionSync(len - 1);
        final last = raf.readByteSync();
        raf.closeSync();
        if (last != 0x0A) prefix = '\n';
      }
    }
    f.writeAsStringSync(
      '$prefix${jsonEncode(sample.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
    return sample;
  }

  /// Reads every whole sample back off disk — the report's input.
  static List<SoakSample> readTrace(String path) {
    final f = File(path);
    if (!f.existsSync()) return const [];
    final out = <SoakSample>[];
    for (final line in f.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      try {
        out.add(SoakSample.fromJson(jsonDecode(line) as Map<String, Object?>));
      } on FormatException {
        // A torn final line is dropped, not fatal.
      }
    }
    return out;
  }
}
