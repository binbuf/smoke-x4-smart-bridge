/// N12 — the History screen's pure projections.
///
/// Grouping, formatting, the recap arithmetic and the chart inputs, tested
/// without a binding (the graph/timeline precedent).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/history/history.dart';

const int _nowMs = 1700000000000;

List<HistoryEntry> _cooks() => <HistoryEntry>[
  for (final seed in kHistorySeeds) HistoryEntry.fromSeed(seed, _nowMs),
];

HistoryEntry _cook(String id) => _cooks().firstWhere((entry) => entry.id == id);

void main() {
  group('groupHistory (N12.3)', () {
    test('splits the seven mock cooks into 4 this week and 3 earlier', () {
      final groups = groupHistory(_cooks(), nowMs: _nowMs);
      expect(groups, hasLength(2));
      expect(groups[0].group, HistoryGroup.thisWeek);
      expect(groups[0].entries.map((e) => e.id), <String>[
        'c1',
        'c2',
        'c3',
        'c4',
      ]);
      expect(groups[1].group, HistoryGroup.earlier);
      expect(groups[1].entries.map((e) => e.id), <String>['c5', 'c6', 'c7']);
    });

    test('skips an empty group', () {
      final groups = groupHistory(<HistoryEntry>[_cook('c6')], nowMs: _nowMs);
      expect(groups, hasLength(1));
      expect(groups.single.group, HistoryGroup.earlier);
    });
  });

  group('formatting (N12.4)', () {
    test('fmtDay is the prototype month-day', () {
      expect(fmtDay(DateTime(2026, 9, 21).millisecondsSinceEpoch), 'Sep 21');
    });

    test('the card facts carry date, duration, marks and photos', () {
      expect(cookCardFacts(_cook('c1')), <String>[
        fmtDay(_nowMs - 8640 * 60000),
        '10h 12m',
        '5 marks',
        '2 photos',
      ]);
      // No photos means no photos fact.
      expect(cookCardFacts(_cook('c2')), hasLength(3));
    });
  });

  group('recap and result (N12.6/N12.7)', () {
    test('c1 is prototype-exact', () {
      final rows = historyRecap(_cook('c1'), TempUnit.fahrenheit);
      expect(rows.map((r) => r.label), <String>[
        'Cook time',
        'Peak temp',
        'Longest stall',
        'Wrapped at',
      ]);
      expect(rows[0].value, '10h 12m');
      expect(rows[0].note, '+12 min vs plan');
      expect(rows[1].value, '203° F');
      expect(rows[1].note, 'Reached target 201° F');
      expect(rows[2].value, '155 min');
      expect(rows[3].value, '165° F');
    });

    test('an unwrapped cook has no wrap row', () {
      final rows = historyRecap(_cook('c2'), TempUnit.fahrenheit);
      expect(rows.any((r) => r.label == 'Wrapped at'), isFalse);
      expect(rows.any((r) => r.label == 'Longest stall'), isFalse);
      expect(rows[1].note, 'Reached target 135° F');
    });

    test('the result grid is Peak / Target / Marks', () {
      final stats = historyResultStats(_cook('c1'), TempUnit.fahrenheit);
      expect(stats.map((s) => s.label), <String>['Peak', 'Target', 'Marks']);
      expect(stats[0].value, '203° F');
      expect(stats[1].value, '201° F');
      expect(stats[2].value, '5');
    });
  });

  group('chart inputs (N12.8)', () {
    test('the domain covers the whole cook with no now cursor', () {
      final domain = historyDomain(_cook('c1'));
      expect(domain.xMin, 0);
      expect(domain.xMax, 612);
      expect(domain.nowVisible, isFalse);
      expect(
        domain.timeAt(0),
        DateTime.fromMillisecondsSinceEpoch(_nowMs - 8640 * 60000),
      );
    });

    test('one series, one target line and the derived marks', () {
      final entry = _cook('c1');
      final samples = historySamples(entry);
      final model = historySeries(entry, samples);
      expect(model.series.single.jack, ProbeJack.one);
      expect(model.isEmpty, isFalse);
      expect(historySeriesMeta(entry)!.label, entry.name);
      expect(historyTargets(entry, TempUnit.fahrenheit).single.value, 201);
      final marks = historyGraphMarks(entry, historyDomain(entry));
      expect(marks, hasLength(4));
      expect(marks.first.xMin, 0);
    });
  });

  group('gaps (N12.15)', () {
    test('a fixture with no recorded gaps derives none', () {
      expect(historyGaps(_cook('c1')), isEmpty);
    });

    test('explicit gaps win', () {
      final entry = _cook('c1').copyWith(
        gaps: const <RecordedGap>[
          RecordedGap(fromT: 60, toT: 90, reason: GapReason.bufferRollover),
        ],
      );
      expect(historyGaps(entry).single.reason, GapReason.bufferRollover);
    });
  });

  test('the export summary names the file, rows and bytes', () {
    final csv = 'header\n0,a\n1,b\n';
    expect(
      cookCsvSummary(_cook('c1'), csv),
      'cook-c1.csv · 2 rows · ${csv.length} bytes',
    );
  });
}
