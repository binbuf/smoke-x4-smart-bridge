/// N12.5–N12.15 — the cook detail.
///
/// One past cook as an annotation: the header, the planned-vs-actual recap, the
/// result stats, the chart (the N7 [CookChart], reused), the notes, the marks
/// rail, the gaps card and the verbs (Cook again, Share/export, End/Reopen,
/// edit marks/notes, Delete).
///
/// Invariants encoded here:
/// * **I10** — every verb edits the annotation; the chart and the CSV are
///   projections of the cache. Deleting never touches a sample row.
/// * **I8** — delete sits behind a cost sheet that states the recording does
///   not stop.
/// * **I3** — a detached probe is absent, never zero.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/export/cook_export.dart';
import '../../data/model/history_entry.dart';
import '../../data/providers.dart';
import '../../data/repository/bridge_repository.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import '../graph/cook_chart.dart';
import '../graph/graph_format.dart';
import '../live/live_format.dart';
import '../shell/app_bar.dart';
import '../shell/overlay.dart';
import '../shell/phone_frame.dart';
import '../shell/shell.dart';
import '../shell/shell_screen.dart';
import '../timeline/timeline_format.dart';
import 'history_format.dart';
import 'history_model.dart';

class CookDetailPage extends ConsumerWidget {
  const CookDetailPage({super.key, this.id});

  /// The cook id from the route (`/settings/history/:id`).
  final String? id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final entries = history.value ?? const <HistoryEntry>[];
    final entry = historyEntryById(entries, id);
    final scope = ShellScope.maybeOf(context);

    if (!history.hasValue) {
      return const LoadingState(
        title: 'Reading the cache',
        copy: 'Waiting for the first history read.',
        actionLabel: 'Retry',
        onAction: _noop,
      );
    }

    if (entry == null) {
      return ShellScrollHost(
        resetToken: ShellScreen.cookDetail,
        child: ProblemState(
          key: const ValueKey<String>('cook-detail-missing'),
          title: 'Cook not found',
          copy:
              'This cook is not in the cache — it may have been deleted. The '
              'bridge recording it pointed at is untouched.',
          actionLabel: 'Back to history',
          onAction: () => scope?.openScreen(ShellScreen.history),
        ),
      );
    }
    return _CookDetailBody(entry: entry);
  }
}

