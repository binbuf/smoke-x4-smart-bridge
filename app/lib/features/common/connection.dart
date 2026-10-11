/// The single place the app manages its link: a compact status chip that lives
/// in every screen's app bar, and a connection sheet it opens.
///
/// Connection state is deliberately *not* embedded in any tab body. One chip,
/// present everywhere, driven by the one [BridgeController.link]; tapping it
/// opens the one sheet. A tab whose content genuinely needs the bridge (Live)
/// or whose cache is empty still states its own honest empty state, but the
/// affordance itself is never duplicated three times over.
library;

import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/bridge_scope.dart';
import '../../data/ble/bridge_transport.dart';
import '../../design/primitives.dart';
import '../../design/tokens.dart';
import '../../platform/system_settings.dart';

/// The app-bar link indicator. Always visible, always the same shape, whatever
/// the tab. Tapping it opens [ConnectionSheet].
class ConnectionChip extends StatelessWidget {
  const ConnectionChip({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = BridgeScope.of(context);
    final chrome = switch (controller.link) {
      BridgeLink.disconnected => (
        icon: Icons.bluetooth_disabled,
        label: 'Offline',
        color: SmokePalette.textMuted,
      ),
      BridgeLink.scanning => (
        icon: Icons.bluetooth_searching,
        label: 'Searching',
        color: SmokePalette.warning,
      ),
      BridgeLink.connecting => (
        icon: Icons.bluetooth_searching,
        label: 'Connecting',
        color: SmokePalette.warning,
      ),
      BridgeLink.error => (
        icon: Icons.error_outline,
        label: 'No link',
        color: SmokePalette.critical,
      ),
      BridgeLink.connected => (
        icon: Icons.bluetooth_connected,
        label: 'Connected',
        color: SmokePalette.positive,
      ),
    };

    return Semantics(
      button: true,
      label: 'Connection status: ${chrome.label}. Opens connection settings.',
      child: InkWell(
        borderRadius: BorderRadius.circular(SmokeRadius.chip),
        onTap: () => showConnectionSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SmokeSpace.sm),
          // The chip's own text/icon would double the label above; the one
          // sentence is the whole semantics node.
          child: ExcludeSemantics(
            child: StatusChip(
              icon: chrome.icon,
              label: chrome.label,
              color: chrome.color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the connection sheet — the one place every connect / disconnect /
/// retry action lives.
Future<void> showConnectionSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: SmokePalette.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(SmokeRadius.card),
      ),
    ),
    builder: (context) => const _ConnectionSheet(),
  );
}

class _ConnectionSheet extends StatelessWidget {
  const _ConnectionSheet();

  @override
  Widget build(BuildContext context) {
    final controller = BridgeScope.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SmokeSpace.lg,
          0,
          SmokeSpace.lg,
          SmokeSpace.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Connection',
              style: TextStyle(
                color: SmokePalette.textHi,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: SmokeSpace.lg),
            _ConnectionBody(controller: controller),
          ],
        ),
      ),
    );
  }
}

class _ConnectionBody extends StatelessWidget {
  const _ConnectionBody({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    switch (controller.link) {
      case BridgeLink.disconnected:
        return _block(
          title: 'Not connected',
          body:
              'Bluetooth is how this app reads your bridge. Pair once and it '
              'reconnects on its own. History and graphs keep working offline '
              'from what is already cached.',
          action: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton.icon(
                onPressed: controller.connect,
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Find my bridge'),
              ),
              if (controller.canForget) ...[
                const SizedBox(height: SmokeSpace.sm),
                _ForgetButton(controller: controller),
              ],
            ],
          ),
        );

      case BridgeLink.scanning:
      case BridgeLink.connecting:
        final scanning = controller.link == BridgeLink.scanning;
        return Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(width: SmokeSpace.lg),
            Expanded(
              child: Text(
                scanning
                    ? 'Searching for your bridge…'
                    : 'Connecting and pairing…',
                style: const TextStyle(
                  color: SmokePalette.textBody,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        );

      case BridgeLink.error:
        return _block(
          title: "Couldn't connect",
          body: controller.errorMessage ?? 'The bridge could not be reached.',
          action: _RecoveryActions(controller: controller),
        );

      case BridgeLink.connected:
        final id = controller.identity;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Connected',
                    style: TextStyle(
                      color: SmokePalette.textHi,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                FreshnessChip(freshness: controller.freshness),
              ],
            ),
            if (id != null) ...[
              const SizedBox(height: SmokeSpace.md),
              Text(
                '${id.model} · ${id.id} · fw ${id.fw}',
                style: const TextStyle(
                  color: SmokePalette.textMuted,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: SmokeSpace.md),
            _WireStatus(controller: controller),
            const SizedBox(height: SmokeSpace.lg),
            Wrap(
              spacing: SmokeSpace.sm,
              runSpacing: SmokeSpace.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: controller.disconnect,
                  icon: const Icon(Icons.bluetooth_disabled, size: 18),
                  label: const Text('Disconnect'),
                ),
                if (controller.canForget) _ForgetButton(controller: controller),
              ],
            ),
          ],
        );
    }
  }

  Widget _block({
    required String title,
    required String body,
    required Widget action,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: SmokePalette.textHi,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: SmokeSpace.sm),
        Text(
          body,
          style: const TextStyle(
            color: SmokePalette.textBody,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: SmokeSpace.lg),
        action,
      ],
    );
  }
}

