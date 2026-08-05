/// Branch 2 — `/cooks`: the session list, as **annotations over a continuous
/// recording** (newapp §B.2, §C.3, §D.1).
///
/// **Cache-only. No transport is touched.** Scrolling an 18-hour cook on the
/// sofa with the bridge unplugged is literally the acceptance test, and that
/// property is older than this rewrite.
///
/// What is new is what a row *is*. It used to be a device session — a thing the
/// bridge started and stopped, which the user could neither create nor edit.
/// Now it is a `Cooks` row: named, time-bounded, retargetable, splittable,
/// backdatable. The "+" in the app bar therefore does something that used to be
/// impossible — **create a cook now, over readings that already exist**.
///
/// FireBoard's sessions auto-close after 30 minutes of inactivity and roll over
/// after 24 hours. §C.3 is explicit that this app should not: because the bridge
/// records continuously, a cook runs exactly as long as the user says, and only
/// an explicit edit bounds it.
///
/// **Adaptive.** From 600 dp the list and the detail are one screen and tapping
/// is a *selection*, not a navigation — the canonical list-detail layout, and on
/// this flow also the fix for losing your place on a tablet.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_env.dart';
import '../../app/router.dart';
import '../../core/format.dart';
import '../../data/local/database.dart' show CookSummary;
import '../../data/repos/cook_repository.dart';
import '../../design/design.dart';
import '../../domain/plan/plan.dart';
import '../../ui/ui.dart';
import '../cook/cook_setup_sheet.dart';
import '../shell/shell_scope.dart';
import 'cook_detail_view.dart';

class CooksTab extends StatefulWidget {
  const CooksTab({super.key});

  @override
  State<CooksTab> createState() => _CooksTabState();
}

class _CooksTabState extends State<CooksTab> {
  CookRepository? _repo;
  List<CookListEntry>? _entries;
  StreamSubscription<List<CookAnnotation>>? _watch;

  /// The cook shown in the detail pane on a wide window. Held here rather than
  /// in the detail widget so unfolding the device keeps the cook you were
  /// reading open, and refolding leaves you on it.
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_watch?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    final env = AppEnv.instance;
    final bridgeId = await env?.db.sessionDao.knownBridgeId();
    if (env == null || bridgeId == null) {
      if (mounted) {
        setState(() => _entries = const []);
      }
      return;
    }
    final repo = CookRepository(env.db, bridgeId: bridgeId);
    _repo = repo;
    // Watch, don't poll: a cook created by the monitor, or by a split on
    // another screen, must appear without a relaunch.
    _watch = repo.watchCooks().listen((_) => unawaited(_rebuild()));
    await _rebuild();
  }

  Future<void> _rebuild() async {
    final repo = _repo;
    if (repo == null) {
      return;
    }
    final entries = await repo.listEntries();
    if (mounted) {
      setState(() => _entries = entries);
    }
  }

  void _open(CookAnnotation cook) {
    if (context.window.usesSplitPane) {
      setState(() => _selectedId = cook.id);
      return;
    }
    // Compact: push **inside this branch**, so the nav bar stays and system
    // back returns to the list with its scroll intact (§13.3.4).
    context.push(AppRoutes.cookDetail(cook.id));
  }

  /// §C.3's "+" — create a cook over the recording that is already happening.
  Future<void> _create() async {
    final session = ShellScope.maybeOf(context);
    final repo = _repo;
    if (repo == null) {
      return;
    }
    final plan = await showCookSetupSheet(
      context,
      celsius: session?.celsius ?? false,
    );
    if (plan == null || !mounted) {
      return;
    }
    if (session != null) {
      await session.startCook(plan);
    } else {
      await repo.startFromPlan(plan);
    }
    await _rebuild();
  }

  @override
  Widget build(BuildContext context) {
    final window = context.window;
    final celsius = ShellScope.maybeOf(context)?.celsius ?? false;
    final entries = _entries;

    final list = entries == null
        ? const Center(child: CircularProgressIndicator())
        : entries.isEmpty
        ? EmptyState(
            key: const Key('cooks-empty'),
            icon: Icons.outdoor_grill_outlined,
            title: 'No cooks yet',
            // Reinforces the annotate-over-continuous model rather than
            // implying nothing has been recorded.
            message:
                'Your bridge is still recording. Start a cook any time — you '
                'can even name a stretch that has already happened.',
            action: FilledButton.tonal(
              onPressed: () => unawaited(_create()),
              child: const Text('Start a cook'),
            ),
          )
        : _CooksListView(
            entries: entries,
            celsius: celsius,
            selectedId: window.usesSplitPane ? _selectedId : null,
            onOpen: _open,
          );

    // Keep a selection valid: a cook deleted from the detail pane must not
    // leave that pane rendering a ghost.
    final selected = entries
        ?.where((e) => e.cook.id == _selectedId)
        .firstOrNull
        ?.cook;

    final body = !window.usesSplitPane
        ? list
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: window.splitAt(window.width), child: list),
              SizedBox(width: window.hingeIsVertical ? window.hingeGap : 0),
              VerticalDivider(width: 1, color: context.tokens.hairline),
              Expanded(
                child: selected == null
                    ? const EmptyState(
                        icon: Icons.touch_app_outlined,
                        title: 'Pick a cook',
                        message:
                            'Choose one on the left and it opens here — chart, '
                            'statistics and marks.',
                      )
                    : CookDetailView(
                        key: ValueKey(selected.id),
                        repo: _repo!,
                        cook: selected,
                        celsius: celsius,
                        onChanged: _rebuild,
                      ),
              ),
            ],
          );

    return SafeArea(
      top: false,
      child: Column(
        children: [
          _header(context),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SmokeTokens.s4,
        SmokeTokens.s3,
        SmokeTokens.s2,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Cooks',
              style: SmokeType.displayS.copyWith(color: t.textHi),
            ),
          ),
          IconButton(
            key: const Key('cooks-create'),
            tooltip: 'Start a cook',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => unawaited(_create()),
          ),
        ],
      ),
    );
  }
}

