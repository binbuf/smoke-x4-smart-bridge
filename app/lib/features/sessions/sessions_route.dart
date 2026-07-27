/// Composition roots for the sessions list and detail (A11.2–A11.4), rebuilt
/// as the History branch (design 13 §13.3.2, §13.5.4).
///
/// Both read the **cache only** — no transport is touched, which is what makes
/// "scrolling an 18-hour cook on the couch with the bridge unplugged" literally
/// the acceptance test rather than a figure of speech.
///
/// **What changed, and why it mattered.** These were full `Scaffold`s with
/// their own `AppBar` and a back arrow wired to `context.go('/')`. Mounted as a
/// shell tab that produced a nested app bar and a back arrow pointing at the
/// screen you were already on; and opening a cook did `context.go('/sessions/:id')`,
/// a **root** navigation that unmounted `AppShell`, disposed the `ShellSession`
/// and killed the live link. Getting back cost three taps and landed on the
/// Cook tab, reconnecting from scratch. [embedded] drops the scaffold — the
/// shell owns the chrome — and the router now pushes the detail *inside* the
/// History branch, so the nav bar stays and back means back.
///
/// **Adaptive.** From 600 dp the list and the detail are one screen: tapping a
/// cook is a **selection**, not a navigation. That is the canonical list-detail
/// layout, and on this flow it is also the fix for the context loss above — on
/// a tablet or an unfolded Fold there is no navigation left to lose context in.
///
/// **Live.** The list watches drift (`watchSessions`, which had existed with
/// zero production callers) instead of loading once in `initState`. All four
/// branches stay mounted, so a one-shot load meant a cook that started while
/// the app was open never appeared until relaunch.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_env.dart';
import '../../app/router.dart';
import '../../data/repos/repositories.dart';
import '../../design/design.dart';
import '../../domain/entities/entities.dart';
import '../../ui/ui.dart';
import '../shell/shell_scope.dart';
import 'export.dart';
import 'sessions_screen.dart';

class SessionsRoute extends StatefulWidget {
  const SessionsRoute({super.key, this.embedded = false});

  /// True inside the shell: no scaffold, no app bar, no back arrow — the shell
  /// owns all three.
  final bool embedded;

  @override
  State<SessionsRoute> createState() => _SessionsRouteState();
}

class _SessionsRouteState extends State<SessionsRoute> {
  List<SessionListRow>? _rows;
  StreamSubscription<List<CookSession>>? _watch;
  SessionRepository? _repo;

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
    if (env == null) {
      setState(() => _rows = const []);
      return;
    }
    final bridgeId = await env.db.sessionDao.knownBridgeId();
    if (bridgeId == null) {
      setState(() => _rows = const []);
      return;
    }
    final repo = SessionRepository(env.db, bridgeId: bridgeId);
    _repo = repo;
    // Watch, don't poll: a cook that starts while the app is open must appear.
    _watch = repo.watchSessions().listen((sessions) {
      unawaited(_rebuild(repo, sessions));
    });
  }

  Future<void> _rebuild(
    SessionRepository repo,
    List<CookSession> sessions,
  ) async {
    final summaries = await repo.summaries();
    final rows = <SessionListRow>[];
    for (final s in sessions) {
      rows.add(
        SessionListRow(
          session: s,
          summary: summaries[s.id],
          sparkline: await repo.sparkline(s.id),
        ),
      );
    }
    if (mounted) {
      setState(() => _rows = rows);
    }
  }

  void _open(CookSession s) {
    final window = context.window;
    if (window.usesSplitPane) {
      setState(() => _selectedId = s.id);
      return;
    }
    // Compact: push **inside this branch**, so the nav bar stays and system
    // back returns to the list with its scroll intact (§13.3.4).
    context.push('${AppRoutes.history}/${s.id}');
  }

  @override
  Widget build(BuildContext context) {
    final window = context.window;
    final celsius = ShellScope.maybeOf(context)?.celsius ?? false;
    final rows = _rows;

    final list = rows == null
        ? const Center(child: CircularProgressIndicator())
        : SessionsListView(
            rows: rows,
            celsius: celsius,
            selectedId: window.usesSplitPane ? _selectedId : null,
            onOpen: _open,
          );

    // Keep a selection valid: a cook that vanished from the cache must not
    // leave the detail pane rendering a ghost.
    final selected = rows
        ?.where((r) => r.session.id == _selectedId)
        .firstOrNull
        ?.session;

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
                    : _DetailPane(
                        key: ValueKey(selected.id),
                        repo: _repo,
                        session: selected,
                        celsius: celsius,
                      ),
              ),
            ],
          );

    if (widget.embedded) {
      return SafeArea(top: false, child: body);
    }
    return Scaffold(
      appBar: AppBar(
        // The tab says History; this said "Cooks". One name.
        title: const Text('History'),
        leading: IconButton(
          key: const Key('sessions-back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.history),
        ),
      ),
      body: SafeArea(child: body),
    );
  }
}

