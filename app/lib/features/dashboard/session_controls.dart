/// A9.4 — the session controls (design 08 §8.6, 06 §6.2).
///
/// Stop cook · Add mark · Export. Each dispatches a [ControlCommand]
/// through the transport and **nothing else**: no local optimistic session
/// state, no second copy of "is a cook running". The device is the source
/// of truth (09 §9.1), and a session the app thinks is running while the
/// bridge disagrees is precisely the class of bug that discipline exists
/// to prevent.
///
/// Stopping asks first. Fourteen hours is a long time to lose to a
/// mis-tap in the dark.
library;

import 'package:flutter/material.dart';

import '../../data/transport/ble_transport.dart';
import '../../data/transport/bridge_transport.dart';
import '../../domain/entities/entities.dart';
import 'dashboard_snapshot.dart';

class SessionControls extends StatelessWidget {
  const SessionControls({
    required this.snapshot,
    required this.onControl,
    this.onExport,
    this.enabled = true,
    this.disabledReason = '',
    super.key,
  });

  final DashboardSnapshot snapshot;
  final Future<void> Function(ControlCommand) onControl;
  final VoidCallback? onExport;

  /// False when the transport cannot control. The buttons then say why
  /// rather than failing on tap.
  final bool enabled;
  final String disabledReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('session-controls'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!enabled && disabledReason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              disabledReason,
              key: const Key('session-controls-disabled'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: snapshot.sessionActive
                  ? OutlinedButton.icon(
                      key: const Key('control-stop'),
                      onPressed: enabled ? () => _confirmStop(context) : null,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Stop cook'),
                    )
                  : FilledButton.icon(
                      key: const Key('control-start'),
                      onPressed: enabled
                          ? () => _run(
                              context,
                              const ControlCommand.sessionStart(),
                            )
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start cook'),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('control-mark'),
                onPressed: enabled && snapshot.sessionActive
                    ? () => _addMark(context)
                    : null,
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Add mark'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('control-export'),
                onPressed: onExport,
                icon: const Icon(Icons.ios_share),
                label: const Text('Export'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmStop(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('control-stop-confirm'),
        title: const Text('Stop this cook?'),
        content: const Text(
          'The bridge stops recording. The cook stays in your history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep cooking'),
          ),
          FilledButton(
            key: const Key('control-stop-confirm-yes'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Stop cook'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _run(context, const ControlCommand.sessionStop());
    }
  }

  Future<void> _addMark(BuildContext context) async {
    final kind = await showModalBottomSheet<MarkKind>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          key: const Key('control-mark-sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final k in _userMarkKinds)
              ListTile(
                key: Key('mark-kind-${k.name}'),
                title: Text(_markLabel(k)),
                onTap: () => Navigator.of(ctx).pop(k),
              ),
          ],
        ),
      ),
    );
    if (kind != null && context.mounted) {
      await _run(
        context,
        ControlCommand.mark(kind: kind, text: _markLabel(kind)),
      );
    }
  }

  Future<void> _run(BuildContext context, ControlCommand cmd) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await onControl(cmd);
    } on BridgeControlException catch (e) {
      // Typed meaning, never a stack trace and never a magic number.
      messenger?.showSnackBar(
        SnackBar(content: Text('The bridge refused: ${e.status.name}')),
      );
    } on BridgeUnsupportedException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('$e')));
    } on Object {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not reach the bridge')),
      );
    }
  }
}

/// The kinds a human places. `alarm` and `autoDetected` are the
/// firmware's to write (09 §9.2, §9.4) and are deliberately absent.
const List<MarkKind> _userMarkKinds = [
  MarkKind.note,
  MarkKind.wrapped,
  MarkKind.lidOpen,
  MarkKind.fuel,
  MarkKind.probeMoved,
  MarkKind.phaseChange,
];

String _markLabel(MarkKind k) => switch (k) {
  MarkKind.note => 'Note',
  MarkKind.wrapped => 'Wrapped',
  MarkKind.lidOpen => 'Lid open',
  MarkKind.fuel => 'Added fuel',
  MarkKind.probeMoved => 'Moved a probe',
  MarkKind.alarm => 'Alarm',
  MarkKind.phaseChange => 'Phase change',
  MarkKind.autoDetected => 'Auto-detected',
};

/// Shared with the sessions detail timeline (A11.3), so a mark reads the
/// same wherever it appears.
String markLabel(MarkKind k) => _markLabel(k);
