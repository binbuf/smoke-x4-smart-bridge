/// N12 — the History screen's pure projections.
///
/// Grouping, formatting, the recap arithmetic, the chart inputs, the marks rail
/// and the gaps only: no Flutter, no repository. Keeping it here lets the
/// prototype's exact `viewHistory`/`viewCookDetail` behaviour be unit-tested
/// without a binding.
///
/// Invariants this file holds:
///  * **I10** — a cook is a time-window annotation over one continuous
///    recording. Nothing here reads or rewrites a sample row; the chart and the
///    CSV are projections of the cache.
///  * **I3** — a detached probe is absent, never `0`; the CSV leaves its field
///    empty.
library;

import '../../data/content/catalog.dart';
import '../../data/export/cook_export.dart';
import '../../data/model/history_entry.dart';
import '../../domain/domain.dart';
import '../graph/graph_format.dart';
import '../live/live_format.dart';
import '../temps/temps_format.dart';
import '../timeline/timeline_format.dart';

/// The seven-day boundary the prototype uses for "This week".
const int kHistoryWeekMs = 7 * 24 * 3600 * 1000;

/// The two history groups (`app.js` `viewHistory`).
enum HistoryGroup {
  thisWeek,
  earlier;

  String get label => switch (this) {
    HistoryGroup.thisWeek => 'This week',
    HistoryGroup.earlier => 'Earlier',
  };
}

/// One group of cooks, in newest-first order.
class HistoryGrouping {
  const HistoryGrouping({required this.group, required this.entries});

  final HistoryGroup group;
  final List<HistoryEntry> entries;
}

/// Groups [entries] into This week / Earlier, skipping empty groups.
///
/// The prototype's rule: an entry is "this week" when it started less than
/// seven days before [nowMs]; everything left over is "Earlier".
List<HistoryGrouping> groupHistory(
  List<HistoryEntry> entries, {
  required int nowMs,
}) {
  final used = <String>{};
  final out = <HistoryGrouping>[];
  for (final group in HistoryGroup.values) {
    final rows = <HistoryEntry>[
      for (final entry in entries)
        if (!used.contains(entry.id) &&
            (group == HistoryGroup.thisWeek
                ? nowMs - entry.startedAtMs < kHistoryWeekMs
                : true))
          entry,
    ];
    for (final row in rows) {
      used.add(row.id);
    }
    if (rows.isNotEmpty) {
      out.add(HistoryGrouping(group: group, entries: rows));
    }
  }
  return out;
}

/// `Sep 21` — the prototype's `fmtDay`.
String fmtDay(int ms) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_months[date.month - 1]} ${date.day}';
}

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// The card's meta line: date, duration, marks, photos (N12.4).
List<String> cookCardFacts(HistoryEntry entry) => <String>[
  fmtDay(entry.startedAtMs),
  fmtDuration(entry.durationMin * 60000),
  '${entry.marks} marks',
  if (entry.photos > 0) '${entry.photos} photos',
];

/// The named style for [entry], or null when the cut has none.
String? historyStyleName(CatalogTable catalog, HistoryEntry entry) {
  for (final style in catalog.stylesFor(entry.presetId)) {
    if (style.id == entry.styleId) {
      return style.name;
    }
  }
  return null;
}

/// The entry with [id], or null (a deep link to a deleted cook).
HistoryEntry? historyEntryById(List<HistoryEntry> entries, String? id) {
  if (id == null) {
    return null;
  }
  for (final entry in entries) {
    if (entry.id == id) {
      return entry;
    }
  }
  return null;
}

/// One planned-vs-actual recap row (N12.6).
class HistoryRecapRow {
  const HistoryRecapRow({
    required this.label,
    required this.value,
    this.note = '',
  });

  final String label;
  final String value;
  final String note;
}

/// The recap card's rows, prototype-exact (`app.js` `viewCookDetail`).
List<HistoryRecapRow> historyRecap(HistoryEntry entry, TempUnit unit) {
  final rows = <HistoryRecapRow>[];
  final planned = entry.plannedMin > 0 ? entry.plannedMin : entry.durationMin;
  final diff = entry.durationMin - planned;
  final planNote = entry.plannedMin <= 0
      ? ''
      : diff == 0
      ? 'On plan'
      : diff > 0
      ? '+$diff min vs plan'
      : '$diff min vs plan';
  rows.add(
    HistoryRecapRow(
      label: 'Cook time',
      value: fmtDuration(entry.durationMin * 60000),
      note: planNote,
    ),
  );

  final peak = fmtTempUnit(entry.peakF10, unit);
  final peakNote = entry.targetF10 <= 0
      ? ''
      : entry.peakF10 >= entry.targetF10
      ? 'Reached target ${fmtTempUnit(entry.targetF10, unit)}'
      : 'Target ${fmtTempUnit(entry.targetF10, unit)}';
  rows.add(HistoryRecapRow(label: 'Peak temp', value: peak, note: peakNote));

  if (entry.stalledMin > 0) {
    rows.add(
      HistoryRecapRow(
        label: 'Longest stall',
        value: '${entry.stalledMin} min',
        note: 'Evaporative plateau',
      ),
    );
  }
  if (entry.wrapAtF10 != null) {
    rows.add(
      HistoryRecapRow(
        label: 'Wrapped at',
        value: fmtTempUnit(entry.wrapAtF10, unit),
      ),
    );
  }
  return rows;
}

