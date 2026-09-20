/// Branch 2 — `/cooks`: "Show me my cooks, past and running" (16 §16.6,
/// newapp §B.2, §C.3, §D.1).
///
/// **Cache-only. No transport is touched.** Scrolling an 18-hour cook on the
/// sofa with the bridge unplugged is literally the acceptance test, and that
/// property is older than this rewrite.
///
/// What is new is what a row *is*. It used to be a device session — a thing the
/// bridge started and stopped, which the user could neither create nor edit.
/// Now it is a `Cooks` row: named, time-bounded, retargetable, splittable,
/// backdatable. The "+" therefore does something that used to be impossible —
/// **create a cook now, over readings that already exist** — and the sheet it
/// opens is where that model gets taught.
///
/// FireBoard's sessions auto-close after 30 minutes of inactivity and roll over
/// after 24 hours. §C.3 is explicit that this app should not: because the
/// bridge records continuously, a cook runs exactly as long as the user says,
/// and only an explicit edit bounds it.
///
/// **Adaptive.** From 600 dp the list and the detail are one screen and tapping
/// is a *selection*, not a navigation — the canonical list-detail layout, and
/// on this flow also the fix for losing your place on a tablet.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_env.dart';
import '../../app/router.dart';
import '../../data/repos/cook_repository.dart';
import '../../design/design.dart';
import '../../domain/plan/plan.dart';
import '../../ui/ui.dart';
import '../cook/cook_setup_sheet.dart';
import '../shell/shell_scope.dart';
import 'cook_create_sheet.dart';
import 'cook_detail_view.dart';
import 'cook_list_model.dart';
import 'cook_list_view.dart';

class CooksTab extends StatefulWidget {
  const CooksTab({super.key});

  @override
  State<CooksTab> createState() => _CooksTabState();
}

/// What the screen can be showing. Every one of these renders — the ladder in
/// §16.7 is a checklist, not a suggestion.
enum _Phase { loading, noBridge, ready, failed }

