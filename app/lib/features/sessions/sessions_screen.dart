/// A11.2 / A11.3 — the sessions list and the detail view (design 08 §8.6,
/// 09 §9.4).
///
/// Cache-first like everything else, so both screens render with the
/// bridge unplugged — scrolling an 18-hour cook on the couch has been the
/// acceptance test for the data layer since A4.4.
///
/// A cook the *device* has since purged still appears here: the app owns a
/// full copy of every cook it has **seen**, which is why A4.2's reconcile
/// is deliberately upsert-only.
library;

import 'package:flutter/material.dart';

import '../../app/palette.dart';
import '../../core/format.dart';
import '../../data/local/database.dart' show SampleSummary;
import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';
import '../chart/chart_viewport.dart';
import '../chart/cook_chart.dart';
import '../dashboard/probe_tile.dart';
import '../dashboard/session_controls.dart' show markLabel;

/// One list row's data, assembled from the aggregate query — never from
/// the samples themselves (A11.2's epic flag).
class SessionListRow {
  const SessionListRow({
    required this.session,
    this.summary,
    this.sparkline = const [],
  });

  final CookSession session;
  final SampleSummary? summary;
  final List<({int t, double f})> sparkline;
}

class SessionsListView extends StatelessWidget {
  const SessionsListView({
    required this.rows,
    this.onOpen,
    this.celsius = false,
    super.key,
  });

