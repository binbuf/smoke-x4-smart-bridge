/// `/cooks/:id` — cook detail (newapp §C.4).
///
/// The chart, the statistics and the mark timeline are the existing
/// [SessionDetailView], unchanged and reused: it was already the richest screen
/// in the app and §C.4 asks to keep its statistics set intact. What wraps it is
/// new, and is the whole point of the reframe — **the edits**:
///
///  * rename (the dialog existed with no route wiring; now it has one);
///  * **move the start time**, offering anchors detected from the recording
///    (§D.3) — the differentiator no competitor has;
///  * retarget, including on a running cook;
///  * split at a time, merge with a neighbour;
///  * notes, favourite, repeat, export;
///  * delete, behind a cost sheet that says plainly that the **recording does
///    not stop** — only the annotation goes.
///
/// It also renders §E.5's gaps honestly, which the statistics table alone could
/// not: a connectivity hole and a buffer rollover both look like a missing
/// stretch of line, and only one of them is ever coming back.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/repos/cook_repository.dart';
import '../../design/design.dart';
import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';
import '../../domain/plan/plan.dart';
import '../../ui/ui.dart';
import '../cook/cook_setup_sheet.dart';
import '../sessions/sessions_screen.dart';
import 'cook_actions.dart';
import 'cook_edit_sheets.dart';

class CookDetailView extends StatefulWidget {
  const CookDetailView({
    required this.repo,
    required this.cook,
    this.celsius = false,
    this.onChanged,
    this.onDeleted,
    super.key,
  });

  final CookRepository repo;
  final CookAnnotation cook;
  final bool celsius;

  /// Called after any edit, so the list behind can re-read.
  final Future<void> Function()? onChanged;

  /// Called after the annotation is deleted, so a pushed route can pop.
  final VoidCallback? onDeleted;

  @override
  State<CookDetailView> createState() => _CookDetailViewState();
}

