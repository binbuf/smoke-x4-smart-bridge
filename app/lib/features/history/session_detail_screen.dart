/// One session in full: the chart, the honest statistics, and any recording
/// holes named by cause.
///
/// A gap is never drawn or described as one undifferentiated thing: a
/// connectivity hole is recoverable ("not synced yet") while a buffer rollover
/// is permanent ("gone for good"). Presenting them alike would tell someone to
/// wait for data that is never coming.
library;

import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/bridge_scope.dart';
import '../../design/format.dart';
import '../../design/primitives.dart';
import '../../design/tokens.dart';
import '../../domain/domain.dart';
import '../graph/temp_chart.dart';

typedef _Detail = ({List<Sample> samples, List<RecordedGap> gaps});

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({super.key, required this.session});

  final SessionInfo session;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  Future<_Detail>? _future;
  int? _version;

  void _ensure(BridgeController c, int dataVersion) {
    if (_future == null || _version != dataVersion) {
      _version = dataVersion;
      _future = _load(c);
    }
  }

  Future<_Detail> _load(BridgeController c) async {
    final samples = await c.samplesFor(widget.session.id);
    final gaps = await c.gapsFor(widget.session.id);
    return (samples: samples, gaps: gaps);
  }

  @override
  Widget build(BuildContext context) {
    final controller = BridgeScope.of(context);
    _ensure(controller, controller.dataVersion);
    final name = widget.session.name.isEmpty
        ? 'Session #${widget.session.id}'
        : widget.session.name;

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: FutureBuilder<_Detail>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (data.samples.isEmpty) {
              return const EmptyState(
                icon: Icons.show_chart,
                title: 'No readings cached',
                message:
                    'This session has not been synced to this phone yet. '
                    'Connect and pull to sync.',
              );
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(SmokeSpace.lg),
              children: [
                TempChart(samples: data.samples, unit: controller.unit),
                const SizedBox(height: SmokeSpace.lg),
                _Stats(samples: data.samples, session: widget.session),
                const SizedBox(height: SmokeSpace.lg),
                _Gaps(gaps: data.gaps),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.samples, required this.session});

  final List<Sample> samples;
  final SessionInfo session;

  @override
  Widget build(BuildContext context) {
    final span = samples.last.t - samples.first.t;
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
          const Text(
            'Statistics',
            style: TextStyle(
              color: SmokePalette.textHi,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SmokeSpace.md),
          _Row(label: 'Span', value: formatDuration(span)),
          _Row(label: 'Readings', value: '${samples.length}'),
          _Row(
            label: 'Probes seen',
            value: probes.isEmpty ? '—' : (probes.toList()..sort()).join(', '),
          ),
          _Row(label: 'Started', value: formatClock(session.startedUnixMs)),
          _Row(
            label: 'Ended',
            value: session.closed
                ? formatClock(session.endedUnixMs)
                : 'Still recording',
          ),
        ],
      ),
    );
  }
}

class _Gaps extends StatelessWidget {
  const _Gaps({required this.gaps});

  final List<RecordedGap> gaps;

  @override
  Widget build(BuildContext context) {
    if (gaps.isEmpty) {
      return const SizedBox.shrink();
    }
    return SmokeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Gaps in recording',
            style: TextStyle(
              color: SmokePalette.textHi,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SmokeSpace.sm),
          for (final g in gaps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SmokeSpace.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${formatDuration(g.fromT)} → ${formatDuration(g.toT)} '
                    '(${formatDuration(g.durationS)} missing)',
                    style: const TextStyle(
                      color: SmokePalette.textBody,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '${g.reason.label} — ${g.reason.explanation}',
                    style: TextStyle(
                      color: g.reason.isPermanent
                          ? SmokePalette.critical
                          : SmokePalette.textMuted,
                      fontSize: 12,
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

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SmokeSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
