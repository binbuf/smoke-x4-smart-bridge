/// A24.8 — the connection sheet (design 05 §5.7).
///
/// The one place the app lets you *steer* the transport rather than only
/// observe it: which link you are on and its health, the fallback story in
/// plain words, a preferred-transport choice, the "keep Bluetooth as backup"
/// toggle, and the manual-address escape hatch. It hangs off the header chip's
/// tap — the affordance `SystemStatusBar` plumbed but never wired.
///
/// The widget is pure over a value model and callbacks, so it renders in a
/// widget test with no radio; [showConnectionSheet] binds it to the live
/// [ShellSession].
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/transport/bridge_transport.dart';
import '../dashboard/dashboard_snapshot.dart';
import '../settings/settings_screen.dart' show SettingsSection;
import 'shell_session.dart';

/// Presents the connection sheet bound to [session]. The sheet REBUILDS on
/// every session change while open, so a chosen switch (Bluetooth now,
/// Wi-Fi upgrade, a failover) is *seen completing* — the current-transport
/// row flips in place instead of the sheet showing stale state.
Future<void> showConnectionSheet(BuildContext context, ShellSession session) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => ListenableBuilder(
      listenable: session,
      builder: (_, _) {
        final live = session.liveLink;
        final snap = session.snapshot;
        return ConnectionSheet(
          link: snap?.link ?? live?.link ?? LinkKind.offline,
          netMode: snap?.netMode,
          degraded: live?.degraded ?? false,
          upgrading: live?.upgrading ?? false,
          address: snap?.address ?? live?.address ?? '',
          preferred: session.preferredTransport,
          holdBle: session.holdBleWhenOnWifi,
          onPreferredChanged: session.setPreferredTransport,
          onHoldBleChanged: session.setHoldBleWhenOnWifi,
          onReachDirectly: () {
            Navigator.of(sheetContext).pop();
            context.go('${AppRoutes.bridge}/${SettingsSection.network.slug}');
          },
        );
      },
    ),
  );
}

class ConnectionSheet extends StatefulWidget {
  const ConnectionSheet({
    required this.link,
    required this.preferred,
    required this.holdBle,
    required this.onPreferredChanged,
    required this.onHoldBleChanged,
    this.netMode,
    this.degraded = false,
    this.upgrading = false,
    this.address = '',
    this.onReachDirectly,
    super.key,
  });

  final LinkKind link;
  final String? netMode;
  final bool degraded;
  final bool upgrading;
  final String address;
  final PreferredTransport preferred;
  final bool holdBle;
  final ValueChanged<PreferredTransport> onPreferredChanged;
  final ValueChanged<bool> onHoldBleChanged;
  final VoidCallback? onReachDirectly;

  @override
  State<ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<ConnectionSheet> {
  late PreferredTransport _preferred = widget.preferred;
  late bool _holdBle = widget.holdBle;

  String get _statusLabel => switch (widget.link) {
    LinkKind.http => widget.netMode == 'ap' ? 'Wi-Fi (hosted)' : 'Wi-Fi',
    LinkKind.ble => 'Bluetooth',
    LinkKind.offline => 'Offline',
  };

  IconData get _statusIcon => switch (widget.link) {
    LinkKind.http => Icons.wifi_rounded,
    LinkKind.ble => Icons.bluetooth_rounded,
    LinkKind.offline => Icons.cloud_off_rounded,
  };

  /// The fallback story, in the user's terms — what this link gives, and what
  /// the other one is doing for them right now.
  String get _story => switch (widget.link) {
    LinkKind.ble =>
      'Live temperatures work anywhere, no network needed. Connect to '
          'Wi-Fi for full cook history and settings.',
    LinkKind.http =>
      widget.upgrading
          ? 'Reconnecting to Wi-Fi…'
          : 'Full history and settings over Wi-Fi. '
                '${_holdBle ? "Bluetooth is held as backup, so a dropped "
                          "network won’t stop your cook." : "Bluetooth backup is "
                          "off — turn it on for instant fallback if Wi-Fi drops."}',
    LinkKind.offline =>
      'Saved cooks are still here. The app reconnects on its own when the '
          'bridge is back.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          key: const Key('connection-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connection', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(_statusIcon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.upgrading && widget.link == LinkKind.ble
                            ? '$_statusLabel · reconnecting to Wi-Fi'
                            : _statusLabel,
                        key: const Key('connection-current'),
                        style: theme.textTheme.titleMedium,
                      ),
                      if (widget.address.isNotEmpty)
                        Text(
                          widget.address,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _story,
              key: const Key('connection-story'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 32),
            Text('Prefer', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<PreferredTransport>(
              key: const Key('connection-preferred'),
              segments: const [
                ButtonSegment(
                  value: PreferredTransport.auto,
                  label: Text('Auto'),
                  icon: Icon(Icons.auto_mode_rounded),
                ),
                ButtonSegment(
                  value: PreferredTransport.wifi,
                  label: Text('Wi-Fi'),
                  icon: Icon(Icons.wifi_rounded),
                ),
                ButtonSegment(
                  value: PreferredTransport.ble,
                  label: Text('Bluetooth'),
                  icon: Icon(Icons.bluetooth_rounded),
                ),
              ],
              selected: {_preferred},
              onSelectionChanged: (sel) {
                final t = sel.first;
                setState(() => _preferred = t);
                widget.onPreferredChanged(t);
              },
            ),
            const SizedBox(height: 4),
            Text(
              switch (_preferred) {
                PreferredTransport.auto =>
                  'Shows data the instant you open the app, then uses Wi-Fi '
                      'when it’s available.',
                PreferredTransport.wifi =>
                  'Leads with Wi-Fi for full history; falls back to Bluetooth '
                      'when there’s no network.',
                PreferredTransport.ble =>
                  'Switches to Bluetooth now and stays there — for weak or '
                      'changing Wi-Fi. Full history needs a Wi-Fi connection.',
              },
              key: const Key('connection-preferred-hint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SwitchListTile(
              key: const Key('connection-hold-ble'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Keep Bluetooth as backup'),
              subtitle: const Text(
                'Holds the Bluetooth link while on Wi-Fi so a dropped network '
                'fails over instantly. Costs the bridge a little battery.',
              ),
              value: _holdBle,
              onChanged: (v) {
                setState(() => _holdBle = v);
                widget.onHoldBleChanged(v);
              },
            ),
            const Divider(height: 24),
            // One label used to hide two unrelated destinations, and the
            // visible one was the less important: "Reach it directly by
            // address" sounded like a manual-IP field and actually opened the
            // entire settings tree — which was the *only* way in, so probes,
            // units and alarm rules had no discoverable entry point at all.
            // Settings now lives on the Bridge tab; this says where it went.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('connection-reach-directly'),
                onPressed: widget.onReachDirectly,
                icon: const Icon(Icons.settings_ethernet_rounded),
                label: const Text('Network settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
