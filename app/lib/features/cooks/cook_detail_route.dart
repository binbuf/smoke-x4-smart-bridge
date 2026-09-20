/// The pushed cook routes: `/cooks/:id` and `/cooks/:id/edit` (newapp §B.2,
/// §C.4).
///
/// Both are **pushed inside the Cooks branch**, so the nav bar stays, the shell
/// stays mounted, the live link stays alive, and system back returns to the list
/// with its scroll intact (§13.3.4). `context.go` appears nowhere here.
///
/// `/cooks/:id/edit` exists as a route rather than only as sheets because a
/// rename used to be a dialog **no route passed a callback to** — the code was
/// written, wired to nothing, and therefore untestable and unreachable. Every
/// edit now also lives on `/cooks/:id` itself, one tap from the cook; this route
/// survives as the URL-addressable form, not as the only way in.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_env.dart';
import '../../data/repos/cook_repository.dart';
import '../../design/design.dart';
import '../../domain/plan/plan.dart';
import '../../ui/ui.dart';
import '../shell/shell_scope.dart';
import 'cook_detail_view.dart';
import 'cook_sheet_shell.dart';

/// Loads a cook by id and hands it to [CookDetailView].
class CookDetailRoute extends StatefulWidget {
  const CookDetailRoute({required this.cookId, super.key});

  final int cookId;

  @override
  State<CookDetailRoute> createState() => _CookDetailRouteState();
}

class _CookDetailRouteState extends State<CookDetailRoute> {
  CookRepository? _repo;
  CookAnnotation? _cook;
  bool _loaded = false;

  /// True when the read itself threw, which is not the same thing as the cook
  /// being absent — "that cook isn't here" over a database that would not open
  /// is a claim this screen cannot make (§16.4).
  bool _failed = false;

  /// The row on screen. Starts as the route's id and **follows a merge**, which
  /// keeps the earlier cook's row and deletes this one; re-reading the URL's id
  /// after that finds nothing.
  late int _id = widget.cookId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final env = AppEnv.instance;
      final bridgeId = await env?.db.sessionDao.knownBridgeId();
      if (env == null || bridgeId == null) {
        if (mounted) {
          setState(() => _loaded = true);
        }
        return;
      }
      final repo = CookRepository(env.db, bridgeId: bridgeId);
      final cook = await repo.cook(_id);
      if (mounted) {
        setState(() {
          _repo = repo;
          _cook = cook;
          _failed = false;
          _loaded = true;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _failed = true;
          _loaded = true;
        });
      }
    }
  }

  void _retry() {
    setState(() {
      _loaded = false;
      _failed = false;
    });
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final celsius = ShellScope.maybeOf(context)?.celsius ?? false;
    final cook = _cook;
    final repo = _repo;
    return Scaffold(
      backgroundColor: context.tokens.bg,
      // §16.5: the screen title lives in the content *except* on a pushed
      // route, which is this one — so the view below renders without its own.
      appBar: AppBar(title: Text(cook?.displayName() ?? 'Cook')),
      body: SafeArea(
        child: !_loaded
            ? const _Loading()
            : _failed
            ? ProblemState(
                key: const Key('cook-detail-route-failed'),
                title: 'Couldn’t read this cook',
                message:
                    'Something is wrong with this phone’s copy of your '
                    'history. Nothing has been lost on the bridge.',
                action: FilledButton.tonal(
                  onPressed: _retry,
                  child: const Text('Try again'),
                ),
              )
            : cook == null || repo == null
            ? EmptyState(
                key: const Key('cook-detail-missing'),
                icon: Icons.search_off_rounded,
                title: 'That cook isn’t here',
                message:
                    'This phone has no copy of it. It may have been deleted '
                    'from another screen.',
                action: FilledButton.tonal(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Back to cooks'),
                ),
              )
            : CookDetailView(
                repo: repo,
                cook: cook,
                celsius: celsius,
                showTitle: false,
                onChanged: _load,
                onIdChanged: (id) => _id = id,
                onDeleted: () => Navigator.of(context).maybePop(),
              ),
      ),
    );
  }
}

/// `/cooks/:id/edit` — the URL-addressable rename, and the merge.
///
/// Everything here is also one tap from `/cooks/:id`. This route stays because
/// a URL is the cheapest way to make an editor exist, and because a deep link
/// that lands on nothing is worse than a screen that repeats itself.
class CookEditRoute extends StatefulWidget {
  const CookEditRoute({required this.cookId, super.key});

