/// `/cooks/:id` — "What happened in this cook?" (16 §16.6, newapp §C.4).
///
/// The chart, the statistics and the mark timeline come from
/// [SessionDetailView], which is the richest thing in the app and which §C.4
/// asks to keep intact. What this screen adds is everything a *cook* is that a
/// device session never was — and the order it adds it in is the design:
///
///  1. **who it is** — name, whether it is still open, when it ended;
///  2. **when it started, and the offer to move that** — the differentiator,
///     given the screen's one ember button (rail R1). No competitor lets you
///     truly re-anchor a cook's start; this card is where that becomes
///     obvious rather than something buried behind an edit pencil;
///  3. **what it came to** — three numbers, above the fold, answering the
///     screen's one question before the chart has to be read;
///  4. **where it is missing** — the two kinds of hole, told apart (§E.5),
///     *above* the chart, so nobody reads a hole as a flat line;
///  5. the chart, statistics and marks;
///  6. notes, then every edit as a 52 dp row — rename, move start, retarget,
///     split, merge, repeat, favourite, end, export — each **one tap from
///     here**, so no edit is more than two taps from the cook;
///  7. delete, alone, behind a cost sheet that says plainly that the
///     **recording does not stop**.
///
/// Cache-only throughout. Every read on this screen is a drift read; nothing
/// here touches a transport, which is what lets the whole flow work with the
/// bridge unplugged.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/local/database.dart' show CookSummary;
import '../../data/repos/cook_repository.dart';
import '../../design/design.dart';
import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';
import '../../domain/plan/plan.dart';
import '../../ui/probe/food_avatar.dart';
import '../../ui/ui.dart';
import '../cook/cook_setup_sheet.dart';
import '../sessions/sessions_screen.dart';
import 'cook_actions.dart';
import 'cook_backdate_sheet.dart';
import 'cook_edit_sheets.dart';
import 'cook_gaps_card.dart';
import 'cook_list_view.dart';
import 'cook_sheet_shell.dart';

class CookDetailView extends StatefulWidget {
  const CookDetailView({
    required this.repo,
    required this.cook,
    this.celsius = false,
    this.showTitle = true,
    this.onChanged,
    this.onDeleted,
    this.onIdChanged,
    super.key,
  });

  final CookRepository repo;
  final CookAnnotation cook;
  final bool celsius;

  /// False on a pushed route, where the AppBar already carries the name —
  /// §16.5 puts the screen title in the content *except* on pushed routes, and
  /// rendering it twice is how a screen starts to look unconsidered.
  final bool showTitle;

  /// Called after any edit, so the list behind can re-read.
  final Future<void> Function()? onChanged;

  /// Called after the annotation is deleted, so a pushed route can pop.
  final VoidCallback? onDeleted;

  /// Called when an edit leaves this cook living under a **different** row id.
  /// Merging with the earlier neighbour keeps that cook's row and deletes this
  /// one, so a caller that loads by id has to follow — one that keeps re-reading
  /// its old id finds nothing and reports the cook missing at the exact moment
  /// the merge succeeded.
  final ValueChanged<int>? onIdChanged;

  @override
  State<CookDetailView> createState() => _CookDetailViewState();
}

/// What the screen can be showing. §16.7's ladder is a checklist, not a
/// suggestion, and a read that throws must not leave a spinner turning over a
/// cook this phone can no longer parse.
enum _Phase { loading, ready, failed }

class _CookDetailViewState extends State<CookDetailView> {
  late CookAnnotation _cook = widget.cook;
  List<Sample> _samples = const [];
  List<Mark> _marks = const [];
  List<RecordedGap> _gaps = const [];
  List<CookAnchor> _anchors = const [];
  List<CookAnnotation> _all = const [];

  /// Wall clock at `t = 0` for this cook's samples — the origin the chart, the
  /// marks, the gap times and the export all measure from. Null when the bridge
  /// had no clock, which every one of them renders as elapsed time.
  int? _origin;

  /// Read once, from the same SQL aggregate the list row uses. Scanning the
  /// samples for it in `build` would re-walk a 54-day cook every time the
  /// crosshair moved.
  CookSummary _summary = const CookSummary(count: 0);
  _Phase _phase = _Phase.loading;