class _CooksTabState extends State<CooksTab> {
  CookRepository? _repo;
  List<CookListRow> _rows = const [];
  _Phase _phase = _Phase.loading;
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
        setState(() => _phase = _Phase.noBridge);
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
    try {
      final entries = await repo.listEntries();
      final rows = <CookListRow>[
        for (final e in entries)
          CookListRow(
            entry: e,
            // Bucketed in SQL — a two-month list must not page the cache
            // through Dart to draw itself.
            spark: await loadCookSparkline(
              repo.db,
              e.cook,
              summary: e.summary,
            ),
          ),
      ];
      if (mounted) {
        setState(() {
          _rows = rows;
          _phase = _Phase.ready;
        });
      }
    } on Object {
      if (mounted) {
        setState(() => _phase = _Phase.failed);
      }
    }
  }

  void _open(CookAnnotation cook) {
    if (context.window.usesSplitPane) {
      setState(() => _selectedId = cook.id);
      return;
    }
    // Compact: push **inside this branch**, so the nav bar stays and system
    // back returns to the list with its scroll intact (§13.3.4).
    unawaited(context.push(AppRoutes.cookDetail(cook.id)));
  }

  /// §16.6's "+" — create a cook over the recording that is already happening.
  Future<void> _create() async {
    final repo = _repo;
    if (repo == null) {
      return;
    }
    final choice = await showCreateCookSheet(context);
    if (choice == null || !mounted) {
      return;
    }
    final created = switch (choice) {
      CookCreateChoice.now => await _startNow(repo),
      CookCreateChoice.withTargets => await _startWithTargets(repo),
    };
    await _rebuild();
    if (created != null && mounted) {
      // Straight into the cook, where the start card offers to move the start
      // back to where the recording says it belongs (§D.3.1).
      _open(created);
    }
  }

  /// A cook with no targets, starting now, over readings that already exist.
  ///
  /// Deliberately **not** routed through `ShellSession.startCook`: that installs
  /// the guided overlay on `/live`, and there is nothing to guide until a target
  /// exists. The annotation is the whole of what was asked for.
  Future<CookAnnotation?> _startNow(CookRepository repo) async {
    final plan = CookPlan(
      presetId: 'custom',
      title: '',
      // Nobody has said what this is yet — that is the entire point of
      // "start one now, decide later" — so it takes the class that carries a
      // floor rather than the one that carries none. A retarget re-asks.
      hazard: HazardClass.unstated,
      doneness: '',
      probes: const [],
    );
    try {
      return await repo.startFromPlan(plan);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Couldn’t start a cook on this phone.')),
        );
      }
      return null;
    }
  }

  Future<CookAnnotation?> _startWithTargets(CookRepository repo) async {
    final session = ShellScope.maybeOf(context);
    final plan = await showCookSetupSheet(
      context,
      celsius: session?.celsius ?? false,
    );
    if (plan == null || !mounted) {
      return null;
    }
    if (session != null) {
      await session.startCook(plan);
      final id = plan.cookId;
      return id == null ? null : repo.cook(id);
    }
    return repo.startFromPlan(plan);
  }

  @override
  Widget build(BuildContext context) {
    final window = context.window;
    final celsius = ShellScope.maybeOf(context)?.celsius ?? false;
    final now = DateTime.now().millisecondsSinceEpoch;

    final list = switch (_phase) {
      _Phase.loading => const _Loading(),
      _Phase.noBridge => const EmptyState(
        key: Key('cooks-no-bridge'),
        icon: Icons.hub_outlined,
        title: 'No bridge yet',
        // Not "No cooks yet": promising that the bridge is recording when the
        // app has never met one would be a claim the app cannot support.
        message:
            'Cooks land here once a bridge has recorded something. Set one up '
            'on the Device tab.',
      ),
      _Phase.failed => ProblemState(
        key: const Key('cooks-failed'),
        title: 'Couldn’t read your cooks',
        message:
            'Something is wrong with this phone’s copy of your history. '
            'Nothing has been lost on the bridge.',
        action: FilledButton.tonal(
          onPressed: () => unawaited(_rebuild()),
          child: const Text('Try again'),
        ),
      ),
      _Phase.ready when _rows.isEmpty => EmptyState(
        key: const Key('cooks-empty'),
        icon: Icons.outdoor_grill_outlined,
        title: 'No cooks yet',
        // Reinforces the annotate-over-continuous model rather than implying
        // nothing has been recorded.
        message:
            'Your bridge is still recording. Start one any time — you can '
            'even name a stretch that already happened.',
        action: FilledButton.tonal(
          onPressed: () => unawaited(_create()),
          child: const Text('Start a cook'),
        ),
      ),
      _Phase.ready => CooksListView(
        sections: groupCooks(_rows, nowUnixMs: now),
        celsius: celsius,
        nowUnixMs: now,
        selectedId: window.usesSplitPane ? _selectedId : null,
        onOpen: _open,
      ),
    };

    // Keep a selection valid: a cook deleted from the detail pane must not
    // leave that pane rendering a ghost.
    final selected = _rows
        .where((r) => r.cook.id == _selectedId)
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
                child: selected == null || _repo == null
                    ? const EmptyState(
                        icon: Icons.touch_app_outlined,
                        title: 'Pick a cook',
                        message:
                            'Choose one on the left and it opens here — chart, '
                            'statistics, marks and every edit.',
                      )
                    : CookDetailView(
                        key: ValueKey(selected.id),
                        repo: _repo!,
                        cook: selected,
                        celsius: celsius,
                        onChanged: _rebuild,
                        // Merging keeps the *earlier* cook and deletes the
                        // later row, so the selection can be the id that just
                        // went away — and the pane fell back to "Pick a cook",
                        // losing your place mid-edit. Follow the survivor.
                        onIdChanged: (id) => setState(() => _selectedId = id),
                        onDeleted: () => setState(() => _selectedId = null),
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
            onPressed: _phase == _Phase.noBridge
                ? null
                : () => unawaited(_create()),
          ),
        ],
      ),
    );
  }
}

/// A spinner with no words is worse than an error with words (§16.2).
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      key: const Key('cooks-loading'),
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
            'Reading this phone’s copy of your cooks.',
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          ),
        ],
      ),
    );
  }
}
