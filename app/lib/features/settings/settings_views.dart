import 'package:flutter/material.dart';

import '../../prototype/formatters.dart';
import '../../prototype/prototype_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/prototype_app_bar.dart';
import '../../widgets/prototype_widgets.dart';
import 'settings_details.dart';

class HistoryStorageScreen extends StatelessWidget {
  const HistoryStorageScreen({super.key, required this.controller});

  final PrototypeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final connected = controller.isConnected;
        final bridgeFraction = controller.bridgeCapacity == 0
            ? 0.0
            : controller.bridgeRecords / controller.bridgeCapacity;
        return Scaffold(
          appBar: prototypeAppBar(context, controller, 'History & storage'),
          body: ListView(
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.developer_board_outlined,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Device log',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Text(
                                controller.savedDataSize,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          KeyValueRow(
                            label: 'Readings',
                            value: commaInt(controller.phoneRecords),
                          ),
                          KeyValueRow(
                            label: 'Date range',
                            value: controller.savedDataRange,
                          ),
                          KeyValueRow(
                            label: 'Database',
                            value: controller.savedDataSize,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Stays on this device even if the Bridge is reset.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: scheme.error,
                              side: BorderSide(color: scheme.error),
                            ),
                            onPressed: () => _showDeleteOptions(context),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Delete device log…'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.sd_storage_outlined,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Bridge log',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Text(
                                '${(bridgeFraction * 100).toStringAsFixed(1)}%',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: bridgeFraction,
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          const SizedBox(height: 12),
                          KeyValueRow(
                            label: 'Readings',
                            value:
                                '${commaInt(controller.bridgeRecords)} of ${commaInt(controller.bridgeCapacity)}',
                          ),
                          KeyValueRow(
                            label: 'Capacity',
                            value: '~117 days at 30 s',
                          ),
                          KeyValueRow(
                            label: 'Oldest',
                            value: 'Oct 17, 2026 · 08:14',
                          ),
                          KeyValueRow(
                            label: 'Newest',
                            value: 'Oct 25, 2026 · 18:30',
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'The Bridge overwrites its oldest readings automatically.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: scheme.error,
                              side: BorderSide(color: scheme.error),
                            ),
                            onPressed: connected
                                ? () => clearBridgeHistory(context, controller)
                                : null,
                            icon: const Icon(
                              Icons.sd_card_alert_outlined,
                              size: 18,
                            ),
                            label: Text(
                              connected
                                  ? 'Clear Bridge log…'
                                  : 'Connect to clear the Bridge log',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    InlineNotice(
                      icon: Icons.info_outline,
                      title: 'Two separate copies',
                      message: 'Deleting device log does not clear the Bridge log. Clearing the Bridge log does not delete device log.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showDeleteOptions(BuildContext context) async {
    final count = controller.phoneRecords;
    final older30 = count > 12430 ? 12430 : count;
    final older90 = count;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delete device log',
                style: Theme.of(sheetContext).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Only readings on this device are removed. The Bridge is not changed.',
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _DeleteOption(
                title: 'Older than 30 days',
                subtitle: '${commaInt(older30)} readings · Sep 25 – Oct 24',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  deleteLocalData(context, controller, '30');
                },
              ),
              _DeleteOption(
                title: 'Older than 90 days',
                subtitle: '${commaInt(older90)} readings · Jul 27 – Oct 24',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  deleteLocalData(context, controller, '90');
                },
              ),
              _DeleteOption(
                title: 'Everything',
                subtitle: '${commaInt(count)} readings · Sep 1 – Oct 24',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  deleteLocalData(context, controller, 'all');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteOption extends StatelessWidget {
  const _DeleteOption({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.delete_outline, color: scheme.error),
      title: Text(title, style: TextStyle(color: scheme.error)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key, required this.controller});

  final PrototypeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: prototypeAppBar(context, controller, 'Appearance'),
          body: ListView(
            children: [
              ContentWidth(
                child: SectionCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _ThemeOption(
                        mode: ThemeMode.system,
                        icon: Icons.brightness_auto_outlined,
                        title: 'System',
                        subtitle: 'Match the phone setting',
                        controller: controller,
                      ),
                      const Divider(),
                      _ThemeOption(
                        mode: ThemeMode.light,
                        icon: Icons.light_mode_outlined,
                        title: 'Light',
                        subtitle: 'Warm daylight palette',
                        controller: controller,
                      ),
                      const Divider(),
                      _ThemeOption(
                        mode: ThemeMode.dark,
                        icon: Icons.dark_mode_outlined,
                        title: 'Dark',
                        subtitle: 'Low-light palette for night cooks',
                        controller: controller,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.mode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.controller,
  });

  final ThemeMode mode;
  final IconData icon;
  final String title;
  final String subtitle;
  final PrototypeController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.themeMode == mode;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: selected ? scheme.primary : null),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected
          ? Icon(Icons.check_circle, color: StatusColors.live(context))
          : null,
      onTap: () => controller.setThemeMode(mode),
    );
  }
}

Future<void> showBridgeTimeoutSheet(
  BuildContext context,
  PrototypeController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bridge screen timeout',
                  style: Theme.of(sheetContext).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'The OLED sleeps after this time. A button press or BLE connect wakes it.',
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in const [30, 60, 120, 0])
                      ChoiceChip(
                        label: Text(option == 0 ? 'Never' : '$option s'),
                        selected: controller.displayTimeoutSeconds == option,
                        onSelected: (_) {
                          controller.setDisplayTimeout(option);
                          setSheetState(() {});
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<void> showBridgeNameDialog(
  BuildContext context,
  PrototypeController controller,
) async {
  var draft = controller.deviceName;
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Bridge name'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: draft,
            autofocus: true,
            maxLength: 15,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: 'Backyard Bridge'),
            onChanged: (value) => draft = value,
            onFieldSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          const SizedBox(height: 4),
          Text(
            'Shown in this app only. The Bluetooth name stays SmokeX4-${controller.deviceId}.',
            style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(draft.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (result != null && result.isNotEmpty) {
    controller.setDeviceName(result);
  }
}