  final int cookId;

  @override
  State<CookEditRoute> createState() => _CookEditRouteState();
}

class _CookEditRouteState extends State<CookEditRoute> {
  CookRepository? _repo;
  CookAnnotation? _cook;
  List<CookAnnotation> _all = const [];
  bool _loaded = false;
  late final TextEditingController _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final env = AppEnv.instance;
    final bridgeId = await env?.db.sessionDao.knownBridgeId();
    if (env == null || bridgeId == null) {
      if (mounted) {
        setState(() => _loaded = true);
      }
      return;
    }
    final repo = CookRepository(env.db, bridgeId: bridgeId);
    final cook = await repo.cook(widget.cookId);
    final all = await repo.cooks();
    if (mounted) {
      setState(() {
        _repo = repo;
        _cook = cook;
        _all = all;
        _loaded = true;
        _name.text = cook?.name ?? '';
      });
    }
  }

  /// The cook immediately before or after this one — the only two a merge can
  /// sensibly offer, and offering the whole list would be a picker nobody
  /// reads.
  List<CookAnnotation> get _neighbours {
    final cook = _cook;
    if (cook == null) {
      return const [];
    }
    final sorted = [..._all]
      ..sort((a, b) => a.startUnixMs.compareTo(b.startUnixMs));
    final i = sorted.indexWhere((c) => c.id == cook.id);
    if (i < 0) {
      return const [];
    }
    return [
      if (i > 0) sorted[i - 1],
      if (i < sorted.length - 1) sorted[i + 1],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cook = _cook;
    final repo = _repo;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Edit cook')),
      body: SafeArea(
        child: !_loaded
            ? const _Loading()
            : cook == null || repo == null
            ? const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'That cook isn’t here',
                message: 'It may have been deleted from another screen.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  SmokeTokens.s4,
                  SmokeTokens.s4,
                  SmokeTokens.s4,
                  SmokeTokens.s6,
                ),
                children: [
                  Text(
                    'NAME',
                    style: SmokeType.label.copyWith(color: t.textMuted),
                  ),
                  const SizedBox(height: SmokeTokens.s2),
                  SmokeCard(
                    child: TextField(
                      key: const Key('cook-edit-name'),
                      controller: _name,
                      style: SmokeType.body.copyWith(color: t.textHi),
                      decoration: InputDecoration(
                        hintText: cook.displayName(),
                        hintStyle: SmokeType.bodySm.copyWith(
                          color: t.textMuted,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (v) =>
                          unawaited(_save(() => repo.rename(cook, v.trim()))),
                    ),
                  ),
                  const SizedBox(height: SmokeTokens.s3),
                  PrimaryAction(
                    label: 'Save name',
                    icon: Icons.check_rounded,
                    onPressed: () => unawaited(
                      _save(() => repo.rename(cook, _name.text.trim())),
                    ),
                  ),
                  const SizedBox(height: SmokeTokens.s5),
                  Text(
                    'MERGE',
                    style: SmokeType.label.copyWith(color: t.textMuted),
                  ),
                  const SizedBox(height: SmokeTokens.s2),
                  SmokeCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < _neighbours.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              thickness: 1,
                              indent: SmokeTokens.s4,
                              endIndent: SmokeTokens.s4,
                              color: t.hairlineStrong,
                            ),
                          CookSheetRow(
                            key: Key('cook-merge-${_neighbours[i].id}'),
                            icon: Icons.merge_rounded,
                            title:
                                'Merge with “${_neighbours[i].displayName()}”',
                            subtitle:
                                _neighbours[i].startUnixMs < cook.startUnixMs
                                ? 'the cook before this one'
                                : 'the cook after this one',
                            onTap: () => unawaited(
                              _merge(repo, cook, _neighbours[i]),
                            ),
                          ),
                        ],
                        if (_neighbours.isEmpty)
                          const CookSheetRow(
                            icon: Icons.merge_rounded,
                            title: 'Merge with a neighbour',
                            enabled: false,
                            reason:
                                'Nothing is recorded next to this cook to '
                                'merge with.',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _save(Future<CookAnnotation> Function() edit) async {
    await edit();
    await _load();
    if (mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Saved.')));
    }
  }

  Future<void> _merge(
    CookRepository repo,
    CookAnnotation cook,
    CookAnnotation other,
  ) async {
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
    if (!ok) {
      return;
    }
    await repo.merge(cook, other);
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }
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