/// The Result stat grid: Peak / Target / Marks (N12.7).
List<({String label, String value})> historyResultStats(
  HistoryEntry entry,
  TempUnit unit,
) => <({String label, String value})>[
  (label: 'Peak', value: fmtTempUnit(entry.peakF10, unit)),
  (label: 'Target', value: fmtTempUnit(entry.targetF10, unit)),
  (label: 'Marks', value: '${entry.marks}'),
];

/// One event on the marks rail (N12.10).
class HistoryMark {
  const HistoryMark({
    required this.atMs,
    required this.title,
    required this.kind,
  });

  final int atMs;
  final String title;
  final MarkKind kind;
}

/// The rail's events, actual marks first, each with a real wall-clock time.
List<HistoryMark> historyMarks(HistoryEntry entry) => <HistoryMark>[
  for (final mark in historyRail(entry))
    HistoryMark(
      atMs: entry.startedAtMs + mark.t * 1000,
      title: mark.text.isEmpty ? markKindWord(mark.kind) : mark.text,
      kind: mark.kind,
    ),
];

/// The chart window for a past cook: the whole cook, no "now" cursor.
GraphDomain historyDomain(HistoryEntry entry) => GraphDomain(
  startedMs: entry.startedAtMs,
  elapsedMin: entry.durationMin.toDouble(),
  xMin: 0,
  xMax: entry.durationMin.toDouble(),
  // A past cook has no "now": pushing it past xMax keeps the cursor off.
  nowMin: entry.durationMin + 1,
);

/// The entry's jack, or null when the fixture's jack is out of range.
ProbeJack? historyJack(HistoryEntry entry) => ProbeJack.fromN(entry.jack);

/// The N1.14 render model for the cook's one probe.
ChartSeriesModel historySeries(HistoryEntry entry, List<Sample> samples) {
  final jack = historyJack(entry);
  return buildChartSeries(
    samples,
    fromT: 0,
    toT: entry.durationS,
    probes: jack == null ? const <ProbeJack>[] : <ProbeJack>[jack],
  );
}

/// The chart's series identity (the cook's name).
GraphSeriesMeta? historySeriesMeta(HistoryEntry entry) {
  final jack = historyJack(entry);
  if (jack == null) {
    return null;
  }
  return GraphSeriesMeta(jack: jack, label: entry.name, isPit: false);
}

/// The target line for the cook (N12.8).
List<GraphTarget> historyTargets(HistoryEntry entry, TempUnit unit) {
  final jack = historyJack(entry);
  if (jack == null || entry.targetF10 <= 0) {
    return const <GraphTarget>[];
  }
  return <GraphTarget>[
    GraphTarget(
      jack: jack,
      value: displayTemp(entry.targetF10 / 10, unit),
      label: fmtTempUnit(entry.targetF10, unit),
    ),
  ];
}

/// The marks that fall inside the cook, as chart verticals.
List<GraphMark> historyGraphMarks(HistoryEntry entry, GraphDomain domain) =>
    <GraphMark>[
      for (final mark in historyMarks(entry))
        if ((mark.atMs - entry.startedAtMs) / 60000 >= domain.xMin &&
            (mark.atMs - entry.startedAtMs) / 60000 <= domain.xMax)
          GraphMark(
            xMin: (mark.atMs - entry.startedAtMs) / 60000,
            label: mark.title,
            kind: mark.kind,
          ),
    ];

/// The holes a cook contains: the explicit gaps when the cache recorded them,
/// otherwise the connectivity gaps derived from the sample grid (N12.15).
///
/// The threshold follows the grid's own cadence — the fixture resamples a cook
/// into [kHistorySampleCount] points, so judging it against the device's 30 s
/// cadence would read every interval as a dropout.
List<RecordedGap> historyGaps(HistoryEntry entry) {
  if (entry.gaps.isNotEmpty) {
    return entry.gaps;
  }
  final period = entry.durationS ~/ kHistorySampleCount;
  return detectConnectivityGaps(
    historySamples(entry),
    samplePeriodS: period < 1 ? 30 : period,
  );
}

/// The exported file's name.
String cookCsvFilename(HistoryEntry entry) => 'cook-${entry.id}.csv';

/// The share toast: file name, rows and bytes, all real.
String cookCsvSummary(HistoryEntry entry, String csv) {
  final rows = csv.split('\n').where((line) => line.isNotEmpty).length - 1;
  final bytes = csv.length;
  return '${cookCsvFilename(entry)} · $rows rows · $bytes bytes';
}