/// The pairing escape hatch: drop the OS bond so the next connect scans fresh.
/// Offered only when a bridge is actually remembered, in both the connected and
/// disconnected states — the two places a wrong or stale pairing can strand you.
class _ForgetButton extends StatelessWidget {
  const _ForgetButton({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: controller.forgetBridge,
      icon: const Icon(Icons.link_off, size: 18),
      label: const Text('Forget bridge'),
    );
  }
}

/// The bridge's own telemetry: battery (when it can report one) and the two
/// radio hops — the phone ↔ bridge link and the last LoRa state message. These
/// are the signals a field user reads before walking away, so they sit in the
/// one sheet that already answers "is this link healthy?".
class _WireStatus extends StatelessWidget {
  const _WireStatus({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    final live = controller.latestLive;
    final parts = <String>[
      if (live?.socPct != null) 'Battery ${live!.socPct}%',
      if (controller.linkRssiDbm != null) 'Link ${controller.linkRssiDbm} dBm',
      if (live != null) 'LoRa ${live.rssiLora} dBm',
    ];
    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        const Icon(Icons.sensors, size: 16, color: SmokePalette.textMuted),
        const SizedBox(width: SmokeSpace.sm),
        Expanded(
          child: Text(
            parts.join(' · '),
            style: const TextStyle(color: SmokePalette.textBody, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

/// The honest empty state a tab shows when it needs the bridge and has none.
///
/// One widget, so Graph, History and Live never invent three different connect
/// prompts. [primaryAction] gives the tab that genuinely cannot show anything
/// without a link (Live) a filled button; a cache-backed tab gets a quieter text
/// action, because its chip in the app bar is already the primary affordance.
class ConnectionEmpty extends StatelessWidget {
  const ConnectionEmpty({
    super.key,
    this.title,
    this.message,
    this.primaryAction = false,
  });

  final String? title;
  final String? message;
  final bool primaryAction;

  @override
  Widget build(BuildContext context) {
    final controller = BridgeScope.of(context);

    switch (controller.link) {
      case BridgeLink.scanning:
      case BridgeLink.connecting:
        return const EmptyState(
          icon: Icons.bluetooth_searching,
          title: 'Connecting…',
          message: 'Searching for your bridge. This can take a moment.',
        );
      case BridgeLink.error:
        return EmptyState(
          icon: Icons.error_outline,
          title: "Couldn't connect",
          message:
              controller.errorMessage ?? 'The bridge could not be reached.',
          action: _RecoveryActions(controller: controller),
        );
      case BridgeLink.disconnected:
      case BridgeLink.connected:
        return EmptyState(
          icon: Icons.bluetooth_searching,
          title: title ?? 'Not connected',
          message:
              message ??
              'Live readings come from your bridge over Bluetooth. History '
                  'and graphs keep working offline from what is cached.',
          action: primaryAction
              ? FilledButton.icon(
                  onPressed: controller.connect,
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Find my bridge'),
                )
              : TextButton(
                  onPressed: () => showConnectionSheet(context),
                  child: const Text('Connection settings'),
                ),
        );
    }
  }
}

/// The one action that can actually change a failed connection: a retry, plus a
/// settings deep-link when the blocker is one only the OS can clear — a radio
/// that is off, a permission the user refused, a bond the OS will not forget.
class _RecoveryActions extends StatelessWidget {
  const _RecoveryActions({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    final settings = switch (controller.problem) {
      ConnectionProblem.permissions ||
      ConnectionProblem.permissionsPermanentlyDenied => OutlinedButton.icon(
        onPressed: openAppSettings,
        icon: const Icon(Icons.settings, size: 18),
        label: const Text('App settings'),
      ),
      ConnectionProblem.bluetoothOff ||
      ConnectionProblem.staleBond => OutlinedButton.icon(
        onPressed: openBluetoothSettings,
        icon: const Icon(Icons.bluetooth, size: 18),
        label: const Text('Bluetooth settings'),
      ),
      _ => null,
    };
    return Wrap(
      spacing: SmokeSpace.sm,
      runSpacing: SmokeSpace.sm,
      alignment: WrapAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: controller.connect,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
        ?settings,
      ],
    );
  }
}