  /// The notes field's text, held here rather than left to the widget.
  ///
  /// It used to persist on `onFieldSubmitted`, which a `maxLines: 3` field can
  /// never call: Flutter gives a multi-line field `TextInputAction.newline`, and
  /// `EditableText.performAction` only forwards to `onSubmitted` when
  /// `maxLines == 1`. Enter inserted a newline and the note was thrown away on
  /// the next rebuild — a control that appears to work and does nothing, which
  /// §16.2 ranks worse than no control at all.
  late final TextEditingController _notes = TextEditingController(
    text: _cook.notes,
  );

  /// A notes field with no save button has to save itself, and the moment it
  /// can is the moment the field stops being the thing you are typing into.
  late final FocusNode _notesFocus = FocusNode()..addListener(_onNotesFocus);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(CookDetailView old) {
    super.didUpdateWidget(old);
    if (old.cook.id != widget.cook.id) {
      // A split pane swaps the cook under the field without ever unmounting it,
      // which loses an unsaved note exactly the way walking away used to. Same
      // loss, same write.
      if (_notes.text != _cook.notes) {
        unawaited(widget.repo.setNotes(_cook, _notes.text));
      }
      _cook = widget.cook;
      _notes.text = _cook.notes;
      _phase = _Phase.loading;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    // Leaving the screen is the commonest way to finish a note, and `dispose`
    // cannot await — so the write is handed to the repository and left to land.
    // Nothing on screen is waiting to read it back.
    if (_notes.text != _cook.notes) {
      unawaited(widget.repo.setNotes(_cook, _notes.text));
    }
    _notesFocus
      ..removeListener(_onNotesFocus)
      ..dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final samples = await widget.repo.samplesFor(_cook);
      final gaps = await widget.repo.gapsFor(_cook);
      final marks = await _marksFor();
      // Loaded up front rather than on tap, because the *count* is the pitch:
      // "the recording found four moments this could have started at" is what
      // makes someone open the sheet in the first place.
      final anchors = await widget.repo.anchorsFor(_cook);
      final all = await widget.repo.cooks();
      final summary = await widget.repo.summaryFor(_cook);
      final origin = await widget.repo.originFor(_cook);
      if (mounted) {
        setState(() {
          _samples = samples;
          _gaps = gaps;
          _marks = marks;
          _anchors = anchors;
          _all = all;
          _summary = summary;
          _origin = origin;
          _phase = _Phase.ready;
        });
        _syncNotes();
      }
    } on Object {
      // Nothing here touches a transport, so a failure is this phone's cache
      // disagreeing with itself. Say so and offer the read again.
      if (mounted) {
        setState(() => _phase = _Phase.failed);
      }
    }
  }

  void _retry() {
    setState(() => _phase = _Phase.loading);
    unawaited(_load());
  }

  /// The marks that fall **inside** this cook.
  ///
  /// Marks still hang off the device session — inventing cross-session mark ids
  /// would mint phone-side identity — so a cook spanning two sessions reads the
  /// marks of both. What it must not do is inherit a session's *other* marks: a
  /// cook is a window over the recording, and something marked two hours outside
  /// it did not happen in this cook.
  Future<List<Mark>> _marksFor() async {
    final anchor = _cook.anchorSessionId;
    if (anchor != null) {
      // Pinned to one whole session (the clockless bridge), so the cook's
      // window *is* that session and every mark in it belongs.
      return widget.repo.db.markDao.forSession(widget.repo.bridgeId, anchor);
    }
    final sessions = await widget.repo.db.sessionDao.allSessions(
      widget.repo.bridgeId,
    );
    final out = <Mark>[];
    for (final s in sessions) {
      final started = s.startedUnixMs;
      if (started == null) {
        continue;
      }
      // A cheap span test before the query. **An open end is unbounded, not
      // zero-length**: reading a running session's end as its own start hid
      // every mark from every cook that began after the session did, which is
      // most of them.
      final cookEnd = _cook.endUnixMs;
      final sessionEnd = s.endedUnixMs;
      if ((sessionEnd != null && sessionEnd < _cook.startUnixMs) ||
          (cookEnd != null && started > cookEnd)) {
        continue;
      }
      final marks = await widget.repo.db.markDao.forSession(
        widget.repo.bridgeId,
        s.id,
      );
      out.addAll(marks.where((m) => _cook.covers(started + m.t * 1000)));
    }
    return out;
  }

