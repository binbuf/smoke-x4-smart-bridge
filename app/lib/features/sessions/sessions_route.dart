/// Composition roots for the sessions list and detail (A11.2–A11.4).
///
/// Both read the **cache only** — no transport is touched, which is what
/// makes "scrolling an 18-hour cook on the couch with the bridge
/// unplugged" literally the acceptance test rather than a figure of
/// speech.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_env.dart';
import '../../app/router.dart';
import '../../data/repos/repositories.dart';
import '../../domain/entities/entities.dart';
import 'export.dart';
import 'sessions_screen.dart';

class SessionsRoute extends StatefulWidget {
  const SessionsRoute({super.key});

  @override
  State<SessionsRoute> createState() => _SessionsRouteState();
}

class _SessionsRouteState extends State<SessionsRoute> {
  List<SessionListRow>? _rows;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
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
    final sessions = await repo.sessions();
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Cooks'),
      leading: IconButton(
        key: const Key('sessions-back'),
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go(AppRoutes.home),
      ),
    ),
    body: SafeArea(
      child: _rows == null
          ? const Center(child: CircularProgressIndicator())
          : SessionsListView(
              rows: _rows!,
              onOpen: (s) => context.go('${AppRoutes.sessions}/${s.id}'),
            ),
    ),
  );
}

class SessionDetailRoute extends StatefulWidget {
  const SessionDetailRoute({required this.sessionId, super.key});

  final int sessionId;

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cook'),
        leading: IconButton(
          key: const Key('session-detail-back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.sessions),
        ),
      ),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : session == null
            ? const Center(
                key: Key('session-detail-missing'),
                child: Text('That cook is not in this phone\'s history.'),
              )
            : SessionDetailView(
                session: session,
                samples: _samples,
                marks: _marks,
                probes: session.probes,
                onExport: () => unawaited(_export(session)),
              ),
      ),
    );
  }

  Future<void> _export(CookSession session) async {
    final env = AppEnv.instance;
    if (env == null) {
      return;
    }
    final where = await exportSessionCsv(
      session: session,
      samples: _samples,
      sink: env.exportSink,
    );
    if (mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Exported $where')));
    }
  }
}
