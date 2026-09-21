/// N10.12–N10.15 — the Settings "Bridge" card.
///
/// The settings-side face of the same dual-link model the connect sheet uses:
/// two independent rows, the battery, the recording line, and the three verbs
/// (Re-sync, Change mode, Disconnect). It also carries the two-hop discipline
/// (N10.13): the Bluetooth row names the phone→bridge hop and the Wi-Fi row
/// names the bridge→router hop, so the two signals are never read as one.
///
/// **I13/N10.15** — when the active transport cannot do full history, the card
/// says so in words ("Full history needs Wi-Fi") instead of offering a dead
/// control. "Forget network" appears only when a home network is actually
/// joined (N10.9).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/model/connection_state.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import '../shell/shell.dart';
import 'connection_format.dart';

/// The bridge/device card for the Settings tree.
class BridgeCard extends ConsumerWidget {
  const BridgeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final snapshot = ref.watch(snapshotProvider).value;
    if (snapshot == null) {
      return const SizedBox.shrink();
    }
    final connection = snapshot.connection;
    final modes = ref.watch(bridgeRepositoryProvider).connectionModes;
    final scope = ShellScope.maybeOf(context);
    final fullHistoryNotice = fullHistoryRefusal(connection, modes);
    final joinedHomeWifi =
        connection.wifi.mode == WifiMode.sta && connection.wifi.connected;

    final pulse = switch (connection.phase) {
      ConnectionPhase.offline => PulseState.idle,
      ConnectionPhase.connected => PulseState.live,
      _ => PulseState.warn,
    };

    return SmokeCard(
      key: const ValueKey<String>('bridge-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              SmokeIcon(SmokeGlyph.link, color: tokens.textBody),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  connection.deviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SmokeText.bodyStrong.copyWith(
                    fontSize: 14,
                    color: tokens.textHi,
                  ),
                ),
              ),
              PulseDot(state: pulse),
            ],
          ),
          const SizedBox(height: 4),
          LinkRow(
            key: const ValueKey<String>('bridge-bt'),
            icon: SmokeGlyph.bluetooth,
            name: 'Bluetooth',
            sub: bridgeBluetoothSubtitle(connection.bt),
            off: !connection.bt.connected,
            right: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (connection.primary == LinkPrimary.bt &&
                    connection.bt.connected) ...<Widget>[
                  const ModeBadge(
                    key: ValueKey<String>('bridge-bt-data'),
                    label: 'Data',
                  ),
                  const SizedBox(width: 8),
                ] else if (connection.bt.warm) ...<Widget>[
                  const ModeBadge(
                    key: ValueKey<String>('bridge-bt-warm'),
                    label: 'Warm',
                  ),
                  const SizedBox(width: 8),
                ],
                SignalBars(bars: connection.bt.bars ?? 0),
              ],
            ),
          ),
          LinkRow(
            key: const ValueKey<String>('bridge-wifi'),
            icon: connection.wifi.mode == WifiMode.ap
                ? SmokeGlyph.wifi
                : SmokeGlyph.router,
            name: 'Wi-Fi',
            sub: bridgeWifiSubtitle(connection),
            off: !connection.wifi.connected,
            right: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (connection.primary == LinkPrimary.wifi &&
                    connection.wifi.connected) ...<Widget>[
                  const ModeBadge(
                    key: ValueKey<String>('bridge-wifi-data'),
                    label: 'Data',
                  ),
                  const SizedBox(width: 8),
                ],
                SignalBars(bars: connection.wifi.bars ?? 0),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _FactRow(
            key: const ValueKey<String>('bridge-battery'),
            label: 'Battery',
            value: connection.batteryPct == null
                ? '—'
                : '${connection.batteryPct}%',
          ),
          const SizedBox(height: 6),
          _FactRow(
            key: const ValueKey<String>('bridge-recording'),
            label: 'Recording',
            value: connection.recording ? 'Yes — on the bridge' : 'No',
          ),
          if (fullHistoryNotice != null) ...<Widget>[
            const SizedBox(height: 12),
            CapabilityNotice(
              key: const ValueKey<String>('bridge-capability'),
              message:
                  '$fullHistoryNotice Join your network or the bridge '
                  'hotspot to download past cooks.',
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: SmokeButton(
                  key: const ValueKey<String>('bridge-resync'),
                  label: 'Re-sync',
                  icon: SmokeGlyph.refresh,
                  size: SmokeButtonSize.sm,
                  onPressed: () async {
                    await ref.read(bridgeRepositoryProvider).resync();
                    scope?.showToast('Re-synced · up to date');
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SmokeButton(
                  key: const ValueKey<String>('bridge-change-mode'),
                  label: 'Change mode',
                  icon: SmokeGlyph.sliders,
                  variant: SmokeButtonVariant.ghost,
                  size: SmokeButtonSize.sm,
                  onPressed: () => scope?.openOverlay(DevOverlay.modes),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SmokeButton(
            key: const ValueKey<String>('bridge-disconnect'),
            label: 'Disconnect',
            icon: SmokeGlyph.unlink,
            variant: SmokeButtonVariant.ghost,
            size: SmokeButtonSize.sm,
            onPressed: () async {
              await ref.read(bridgeRepositoryProvider).disconnect();
              scope?.showToast('Disconnected — the bridge keeps recording');
            },
          ),
          if (joinedHomeWifi) ...<Widget>[
            const SizedBox(height: 4),
            SettingsRow(
              key: const ValueKey<String>('bridge-forget-network'),
              icon: SmokeGlyph.unlink,
              name: 'Forget network',
              sub: connection.wifi.ssid ?? 'Home Wi-Fi',
              onTap: () async {
                await ref.read(bridgeRepositoryProvider).forgetNetwork();
                scope?.showToast('Network forgotten');
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: SmokeText.labelSm.copyWith(
              fontSize: 12,
              color: tokens.textMuted,
            ),
          ),
        ),
        Text(
          value,
          style: SmokeText.bodyStrong.copyWith(
            fontSize: 12.5,
            color: tokens.textHi,
          ),
        ),
      ],
    );
  }
}