  /// The sample `t` this cook calls zero.
  ///
  /// A cook is a window over a session's recording, so a cook that begins two
  /// hours into a session must still print its first mark as `00:00:00`. An
  /// anchored cook is pinned to a whole session, so the two zeros coincide.
  int get _originT {
    final origin = _origin;
    if (origin == null || _cook.anchorSessionId != null) {
      return 0;
    }
    return ((_cook.startUnixMs - origin) / 1000).round();
  }

  /// The cook immediately before and after this one. Merging across the whole
  /// list would be a picker nobody reads.
  List<CookAnnotation> get _neighbours {
    final sorted = [..._all]
      ..sort((a, b) => a.startUnixMs.compareTo(b.startUnixMs));
    final i = sorted.indexWhere((c) => c.id == _cook.id);
    if (i < 0) {
      return const [];
    }
    return [
      if (i > 0) sorted[i - 1],
      if (i < sorted.length - 1) sorted[i + 1],
    ];
  }

  /// Runs an edit and re-reads. Returns false when the model refused it, so a
  /// caller does not report success over a rejection.
  Future<bool> _apply(Future<CookAnnotation> Function() edit) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final next = await edit();
      if (mounted) {
        setState(() => _cook = next);
      }
      await _load();
      await widget.onChanged?.call();
      return true;
    } on ArgumentError catch (e) {
      // The food-safety gate, or an impossible time bound. Copy over error.
      messenger?.showSnackBar(
        SnackBar(content: Text(e.message?.toString() ?? 'That isn’t allowed.')),
      );
      return false;
    }
  }

  void _say(String message, {SnackBarAction? action}) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(message),
          action: action,
          showCloseIcon: true,
          duration: const Duration(seconds: 6),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.failed) {
      return ProblemState(
        key: const Key('cook-detail-failed'),
        title: 'Couldn’t read this cook',
        message:
            'Something is wrong with this phone’s copy of it. Nothing has '
            'been lost on the bridge.',
        action: FilledButton.tonal(
          onPressed: _retry,
          child: const Text('Try again'),
        ),
      );
    }
    if (_phase == _Phase.loading) {
      return const _Loading();
    }
    final t = context.tokens;
    final now = DateTime.now().millisecondsSinceEpoch;
    // The chart and statistics speak `CookSession`; the annotation supplies its
    // own bounds. This projection is the seam, and it is deliberately shallow —
    // nothing downstream needs to know a cook is now an annotation.
    final asSession = CookSession(
      id: _cook.id,
      name: _cook.displayName(),
      startedUnixMs: _origin,
      endedUnixMs: _cook.endUnixMs,
      closed: _cook.endUnixMs != null,
      probes: [
        for (final r in _cook.roles)
          Probe(
            n: r.jack,
            name: r.label,
            role: r.role,
            targetF10: r.targetF10,
            // The band lives on the cook, not on the role — and these two
            // fields are the *only* inputs to the chart's shaded band and to
            // the "Time in band" statistic. Leaving them null is why a brisket
            // preset that sets 225–275 °F still read "no band set".
            alarmMinF10: r.role == ProbeRole.pit ? _cook.pitBandMinF10 : null,
            alarmMaxF10: r.role == ProbeRole.pit ? _cook.pitBandMaxF10 : null,
          ),
      ],
    );

    return SessionDetailView(
      key: ValueKey('cook-detail-${_cook.id}'),
      session: asSession,
      samples: _samples,
      marks: _marks,
      probes: asSession.probes,
      gaps: _gaps,
      celsius: widget.celsius,
      showIdentity: false,
      originT: _originT,
      header: [
        _identity(t, now),
        const SizedBox(height: SmokeTokens.s3),
        _startCard(t),
        const SizedBox(height: SmokeTokens.s3),
        _statStrip(t, now),
        if (_cook.hasNoTarget) ...[
          const SizedBox(height: SmokeTokens.s3),
          _setTargetCard(t),
        ],
        if (_gaps.isNotEmpty) ...[
          const SizedBox(height: SmokeTokens.s3),
          CookGapsCard(gaps: _gaps, startedUnixMs: _origin),
        ],
      ],
      footer: [
        _section(t, 'NOTES'),
        _notesCard(t),
        _section(t, 'EDIT THIS COOK'),
        _editList(t),
        const SizedBox(height: SmokeTokens.s5),
        _deleteCard(t),
      ],
    );
  }

  // ── the header ───────────────────────────────────────────────────────

  /// Who this cook is: its avatar, its name, whether it is still open.
  ///
  /// The [FoodAvatar] is §17.3 A's third call site and the one that pays off
  /// the other two — a cook opened from a list of avatars should land on the
  /// same avatar, at a size that reads as a portrait rather than as a bullet.
  /// It is the identity channel (§17.2), so it is the same picture whether this
  /// cook ran perfectly or fell off a cliff at hour nine; the status pill beside
  /// it is what carries state, in chrome, with an icon and a word.
  ///
  /// It renders even when the pushed route already carries the name in its
  /// AppBar — a title repeated is clutter, but a *picture* of the subject is
  /// the thing the AppBar cannot give.
  Widget _identity(SmokeTokens t, int now) {
    final status = _cook.statusAt(now);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FoodAvatar(
          key: const Key('cook-detail-avatar'),
          glyph: FoodGlyph.forCook(
            presetId: _cook.presetId,
            hazard: _cook.hazard,
            name: _cook.name,
          ),
          size: 44,
          // §17.5 — the same rule the list applies, so opening a cook does not
          // change its colour. A finished cook is a record and wears the rich
          // register; a recording one is live and cools.
          vivid: status != CookStatus.running,
        ),
        const SizedBox(width: SmokeTokens.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (widget.showTitle)
                    Expanded(
                      child: Text(
                        _cook.displayName(),
                        style: SmokeType.displayL.copyWith(color: t.textHi),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                  if (status != CookStatus.finished)
                    CookStatusPill(status: status),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                switch (status) {
                  CookStatus.scheduled =>
                    'Armed for ${formatSessionDate(_cook.startUnixMs)}. It '
                        'becomes a cook when that time arrives.',
                  CookStatus.running =>
                    'No end set. The bridge keeps recording either way.',
                  CookStatus.finished =>
                    'Ran until ${formatSessionDate(_cook.endUnixMs)}.',
                },
                style: SmokeType.bodySm.copyWith(color: t.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The differentiator, given the screen's one ember button.
  Widget _startCard(SmokeTokens t) => SmokeCard(
    key: const Key('cook-start-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('STARTED', style: SmokeType.label.copyWith(color: t.textMuted)),
        const SizedBox(height: SmokeTokens.s1),
        Text(
          formatSessionDate(_cook.startUnixMs),
          style: SmokeType.displayS.copyWith(color: t.textHi),
        ),
        const SizedBox(height: SmokeTokens.s2),
        Text(
          _anchors.isEmpty
              ? 'Nothing in the recording points at an earlier start. You can '
                    'still set the time yourself.'
              : 'The recording holds '
                    '${_anchors.length} ${_anchors.length == 1 ? 'moment' : 'moments'} '
                    'this cook could have started at. Moving the start does '
                    'not move a single reading.',
          style: SmokeType.bodySm.copyWith(color: t.textBody),
        ),
        const SizedBox(height: SmokeTokens.s4),
        PrimaryAction(
          key: const Key('cook-backdate'),
          label: 'Move start',
          icon: Icons.schedule_rounded,
          onPressed: () => unawaited(_backdate()),
        ),
      ],
    ),
  );

  /// Three numbers, above the fold: the screen's one question, answered before
  /// the chart has to be read.
  Widget _statStrip(SmokeTokens t, int now) {
    final elapsedS = _cook.elapsedMsAt(now) ~/ 1000;
    final running = _cook.statusAt(now) == CookStatus.running;
    final missingS = _gaps.fold(0, (a, g) => a + g.durationS);
    return SmokeCard(
      key: const Key('cook-stat-strip'),
      // A Wrap, not a Row: at 200% text scale on a 360 dp phone three
      // tabular numbers do not fit on one line, and reflowing them beats
      // ellipsing the answer the screen exists to give.
      child: Wrap(
        spacing: SmokeTokens.s7,
        runSpacing: SmokeTokens.s3,
        children: [
          _stat(
            t,
            running ? 'SO FAR' : 'TOTAL TIME',
            formatDuration(elapsedS),
          ),
          _stat(
            t,
            'PEAK',
            formatTemp(_summary.peakF10, celsius: widget.celsius),
          ),
          if (missingS > 0)
            _stat(t, 'MISSING', formatDuration(missingS))
          else
            _stat(t, 'READINGS', _grouped(_summary.count)),
        ],
      ),
    );
  }

  Widget _stat(SmokeTokens t, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: SmokeType.monoBig.copyWith(color: t.textHi),
        maxLines: 1,
      ),
      const SizedBox(height: SmokeTokens.s1),
      Text(label, style: SmokeType.labelSm.copyWith(color: t.textMuted)),
    ],
  );

  Widget _setTargetCard(SmokeTokens t) => SmokeCard(
    key: const Key('cook-set-target'),
    padding: EdgeInsets.zero,
    child: CookSheetRow(
      icon: Icons.adjust_rounded,
      title: 'Set a target',
      subtitle:
          'This cook has no target yet. Adding one turns on the gauges and '
          'the estimate, and it works retroactively.',
      onTap: () => unawaited(_retarget()),
    ),
  );

  // ── the footer ───────────────────────────────────────────────────────

  Widget _section(SmokeTokens t, String label) => Padding(
    padding: const EdgeInsets.only(
      top: SmokeTokens.s5,
      bottom: SmokeTokens.s2,
      left: SmokeTokens.s1,
    ),
    child: Text(label, style: SmokeType.label.copyWith(color: t.textMuted)),
  );

  /// Writes the notes if they changed. Called on focus loss, on a tap outside
  /// and on dispose — never on Enter, which in a three-line field means a
  /// newline and nothing else.
  Future<void> _saveNotes() async {
    if (_notes.text == _cook.notes) {
      return;
    }
    await _apply(() => widget.repo.setNotes(_cook, _notes.text));
  }

  void _onNotesFocus() {
    if (!_notesFocus.hasFocus) {
      unawaited(_saveNotes());
    }
  }

  /// Keeps the field in step with the row when something *else* changed the
  /// notes — a merge concatenates both cooks' — without pulling the text out
  /// from under someone mid-sentence.
  void _syncNotes() {
    if (!_notesFocus.hasFocus && _notes.text != _cook.notes) {
      _notes.text = _cook.notes;
    }
  }

  Widget _notesCard(SmokeTokens t) => SmokeCard(
    child: TextField(
      key: const Key('cook-notes'),
      controller: _notes,
      focusNode: _notesFocus,
      maxLength: 200,
      maxLines: 3,
      minLines: 1,
      style: SmokeType.body.copyWith(color: t.textHi),
      decoration: InputDecoration(
        hintText: 'Wrapped at 165, apple wood',
        hintStyle: SmokeType.bodySm.copyWith(color: t.textMuted),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.zero,
      ),
      // Tapping away is how people finish a note. On a phone that gesture does
      // not drop focus by itself, so it is made to — and the focus listener
      // does the writing.
      onTapOutside: (_) => _notesFocus.unfocus(),
    ),
  );

  /// Every edit, one tap from here — so no edit is more than two taps from the
  /// cook itself. Rows that cannot run render dimmed with their reason.
  Widget _editList(SmokeTokens t) {
    final targets = [
      for (final r in _cook.roles)
        if (r.role == ProbeRole.food && r.targetF10 != null)
          'probe ${r.jack} to '
              '${formatSetpoint(r.targetF10, celsius: widget.celsius)}',
    ];
    final running = _cook.endUnixMs == null;
    final rows = <Widget>[
      CookSheetRow(
        key: const Key('cook-rename'),
        icon: Icons.drive_file_rename_outline_rounded,
        title: 'Rename',
        subtitle: _cook.name.isEmpty
            ? 'It has no name yet, so the list calls it '
                  '“${_cook.displayName()}”.'
            : 'It is called “${_cook.name}”.',
        onTap: () => unawaited(_rename()),
      ),
      CookSheetRow(
        key: const Key('cook-move-start'),
        icon: Icons.schedule_rounded,
        title: 'Move start',
        subtitle: _anchors.isEmpty
            ? 'Set the moment this cook really began.'
            : '${_anchors.length} moments in the recording could be it.',
        onTap: () => unawaited(_backdate()),
      ),
      CookSheetRow(
        key: const Key('cook-retarget'),
        icon: Icons.adjust_rounded,
        title: _cook.hasNoTarget ? 'Set a target' : 'Change targets',
        subtitle: targets.isEmpty
            ? 'Nothing to reach yet. Add one and the gauges follow.'
            : targets.join(', '),
        onTap: () => unawaited(_retarget()),
      ),
      CookSheetRow(
        key: const Key('cook-split'),
        icon: Icons.call_split_rounded,
        title: 'Split in two',
        subtitle: 'Cut this cook at a mark or a time. No reading moves.',
        enabled: _samples.length > 1,
        reason: 'Nothing is recorded inside this cook to split.',
        onTap: () => unawaited(_split()),
      ),
      CookSheetRow(
        key: const Key('cook-merge'),
        icon: Icons.merge_rounded,
        title: 'Merge with a neighbour',
        subtitle: 'Join this cook to the one before or after it.',
        enabled: _neighbours.isNotEmpty,
        reason: 'Nothing is recorded next to this cook.',
        onTap: () => unawaited(_merge()),
      ),
      CookSheetRow(
        key: const Key('cook-repeat'),
        icon: Icons.replay_rounded,
        title: 'Cook this again',
        subtitle: 'Starts a new cook now with the same roles and targets.',
        onTap: () => unawaited(_repeat()),
      ),
      CookSheetRow(
        key: const Key('cook-favourite'),
        icon: _cook.favourite ? Icons.star_rounded : Icons.star_outline_rounded,
        title: 'Favourite',
        subtitle: 'Marks it with a star in the list.',
        trailing: _cook.favourite ? 'On' : 'Off',
        onTap: () => unawaited(
          _apply(() => widget.repo.setFavourite(_cook, !_cook.favourite)),
        ),
      ),
      CookSheetRow(
        key: Key(running ? 'cook-end' : 'cook-reopen'),
        icon: running
            ? Icons.stop_circle_outlined
            : Icons.play_circle_outline_rounded,
        title: running ? 'End this cook' : 'Reopen this cook',
        subtitle: running
            ? 'Marks the end here. The bridge keeps recording.'
            : 'Removes the end, so it runs on from where it stopped.',
        onTap: () => unawaited(
          _apply(
            () => running ? widget.repo.end(_cook) : widget.repo.reopen(_cook),
          ),
        ),
      ),
      CookSheetRow(
        key: const Key('cook-export'),
        icon: Icons.ios_share_rounded,
        title: 'Export as CSV',
        subtitle: 'The same columns the bridge writes, from this phone.',
        enabled: _samples.isNotEmpty,
        reason: 'This cook has no readings to export.',
        onTap: () => unawaited(
          exportSamples(
            context,
            name: _cook.displayName(),
            id: _cook.id,
            startedUnixMs: _origin,
            samples: _samples,
          ),
        ),
      ),
    ];
    return SmokeCard(
      key: const Key('cook-edits'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: SmokeTokens.s4,
                endIndent: SmokeTokens.s4,
                color: t.hairlineStrong,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _deleteCard(SmokeTokens t) => SmokeCard(
    padding: EdgeInsets.zero,
    child: CookSheetRow(
      key: const Key('cook-delete'),
      icon: Icons.delete_outline_rounded,
      iconColor: StatusPalette.critical,
      title: 'Delete this cook',
      subtitle: 'The readings stay. Only the name, notes and targets go.',
      onTap: () => unawaited(_delete()),
    ),
  );

  // ── the edits ────────────────────────────────────────────────────────

  Future<void> _rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => Theme(
        data: SmokeTheme.dark,
        child: _RenameDialog(
          initial: _cook.name,
          hint: _cook.displayName(),
        ),
      ),
    );
    if (name == null || name.isEmpty) {
      return;
    }
    await _apply(() => widget.repo.rename(_cook, name));
  }

  /// The differentiator's flow: offer what the recording knows, commit on tap,
  /// then **report in past tense and offer the way back** (§16.4).
  Future<void> _backdate() async {
    final was = _cook.startUnixMs;
    final at = await showBackdateSheet(
      context,
      cook: _cook,
      anchors: _anchors,
    );
    if (at == null || !mounted || at == was) {
      return;
    }
    final moved = shiftLabel(at, was);
    if (await _apply(() => widget.repo.backdate(_cook, at)) && mounted) {
      _say(
        'Start moved. This cook now begins $moved. No readings moved.',
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              unawaited(_apply(() => widget.repo.backdate(_cook, was))),
        ),
      );
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
    // The **whole** projection is persisted, not just its roles. The preset,
    // the doneness, the hazard class, the safety mode and the pit band all come
    // back from the sheet, all of them are targets, and the confirmation below
    // claims every one of them. See [CookAnnotation.retargetedTo] for what this
    // cook keeps regardless.
    final next = CookAnnotation.fromPlan(
      plan,
      bridgeId: widget.repo.bridgeId,
      nowUnixMs: _cook.createdUnixMs,
      id: _cook.id,
    );
    if (await _apply(() => widget.repo.retarget(_cook, next)) && mounted) {
      _say('Targets saved. The gauges and the estimate follow them now.');
    }
  }

  Future<void> _split() async {
    final at = await showSplitSheet(context, cook: _cook, marks: _marks);
    if (at == null || !mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final (before, after) = await widget.repo.split(_cook, at);
      if (mounted) {
        setState(() => _cook = before);
      }
      await _load();
      await widget.onChanged?.call();
      if (mounted) {
        _say(
          'This cook now ends at ${formatSessionDate(at)}. Everything after '
          'it is “${after.displayName()}”.',
        );
      }
    } on ArgumentError catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text(e.message?.toString() ?? 'Can’t split there.')),
      );
    }
  }

  Future<void> _merge() async {
    final other = await showMergeSheet(
      context,
      cook: _cook,
      neighbours: _neighbours,
    );
    if (other == null || !mounted) {
      return;
    }
    final ok = await showCostSheet(
      context,
      title: 'Merge these two cooks?',
      body:
          'They become one cook spanning both, keeping the earlier one’s name '
          'and targets.',
      keeps: 'Every reading, and both sets of notes.',
      loses: 'The later cook’s own name and targets.',
      confirmLabel: 'Merge',
      cancelLabel: 'Keep them separate',
    );
    if (!ok || !mounted) {
      return;
    }
    final was = _cook.id;
    final merged = await widget.repo.merge(_cook, other);
    if (mounted) {
      setState(() => _cook = merged);
    }
    await _load();
    // Merging with the *earlier* neighbour keeps that cook's row and deletes
    // this one. A caller loading by id has to be told before it re-reads, or it
    // reports the cook missing the moment the merge worked.
    if (merged.id != was) {
      widget.onIdChanged?.call(merged.id);
    }
    await widget.onChanged?.call();
    if (mounted) {
      _say('Merged into “${merged.displayName()}”.');
    }
  }

  Future<void> _repeat() async {
    await repeatCook(context, widget.repo, _cook);
    await widget.onChanged?.call();
  }

  Future<void> _delete() async {
    final ok = await showCostSheet(
      context,
      title: 'Delete this cook?',
      body:
          'This removes the name and targets you gave this stretch of the '
          'recording.',
      // The load-bearing half. People delete a cook expecting the readings to
      // go with it, and they do not.
      keeps: 'Every reading. The bridge never stops recording.',
      loses: 'This cook’s name, notes, targets and its row in the list.',
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

/// Owns its controller, so the field is still alive while the dialog animates
/// out — disposing one the moment `showDialog` returns tears the tree down
/// under the exit transition.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial, required this.hint});

  final String initial;
  final String hint;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Name this cook'),
    content: TextField(
      key: const Key('cook-rename-field'),
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(hintText: widget.hint),
      onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Keep the old name'),
      ),
      FilledButton(
        key: const Key('cook-rename-save'),
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: const Text('Rename'),
      ),
    ],
  );
}

/// A spinner with no words is worse than an error with words (§16.2).
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: SmokeTokens.s3),
          Text(
            'Reading this cook from this phone.',
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          ),
        ],
      ),
    );
  }
}

/// `1,240` — a reading count is read, not parsed.
String _grouped(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) {
      out.write(',');
    }
    out.write(s[i]);
  }
  return out.toString();
}
