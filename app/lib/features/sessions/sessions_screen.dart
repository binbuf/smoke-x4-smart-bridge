/// The cook detail view: chart, statistics, marks (design 08 §8.6, 09 §9.4;
/// 16 §16.5, §16.6).
///
/// Cache-first like everything else, so it renders with the bridge unplugged —
/// scrolling an 18-hour cook on the couch has been the acceptance test for the
/// data layer since A4.4.
///
/// **Rebuilt into the design system**, because it was the last Material-default
/// screen the redesign still routed to: `titleMedium` headings, a bare 240 dp
/// chart floating on the scaffold, and a statistics table that was one
/// undifferentiated column of nineteen rows. The content did not change — §C.4
/// asks explicitly to keep the statistics set, and it is the richest thing in
/// the app — but what it is *made of* did:
///
///  * the chart lives in a [SmokeCard], which is the surface the series palette
///    is validated against, so the strokes are drawn on the surface they were
///    measured on;
///  * the statistics split into three labelled groups — the recording, the
///    pit, each probe — because nineteen rows in one list is a table nobody
///    reads to the bottom of;
///  * a probe's row wears its series hue as an 8 dp dot, which is the whole
///    permitted use of a series hue outside the chart, and ties the row to the
///    line above it;
///  * the two kinds of gap are told apart *in the statistics too*, not only in
///    the caller's card (§E.5).
///
/// [header] and [footer] let a caller that knows more about this cook than a
/// `CookSession` can carry — its annotation bounds, its notes, its edits —
/// wrap the whole thing in one scroll view rather than stacking two.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/local/database.dart' show SampleSummary;
import '../../design/design.dart';
import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';
import '../../ui/ui.dart';
import '../chart/chart_viewport.dart';
import '../chart/cook_chart.dart';
import '../cook/mark_sheet.dart' show markLabel;

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

/// The device-session list. Superseded by `/cooks` — a cook is an annotation
/// now, not a device session — and kept for the legacy `/sessions` entry point.
class SessionsListView extends StatelessWidget {
  const SessionsListView({
    required this.rows,
    this.onOpen,
    this.celsius = false,
    this.selectedId,
    super.key,
  });

  final List<SessionListRow> rows;
  final ValueChanged<CookSession>? onOpen;
  final bool celsius;