class _CookDetailBody extends ConsumerWidget {
  const _CookDetailBody({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final scope = ShellScope.maybeOf(context);
    final repo = ref.watch(bridgeRepositoryProvider);
    final catalog = repo.catalog;
    final unit = ref.watch(historyUnitProvider);

    final samples = historySamples(entry);
    final domain = historyDomain(entry);
    final series = historySeries(entry, samples);
    final meta = historySeriesMeta(entry);
    final targets = historyTargets(entry, unit);
    final marks = historyGraphMarks(entry, domain);
    final rail = historyMarks(entry);
    final gaps = historyGaps(entry);
    final styleName = historyStyleName(catalog, entry);

    return ShellScrollHost(
      resetToken: ShellScreen.cookDetail,
      child: Column(
        key: const ValueKey<String>('cook-detail-page'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Header(entry: entry, styleName: styleName),
          const SectionLabel(label: 'Recap'),
          _RecapCard(entry: entry, unit: unit),
          const SectionLabel(label: 'Result'),
          StatGrid(
            key: const ValueKey<String>('cook-detail-result'),
            stats: <SmokeStat>[
              for (final stat in historyResultStats(entry, unit))
                SmokeStat(label: stat.label, value: stat.value),
            ],
          ),
          const SectionLabel(label: 'Chart'),
          SmokeCard(
            padding: const EdgeInsets.fromLTRB(12, 14, 10, 8),
            child: SizedBox(
              height: 210,
              child: CookChart(
                key: const ValueKey<String>('cook-detail-chart'),
                model: series,
                domain: domain,
                unit: unit,
                series: <GraphSeriesMeta>[?meta],
                targets: targets,
                band: null,
                marks: marks,
              ),
            ),
          ),
          const SectionLabel(label: 'Notes'),
          _NotesCard(entry: entry),
          const SectionLabel(label: 'Marks'),
          _MarksRail(entry: entry, marks: rail),
          if (gaps.isNotEmpty) ...<Widget>[
            const SectionLabel(label: 'Recording gaps'),
            _GapsCard(gaps: gaps, startedAtMs: entry.startedAtMs),
          ],
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: SmokeButton(
                  key: const ValueKey<String>('cook-detail-repeat'),
                  label: 'Cook again',
                  icon: SmokeGlyph.refresh,
                  onPressed: () =>
                      scope?.openOverlay(DevOverlay.setup, <String, String>{
                        'food': entry.presetId,
                        if (entry.styleId.isNotEmpty) 'style': entry.styleId,
                        'jack': '${entry.jack}',
                      }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SmokeButton(
                  key: const ValueKey<String>('cook-detail-share'),
                  label: 'Share',
                  icon: SmokeGlyph.share,
                  variant: SmokeButtonVariant.ghost,
                  onPressed: () async {
                    // Generated from the cache, so it works with the bridge
                    // offline (N12.12).
                    final csv = await repo.exportCookCsv(entry.id);
                    if (csv.isEmpty) {
                      scope?.showToast('Nothing to export for this cook');
                      return;
                    }
                    scope?.showToast(
                      'Opening share sheet — ${cookCsvSummary(entry, csv)}',
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SmokeButton(
            key: const ValueKey<String>('cook-detail-end'),
            label: entry.isOpen ? 'End this cook' : 'Reopen this cook',
            icon: entry.isOpen ? SmokeGlyph.check : SmokeGlyph.refresh,
            variant: SmokeButtonVariant.ghost,
            onPressed: () => repo.setCookEnded(entry.id, entry.isOpen),
          ),
          const SizedBox(height: 10),
          SmokeButton(
            key: const ValueKey<String>('cook-detail-delete'),
            label: 'Delete cook',
            icon: SmokeGlyph.trash,
            variant: SmokeButtonVariant.danger,
            onPressed: () => _confirmDelete(context, scope, repo),
          ),
          const SizedBox(height: 8),
          Text(
            'Deleting removes the annotation and its marks. The bridge keeps '
            'recording — the sample rows are never touched.',
            key: const ValueKey<String>('cook-detail-delete-note'),
            textAlign: TextAlign.center,
            style: SmokeText.labelSm.copyWith(
              fontSize: 11,
              color: tokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ShellScope? scope,
    BridgeRepository repo,
  ) async {
    final confirmed = await showCostSheet(
      context,
      title: 'Delete this cook?',
      message:
          'This removes the annotation and its marks. The underlying bridge '
          'recording is kept.',
      confirmLabel: 'Delete cook',
      cancelLabel: 'Keep it',
      keeps: <String>[
        'The bridge recording — every sample row stays (I10)',
        'Any other cook annotation',
      ],
      loses: <String>[
        'This cook’s name, notes, marks and favourite',
        'Its place in History',
      ],
    );
    if (confirmed != true) {
      return;
    }
    await repo.deleteCook(entry.id);
    scope?.showToast('Cook deleted — the recording is untouched');
    scope?.openScreen(ShellScreen.history);
  }
}

/// N12.5 — avatar, name, date/time/duration/style, star rating, favourite.
class _Header extends ConsumerWidget {
  const _Header({required this.entry, this.styleName});

  final HistoryEntry entry;
  final String? styleName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final repo = ref.watch(bridgeRepositoryProvider);
    final line = <String>[
      fmtDay(entry.startedAtMs),
      fmtClock(DateTime.fromMillisecondsSinceEpoch(entry.startedAtMs)),
      fmtDuration(entry.durationMin * 60000),
      if (styleName != null && styleName!.isNotEmpty) styleName!,
    ].join(' · ');

    return SmokeCard(
      key: const ValueKey<String>('cook-detail-header'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FoodAvatar(FoodGlyph.parse(entry.glyph), size: FoodAvatarSize.lg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  entry.name,
                  key: const ValueKey<String>('cook-detail-name'),
                  style: SmokeText.cardTitle.copyWith(
                    fontSize: 17,
                    color: tokens.textHi,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  line,
                  key: const ValueKey<String>('cook-detail-line'),
                  style: SmokeText.labelSm.copyWith(
                    fontSize: 12,
                    color: tokens.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                _Stars(rating: entry.rating),
              ],
            ),
          ),
          ShellIconButton(
            key: const ValueKey<String>('cook-detail-fav'),
            glyph: SmokeGlyph.star,
            label: entry.favourite ? 'Unfavourite' : 'Favourite',
            onTap: () => repo.setFavourite(entry.id, !entry.favourite),
          ),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Row(
      key: const ValueKey<String>('cook-detail-stars'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < 5; i++)
          SmokeIcon(
            SmokeGlyph.star,
            size: 13,
            color: i < rating ? tokens.warning : tokens.hairlineStrong,
          ),
      ],
    );
  }
}

/// N12.6 — the planned-vs-actual recap.
class _RecapCard extends StatelessWidget {
  const _RecapCard({required this.entry, required this.unit});

  final HistoryEntry entry;
  final TempUnit unit;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final rows = historyRecap(entry, unit);
    return SmokeCard(
      key: const ValueKey<String>('cook-detail-recap'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < rows.length; i++)
            Container(
              key: ValueKey<String>(
                'cook-detail-recap-${_slug(rows[i].label)}',
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: tokens.hairline)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      rows[i].label,
                      style: SmokeText.sub.copyWith(color: tokens.textBody),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: rows[i].value,
                            style: SmokeText.monoSmall.copyWith(
                              fontWeight: FontWeight.w700,
                              color: tokens.textHi,
                            ),
                          ),
                          if (rows[i].note.isNotEmpty)
                            TextSpan(
                              text: ' · ${rows[i].note}',
                              style: SmokeText.labelSm.copyWith(
                                fontSize: 10.5,
                                color: tokens.textMuted,
                              ),
                            ),
                        ],
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// N12.9/N12.14 — the notes card and its editor.
class _NotesCard extends ConsumerWidget {
  const _NotesCard({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final repo = ref.watch(bridgeRepositoryProvider);
    return SmokeCard(
      key: const ValueKey<String>('cook-detail-notes'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            entry.notes.isEmpty ? 'No notes for this cook.' : entry.notes,
            key: const ValueKey<String>('cook-detail-notes-text'),
            style: SmokeText.body.copyWith(
              fontSize: 13,
              color: entry.notes.isEmpty ? tokens.textMuted : tokens.textBody,
            ),
          ),
          const SizedBox(height: 10),
          SmokeButton(
            key: const ValueKey<String>('cook-detail-notes-edit'),
            label: entry.notes.isEmpty ? 'Add a note' : 'Edit notes',
            icon: SmokeGlyph.edit,
            variant: SmokeButtonVariant.ghost,
            size: SmokeButtonSize.sm,
            onPressed: () => showSheet(
              context,
              title: 'Notes',
              sub: entry.name,
              body: _NotesEditorBody(
                entry: entry,
                onSave: (notes) => repo.setCookNotes(entry.id, notes),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotesEditorBody extends StatefulWidget {
  const _NotesEditorBody({required this.entry, required this.onSave});

  final HistoryEntry entry;
  final ValueChanged<String> onSave;

  @override
  State<_NotesEditorBody> createState() => _NotesEditorBodyState();
}

class _NotesEditorBodyState extends State<_NotesEditorBody> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.entry.notes,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Column(
      key: const ValueKey<String>('cook-detail-notes-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          key: const ValueKey<String>('cook-detail-notes-field'),
          controller: _controller,
          maxLines: 4,
          style: SmokeText.body.copyWith(color: tokens.textHi),
          decoration: InputDecoration(
            hintText: 'What worked, what to change…',
            hintStyle: SmokeText.body.copyWith(color: tokens.textMuted),
            filled: true,
            fillColor: tokens.well,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(tokens.radii.control),
              borderSide: BorderSide(color: tokens.hairlineStrong),
            ),
          ),
        ),
        const SizedBox(height: 12),
        PrimaryAction(
          key: const ValueKey<String>('cook-detail-notes-save'),
          label: 'Save notes',
          onPressed: () {
            widget.onSave(_controller.text.trim());
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

/// N12.10/N12.14 — the marks rail with add and delete.
class _MarksRail extends ConsumerWidget {
  const _MarksRail({required this.entry, required this.marks});

  final HistoryEntry entry;
  final List<HistoryMark> marks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final repo = ref.watch(bridgeRepositoryProvider);
    return Column(
      key: const ValueKey<String>('cook-detail-marks'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (marks.isEmpty)
          Text(
            'Nothing logged for this cook.',
            key: const ValueKey<String>('cook-detail-marks-empty'),
            style: SmokeText.sub.copyWith(color: tokens.textMuted),
          )
        else
          for (var i = 0; i < marks.length; i++)
            _RailItem(
              index: i,
              mark: marks[i],
              last: i == marks.length - 1,
              onDelete: () => repo.deleteCookMark(entry.id, i),
            ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: SmokeButton(
                key: const ValueKey<String>('cook-detail-add-mark'),
                label: 'Add mark',
                icon: SmokeGlyph.bookmark,
                size: SmokeButtonSize.sm,
                variant: SmokeButtonVariant.ghost,
                onPressed: () => showSheet(
                  context,
                  title: 'Add a mark',
                  sub: entry.name,
                  body: _MarkEditorBody(
                    onSave: (kind, text) =>
                        repo.addCookMark(entry.id, kind: kind, text: text),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SmokeButton(
                key: const ValueKey<String>('cook-detail-pull'),
                label: 'Pull',
                icon: SmokeGlyph.check,
                size: SmokeButtonSize.sm,
                variant: SmokeButtonVariant.ghost,
                onPressed: () => repo.addCookMark(
                  entry.id,
                  kind: MarkKind.note,
                  text: 'Pulled',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.index,
    required this.mark,
    required this.last,
    required this.onDelete,
  });

  final int index;
  final HistoryMark mark;
  final bool last;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Padding(
      key: ValueKey<String>('cook-detail-mark-$index'),
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tokens.positive,
                border: Border.all(color: tokens.positive, width: 2),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  fmtClock(DateTime.fromMillisecondsSinceEpoch(mark.atMs)),
                  key: ValueKey<String>('cook-detail-mark-time-$index'),
                  style: SmokeText.monoSmall.copyWith(color: tokens.textMuted),
                ),
                Text(
                  mark.title,
                  key: ValueKey<String>('cook-detail-mark-title-$index'),
                  style: SmokeText.bodyStrong.copyWith(
                    fontSize: 13.5,
                    color: tokens.textHi,
                  ),
                ),
              ],
            ),
          ),
          ShellIconButton(
            key: ValueKey<String>('cook-detail-mark-delete-$index'),
            glyph: SmokeGlyph.x,
            label: 'Delete mark ${mark.title}',
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}

class _MarkEditorBody extends StatefulWidget {
  const _MarkEditorBody({required this.onSave});

  final void Function(MarkKind kind, String text) onSave;

  @override
  State<_MarkEditorBody> createState() => _MarkEditorBodyState();
}

class _MarkEditorBodyState extends State<_MarkEditorBody> {
  final TextEditingController _text = TextEditingController();
  MarkKind _kind = MarkKind.note;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Column(
      key: const ValueKey<String>('cook-detail-mark-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FilterChips<MarkKind>(
          key: const ValueKey<String>('cook-detail-mark-kinds'),
          options: <SmokeSegment<MarkKind>>[
            for (final kind in const <MarkKind>[
              MarkKind.note,
              MarkKind.wrapped,
              MarkKind.spritz,
              MarkKind.turn,
              MarkKind.lidOpen,
              MarkKind.fuel,
              MarkKind.probeMoved,
            ])
              SmokeSegment<MarkKind>(value: kind, label: markKindWord(kind)),
          ],
          value: _kind,
          onChanged: (kind) => setState(() => _kind = kind),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey<String>('cook-detail-mark-text'),
          controller: _text,
          style: SmokeText.body.copyWith(color: tokens.textHi),
          decoration: InputDecoration(
            hintText: 'Optional note',
            hintStyle: SmokeText.body.copyWith(color: tokens.textMuted),
            filled: true,
            fillColor: tokens.well,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(tokens.radii.control),
              borderSide: BorderSide(color: tokens.hairlineStrong),
            ),
          ),
        ),
        const SizedBox(height: 12),
        PrimaryAction(
          key: const ValueKey<String>('cook-detail-mark-save'),
          label: 'Add mark',
          onPressed: () {
            widget.onSave(_kind, _text.text.trim());
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

/// N12.15 — the gaps card: connectivity (recoverable) vs buffer rollover.
class _GapsCard extends StatelessWidget {
  const _GapsCard({required this.gaps, required this.startedAtMs});

  final List<RecordedGap> gaps;
  final int startedAtMs;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return SmokeCard(
      key: const ValueKey<String>('cook-detail-gaps'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < gaps.length; i++) ...<Widget>[
            if (i > 0) Divider(height: 18, color: tokens.hairline),
            _GapRow(index: i, gap: gaps[i], startedAtMs: startedAtMs),
          ],
        ],
      ),
    );
  }
}

class _GapRow extends StatelessWidget {
  const _GapRow({
    required this.index,
    required this.gap,
    required this.startedAtMs,
  });

  final int index;
  final RecordedGap gap;
  final int startedAtMs;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final permanent = gap.reason.isPermanent;
    final hue = permanent ? tokens.critical : tokens.warning;
    final from = fmtClock(
      DateTime.fromMillisecondsSinceEpoch(startedAtMs + gap.fromT * 1000),
    );
    final to = fmtClock(
      DateTime.fromMillisecondsSinceEpoch(startedAtMs + gap.toT * 1000),
    );
    final minutes = (gap.durationS / 60).round();
    return Column(
      key: ValueKey<String>('cook-detail-gap-$index'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            SmokeIcon(
              permanent ? SmokeGlyph.alertTriangle : SmokeGlyph.info,
              size: 15,
              color: hue,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                gap.reason.label,
                style: SmokeText.bodyStrong.copyWith(fontSize: 13, color: hue),
              ),
            ),
            Text(
              '$minutes min',
              style: SmokeText.monoSmall.copyWith(color: tokens.textHi),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '$from → $to',
          style: SmokeText.monoSmall.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: 4),
        Text(
          gap.reason.explanation,
          style: SmokeText.labelSm.copyWith(
            fontSize: 11.5,
            color: tokens.textBody,
          ),
        ),
      ],
    );
  }
}

String _slug(String value) =>
    value.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');

void _noop() {}
