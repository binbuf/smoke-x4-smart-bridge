/// A11.4 — the export actually reaches a file.
///
/// `InMemoryExportSink` is what the rest of the suite asserts bytes
/// against; this is the other half — the sink the app ships with, writing
/// through a real `dart:io` stream to a real path.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/features/sessions/export.dart';

import '../support/shapes.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('smoke_export'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('an 18-hour cook streams to a real file, header first', () async {
    final cook = syntheticCook(hours: 18);
    final session = sessionFor(cook);
    final path = await exportSessionCsv(
      session: session,
      samples: cook,
      sink: FileExportSink(dir),
    );
    expect(path, endsWith('cook-0027-brisket.csv'));
    final lines = File(path).readAsLinesSync();
    expect(lines.first, csvHeader);
    expect(lines.length, cook.length + 1);
    // The invariant, in the file somebody will actually open.
    expect(lines[1].split(',').sublist(4, 6), ['', '']);
  });

  test('a missing directory is created rather than thrown at', () async {
    final nested = Directory('${dir.path}${Platform.pathSeparator}exports');
    final path = await exportSessionCsv(
      session: sessionFor(const []),
      samples: const [],
      sink: FileExportSink(nested),
    );
    expect(File(path).existsSync(), isTrue);
    expect(File(path).readAsStringSync(), '$csvHeader\n');
  });
}
