/// Settings: the one place the bridge's lifecycle lives.
///
/// Four cards, in the order a field user reaches for them: the link (identity,
/// telemetry, connect / disconnect / forget), the Smoke X4 (pairing status and
/// the pair / unpair verbs), the bridge (identify, OLED units, battery saver,
/// probes, preferences, stats), and the destructive actions (reboot, factory
/// reset, power off).
///
/// Every bridge action is disabled without a link, and the two that cannot be
/// undone — factory reset and power off — are confirmed first. The verbs live on
/// [BridgeController]; this file is presentation only.
library;

import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/bridge_scope.dart';
import '../../data/ble/bridge_transport.dart';
import '../../design/primitives.dart';
import '../../design/tokens.dart';
import '../../domain/domain.dart';
import '../common/bridge_app_bar.dart';
import 'probes_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = BridgeScope.of(context);
    return Scaffold(
      appBar: const BridgeAppBar(title: 'Settings'),
      body: ListView(
        padding: const EdgeInsets.all(SmokeSpace.lg),
        children: [
          _LinkCard(controller: controller),
          const SizedBox(height: SmokeSpace.lg),
          _SmokeXCard(controller: controller),
          const SizedBox(height: SmokeSpace.lg),
          _BridgeCard(controller: controller),
          const SizedBox(height: SmokeSpace.lg),
          _ProbesCard(controller: controller),
          const SizedBox(height: SmokeSpace.lg),
          _PreferencesCard(controller: controller),
          const SizedBox(height: SmokeSpace.lg),
          _StatsCard(controller: controller),
          const SizedBox(height: SmokeSpace.lg),
          _DangerCard(controller: controller),
        ],
      ),
    );
  }
}

