/// N12.12 — the cache-side CSV export and the past-cook curve.
///
/// The CSV must stay byte-compatible with the device's own `format=csv`
/// (docs/design/06-device-api.md §258): same header, same field order, detached
/// probes as empty fields, ISO-8601 UTC, and an empty `iso8601` when the
/// session has no clock (I11).
library;

import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

const int _startedMs = 1758447660000; // 2025-09-21T09:41:00Z

HistoryEntry _entry({
  String id = 'c1',
  int jack = 1,
  int peakF10 = 2031,
  int durationMin = 612,
  int? wrapAtF10 = 1650,
}) => HistoryEntry(
  id: id,
  name: 'Labor Day Pulled Pork',
  presetId: 'pork_butt',
  styleId: 'texas_pulled',
  glyph: 'pork',
  jack: jack,
  startedAtMs: _startedMs,
  durationMin: durationMin,
  plannedMin: durationMin,
  peakF10: peakF10,
  targetF10: 2010,
  wrapAtF10: wrapAtF10,
);

void main() {
  group('buildCookCsv', () {
    test('header and one row are byte-compatible with the device', () {
      final csv = buildCookCsv(
        samples: const <Sample>[
          Sample(t: 0, tempsF10: <int?>[680, null, null, 920], rssi: -60),
        ],
        sessionStartedUnixMs: _startedMs,
      );
      expect(
        csv,
        't_s,iso8601,p1_f,p2_f,p3_f,p4_f,billows,rssi\n'
        '0,2025-09-21T09:41:00.000Z,68.0,,,92.0,0,-60\n',
      );
    });

    test('a detached probe is an empty field, never 0 (I3)', () {
      final csv = buildCookCsv(
        samples: const <Sample>[
          Sample(t: 30, tempsF10: <int?>[null, null, null, null]),
        ],
        sessionStartedUnixMs: _startedMs,
      );
      final row = csv.trimRight().split('\n')[1];
      expect(row, '30,2025-09-21T09:41:30.000Z,,,,,0,0');
      expect(row.contains(',0.0,'), isFalse);
    });

    test('a clockless session emits an empty iso8601 column (I11)', () {
      final csv = buildCookCsv(
        samples: const <Sample>[
          Sample(t: 0, tempsF10: <int?>[680, null, null, null]),
        ],
        sessionStartedUnixMs: null,
      );
      final row = csv.trimRight().split('\n')[1];
      expect(row, '0,,68.0,,,,0,0');
    });

    test('billows renders 1 when set', () {
      final csv = buildCookCsv(
        samples: const <Sample>[
          Sample(t: 0, tempsF10: <int?>[680, null, null, null], billows: true),
        ],
        sessionStartedUnixMs: null,
      );
      expect(csv.trimRight().split('\n')[1], '0,,68.0,,,,1,0');
    });
  });

  group('historySamples', () {
    test('is a stable grid ending on the recorded peak', () {
      final samples = historySamples(_entry());
      expect(samples, hasLength(kHistorySampleCount + 1));
      expect(samples.first.t, 0);
      expect(samples.last.t, 612 * 60);
      expect(samples.last.tempsF10[0], 2031);
      // Every sample carries only the cook's own jack.
      for (final sample in samples) {
        expect(sample.tempsF10[1], isNull);
        expect(sample.tempsF10[2], isNull);
        expect(sample.tempsF10[3], isNull);
      }
      // Deterministic: the same entry yields the same curve.
      expect(
        historySamples(_entry()).map((s) => s.tempsF10[0]).toList(),
        samples.map((s) => s.tempsF10[0]).toList(),
      );
    });

    test('a jack-2 cook writes its readings into slot 2', () {
      final samples = historySamples(_entry(id: 'c5', jack: 2));
      expect(samples.last.tempsF10[1], isNotNull);
      expect(samples.last.tempsF10[0], isNull);
    });
  });

  group('historyRail', () {
    test('derives the prototype milestones for a wrapped cook', () {
      final rail = historyRail(_entry());
      expect(rail.map((m) => m.text), <String>[
        'Cook started',
        'Wrapped',
        'Probe-tender',
        'Pulled',
      ]);
    });

    test('omits the wrap milestone when the cook was never wrapped', () {
      final rail = historyRail(_entry(wrapAtF10: null));
      expect(rail.map((m) => m.text), <String>[
        'Cook started',
        'Probe-tender',
        'Pulled',
      ]);
    });

    test('an explicit rail wins over the derived one', () {
      final entry = _entry().copyWith(
        markEvents: const <Mark>[
          Mark(t: 5, kind: MarkKind.spritz, text: 'Spritzed'),
        ],
      );
      expect(historyRail(entry), hasLength(1));
      expect(historyRail(entry).single.text, 'Spritzed');
    });
  });
}