  /// The row showing in the detail pane, on a window wide enough to have one.
  final int? selectedId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rows.isEmpty) {
      return const EmptyState(
        key: Key('sessions-empty'),
        icon: Icons.outdoor_grill_outlined,
        title: 'No cooks yet',
        message:
            'Your bridge is still recording. Start one any time — you can '
            'even name a stretch that already happened.',
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
          selected: selectedId == s.id,
          selectedTileColor: theme.colorScheme.primaryContainer.withValues(
            alpha: 0.28,
          ),
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
                  // "cooking" claimed a state the app may not have: the
                  // bridge records whether or not a cook was ever set up
                  // (§13.7.6), and an open session only means recording.
                  child: Text(
                    'Recording',
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
                    'Time not set',
                  formatDuration(row.summary?.durationS ?? 0),
                  'peak ${formatTemp(row.summary?.peakF10, celsius: celsius)}',
                  '${s.numProbes} probes',
                ].join(' · '),
                style: theme.textTheme.bodyMedium,
              ),
              // The design system's `Sparkline`, not a raw painter from the
              // deleted `probe_tile.dart` — that file carried a second copy of
              // the palette, and this row was the only thing keeping it alive.
              if (row.sparkline.length > 2)
                SizedBox(
                  height: 22,
                  child: Sparkline(
                    points: row.sparkline,
                    color: ProbePalette.styleFor(1, theme.brightness).color,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The detail view: chart, the §9.4 statistics, the mark timeline.
class SessionDetailView extends StatefulWidget {
  const SessionDetailView({
    required this.session,
    required this.samples,
    this.marks = const [],
    this.probes = const [],
    this.gaps = const [],
    this.onExport,
    this.onRename,
    this.celsius = false,
    this.showIdentity = true,
    this.header = const [],
    this.footer = const [],
    this.originT = 0,
    super.key,
  });

  final CookSession session;
  final List<Sample> samples;
  final List<Mark> marks;
  final List<Probe> probes;

  /// The holes this cook spans, both kinds. Empty falls back to what the
  /// statistics can derive from the samples alone — which can see that a hole
  /// exists but not that the data behind it is gone for good.
  final List<RecordedGap> gaps;

  final VoidCallback? onExport;
  final ValueChanged<String>? onRename;
  final bool celsius;

  /// False when the caller owns the name and the dates — a pushed route with
  /// the name in its AppBar, or `/cooks/:id`, which says far more about a cook
  /// than a `CookSession` can.
  final bool showIdentity;

  /// Cards rendered **above the chart**.
  final List<Widget> header;

  /// Cards rendered **below the marks**.
  final List<Widget> footer;

  /// The sample `t` this view calls zero when it prints an elapsed time.
  ///
  /// Zero for a device session, whose `t` already counts from its own start. A
  /// **cook** is a window over that recording and can begin hours into it, so
  /// `/cooks/:id` passes the cook's own start here — otherwise the first mark
  /// of a ten-minute cook reads "02:00:00", which is a true fact about the
  /// session and a false one about the cook the reader is looking at.
  final int originT;

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
    final t = context.tokens;
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
      padding: const EdgeInsets.fromLTRB(
        SmokeTokens.s4,
        SmokeTokens.s3,
        SmokeTokens.s4,
        SmokeTokens.s6,
      ),
      children: [
        ...widget.header,
        if (widget.showIdentity) _identity(t),
        const SizedBox(height: SmokeTokens.s5),
        // The chart sits on `card`, which is the surface the series palette
        // was measured against (§14.6.2) — so the strokes read at the contrast
        // they were validated at, not at whatever the scaffold happens to be.
        SmokeCard(
          padding: const EdgeInsets.all(SmokeTokens.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ChartControls(
                viewport: _viewport,
                onViewport: (v) => setState(() => _viewport = v),
              ),
              const SizedBox(height: SmokeTokens.s2),
              SizedBox(
                height: 240,
                child: CookChart(
                  model: model,
                  viewport: _viewport,
                  probes: widget.probes,
                  marks: widget.marks,
                  startedUnixMs: widget.session.startedUnixMs,
                  celsius: widget.celsius,
                  crosshairT: _crosshairT,
                  onCrosshair: (t) => setState(() => _crosshairT = t),
                  onViewport: (v) => setState(() => _viewport = v),
                ),
              ),
              if (_crosshairT != null) ...[
                const SizedBox(height: SmokeTokens.s2),
                CrosshairReadout(
                  readings: crosshairAt(model, _crosshairT!),
                  atT: _crosshairT!,
                  startedUnixMs: widget.session.startedUnixMs,
                  probes: widget.probes,
                  celsius: widget.celsius,
                ),
              ],
            ],
          ),
        ),
        _StatsSection(
          stats: stats,
          gaps: widget.gaps,
          probes: widget.probes,
          celsius: widget.celsius,
        ),
        _label(t, 'MARKS'),
        _marksCard(t),
        ...widget.footer,
      ],
    );
  }

  Widget _identity(SmokeTokens t) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              widget.session.name.isEmpty
                  ? 'Cook #${widget.session.id}'
                  : widget.session.name,
              style: SmokeType.displayL.copyWith(color: t.textHi),
            ),
          ),
          if (widget.onRename != null)
            IconButton(
              key: const Key('session-rename'),
              tooltip: 'Rename',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _rename(context),
            ),
          if (widget.onExport != null)
            IconButton(
              key: const Key('session-export'),
              tooltip: 'Export',
              icon: const Icon(Icons.ios_share),
              onPressed: widget.onExport,
            ),
        ],
      ),
      Text(
        formatSessionDate(widget.session.startedUnixMs).isEmpty
            ? 'started before the bridge knew the time'
            : formatSessionDate(widget.session.startedUnixMs),
        style: SmokeType.bodySm.copyWith(color: t.textMuted),
      ),
    ],
  );

  Widget _marksCard(SmokeTokens t) {
    if (widget.marks.isEmpty) {
      return SmokeCard(
        child: Text(
          'Nothing marked on this cook.',
          key: const Key('session-marks-empty'),
          style: SmokeType.bodySm.copyWith(color: t.textMuted),
        ),
      );
    }
    return SmokeCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.marks.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: SmokeTokens.s4,
                endIndent: SmokeTokens.s4,
                color: t.hairlineStrong,
              ),
            _MarkRow(
              mark: widget.marks[i],
              originT: widget.originT,
              // Tapping a mark takes the chart there — the reason to record
              // one in the first place. The chart's x-axis is the session's
              // own `t`, so this is the raw one, not the rebased one.
              onTap: () => setState(
                () => _viewport = _viewport.centreOn(widget.marks[i].t),
              ),
            ),
          ],
        ],
      ),
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
            child: const Text('Keep the old name'),
          ),
          FilledButton(
            key: const Key('session-rename-save'),
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      widget.onRename?.call(name);
    }
  }
}

Widget _label(SmokeTokens t, String text) => Padding(
  padding: const EdgeInsets.only(
    top: SmokeTokens.s5,
    bottom: SmokeTokens.s2,
    left: SmokeTokens.s1,
  ),
  child: Text(text, style: SmokeType.label.copyWith(color: t.textMuted)),
);

class _MarkRow extends StatelessWidget {
  const _MarkRow({
    required this.mark,
    required this.onTap,
    this.originT = 0,
  });

  final Mark mark;

