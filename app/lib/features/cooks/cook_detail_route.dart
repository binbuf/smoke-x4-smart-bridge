/// The pushed cook routes: `/cooks/:id` and `/cooks/:id/edit` (newapp §B.2,
/// §C.4).
///
/// Both are **pushed inside the Cooks branch**, so the nav bar stays, the shell
/// stays mounted, the live link stays alive, and system back returns to the list
/// with its scroll intact (§13.3.4). `context.go` appears nowhere here.
///
/// `/cooks/:id/edit` exists as a route rather than only as sheets because a
/// rename used to be a dialog **no route passed a callback to** — the code was
/// written, wired to nothing, and therefore untestable and unreachable. A URL
/// is the cheapest way to make an editor exist.
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
import '../shell/shell_scope.dart';
import 'cook_detail_view.dart';

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

  @override
  void initState() {
    super.initState();
    unawaited(_load());
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
    if (mounted) {
      setState(() {
        _repo = repo;
        _cook = cook;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final celsius = ShellScope.maybeOf(context)?.celsius ?? false;
    final cook = _cook;
    final repo = _repo;
    return Scaffold(
      backgroundColor: context.tokens.bg,
      appBar: AppBar(
        title: Text(cook?.displayName() ?? 'Cook'),
        actions: [
          if (cook != null)
            IconButton(
              key: const Key('cook-open-editor'),
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                await context.push(AppRoutes.cookEdit(cook.id));
                await _load();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
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
                onChanged: _load,
                onDeleted: () => Navigator.of(context).maybePop(),
              ),
      ),
    );
  }
}

/// `/cooks/:id/edit` — rename, and the two bounds.
///
/// The heavier edits (retarget, split, merge) live as sheets on the detail
/// screen because each needs the cook's own samples or its neighbours; this
/// route is the plain metadata form, which is what "edit" means to most people.
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
            ? const Center(child: CircularProgressIndicator())
            : cook == null || repo == null
            ? const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'That cook isn’t here',
                message: 'It may have been deleted from another screen.',
              )
            : ListView(
                padding: const EdgeInsets.all(SmokeTokens.s4),
                children: [
                  SmokeCard(
                    child: TextField(
                      key: const Key('cook-edit-name'),
                      controller: _name,
                      style: SmokeType.body.copyWith(color: t.textHi),
                      decoration: InputDecoration(
                        labelText: 'Name',
                        hintText: cook.displayName(),
                        hintStyle: SmokeType.bodySm.copyWith(
                          color: t.textMuted,
                        ),
                        border: InputBorder.none,
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
                  if (_neighbours.isEmpty)
                    Text(
                      'Nothing next to this cook to merge with.',
                      style: SmokeType.bodySm.copyWith(color: t.textMuted),
                    )
                  else
                    for (final other in _neighbours)
                      Padding(
                        padding: const EdgeInsets.only(bottom: SmokeTokens.s2),
                        child: SmokeCard(
                          key: Key('cook-merge-${other.id}'),
                          onTap: () =>
                              unawaited(_merge(repo, cook, other)),
                          child: Row(
                            children: [
                              Icon(Icons.merge_rounded, color: t.textBody),
                              const SizedBox(width: SmokeTokens.s3),
                              Expanded(
                                child: Text(
                                  'Merge with “${other.displayName()}”',
                                  style: SmokeType.title.copyWith(
                                    color: t.textHi,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
      Navigator.of(context).maybePop();
    }
  }
}
