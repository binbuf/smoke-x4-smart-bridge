/// A11.4 — CSV export (design 06 §6.2, 04 §4.2).
///
/// The exit gate's last clause, and the one place the app writes a file
/// somebody else will read. Two rules make it more than a `join(',')`:
///
///  * **It is byte-compatible with the device's own `format=csv`.** Same
///    header, same column order, same ISO-8601 spelling (milliseconds and
///    a `Z`, matching `csv_sink` in `app_api_sessions.c`), same `\n`. Two
///    spellings of the same export is how a support conversation becomes
///    unanswerable.
///  * **A detached probe is an empty field.** Never `0`, never `null`,
///    never `NaN`. The invariant survives all the way into the
///    spreadsheet somebody opens six months from now.
///
/// It is generated from the **cache**, so it works with the bridge
/// unplugged, and it is emitted as a stream of lines rather than one
/// concatenated string, so a 54-day export does not allocate itself into
/// an out-of-memory.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/format.dart';
import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';

/// The exact header the firmware emits.
const String csvHeader = 't_s,iso8601,p1_f,p2_f,p3_f,p4_f,billows,rssi';

/// One record, formatted as `csv_sink` formats it.
String csvLineFor(Sample s, {int? startedUnixMs}) {
  final iso = startedUnixMs == null
      ? ''
      : formatIso8601(startedUnixMs + s.t * 1000);
  final temps = [
    for (var p = 1; p <= 4; p++)
      probeValue(s, p) == null
          ? ''
          : (probeValue(s, p)! / 10).toStringAsFixed(1),
  ];
  return '${s.t},$iso,${temps.join(',')},${s.billows ? 1 : 0},${s.rssi}';
}

/// Streams the whole export, header first. Lazily, one line at a time.
Stream<String> csvLines(List<Sample> samples, {int? startedUnixMs}) async* {
  yield '$csvHeader\n';
  for (final s in samples) {
    yield '${csvLineFor(s, startedUnixMs: startedUnixMs)}\n';
  }
}

/// Where an export goes. A seam, so `flutter test` can assert the bytes
/// without a file system and without a share sheet.
abstract interface class ExportSink {
  /// [suggestedName] is `cook-27-brisket.csv`; the implementation decides
  /// where that actually lands.
  Future<String> write(String suggestedName, Stream<List<int>> bytes);
}

/// Collects into memory. The test double, and also the honest fallback on
/// a platform with nowhere to write.
class InMemoryExportSink implements ExportSink {
  final Map<String, String> files = {};

  @override
  Future<String> write(String suggestedName, Stream<List<int>> bytes) async {
    final buf = <int>[];
    await for (final chunk in bytes) {
      buf.addAll(chunk);
    }
    files[suggestedName] = utf8.decode(buf);
    return suggestedName;
  }
}

/// Writes the export to a real file, streaming.
///
/// It lands in the app's documents directory and the UI names the path,
/// which is honest but not yet convenient: **there is no share sheet.**
/// Handing the file to another app needs a platform intent, and a
/// platform intent needs a device to test it on — so it is A15.5's first
/// job at the bench rather than an untested guess committed now.
class FileExportSink implements ExportSink {
  FileExportSink(this.directory);

  /// Where files land. Injected so this class is testable without a
  /// plugin: the production caller passes the documents directory.
  final Directory directory;

  @override
  Future<String> write(String suggestedName, Stream<List<int>> bytes) async {
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}$suggestedName',
    );
    final out = file.openWrite();
    await out.addStream(bytes);
    await out.flush();
    await out.close();
    return file.path;
  }
}

/// A filename that sorts, survives a file system, and still says what it
/// is: `cook-0027-brisket.csv`.
String exportFileName(CookSession session) {
  final slug = session.name
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp('^-+|-+\$'), '');
  final id = session.id.toString().padLeft(4, '0');
  return slug.isEmpty ? 'cook-$id.csv' : 'cook-$id-$slug.csv';
}

/// Runs the export. Returns whatever the sink calls the result — a path,
/// a URI, a name — so the UI can say where it went.
Future<String> exportSessionCsv({
  required CookSession session,
  required List<Sample> samples,
  required ExportSink sink,
}) => sink.write(
  exportFileName(session),
  csvLines(
    samples,
    startedUnixMs: session.startedUnixMs,
  ).transform(utf8.encoder),
);
