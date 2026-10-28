import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/formatters.dart';
import '../../data/history/history_deletion.dart';
import '../../theme/app_theme.dart';
import '../../widgets/prototype_app_bar.dart';
import '../../widgets/prototype_widgets.dart';
import 'settings_details.dart';

class HistoryStorageScreen extends StatefulWidget {
  const HistoryStorageScreen({super.key, required this.controller});

  final BridgeController controller;

  @override
  State<HistoryStorageScreen> createState() => _HistoryStorageScreenState();
}

class _HistoryStorageScreenState extends State<HistoryStorageScreen> {
  BridgeController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // Opening the screen is a read. It never deletes anything.
    unawaited(controller.refreshLocalHistorySummary());
  }

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
                          KeyValueRow(
                            label: 'Storage used',
                            value: view.savedDataSize,
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
                            value: view.bridgeOldestReadingLabel,
                          ),
                          KeyValueRow(
                            label: 'Newest reading',
                            value: view.bridgeNewestReadingLabel,
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
    final plans = await Future.wait([
      controller.planLocalDeletion(HistoryDeletionScope.olderThan30Days),
      controller.planLocalDeletion(HistoryDeletionScope.olderThan90Days),
      controller.planLocalDeletion(HistoryDeletionScope.all),
    ]);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
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
              for (final plan in plans)
                _DeleteOption(
                  title: plan.scope.label,
                  subtitle: _planSubtitle(plan),
                  onTap: plan.isEmpty
                      ? null
                      : () {
                          Navigator.of(sheetContext).pop();
                          deleteLocalData(
                            context,
                            controller,
                            plan.scope,
                            plan: plan,
                          );
                        },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _planSubtitle(HistoryDeletionPlan plan) {
  if (plan.isEmpty) {
    return 'No readings in this range';
  }
  return '${commaInt(plan.count)} readings · ${_planRange(plan)}';
}

String _planRange(HistoryDeletionPlan plan) {
  final override = plan.rangeLabelOverride;
  if (override != null) return override;
  final first = plan.firstReadingAt;
  final last = plan.lastReadingAt;
  if (first == null || last == null) return '—';
  return dateRangeLabel(first, last);
}

class _DeleteOption extends StatelessWidget {
  const _DeleteOption({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: Icon(Icons.delete_outline, color: scheme.error),
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? scheme.error : scheme.onSurfaceVariant,
        ),
      ),
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
    builder: (sheetContext) => ListenableBuilder(
      listenable: controller,
      builder: (sheetContext, _) {
        final view = controller.bridgeDetailsView;
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
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
                const SizedBox(height: 12),
                for (final option in const [30, 60, 120, 0])
                  _TimeoutOption(
                    key: Key('bridge.timeout.$option'),
                    seconds: option,
                    selected: view.displayTimeoutSeconds == option,
                    onTap: () =>
                        unawaited(controller.setDisplayTimeout(option)),
                  ),
                if (view.timeoutSaveState != SettingsSaveState.idle) ...[
                  const SizedBox(height: 8),
                  InlineSaveState(
                    state: view.timeoutSaveState,
                    error: view.timeoutSaveError,
                    savedLabel: 'Saved',
                  ),
                ],
                const SizedBox(height: 14),
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

class _TimeoutOption extends StatelessWidget {
  const _TimeoutOption({
    super.key,
    required this.seconds,
    required this.selected,
    required this.onTap,
  });

  final int seconds;
  final bool selected;
  final VoidCallback onTap;

  String get _label {
    if (seconds == 0) return 'Never';
    if (seconds < 60) return '$seconds sec';
    return '${seconds ~/ 60} min';
  }

  String get _subtitle {
    if (seconds == 0) return 'Screen stays on';
    return '$_label · screen turns off';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: true,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(_label),
      subtitle: Text(_subtitle),
      onTap: onTap,
    );
  }
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
            key: const Key('bridge.name.field'),
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
          key: const Key('bridge.name.done'),
          onPressed: () => Navigator.of(dialogContext).pop(draft.trim()),
          child: const Text('Done'),
        ),
      ],
    ),
  );
  if (result != null && result.isNotEmpty) {
    await controller.setDeviceName(result);
  }
}