/// The list itself — stateless over plain values, so it renders in a golden
/// with no repository behind it.
class _CooksListView extends StatelessWidget {
  const _CooksListView({
    required this.entries,
    required this.celsius,
    required this.onOpen,
    this.selectedId,
  });

  final List<CookListEntry> entries;
  final bool celsius;
  final int? selectedId;
  final void Function(CookAnnotation) onOpen;

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: const Key('cooks-list'),
    padding: const EdgeInsets.all(SmokeTokens.s4),
    itemCount: entries.length,
    itemBuilder: (context, i) => _CookRow(
      entry: entries[i],
      celsius: celsius,
      selected: entries[i].cook.id == selectedId,
      onTap: () => onOpen(entries[i].cook),
    ),
  );
}

class _CookRow extends StatelessWidget {
  const _CookRow({
    required this.entry,
    required this.celsius,
    required this.selected,
    required this.onTap,
  });

  final CookListEntry entry;
  final bool celsius;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cook = entry.cook;
    final s = entry.summary;
    return Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s2),
      child: SmokeCard(
        raised: selected,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    cook.displayName(),
                    style: SmokeType.title.copyWith(color: t.textHi),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (cook.favourite)
                  Padding(
                    padding: const EdgeInsets.only(right: SmokeTokens.s2),
                    child: Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: t.textMuted,
                    ),
                  ),
                if (entry.status != CookStatus.finished)
                  _StatusPill(status: entry.status),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _metaLine(cook, s),
              style: SmokeType.bodySm.copyWith(color: t.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  /// date · duration · peak · probes. Every part that cannot be computed
  /// honestly is simply absent rather than rendered as a zero.
  String _metaLine(CookAnnotation cook, CookSummary s) {
    final parts = <String>[
      formatSessionDate(cook.startUnixMs),
      if (s.minT != null && s.maxT != null)
        formatDuration(s.maxT! - s.minT!),
      if (s.peakF10 != null)
        'peak ${formatTemp(s.peakF10, celsius: celsius)}',
      if (s.count > 0) '${s.count} readings',
      if (s.count == 0) 'no readings yet',
    ];
    return parts.join(' · ');
  }
}

/// "Recording" on the open annotation, "Scheduled" on one that has not begun.
///
/// Deliberately **not** "Cooking": an open cook only means the app is calling
/// this stretch of the recording by that name.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final CookStatus status;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final role = status == CookStatus.running
        ? StatusRole.positive
        : StatusRole.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: StatusPalette.fill(role),
        borderRadius: BorderRadius.circular(SmokeTokens.radiusPill),
        border: Border.all(color: StatusPalette.border(role)),
      ),
      child: Text(
        status.label,
        style: SmokeType.labelSm.copyWith(color: t.textHi),
      ),
    );
  }
}
