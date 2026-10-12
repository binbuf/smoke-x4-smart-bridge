/// History: every session the phone has seen, newest first.
///
/// Cache-only and upsert-only, so a session the bridge has since purged still
/// appears here — the phone owns a full copy of everything it has seen.
library;

import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/bridge_scope.dart';
import '../../design/format.dart';
import '../../design/primitives.dart';
import '../../design/tokens.dart';
import '../../domain/domain.dart';
import '../common/bridge_app_bar.dart';
import '../common/connection.dart';
import 'session_detail_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = BridgeScope.of(context);
    final sessions = controller.sessions;

    return Scaffold(
      appBar: const BridgeAppBar(title: 'History'),
      body: sessions.isEmpty
          ? _HistoryEmpty(controller: controller)
          : RefreshIndicator(
              onRefresh: controller.refresh,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(SmokeSpace.lg),
                itemCount: sessions.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: SmokeSpace.sm),
                itemBuilder: (context, i) => _SessionTile(session: sessions[i]),
              ),
            ),
    );
  }
}

/// The honest empty state: it never dead-ends. Disconnected offers the one
/// action that changes anything; connected just points at the sync control.
class _HistoryEmpty extends StatelessWidget {
  const _HistoryEmpty({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.connected) {
      return const ConnectionEmpty(
        title: 'No sessions yet',
        message:
            'Your bridge records continuously, whether or not you are '
            'cooking. Connect from the status chip above to pull its history '
            'onto this phone.',
      );
    }
    if (controller.identity?.historyFull == false) {
      return const EmptyState(
        icon: Icons.system_update_alt,
        title: 'This bridge serves live only',
        message:
            'Its firmware predates full-history-over-Bluetooth, so history '
            'stays on the bridge for now. Live readings still work.',
      );
    }
    return const EmptyState(
      icon: Icons.history,
      title: 'No sessions yet',
      message:
          'Your bridge records continuously, whether or not you are cooking. '
          'Sync to pull its history onto this phone.',
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final SessionInfo session;

  @override
  Widget build(BuildContext context) {
    final name = session.name.isEmpty ? 'Session #${session.id}' : session.name;
    final duration = session.closed ? session.deviceMaxT : null;
    final subtitle = [
      formatClock(session.startedUnixMs),
      if (duration != null) formatDuration(duration),
      '${session.sampleCount} readings',
    ].join(' · ');

    return Material(
      color: SmokePalette.card,
      borderRadius: BorderRadius.circular(SmokeRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(SmokeRadius.card),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SessionDetailScreen(session: session),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(SmokeSpace.lg),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SmokePalette.textHi,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (!session.closed) ...[
                          const SizedBox(width: SmokeSpace.sm),
                          const StatusChip(
                            icon: Icons.fiber_manual_record,
                            label: 'Recording',
                            color: SmokePalette.warning,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: SmokeSpace.xs),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: SmokePalette.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: SmokePalette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