class _CookDetailViewState extends State<CookDetailView> {
  late CookAnnotation _cook = widget.cook;
  List<Sample> _samples = const [];
  List<Mark> _marks = const [];
  List<RecordedGap> _gaps = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(CookDetailView old) {
    super.didUpdateWidget(old);
    if (old.cook.id != widget.cook.id) {
      _cook = widget.cook;
      _loaded = false;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final samples = await widget.repo.samplesFor(_cook);
    final gaps = await widget.repo.gapsFor(_cook);
    // Marks still hang off the device session; a cook that spans two sessions
    // shows the marks of the session it is anchored in, which is honest —
    // inventing cross-session mark ids would mint phone-side identity.
    final marks = await _marksFor();
    if (mounted) {
      setState(() {
        _samples = samples;
        _gaps = gaps;
        _marks = marks;
        _loaded = true;
      });
    }
  }

  Future<List<Mark>> _marksFor() async {
    final anchor = _cook.anchorSessionId;
    if (anchor != null) {
      return widget.repo.db.markDao.forSession(widget.repo.bridgeId, anchor);
    }
    // Without an anchor, take the marks of every session the cook overlaps.
    final sessions = await widget.repo.db.sessionDao.allSessions(
      widget.repo.bridgeId,
    );
    final out = <Mark>[];
    for (final s in sessions) {
      final started = s.startedUnixMs;
      if (started == null) {
        continue;
      }
      final end = _cook.endUnixMs;
      final sessionEnd = s.endedUnixMs ?? (end ?? started);
      if (sessionEnd < _cook.startUnixMs || (end != null && started > end)) {
        continue;
      }
      out.addAll(
        await widget.repo.db.markDao.forSession(widget.repo.bridgeId, s.id),
      );
    }
    return out;
  }

  Future<void> _apply(Future<CookAnnotation> Function() edit) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final next = await edit();
      if (mounted) {
        setState(() => _cook = next);
      }
      await _load();
      await widget.onChanged?.call();
    } on ArgumentError catch (e) {
      // The food-safety gate, or an impossible time bound. Copy over error.
      messenger?.showSnackBar(
        SnackBar(content: Text(e.message?.toString() ?? 'That isn’t allowed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final t = context.tokens;
    // The chart and statistics speak `CookSession`; the annotation supplies its
    // own bounds. This projection is the seam, and it is deliberately shallow —
    // nothing downstream needs to know a cook is now an annotation.
    final asSession = CookSession(
      id: _cook.id,
      name: _cook.displayName(),
      startedUnixMs: _samples.isEmpty
          ? _cook.startUnixMs
          : _cook.startUnixMs - _samples.first.t * 1000,
      endedUnixMs: _cook.endUnixMs,
      closed: _cook.endUnixMs != null,
      probes: [
        for (final r in _cook.roles)
          Probe(
            n: r.jack,
            name: r.label,
            role: r.role,
            targetF10: r.targetF10,
          ),
      ],
    );

    return Column(
      children: [
        _actionBar(t),
        Expanded(
          child: SessionDetailView(
            session: asSession,
            samples: _samples,
            marks: _marks,
            probes: asSession.probes,
            celsius: widget.celsius,
            onRename: (name) =>
                unawaited(_apply(() => widget.repo.rename(_cook, name))),
            onExport: () => unawaited(
              exportSamples(
                context,
                name: _cook.displayName(),
                id: _cook.id,
                startedUnixMs: asSession.startedUnixMs,
                samples: _samples,
              ),
            ),
            header: _headerCards(t),
          ),
        ),
      ],
    );
  }

  /// The cards above the chart: what this cook is, and the two things §D.3
  /// makes newly possible — set a target after starting, and move the start.
  List<Widget> _headerCards(SmokeTokens t) => [
    if (_cook.hasNoTarget)
      Padding(
        padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
        child: SmokeCard(
          key: const Key('cook-set-target'),
          onTap: () => unawaited(_retarget()),
          child: Row(
            children: [
              Icon(Icons.adjust_rounded, color: t.textBody),
              const SizedBox(width: SmokeTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Set a target',
                      style: SmokeType.title.copyWith(color: t.textHi),
                    ),
                    Text(
                      'This cook has no target yet. Adding one turns on the '
                      'gauges and the estimate — it works retroactively.',
                      style: SmokeType.bodySm.copyWith(color: t.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
      child: SmokeCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row(t, 'Started', formatSessionDate(_cook.startUnixMs)),
            _row(
              t,
              'Ended',
              _cook.endUnixMs == null
                  ? 'Still running'
                  : formatSessionDate(_cook.endUnixMs),
            ),
            if (_cook.presetId != null && _cook.presetId != 'custom')
              _row(t, 'Preset', _cook.presetId!),
            if (_cook.doneness.isNotEmpty) _row(t, 'Doneness', _cook.doneness),
            for (final r in _cook.roles)
              if (r.role == ProbeRole.food && r.targetF10 != null)
                _row(
                  t,
                  'Probe ${r.jack} target',
                  '${formatSetpoint(r.targetF10, celsius: widget.celsius)}'
                      '${r.pullOffsetF10 > 0 ? ' · pull '
                            '${formatSetpoint(r.pullF10, celsius: widget.celsius)}' : ''}',
                ),
          ],
        ),
      ),
    ),
    if (_gaps.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
        child: _gapsCard(t),
      ),
    Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
      child: _notesCard(t),
    ),
  ];

  /// §E.5 — the two kinds of hole, told apart.
  Widget _gapsCard(SmokeTokens t) {
    final permanent = _gaps.where((g) => g.reason.isPermanent).toList();
    final recoverable = _gaps.where((g) => !g.reason.isPermanent).toList();
    String span(List<RecordedGap> gs) =>
        formatDuration(gs.fold(0, (a, g) => a + g.durationS));
    return SmokeCard(
      key: const Key('cook-gaps'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GAPS IN RECORDING',
            style: SmokeType.label.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: SmokeTokens.s2),
          if (permanent.isNotEmpty) ...[
            Text(
              '${permanent.length} lost — ${span(permanent)}',
              style: SmokeType.title.copyWith(color: t.textHi),
            ),
            Text(
              GapReason.bufferRollover.explanation,
              style: SmokeType.bodySm.copyWith(color: t.textBody),
            ),
          ],
          if (permanent.isNotEmpty && recoverable.isNotEmpty)
            const SizedBox(height: SmokeTokens.s2),
          if (recoverable.isNotEmpty) ...[
            Text(
              '${recoverable.length} not synced — ${span(recoverable)}',
              style: SmokeType.title.copyWith(color: t.textHi),
            ),
            Text(
              GapReason.connectivity.explanation,
              style: SmokeType.bodySm.copyWith(color: t.textBody),
            ),
          ],
        ],
      ),
    );
  }

  Widget _notesCard(SmokeTokens t) => SmokeCard(
    child: TextFormField(
      key: const Key('cook-notes'),
      initialValue: _cook.notes,
      maxLength: 200,
      maxLines: 3,
      minLines: 1,
      style: SmokeType.body.copyWith(color: t.textHi),
      decoration: InputDecoration(
        labelText: 'Notes',
        hintText: 'Wrapped at 165, apple wood',
        hintStyle: SmokeType.bodySm.copyWith(color: t.textMuted),
        border: InputBorder.none,
      ),
      onFieldSubmitted: (v) =>
          unawaited(_apply(() => widget.repo.setNotes(_cook, v))),
    ),
  );

  Widget _row(SmokeTokens t, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          ),
        ),
        Text(value, style: SmokeType.body.copyWith(color: t.textHi)),
      ],
    ),
  );

  Widget _actionBar(SmokeTokens t) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(
      horizontal: SmokeTokens.s4,
      vertical: SmokeTokens.s2,
    ),
    child: Row(
      children: [
        _action(
          t,
          key: 'cook-backdate',
          icon: Icons.schedule_rounded,
          label: 'Move start',
          onTap: _backdate,
        ),
        _action(
          t,
          key: 'cook-retarget',
          icon: Icons.adjust_rounded,
          label: _cook.hasNoTarget ? 'Set target' : 'Retarget',
          onTap: _retarget,
        ),
        _action(
          t,
          key: 'cook-split',
          icon: Icons.call_split_rounded,
          label: 'Split',
          onTap: _split,
        ),
        _action(
          t,
          key: 'cook-repeat',
          icon: Icons.replay_rounded,
          label: 'Repeat',
          onTap: () async {
            await repeatCook(context, widget.repo, _cook);
            await widget.onChanged?.call();
          },
        ),
        _action(
          t,
          key: 'cook-favourite',
          icon: _cook.favourite ? Icons.star_rounded : Icons.star_outline_rounded,
          label: _cook.favourite ? 'Favourite' : 'Favourite',
          onTap: () =>
              _apply(() => widget.repo.setFavourite(_cook, !_cook.favourite)),
        ),
        if (_cook.endUnixMs == null)
          _action(
            t,
            key: 'cook-end',
            icon: Icons.stop_circle_outlined,
            label: 'End',
            onTap: () => _apply(() => widget.repo.end(_cook)),
          )
        else
          _action(
            t,
            key: 'cook-reopen',
            icon: Icons.play_circle_outline_rounded,
            label: 'Reopen',
            onTap: () => _apply(() => widget.repo.reopen(_cook)),
          ),
        _action(
          t,
          key: 'cook-delete',
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          onTap: _delete,
        ),
      ],
    ),
  );

  Widget _action(
    SmokeTokens t, {
    required String key,
    required IconData icon,
    required String label,
    required Future<void> Function() onTap,
  }) => Padding(
    padding: const EdgeInsets.only(right: SmokeTokens.s2),
    child: ActionChip(
      key: Key(key),
      avatar: Icon(icon, size: 16, color: t.textBody),
      label: Text(label, style: SmokeType.bodySm.copyWith(color: t.textHi)),
      onPressed: () => unawaited(onTap()),
    ),
  );

  // ── the edits ────────────────────────────────────────────────────────

  Future<void> _backdate() async {
    final anchors = await widget.repo.anchorsFor(_cook);
    if (!mounted) {
      return;
    }
    final at = await showBackdateSheet(
      context,
      cook: _cook,
      anchors: anchors,
    );
    if (at != null) {
      await _apply(() => widget.repo.backdate(_cook, at));
    }
  }

  Future<void> _retarget() async {
    CookPlan? current;
    try {
      current = _cook.toPlan();
    } on ArgumentError {
      current = null; // an annotation the gate would now refuse: start clean
    }
    final plan = await showCookSetupSheet(
      context,
      celsius: widget.celsius,
      initial: current,
      probeNames: {for (final r in _cook.roles) r.jack: r.label},
    );
    if (plan == null || !mounted) {
      return;
    }
    final next = CookAnnotation.fromPlan(
      plan,
      bridgeId: widget.repo.bridgeId,
      nowUnixMs: _cook.createdUnixMs,
      id: _cook.id,
    );
    await _apply(() => widget.repo.retarget(_cook, next.roles));
  }

  Future<void> _split() async {
    final at = await showSplitSheet(context, cook: _cook, marks: _marks);
    if (at == null) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final (before, _) = await widget.repo.split(_cook, at);
      if (mounted) {
        setState(() => _cook = before);
      }
      await _load();
      await widget.onChanged?.call();
    } on ArgumentError catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text(e.message?.toString() ?? 'Can’t split there.')),
      );
    }
  }

  Future<void> _delete() async {
    final ok = await showCostSheet(
      context,
      title: 'Delete this cook?',
      body:
          'This removes the name and targets you gave this stretch of the '
          'recording.',
      // The load-bearing half. Users delete a cook expecting the readings to
      // go with it, and they do not.
      keeps: 'Every reading. The bridge never stops recording.',
      loses: 'This cook’s name, notes, targets and marks in the list.',
      confirmLabel: 'Delete cook',
      cancelLabel: 'Keep it',
    );
    if (!ok) {
      return;
    }
    await widget.repo.deleteCook(_cook.id);
    await widget.onChanged?.call();
    widget.onDeleted?.call();
  }
}
