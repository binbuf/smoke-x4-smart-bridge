/// The probe editor (v1.2): each jack's label, role and alarm target.
///
/// These values live in the bridge's config and drive its OLED pages and its
/// own alarm bands. The bridge has no way to edit them itself, so this is the
/// only place they are set. Read from `device_config`, written one probe at a
/// time via `set_probe`.
library;

import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/bridge_scope.dart';
import '../../design/primitives.dart';
import '../../design/tokens.dart';
import '../../domain/domain.dart';
import '../common/bridge_app_bar.dart';

class ProbesScreen extends StatelessWidget {
  const ProbesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = BridgeScope.of(context);
    final config = controller.deviceConfig;
    final admin = controller.identity?.admin ?? false;
    return Scaffold(
      appBar: const BridgeAppBar(title: 'Probes'),
      body: ListView(
        padding: const EdgeInsets.all(SmokeSpace.lg),
        children: [
          Text(
            'Name each probe and say what it measures. The bridge screen and '
            'its alarm bands follow these.',
            style: const TextStyle(
              color: SmokePalette.textBody,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: SmokeSpace.lg),
          if (!controller.connected)
            const EmptyState(
              icon: Icons.link_off,
              title: 'Not connected',
              message: 'Connect to the bridge to edit its probes.',
            )
          else if (!admin)
            const EmptyState(
              icon: Icons.update,
              title: 'Update required',
              message:
                  'This bridge’s firmware is older than the probe editor. '
                  'Update it over USB to manage probes from the app.',
            )
          else if (config == null)
            const EmptyState(
              icon: Icons.hourglass_empty,
              title: 'Loading',
              message: 'Reading the bridge’s probe settings…',
            )
          else
            for (final probe in config.probes) ...[
              _ProbeTile(controller: controller, probe: probe),
              const SizedBox(height: SmokeSpace.sm),
            ],
        ],
      ),
    );
  }
}

class _ProbeTile extends StatelessWidget {
  const _ProbeTile({required this.controller, required this.probe});

  final BridgeController controller;
  final ProbeConfig probe;

  @override
  Widget build(BuildContext context) {
    final target = probe.targetF10 > 0
        ? '${probe.targetF10 ~/ 10}°F'
        : 'no target';
    return SmokeCard(
      padding: const EdgeInsets.symmetric(
        horizontal: SmokeSpace.lg,
        vertical: SmokeSpace.md,
      ),
      child: Row(
        children: [
          SeriesDot(jack: probe.index + 1),
          const SizedBox(width: SmokeSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  probe.name.isEmpty ? 'Probe ${probe.index + 1}' : probe.name,
                  style: const TextStyle(
                    color: SmokePalette.textHi,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${probe.role.label} · $target',
                  style: const TextStyle(
                    color: SmokePalette.textMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editProbe(context, controller, probe),
          ),
        ],
      ),
    );
  }
}

Future<void> _editProbe(
  BuildContext context,
  BridgeController controller,
  ProbeConfig probe,
) async {
  final nameCtl = TextEditingController(text: probe.name);
  final targetCtl = TextEditingController(
    text: probe.targetF10 > 0 ? '${probe.targetF10 ~/ 10}' : '',
  );
  var role = probe.role;
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: SmokePalette.cardRaised,
        title: Text('Probe ${probe.index + 1}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtl,
              maxLength: 16,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: SmokeSpace.sm),
            DropdownButtonFormField<ProbeRole>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [
                for (final r in ProbeRole.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (r) => setState(() => role = r ?? role),
            ),
            const SizedBox(height: SmokeSpace.sm),
            TextField(
              controller: targetCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Alarm target (°F, blank for none)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (saved == true) {
    final degrees = int.tryParse(targetCtl.text.trim()) ?? 0;
    await controller.setProbeConfig(
      index: probe.index,
      name: nameCtl.text.trim(),
      role: role,
      targetF10: degrees > 0 ? degrees * 10 : 0,
    );
  }
  nameCtl.dispose();
  targetCtl.dispose();
}
