import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/formatters.dart';
import '../../theme/app_theme.dart';
import '../../widgets/prototype_app_bar.dart';
import '../../widgets/prototype_widgets.dart';
import 'settings_details.dart';

class HistoryStorageScreen extends StatelessWidget {
  const HistoryStorageScreen({super.key, required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final view = controller.settingsView;
        final scheme = Theme.of(context).colorScheme;
        final connected = view.connected;
        final bridgeFraction = view.bridgeFraction;
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
                                  'History on this phone',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Text(
                                view.savedDataSize,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          KeyValueRow(
                            label: 'Readings',
                            value: view.phoneRecordsLabel,
                          ),
                          KeyValueRow(
                            label: 'Date range',
                            value: view.savedDataRange,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Stays on this phone even if the Bridge is reset.',
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
                            label: const Text(
                              'Delete history from this phone…',
                            ),
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
                                  'History on the Bridge',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Text(
                                view.bridgeFractionLabel,
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
                                '${view.bridgeRecordsLabel} of ${commaInt(view.bridgeCapacity)}',
                          ),
                          KeyValueRow(
                            label: 'Capacity',
                            value: 'About 117 days at 30-second intervals',
                          ),
                          KeyValueRow(
                            label: 'Oldest reading',
                            value: 'Oct 17, 2026 at 8:14 AM',
                          ),
                          KeyValueRow(
                            label: 'Newest reading',
                            value: 'Oct 25, 2026 at 6:30 PM',
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
                            label: const Text('Clear history on the Bridge…'),
                          ),
                          if (!connected) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Connect to the Bridge to clear it.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    InlineNotice(
                      icon: Icons.info_outline,
                      title: 'Two separate copies',
                      message: 'Deleting history from your phone doesn’t clear the Bridge. Clearing the Bridge doesn’t delete history from your phone.',
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
    final view = controller.settingsView;
    final count = view.phoneRecords;
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
                'Delete history from this phone',
                style: Theme.of(sheetContext).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Only readings on this phone are removed. The Bridge isn’t changed.',
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _DeleteOption(
                title: 'Older than 30 days',
                subtitle:
                    '${commaInt(older30)} readings · Sep 25 – Oct 24, 2026',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  deleteLocalData(context, controller, '30');
                },
              ),
              _DeleteOption(
                title: 'Older than 90 days',
                subtitle:
                    '${commaInt(older90)} readings · Jul 27 – Oct 24, 2026',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  deleteLocalData(context, controller, '90');
                },
              ),
              _DeleteOption(
                title: 'All history on this phone',
                subtitle: '${commaInt(count)} readings · Sep 1 – Oct 24, 2026',
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

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final view = controller.settingsView;
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
                        icon: Icons.brightness_auto_outlined,
                        title: 'System',
                        subtitle: 'Match your phone',
                        selected: view.themeModeLabel == 'System',
                        onTap: () => controller.setThemeMode(ThemeMode.system),
                      ),
                      const Divider(),
                      _ThemeOption(
                        icon: Icons.light_mode_outlined,
                        title: 'Light',
                        subtitle: 'Always use light',
                        selected: view.themeModeLabel == 'Light',
                        onTap: () => controller.setThemeMode(ThemeMode.light),
                      ),
                      const Divider(),
                      _ThemeOption(
                        icon: Icons.dark_mode_outlined,
                        title: 'Dark',
                        subtitle: 'Always use dark',
                        selected: view.themeModeLabel == 'Dark',
                        onTap: () => controller.setThemeMode(ThemeMode.dark),
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
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: selected ? scheme.primary : null),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected
          ? Icon(Icons.check_circle, color: StatusColors.live(context))
          : null,
      onTap: onTap,
    );
  }
}

Future<void> showBridgeTimeoutSheet(
  BuildContext context,
  BridgeController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final view = controller.bridgeDetailsView;
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
                  'The Bridge screen turns off after this time. Press any button or connect with the app to wake it.',
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
                        label: Text(
                          option == 0
                              ? 'Never'
                              : option < 60
                              ? '$option sec'
                              : '${option ~/ 60} min',
                        ),
                        selected: view.displayTimeoutSeconds == option,
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
  BridgeController controller,
) async {
  var draft = controller.bridgeDetailsView.deviceName;
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
            'Only shown in this app. The Bridge’s Bluetooth name doesn’t change.',
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