  /// See [SessionDetailView.originT] — the `t` this row counts from.
  final int originT;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final named = mark.text.isNotEmpty;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: Key('session-mark-${mark.t}-${mark.kind.name}'),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(
            horizontal: SmokeTokens.s4,
            vertical: SmokeTokens.s3,
          ),
          child: Row(
            children: [
              Text(
                formatElapsed(mark.t - originT),
                style: SmokeType.mono.copyWith(color: t.textMuted),
              ),
              const SizedBox(width: SmokeTokens.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      named ? mark.text : markLabel(mark.kind),
                      style: SmokeType.title.copyWith(color: t.textHi),
                    ),
                    if (named)
                      Text(
                        markLabel(mark.kind),
                        style: SmokeType.bodySm.copyWith(color: t.textMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The §9.4 set, in three groups. One list of nineteen rows is a table nobody
/// reads to the bottom of; three labelled groups are three answers.
class _StatsSection extends StatelessWidget {
  const _StatsSection({
    required this.stats,
    required this.gaps,
    required this.probes,
    required this.celsius,
  });

  final CookStats stats;
  final List<RecordedGap> gaps;
  final List<Probe> probes;
  final bool celsius;

  String _t(double? f) => f == null
      ? noValue
      : formatTempPrecise((f * 10).round(), celsius: celsius);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final lost = gaps.where((g) => g.reason.isPermanent).toList();
    final waiting = gaps.where((g) => !g.reason.isPermanent).toList();
    String span(List<RecordedGap> g) =>
        '${g.length} · ${formatDuration(g.fold(0, (a, x) => a + x.durationS))}';

    return Column(
      key: const Key('session-stats'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(t, 'THE RECORDING'),
        _card(t, [
          ('Total time', formatDuration(stats.durationS)),
          ('Readings', '${stats.sampleCount}'),
          // The two kinds are named apart here as well as on the caller's
          // card: one is coming back and the other never is, and a single
          // "gaps" count cannot say which (§E.5).
          if (gaps.isEmpty)
            (
              // "Dropouts" is radio jargon for what the reader experiences as
              // a hole in the graph.
              'Gaps in recording',
              stats.gaps.isEmpty
                  ? 'none'
                  : '${stats.gaps.length} · '
                        '${formatDuration(stats.gapSecondsTotal)} missing',
            )
          else ...[
            if (lost.isNotEmpty) ('Gaps — lost for good', span(lost)),
            if (waiting.isNotEmpty) ('Gaps — not synced yet', span(waiting)),
          ],
        ]),
        _label(t, 'THE PIT'),
        _card(t, [
          ('Pit mean', _t(stats.pitMeanF)),
          (
            // σ is a statistics symbol in a barbecue app. Same number, and the
            // label stops being a filter on who gets to read it.
            'Pit steadiness',
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
        ]),
        if (stats.probes.any((p) => p.attachedEver)) ...[
          _label(t, 'EACH PROBE'),
          SmokeCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final p in stats.probes)
                  if (p.attachedEver)
                    _ProbeStatRow(
                      probe: p,
                      name: probes
                          .where((c) => c.n == p.probe)
                          .firstOrNull
                          ?.name,
                      celsius: celsius,
                    ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _card(SmokeTokens t, List<(String, String)> rows) => SmokeCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SmokeTokens.s1),
            // Both halves flex: at 200% text on a 360 dp phone a value like
            // "241.0° / 258.0°" is wider than half the card, and wrapping it
            // beats clipping the answer.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    label,
                    style: SmokeType.bodySm.copyWith(color: t.textMuted),
                  ),
                ),
                const SizedBox(width: SmokeTokens.s3),
                Expanded(
                  flex: 4,
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: SmokeType.body.copyWith(color: t.textHi),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _ProbeStatRow extends StatelessWidget {
  const _ProbeStatRow({
    required this.probe,
    required this.name,
    required this.celsius,
  });

  final ProbeStats probe;
  final String? name;
  final bool celsius;

  String _t(double? f) => f == null
      ? noValue
      : formatTempPrecise((f * 10).round(), celsius: celsius);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(
        horizontal: SmokeTokens.s4,
        vertical: SmokeTokens.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The one sanctioned appearance of a series hue outside the chart:
          // a mark no larger than 12 dp, tying this row to its line.
          Padding(
            padding: const EdgeInsets.only(top: 6, right: SmokeTokens.s3),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: ProbePalette.hue(probe.probe),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        (name ?? '').isEmpty
                            ? 'Probe ${probe.probe}'
                            : '${name!} · probe ${probe.probe}',
                        style: SmokeType.title.copyWith(color: t.textHi),
                      ),
                    ),
                    const SizedBox(width: SmokeTokens.s2),
                    Flexible(
                      child: Text(
                        'peak ${_t(probe.peakF)}',
                        textAlign: TextAlign.end,
                        style: SmokeType.body.copyWith(color: t.textHi),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'start ${_t(probe.startF)} · end ${_t(probe.endF)}',
                  style: SmokeType.bodySm.copyWith(color: t.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