/// The right-hand pane of the split view: the same detail content the pushed
/// route shows, loading its own samples for the selected cook.
class _DetailPane extends StatefulWidget {
  const _DetailPane({
    required this.repo,
    required this.session,
    required this.celsius,
    super.key,
  });

  final SessionRepository? repo;
  final CookSession session;
  final bool celsius;

  @override
  State<_DetailPane> createState() => _DetailPaneState();
}

class _DetailPaneState extends State<_DetailPane> {
  List<Sample> _samples = const [];
  List<Mark> _marks = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final repo = widget.repo;
    if (repo == null) {
      setState(() => _loaded = true);
      return;
    }
    final samples = await repo.samples(widget.session.id);
    final marks = await repo.marks(widget.session.id);
    if (mounted) {
      setState(() {
        _samples = samples;
        _marks = marks;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => !_loaded
      ? const Center(child: CircularProgressIndicator())
      : SessionDetailView(
          session: widget.session,
          samples: _samples,
          marks: _marks,
          probes: widget.session.probes,
          celsius: widget.celsius,
          onExport: () => unawaited(_export(context, widget.session, _samples)),
        );
}

class SessionDetailRoute extends StatefulWidget {
  const SessionDetailRoute({
    required this.sessionId,
    this.embedded = false,
    super.key,
  });

  final int sessionId;

  /// True when pushed inside the History branch: the shell keeps its nav bar,
  /// and back is a branch pop rather than a root navigation.
  final bool embedded;

  @override
  State<SessionDetailRoute> createState() => _SessionDetailRouteState();
}

class _SessionDetailRouteState extends State<SessionDetailRoute> {
  CookSession? _session;
  List<Sample> _samples = const [];
  List<Mark> _marks = const [];
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
      setState(() => _loaded = true);
      return;
    }
    final repo = SessionRepository(env.db, bridgeId: bridgeId);
    final all = await repo.sessions();
    final session = all.where((s) => s.id == widget.sessionId).firstOrNull;
    final samples = session == null
        ? const <Sample>[]
        : await repo.samples(session.id);
    final marks = session == null
        ? const <Mark>[]
        : await repo.marks(session.id);
    if (mounted) {
      setState(() {
        _session = session;
        _samples = samples;
        _marks = marks;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final celsius = ShellScope.maybeOf(context)?.celsius ?? false;
    final body = !_loaded
        ? const Center(child: CircularProgressIndicator())
        : session == null
        ? EmptyState(
            key: const Key('session-detail-missing'),
            icon: Icons.search_off_rounded,
            title: 'That cook isn’t here',
            message:
                'This phone has no copy of it. Cooks appear here once the app '
                'has seen them over Wi-Fi.',
            action: FilledButton.tonal(
              onPressed: () => context.go(AppRoutes.history),
              child: const Text('Back to history'),
            ),
          )
        : SessionDetailView(
            session: session,
            samples: _samples,
            marks: _marks,
            probes: session.probes,
            celsius: celsius,
            onExport: () => unawaited(_export(context, session, _samples)),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          session == null || session.name.isEmpty ? 'Cook' : session.name,
        ),
        // Inside the branch, back is a pop — go_router supplies the leading
        // button and it does the right thing, so the hand-rolled arrow that
        // used to `context.go` elsewhere is gone.
        leading: widget.embedded
            ? null
            : IconButton(
                key: const Key('session-detail-back'),
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go(AppRoutes.history),
              ),
      ),
      body: SafeArea(child: body),
    );
  }
}

/// Export, and say what happened in the user's terms.
///
/// The old version showed the raw path as the whole message — `Exported
/// /data/user/0/.../cook-27.csv` — which is an outcome only a developer can
/// act on. The headline is now what happened; the path is the supporting
/// line, because it is still the thing you need when a file does not turn up
/// where you expected.
///
/// A **Share** action belongs here and is deliberately absent: `ExportSink`
/// hands back a location, not a shareable handle, and wiring the platform
/// share sheet is a real piece of work (A17.4). A button that did nothing
/// would be worse than no button — that is this app's own rule.
Future<void> _export(
  BuildContext context,
  CookSession session,
  List<Sample> samples,
) async {
  final env = AppEnv.instance;
  if (env == null) {
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final where = await exportSessionCsv(
      session: session,
      samples: samples,
      sink: env.exportSink,
    );
    messenger?.showSnackBar(
      SnackBar(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Cook saved as CSV'),
            Text(where, style: const TextStyle(fontSize: 12)),
          ],
        ),
        showCloseIcon: true,
        duration: const Duration(seconds: 6),
      ),
    );
  } on Object {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Couldn’t save that cook.')),
    );
  }
}