  final List<SessionListRow> rows;
  final ValueChanged<CookSession>? onOpen;
  final bool celsius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rows.isEmpty) {
      return Center(
        key: const Key('sessions-empty'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.outdoor_grill,
                size: 44,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text('No cooks yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Start a cook and it will be saved here — '
                'even when the bridge is switched off.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      key: const Key('sessions-list'),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final row = rows[i];
        final s = row.session;
        final running = !s.closed;
        return ListTile(
          key: Key('session-row-${s.id}'),
          onTap: onOpen == null ? null : () => onOpen!(s),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  s.name.isEmpty ? 'Cook #${s.id}' : s.name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (running)
                Container(
                  key: Key('session-running-${s.id}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'cooking',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  if (formatSessionDate(s.startedUnixMs).isNotEmpty)
                    formatSessionDate(s.startedUnixMs)
                  else
                    'no clock',
                  formatDuration(row.summary?.durationS ?? 0),
                  'peak ${formatTemp(row.summary?.peakF10, celsius: celsius)}',
                  '${s.numProbes} probes',
                ].join(' · '),
                style: theme.textTheme.bodyMedium,
              ),
              if (row.sparkline.length > 2)
                SizedBox(
                  height: 22,
                  child: CustomPaint(
                    painter: SparklinePainter(
                      points: row.sparkline,
                      color: ProbePalette.styleFor(1, theme.brightness).color,
                    ),
                    size: Size.infinite,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A11.3 — the detail view: the chart without the live tiles, plus the
/// §9.4 statistics and the mark timeline.
class SessionDetailView extends StatefulWidget {
  const SessionDetailView({
    required this.session,
    required this.samples,
    this.marks = const [],
    this.probes = const [],
    this.onExport,
    this.onRename,
    this.celsius = false,
    super.key,
  });

  final CookSession session;
  final List<Sample> samples;
  final List<Mark> marks;
  final List<Probe> probes;
  final VoidCallback? onExport;
  final ValueChanged<String>? onRename;
  final bool celsius;

  @override
  State<SessionDetailView> createState() => _SessionDetailViewState();
}

class _SessionDetailViewState extends State<SessionDetailView> {
  late ChartViewport _viewport = ChartViewport.forSession(
    fromT: widget.samples.isEmpty ? 0 : widget.samples.first.t,
    toT: widget.samples.isEmpty ? 60 : widget.samples.last.t,
    window: ChartWindow.all,
  );
  int? _crosshairT;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = cookStats(
      widget.samples,
      marks: widget.marks,
      probeConfig: widget.probes,
    );
    final model = buildChartSeries(
      widget.samples,
      fromT: _viewport.minX,
      toT: _viewport.maxX,
    );
    return ListView(
      key: const Key('session-detail'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.session.name.isEmpty
                    ? 'Cook #${widget.session.id}'
                    : widget.session.name,
                style: theme.textTheme.titleLarge,
              ),
            ),
            if (widget.onRename != null)
              IconButton(
                key: const Key('session-rename'),
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _rename(context),
              ),
            if (widget.onExport != null)
              IconButton(
                key: const Key('session-export'),
                icon: const Icon(Icons.ios_share),
                onPressed: widget.onExport,
              ),
          ],
        ),
        Text(
          formatSessionDate(widget.session.startedUnixMs).isEmpty
              ? 'started before the bridge knew the time'
              : formatSessionDate(widget.session.startedUnixMs),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ChartControls(
          viewport: _viewport,
          onViewport: (v) => setState(() => _viewport = v),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 240,
          child: CookChart(
            model: model,
            viewport: _viewport,
            probes: widget.probes,
            marks: widget.marks,
            startedUnixMs: widget.session.startedUnixMs,
            crosshairT: _crosshairT,
            onCrosshair: (t) => setState(() => _crosshairT = t),
            onViewport: (v) => setState(() => _viewport = v),
          ),
        ),
        if (_crosshairT != null) ...[
          const SizedBox(height: 8),
          CrosshairReadout(
            readings: crosshairAt(model, _crosshairT!),
            atT: _crosshairT!,
            startedUnixMs: widget.session.startedUnixMs,
            probes: widget.probes,
          ),
        ],
        const SizedBox(height: 20),
        Text('Statistics', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _StatsTable(stats: stats, celsius: widget.celsius),
        const SizedBox(height: 20),
        Text('Marks', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (widget.marks.isEmpty)
          Text(
            'Nothing marked on this cook.',
            key: const Key('session-marks-empty'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final m in widget.marks)
            ListTile(
              key: Key('session-mark-${m.t}-${m.kind.name}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(
                formatElapsed(m.t),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              title: Text(m.text.isEmpty ? markLabel(m.kind) : m.text),
              subtitle: m.text.isEmpty ? null : Text(markLabel(m.kind)),
              // Tapping a mark takes the chart there — the reason to
              // record one in the first place.
              onTap: () => setState(() => _viewport = _viewport.centreOn(m.t)),
            ),
      ],
    );
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: widget.session.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename cook'),
        content: TextField(
          key: const Key('session-rename-field'),
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('session-rename-save'),
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      widget.onRename?.call(name);
    }
  }
}

class _StatsTable extends StatelessWidget {
  const _StatsTable({required this.stats, required this.celsius});

  final CookStats stats;
  final bool celsius;

  String _t(double? f) => f == null
      ? noValue
      : formatTempPrecise((f * 10).round(), celsius: celsius);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      ('Total time', formatDuration(stats.durationS)),
      ('Samples', '${stats.sampleCount}'),
      (
        'Dropouts',
        stats.gaps.isEmpty
            ? 'none'
            : '${stats.gaps.length} · ${formatDuration(stats.gapSecondsTotal)} missing',
      ),
      ('Pit mean', _t(stats.pitMeanF)),
      (
        'Pit σ',
        stats.pitStdDevF == null
            ? noValue
            : '±${stats.pitStdDevF!.toStringAsFixed(1)}°',
      ),
      ('Pit min / max', '${_t(stats.pitMinF)} / ${_t(stats.pitMaxF)}'),
      (
        'Time in band',
        stats.timeInBandS == null
            ? 'no band set'
            : formatDuration(stats.timeInBandS!),
      ),
      (
        'Stall',
        stats.stallDurationS == null
            ? 'none detected'
            : formatDuration(stats.stallDurationS!),
      ),
      ('Lid events', '${stats.lidEvents}'),
      for (final p in stats.probes)
        if (p.attachedEver)
          (
            'Probe ${p.probe}',
            'start ${_t(p.startF)} · end ${_t(p.endF)} · peak ${_t(p.peakF)}',
          ),
    ];
    return Column(
      key: const Key('session-stats'),
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 132,
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}
