/// The graph: one session's stored readings, every probe overlaid.
///
/// Cache-only. It never dials the bridge itself — the connection card on the
/// Live tab and the background sync keep the cache current.
library;

import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/bridge_scope.dart';
import '../../design/format.dart';
import '../../design/primitives.dart';
import '../../design/tokens.dart';
import '../../domain/domain.dart';
import '../common/connection.dart';
import '../common/session_picker.dart';
import 'temp_chart.dart';

class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  int? _sessionId;
  int? _loadedVersion;
  int? _loadedFor;
  Future<List<Sample>>? _future;

  Future<List<Sample>> _ensure(BridgeController c) {
    final sessions = c.sessions;
    if (_sessionId == null && sessions.isNotEmpty) {
      _sessionId = sessions.first.id;
    }
    final sid = _sessionId;
    if (sid == null) {
      _future = null;
      return Future.value(const <Sample>[]);
    }
    if (_future == null ||
        _loadedVersion != c.dataVersion ||
        _loadedFor != sid) {
      _loadedVersion = c.dataVersion;
      _loadedFor = sid;
      _future = c.samplesFor(sid);
    }
    return _future!;
  }

  @override
  Widget build(BuildContext context) {
    final controller = BridgeScope.of(context);
    final sessions = controller.sessions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Graph'),
        actions: [
          const ConnectionChip(),
          const SizedBox(width: SmokeSpace.sm),
          IconButton(
            tooltip: controller.syncing
                ? 'Syncing…'
                : (controller.syncError ?? 'Sync now'),
            onPressed: controller.connected ? controller.syncNow : null,
            icon: controller.syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Icon(
                    controller.syncError == null
                        ? Icons.sync
                        : Icons.sync_problem,
                    color: controller.syncError == null
                        ? null
                        : SmokePalette.warning,
                  ),
          ),
          const SizedBox(width: SmokeSpace.sm),
        ],
      ),
      body: sessions.isEmpty
          ? _NoSessions(controller: controller)
          : RefreshIndicator(
              onRefresh: controller.refresh,
              child: FutureBuilder<List<Sample>>(
                future: _ensure(controller),
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(SmokeSpace.lg),
                    children: [
                      SessionPicker(
                        sessions: sessions,
                        selected: _sessionId ?? sessions.first.id,
                        onChanged: (id) => setState(() => _sessionId = id),
                      ),
                      const SizedBox(height: SmokeSpace.lg),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: SmokeSpace.xxl,
                          ),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (data == null || data.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: SmokeSpace.xxl,
                          ),
                          child: Text(
                            'No readings cached for this session yet. '
                            'Pull to sync.',
                            style: TextStyle(
                              color: SmokePalette.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        )
                      else ...[
                        TempChart(samples: data, unit: controller.unit),
                        const SizedBox(height: SmokeSpace.lg),
                        _SessionMeta(
                          samples: data,
                          session: _sessionFor(sessions, _sessionId),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
    );
  }
}

SessionInfo? _sessionFor(List<SessionInfo> sessions, int? id) {
  for (final s in sessions) {
    if (s.id == id) {
      return s;
    }
  }
  return null;
}

class _SessionMeta extends StatelessWidget {
  const _SessionMeta({required this.samples, required this.session});

  final List<Sample> samples;
  final SessionInfo? session;

  @override
  Widget build(BuildContext context) {
    final first = samples.first.t;
    final last = samples.last.t;
    final duration = last - first;
    final probes = <int>{};
    for (final s in samples) {
      for (var j = 0; j < s.tempsF10.length; j++) {
        if (s.tempsF10[j] != null) {
          probes.add(j + 1);
        }
      }
    }
    return SmokeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (session != null)
            Text(
              'Session #${session!.id} · ${session!.name.isEmpty ? 'Unnamed' : session!.name}',
              style: const TextStyle(
                color: SmokePalette.textHi,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: SmokeSpace.md),
          _MetaRow(label: 'Span', value: formatDuration(duration)),
          _MetaRow(label: 'Readings', value: '${samples.length}'),
          _MetaRow(
            label: 'Probes seen',
            value: probes.isEmpty ? '—' : (probes.toList()..sort()).join(', '),
          ),
          _MetaRow(
            label: 'Started',
            value: formatClock(session?.startedUnixMs),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SmokeSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: SmokePalette.textMuted,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: SmokePalette.textHi,
              fontFamily: 'JetBrainsMono',
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoSessions extends StatelessWidget {
  const _NoSessions({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.connected) {
      return const ConnectionEmpty(
        title: 'No sessions cached',
        message:
            'Your bridge records continuously. Connect from the status chip '
            'above to pull its history onto this phone.',
      );
    }
    if (controller.identity?.historyFull == false) {
      return const EmptyState(
        icon: Icons.system_update_alt,
        title: 'This bridge serves live only',
        message:
            'Its firmware predates full-history-over-Bluetooth, so graphs and '
            'history stay on the bridge for now. Live readings still work.',
      );
    }
    return const EmptyState(
      icon: Icons.show_chart,
      title: 'No sessions yet',
      message:
          'Your bridge records continuously. Sync to pull its history '
          'onto this phone.',
    );
  }
}