// ── the link ──────────────────────────────────────────────────────────

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    final id = controller.identity;
    final live = controller.latestLive;
    return _Section(
      title: 'Bridge',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _linkLabel(controller),
                  style: const TextStyle(
                    color: SmokePalette.textHi,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FreshnessChip(freshness: controller.freshness),
            ],
          ),
          const SizedBox(height: SmokeSpace.md),
          if (id != null) ...[
            _StatRow(label: 'Model', value: id.model),
            _StatRow(label: 'Bridge ID', value: id.id),
            _StatRow(label: 'Firmware', value: id.fw),
            _StatRow(label: 'Probes', value: '${id.probes}'),
            _StatRow(
              label: 'Full history',
              value: id.historyFull ? 'Yes' : 'No',
            ),
          ],
          if (controller.linkRssiDbm != null)
            _StatRow(
              label: 'Link signal',
              value: '${controller.linkRssiDbm} dBm',
            ),
          if (live != null)
            _StatRow(label: 'Smoke X4 signal', value: '${live.rssiLora} dBm'),
          if (live != null && live.socPct != null)
            _StatRow(label: 'Battery', value: '${live.socPct}%'),
          if (id == null && live == null && !controller.connected)
            const Text(
              'Not connected. Connect to read the bridge’s identity and '
              'telemetry.',
              style: TextStyle(
                color: SmokePalette.textBody,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          const SizedBox(height: SmokeSpace.lg),
          Wrap(
            spacing: SmokeSpace.sm,
            runSpacing: SmokeSpace.sm,
            children: [
              if (controller.connected)
                OutlinedButton.icon(
                  onPressed: controller.disconnect,
                  icon: const Icon(Icons.bluetooth_disabled, size: 18),
                  label: const Text('Disconnect'),
                )
              else
                FilledButton.icon(
                  onPressed: controller.connect,
                  icon: const Icon(Icons.bluetooth_searching, size: 18),
                  label: const Text('Connect'),
                ),
              if (controller.canForget)
                TextButton.icon(
                  onPressed: controller.forgetBridge,
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('Forget bridge'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _linkLabel(BridgeController c) => switch (c.link) {
    BridgeLink.connected => 'Connected',
    BridgeLink.scanning => 'Searching…',
    BridgeLink.connecting => 'Connecting…',
    BridgeLink.error => c.reconnectExhausted ? 'Lost bridge' : 'No link',
    BridgeLink.disconnected =>
      c.reconnectExhausted ? 'Lost bridge' : 'Not connected',
  };
}

// ── the Smoke X4 ──────────────────────────────────────────────────────

class _SmokeXCard extends StatelessWidget {
  const _SmokeXCard({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    final live = controller.latestLive;
    final paired = live?.paired ?? false;
    final connected = controller.connected;
    return _Section(
      title: 'Smoke X4',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                paired ? Icons.link : Icons.link_off,
                size: 18,
                color: paired ? SmokePalette.positive : SmokePalette.textMuted,
              ),
              const SizedBox(width: SmokeSpace.sm),
              Expanded(
                child: Text(
                  paired ? 'Paired' : 'Not paired',
                  style: const TextStyle(
                    color: SmokePalette.textHi,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: SmokeSpace.md),
          Text(
            paired
                ? 'Readings are arriving from your Smoke X4.'
                : 'Put your Smoke X4 into SYNC, then pair it here. The '
                      'bridge screen confirms the link.',
            style: const TextStyle(
              color: SmokePalette.textBody,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: SmokeSpace.lg),
          Wrap(
            spacing: SmokeSpace.sm,
            runSpacing: SmokeSpace.sm,
            children: [
              if (paired)
                OutlinedButton.icon(
                  onPressed: connected ? controller.unpairSmokeX : null,
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('Unpair Smoke X4'),
                )
              else
                FilledButton.icon(
                  onPressed: connected ? controller.pairSmokeX : null,
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Pair with Smoke X4'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── bridge ────────────────────────────────────────────────────────────

class _BridgeCard extends StatelessWidget {
  const _BridgeCard({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    final connected = controller.connected;
    return _Section(
      title: 'Display & power',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: connected ? controller.identifyBridge : null,
              icon: const Icon(Icons.wb_incandescent_outlined, size: 18),
              label: const Text('Identify (flash screen)'),
            ),
          ),
          const SizedBox(height: SmokeSpace.lg),
          const _FieldLabel('Screen units'),
          const SizedBox(height: SmokeSpace.sm),
          SegmentedButton<TempUnit>(
            segments: const [
              ButtonSegment(value: TempUnit.fahrenheit, label: Text('°F')),
              ButtonSegment(value: TempUnit.celsius, label: Text('°C')),
            ],
            selected: {controller.unit},
            onSelectionChanged: (s) => controller.setUnit(s.first),
          ),
          const SizedBox(height: SmokeSpace.lg),
          const _FieldLabel('Battery saver'),
          const SizedBox(height: SmokeSpace.sm),
          SegmentedButton<BatterySaverMode>(
            segments: const [
              ButtonSegment(value: BatterySaverMode.off, label: Text('Off')),
              ButtonSegment(value: BatterySaverMode.on, label: Text('On')),
              ButtonSegment(value: BatterySaverMode.auto, label: Text('Auto')),
            ],
            selected: {controller.batterySaver},
            onSelectionChanged: connected
                ? (s) => controller.setBatterySaver(s.first)
                : null,
          ),
        ],
      ),
    );
  }
}

// ── the destructive actions ───────────────────────────────────────────

class _DangerCard extends StatelessWidget {
  const _DangerCard({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    final connected = controller.connected;
    return _Section(
      title: 'Bridge control',
      child: Wrap(
        spacing: SmokeSpace.sm,
        runSpacing: SmokeSpace.sm,
        children: [
          OutlinedButton.icon(
            onPressed: connected ? controller.rebootBridge : null,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reboot bridge'),
          ),
          OutlinedButton.icon(
            onPressed: connected ? controller.powerOffBridge : null,
            icon: const Icon(Icons.power_settings_new, size: 18),
            label: const Text('Power off'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: SmokePalette.critical,
            ),
            onPressed: connected
                ? () => _confirm(
                    context,
                    title: 'Factory reset the bridge?',
                    body:
                        'This erases the bridge’s Bluetooth pairing, settings '
                        'and every recorded cook, then reboots it. This phone '
                        'will forget it too. This cannot be undone.',
                    confirmLabel: 'Factory reset',
                    onConfirm: controller.factoryResetBridge,
                  )
                : null,
            icon: const Icon(Icons.delete_forever_outlined, size: 18),
            label: const Text('Factory reset'),
          ),
        ],
      ),
    );
  }

  void _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    required Future<void> Function() onConfirm,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SmokePalette.cardRaised,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SmokePalette.critical,
            ),
            onPressed: () {
              Navigator.of(context).pop();
              onConfirm();
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }
}

// ── probes ────────────────────────────────────────────────────────────

class _ProbesCard extends StatelessWidget {
  const _ProbesCard({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    final admin = controller.identity?.admin ?? false;
    final probes = controller.deviceConfig?.probes ?? const [];
    final summary = probes
        .where((p) => p.role != ProbeRole.unused)
        .map((p) => p.name.isEmpty ? p.role.label : p.name)
        .join(', ');
    return _Section(
      title: 'Probes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.isEmpty
                ? 'Name each probe and say what it measures. The bridge screen '
                      'and its alarm bands follow these.'
                : summary,
            style: const TextStyle(
              color: SmokePalette.textBody,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: SmokeSpace.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: controller.connected && admin
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProbesScreen(),
                      ),
                    )
                  : null,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Edit probes'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── bridge preferences ────────────────────────────────────────────────

class _PreferencesCard extends StatelessWidget {
  const _PreferencesCard({required this.controller});

  final BridgeController controller;

  static const _timeouts = <int>[0, 30, 60, 120, 300];
  static const _maxSessions = <int>[8, 16, 32, 64, 128];
  static const _minFree = <int>[5, 10, 20, 30];

  @override
  Widget build(BuildContext context) {
    final cfg = controller.deviceConfig;
    if (cfg == null) {
      return const SizedBox.shrink();
    }
    final p = cfg.prefs;
    final enabled = controller.connected;
    void save({
      int? timeout,
      bool? led,
      bool? buzzer,
      int? maxSessions,
      int? minFree,
    }) => controller.saveDevicePrefs(
      DevicePrefs(
        displayTimeoutS: timeout ?? p.displayTimeoutS,
        ledEnabled: led ?? p.ledEnabled,
        buzzerEnabled: buzzer ?? p.buzzerEnabled,
        retentionMaxSessions: maxSessions ?? p.retentionMaxSessions,
        retentionMinFreePct: minFree ?? p.retentionMinFreePct,
      ),
    );

    return _Section(
      title: 'Bridge preferences',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Screen timeout'),
          const SizedBox(height: SmokeSpace.sm),
          DropdownButton<int>(
            isExpanded: true,
            value: _timeouts.contains(p.displayTimeoutS)
                ? p.displayTimeoutS
                : 60,
            items: [
              for (final t in _timeouts)
                DropdownMenuItem(
                  value: t,
                  child: Text(t == 0 ? 'Never sleep' : '$t seconds'),
                ),
            ],
            onChanged: enabled ? (v) => save(timeout: v) : null,
          ),
          const SizedBox(height: SmokeSpace.md),
          _SwitchRow(
            label: 'Status LED',
            value: p.ledEnabled,
            onChanged: enabled ? (v) => save(led: v) : null,
          ),
          _SwitchRow(
            label: 'Buzzer',
            value: p.buzzerEnabled,
            onChanged: enabled ? (v) => save(buzzer: v) : null,
          ),
          const SizedBox(height: SmokeSpace.md),
          const _FieldLabel('History retention — keep at most'),
          const SizedBox(height: SmokeSpace.sm),
          DropdownButton<int>(
            isExpanded: true,
            value: _maxSessions.contains(p.retentionMaxSessions)
                ? p.retentionMaxSessions
                : 64,
            items: [
              for (final n in _maxSessions)
                DropdownMenuItem(value: n, child: Text('$n sessions')),
            ],
            onChanged: enabled ? (v) => save(maxSessions: v) : null,
          ),
          const SizedBox(height: SmokeSpace.md),
          const _FieldLabel('…unless free space drops below'),
          const SizedBox(height: SmokeSpace.sm),
          DropdownButton<int>(
            isExpanded: true,
            value: _minFree.contains(p.retentionMinFreePct)
                ? p.retentionMinFreePct
                : 10,
            items: [
              for (final n in _minFree)
                DropdownMenuItem(value: n, child: Text('$n % free')),
            ],
            onChanged: enabled ? (v) => save(minFree: v) : null,
          ),
        ],
      ),
    );
  }
}

// ── bridge stats ──────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.deviceStats;
    if (s == null) {
      return const SizedBox.shrink();
    }
    String pct(int used, int total) =>
        total == 0 ? '—' : '${(used * 100 / total).round()}%';
    return _Section(
      title: 'Bridge stats',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatRow(label: 'Uptime', value: _duration(s.uptimeS)),
          _StatRow(
            label: 'Memory',
            value: '${_kb(s.heapFreeB)} free · ${_kb(s.heapMinB)} min',
          ),
          _StatRow(
            label: 'Storage',
            value:
                '${_kb(s.storageUsedB)} / ${_kb(s.storageTotalB)} '
                '(${pct(s.storageUsedB, s.storageTotalB)})',
          ),
          _StatRow(label: 'Sessions stored', value: '${s.storedSessions}'),
          _StatRow(
            label: 'LoRa',
            value:
                '${(s.loraFreqHz / 1e6).toStringAsFixed(1)} MHz · '
                '${s.loraRssi} dBm · ${s.loraSnr} dB',
          ),
          _StatRow(
            label: 'Packets',
            value: '${s.packetsOk} ok · ${s.packetsBad} bad',
          ),
          _StatRow(label: 'Phone bonds', value: '${s.bonds}'),
          const SizedBox(height: SmokeSpace.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: controller.connected ? controller.refreshStats : null,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ),
        ],
      ),
    );
  }

  static String _kb(int bytes) =>
      bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(0)} KB';

  static String _duration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return h > 0 ? '${h}h ${m}m' : (m > 0 ? '${m}m ${s}s' : '${s}s');
  }
}

// ── shared bits ───────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: SmokeSpace.xs),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: SmokePalette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        const SizedBox(height: SmokeSpace.sm),
        SmokeCard(child: child),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: SmokePalette.textBody, fontSize: 14),
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: SmokePalette.textMuted,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

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
                color: SmokePalette.textBody,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: SmokePalette.textHi,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
