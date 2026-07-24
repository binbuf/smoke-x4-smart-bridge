/// A11.4 — CSV export.
///
/// The load-bearing assertion is the first one: the app's CSV is **byte
/// identical** to the device's own `format=csv`. Two spellings of the same
/// export is how a support conversation becomes unanswerable, so this is
/// checked against the firmware's format rather than against itself.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/sessions/export.dart';

import '../support/shapes.dart';

void main() {
  test('the header is the firmware\'s header, exactly', () {
    // app_api_sessions.c: "t_s,iso8601,p1_f,p2_f,p3_f,p4_f,billows,rssi\n"
    expect(csvHeader, 't_s,iso8601,p1_f,p2_f,p3_f,p4_f,billows,rssi');
  });

  test('a row matches csv_sink field for field', () {
    const startedUnixMs = 1784755815000;
    const s = Sample(
      t: 120,
      tempsF10: [2431, 1632, null, null],
      billows: true,
      rssi: -70,
    );
    // %04d-%02u-%02uT%02d:%02d:%02d.%03uZ, one decimal per temperature,
    // detached probes as EMPTY fields.
    expect(
      csvLineFor(s, startedUnixMs: startedUnixMs),
      '120,2026-07-22T21:32:15.000Z,243.1,163.2,,,1,-70',
    );
  });

  test('a detached probe is an empty field — never 0', () {
    const s = Sample(t: 30, tempsF10: [null, null, null, null]);
    final line = csvLineFor(s, startedUnixMs: 1784755815000);
    expect(line.split(',').sublist(2, 6), ['', '', '', '']);
    expect(line, isNot(contains('0.0')));
  });

  test('no clock means an empty iso column, not an epoch date', () {
    const s = Sample(t: 30, tempsF10: [2400, null, null, null]);
    final line = csvLineFor(s);
    expect(line.split(',')[1], '');
    expect(line, isNot(contains('1970')));
  });

  test(
    'the stream yields the header first, then one line per sample',
    () async {
      final cook = syntheticCook(hours: 1);
      final lines = await csvLines(cook, startedUnixMs: 0).toList();
      expect(lines.first, '$csvHeader\n');
      expect(lines.length, cook.length + 1);
      for (final l in lines) {
        expect(l.endsWith('\n'), isTrue);
      }
    },
  );

  test('the whole export lands in a sink, end to end', () async {
    final cook = syntheticCook(hours: 2);
    final session = sessionFor(cook);
    final sink = InMemoryExportSink();
    final name = await exportSessionCsv(
      session: session,
      samples: cook,
      sink: sink,
    );
    expect(name, 'cook-0027-brisket.csv');
    final text = sink.files[name]!;
    final lines = const LineSplitter().convert(text);
    expect(lines.first, csvHeader);
    expect(lines.length, cook.length + 1);
    expect(lines[1].startsWith('0,'), isTrue);
  });

  test('a 54-day export streams rather than concatenating', () async {
    // The point is that nothing here materialises the whole file: the
    // stream is consumed lazily and only the sink ever holds it all.
    var seen = 0;
    await for (final _ in csvLines(
      syntheticCook(hours: 54 * 24, periodS: 300),
      startedUnixMs: 0,
    )) {
      seen++;
    }
    expect(seen, greaterThan(15000));
  });

  group('file names', () {
    test('sort, survive a file system, and still say what they are', () {
      expect(
        exportFileName(const CookSession(id: 27, name: 'Brisket #3!')),
        'cook-0027-brisket-3.csv',
      );
    });

    test('an unnamed cook still gets a name', () {
      expect(exportFileName(const CookSession(id: 4)), 'cook-0004.csv');
    });
  });
}
