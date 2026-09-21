/// N10.2/N10.3/N10.4/N10.6 — the connect sheet.
///
/// The dual-link model made tangible: two independent rows (Bluetooth and
/// Wi-Fi) with their own health, signal and last sync; a device head with the
/// battery and the recording line; the mode switch with its Bluetooth
/// explainer; and the error/rollback notice with its recovery pair.
///
/// Invariants encoded here:
/// * **I9** — the row that carries data says so; Bluetooth stays visible while
///   Wi-Fi leads, because it is held warm.
/// * **I13** — the rollback explainer states the capability trade in words.
/// * **I14** — exactly one ember [PrimaryAction] (Re-sync now).
/// * **N10.10** — a failed switch never strands the user: the notice always
///   offers Try again and Use hotspot, and Bluetooth remains the escape hatch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/model/connection_state.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import '../shell/shell.dart';
import 'connection_format.dart';
import 'mode_cards.dart';

/// The body behind `?overlay=connect`.
class ConnectSheetBody extends ConsumerWidget {
  const ConnectSheetBody({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final snapshot = ref.watch(snapshotProvider).value;
    if (snapshot == null) {
      return const SizedBox.shrink();
    }
    final connection = snapshot.connection;
    final modes = ref.watch(bridgeRepositoryProvider).connectionModes;
    final activeId = activeModeId(connection);
    final scope = ShellScope.maybeOf(context);

    final pulse = switch (connection.phase) {
      ConnectionPhase.offline => PulseState.idle,
      ConnectionPhase.connected => PulseState.live,
      _ => PulseState.warn,
    };

    return Column(
      key: const ValueKey<String>('connection-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SmokeCard(
          key: const ValueKey<String>('connection-device'),
          child: Row(
            children: <Widget>[
              SmokeIcon(
                connection.phase == ConnectionPhase.offline
                    ? SmokeGlyph.unlink
                    : SmokeGlyph.link,
                color: tokens.textBody,
              ),
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
        ),
        const SizedBox(height: 4),
        LinkRow(
          key: const ValueKey<String>('connection-link-bt'),
          icon: SmokeGlyph.bluetooth,
          name: 'Bluetooth',
          sub: bluetoothSubtitle(connection.bt),
          off: !connection.bt.connected,
          right: _LinkRight(
            data:
                connection.primary == LinkPrimary.bt && connection.bt.connected,
            bars: connection.bt.bars ?? 0,
            dataKey: 'connection-link-bt-data',
          ),
        ),
        LinkRow(
          key: const ValueKey<String>('connection-link-wifi'),
          icon: connection.wifi.mode == WifiMode.ap
              ? SmokeGlyph.wifi
              : SmokeGlyph.router,
          name: 'Wi-Fi',
          sub: wifiSubtitle(connection),
          off: !connection.wifi.connected,
          right: _LinkRight(
            data:
                connection.primary == LinkPrimary.wifi &&
                connection.wifi.connected,
            bars: connection.wifi.bars ?? 0,
            dataKey: 'connection-link-wifi-data',
          ),
        ),
        const SizedBox(height: 8),
        _FactRow(
          key: const ValueKey<String>('connection-battery'),
          label: 'Battery',
          value: connection.batteryPct == null
              ? '—'
              : '${connection.batteryPct}%',
        ),
        const SizedBox(height: 6),
        _FactRow(
          key: const ValueKey<String>('connection-recording'),
          label: 'Recording',
          value: connection.recording ? 'Yes — on the bridge' : 'No',
        ),
        if (connectionHasProblem(connection)) ...<Widget>[
          const SizedBox(height: 12),
          InsightBanner(
            key: const ValueKey<String>('connection-error'),
            message: connectionErrorCopy(connection, notice: snapshot.notice),
            severity: connectionProblemIsWarning(connection)
                ? BannerSeverity.warn
                : BannerSeverity.critical,
            icon: SmokeGlyph.alertTriangle,
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: SmokeButton(
                  key: const ValueKey<String>('connection-try-again'),
                  label: 'Try again',
                  icon: SmokeGlyph.refresh,
                  onPressed: () => scope?.openOverlay(DevOverlay.provisionSta),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SmokeButton(
                  key: const ValueKey<String>('connection-use-hotspot'),
                  label: 'Use hotspot',
                  icon: SmokeGlyph.wifi,
                  variant: SmokeButtonVariant.ghost,
                  onPressed: () => scope?.openOverlay(DevOverlay.provisionAp),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        Text(
          'SWITCH MODE — ALWAYS AVAILABLE OVER BLUETOOTH',
          key: const ValueKey<String>('connection-switch-label'),
          style: SmokeText.labelSm.copyWith(
            letterSpacing: 0.9,
            color: tokens.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        for (final mode in modes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ConnectionModeCard(
              key: ValueKey<String>('connection-mode-${mode.id}'),
              mode: mode,
              active: mode.id == activeId,
              onTap: () => _selectMode(ref, scope, mode.id),
              onInfo: () =>
                  scope?.openOverlay(DevOverlay.modesRef, {'mode': mode.id}),
            ),
          ),
        const CapabilityNotice(
          key: ValueKey<String>('connection-rollback-notice'),
          message:
              'Switching to Wi-Fi happens over Bluetooth, so it works even '
              'when the bridge is not on a network. If the new mode fails, the '
              'bridge keeps its old network and Bluetooth stays as your escape '
              'hatch.',
        ),
        const SizedBox(height: 16),
        PrimaryAction(
          key: const ValueKey<String>('connection-resync'),
          label: 'Re-sync now',
          icon: SmokeGlyph.refresh,
          onPressed: () => _resync(ref, scope),
        ),
        const SizedBox(height: 8),
        SmokeButton(
          key: const ValueKey<String>('connection-disconnect'),
          label: 'Disconnect',
          icon: SmokeGlyph.unlink,
          variant: SmokeButtonVariant.ghost,
          onPressed: () => _disconnect(ref, scope),
        ),
      ],
    );
  }

  Future<void> _selectMode(WidgetRef ref, ShellScope? scope, String id) async {
    if (id == 'ble') {
      await ref.read(bridgeRepositoryProvider).applyMode('ble');
      scope?.showToast('Switched to Bluetooth');
      onDone();
      return;
    }
    scope?.openOverlay(
      id == 'ap' ? DevOverlay.provisionAp : DevOverlay.provisionSta,
    );
  }

  Future<void> _resync(WidgetRef ref, ShellScope? scope) async {
    await ref.read(bridgeRepositoryProvider).resync();
    scope?.showToast('Re-synced · up to date');
  }

  Future<void> _disconnect(WidgetRef ref, ShellScope? scope) async {
    await ref.read(bridgeRepositoryProvider).disconnect();
    scope?.showToast('Disconnected — the bridge keeps recording');
    onDone();
  }
}

class _LinkRight extends StatelessWidget {
  const _LinkRight({
    required this.data,
    required this.bars,
    required this.dataKey,
  });

  final bool data;
  final int bars;
  final String dataKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (data) ...<Widget>[
          ModeBadge(key: ValueKey<String>(dataKey), label: 'Data'),
          const SizedBox(width: 8),
        ],
        SignalBars(bars: bars),
      ],
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
