import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../data/ble/bridge_protocol.dart';
import '../../app/formatters.dart';
import '../../data/history/history_deletion.dart';
import '../../theme/app_theme.dart';
import '../../widgets/connection_log.dart';
import '../../widgets/prototype_app_bar.dart';
import '../../widgets/prototype_widgets.dart';
import '../setup/setup_screen.dart';

enum DestructiveKind {
  forgetPhone,
  clearBridgeHistory,
  delete30,
  delete90,
  deleteAll,
  factoryReset,
  powerOff,
}

class BillowsSettingsScreen extends StatelessWidget {
  const BillowsSettingsScreen({super.key, required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final view = controller.bridgeDetailsView;
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: prototypeAppBar(context, controller, 'Billows'),
          body: ListView(
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InlineNotice(
                      icon: Icons.lock_outline,
                      title: view.connected
                          ? 'Billows status'
                          : 'Last observed state',
                      message: view.connected
                          ? 'Billows reports through the Smoke X4. Its set temperature comes from the Smoke X4; this app shows it for reference.'
                          : 'Reconnect to refresh the Billows status and set temperature.',
                    ),
                    const SizedBox(height: 16),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  view.connected
                                      ? 'Status'
                                      : 'Last observed status',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Pill(
                                label: view.billows.attachmentLabel,
                                color: view.billows.detected
                                    ? StatusColors.live(context)
                                    : StatusColors.stale(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          KeyValueRow(
                            label: 'Last detected',
                            value: view.billows.lastDetectedLabel,
                          ),
                          KeyValueRow(
                            label: view.billows.setTempLabel,
                            value: view.billows.setTempKnown
                                ? view.billows.setTempText
                                : '—',
                          ),
                          KeyValueRow(
                            label: 'Set on',
                            value: view.billows.sourceLabel,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Detected means the Smoke X4 is receiving Billows data. The set temp can only be changed on the Smoke X4. Detection doesn’t mean the fan is running.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.history,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Connection log',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Newest first. The full Bridge timeline is in Bridge details → Connection log.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          ConnectionLogList(
                            events: view.billowsLog,
                            billowsOnly: true,
                          ),
                        ],
                      ),
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
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.controller, this.onOpenLab});

  final BridgeController controller;
  final VoidCallback? onOpenLab;

  @override
  Widget build(BuildContext context) {
    final view = controller.bridgeDetailsView;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: prototypeAppBar(context, controller, 'About'),
      body: ListView(
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: onOpenLab,
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.thermostat,
                                color: scheme.primary,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Smoke X4 Smart Bridge',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  Text(
                                    'App 0.1.0',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        KeyValueRow(label: 'Firmware', value: view.firmware),
                        KeyValueRow(
                          label: 'Bridge protocol',
                          value: view.protocol,
                        ),
                        KeyValueRow(label: 'Bridge ID', value: view.deviceId),
                        KeyValueRow(
                          label: 'Bluetooth name',
                          value: 'SmokeX4-${view.deviceId}',
                        ),
                        const KeyValueRow(
                          label: 'Hardware',
                          value: 'Heltec WiFi LoRa 32 V3',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Firmware updates',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Firmware updates require a USB connection to a computer. This app can’t update the Bridge over Bluetooth.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Privacy',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'No cloud, no account. Data stays on this phone and the Bridge.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Attribution',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Smoke X protocol decoding is based on G-Two/smoke-x-receiver (MIT © 2022 G-Two). Not affiliated with or endorsed by ThermoWorks. Smoke X is a trademark of its owner.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RePairScreen extends StatefulWidget {
  const RePairScreen({super.key, required this.controller});

  final BridgeController controller;

  @override
  State<RePairScreen> createState() => _RePairScreenState();
}

class _RePairScreenState extends State<RePairScreen> {
  bool _busy = false;
  bool _cleared = false;
  String? _error;

  Future<void> _rePair() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final status = await widget.controller.startRePair();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _cleared = status == BridgeConfigStatus.ok;
      _error = _cleared
          ? null
          : widget.controller.bridgeRefusalMessage(status);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: prototypeAppBar(context, widget.controller, 'Re-pair Smoke X4'),
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
                      Text(
                        _cleared
                            ? 'Put the Smoke X4 into SYNC mode'
                            : 'Re-pair the Smoke X4',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 14),
                      if (_cleared) ...[
                        const _NumberedStep(
                          number: '1',
                          text: 'Put the Smoke X4 into SYNC mode.',
                        ),
                        const _NumberedStep(
                          number: '2',
                          text: 'Hold its button until it beeps.',
                        ),
                        const _NumberedStep(
                          number: '3',
                          text: 'The Bridge confirms the pairing.',
                        ),
                        const SizedBox(height: 14),
                      ],
                      Text(
                        'This clears the old radio pairing only. History on the Bridge, phone pairings, and settings are kept.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const Key('bridge.repair.error'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('bridge.repair.start'),
                  onPressed: _busy
                      ? null
                      : _cleared
                      ? () => Navigator.of(context).pop()
                      : _rePair,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(_cleared ? 'Done' : 'Start re-pairing'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberedStep extends StatelessWidget {
  const _NumberedStep({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: scheme.primary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(text),
            ),
          ),
        ],
      ),
    );
  }
}

class SavedDataScreen extends StatelessWidget {
  const SavedDataScreen({super.key, required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final view = controller.settingsView;
        final scheme = Theme.of(context).colorScheme;
        final empty = view.localHistoryEmpty;
        return Scaffold(
          appBar: prototypeAppBar(context, controller, 'History on this phone'),
          body: ListView(
            children: [
              ContentWidth(
                child: empty
                    ? const EmptyState(
                        icon: Icons.folder_off_outlined,
                        title: 'No history on this phone',
                        message: 'There is no history on this phone yet. The Bridge records whenever it’s on and paired with the Smoke X4.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'On this phone',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall,
                                ),
                                const SizedBox(height: 12),
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
                                const SizedBox(height: 8),
                                Text(
                                  'This history is stored on your phone, not on the Bridge. It stays until you delete it.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          InlineNotice(
                            icon: Icons.info_outline,
                            title: 'The Bridge isn’t needed',
                            message: 'You can review or delete this history even after forgetting or resetting the Bridge.',
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: scheme.error,
                              side: BorderSide(color: scheme.error),
                            ),
                            onPressed: () => deleteSavedData(context),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text(
                              'Delete history from this phone…',
                            ),
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

  Future<void> deleteSavedData(BuildContext context) async {
    final plan = await controller.planLocalDeletion(HistoryDeletionScope.all);
    if (!context.mounted) return;
    if (plan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no readings to delete.')),
      );
      return;
    }
    final confirmed = await showLossSheet(
      context,
      title: 'Delete all history from this phone?',
      intro: 'This deletes every reading stored on this phone. It can’t be undone.',
      bullets: [
        '${commaInt(plan.count)} readings',
        _deletionRangeLabel(plan),
        'The Bridge isn’t changed and keeps recording.',
      ],
      keepNote: 'This is the only copy of this history.',
      confirmLabel: 'Delete ${commaInt(plan.count)} readings',
    );
    if (confirmed == true && context.mounted) {
      await controller.applyLocalDeletion(plan);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('History deleted from this phone.')),
      );
    }
  }
}

class PowerOffScreen extends StatelessWidget {
  const PowerOffScreen({super.key, required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: prototypeAppBar(context, controller, 'Bridge is off'),
      body: Center(
        child: ContentWidth(
          maxWidth: 520,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.power_settings_new,
                  size: 42,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Bridge is off',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'The Bridge isn’t recording. Hold PRG for 1.5 seconds to turn it back on.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  controller.wake();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                icon: const Icon(Icons.power_settings_new),
                label: const Text('Hold PRG for 1.5 seconds'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ConfirmationPreviewScreen extends StatefulWidget {
  const ConfirmationPreviewScreen({
    super.key,
    required this.controller,
    required this.kind,
  });

  final BridgeController controller;
  final DestructiveKind kind;

  @override
  State<ConfirmationPreviewScreen> createState() =>
      _ConfirmationPreviewScreenState();
}

class _ConfirmationPreviewScreenState extends State<ConfirmationPreviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: prototypeAppBar(
        context,
        widget.controller,
        'Confirmation preview',
      ),
      body: Center(
        child: ContentWidth(
          maxWidth: 520,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 54,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 14),
              Text(
                _title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'The confirmation sheet uses the same code path as Settings. Review builds may show the outcome without hardware.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.tonal(
                onPressed: _show,
                child: const Text('Show confirmation again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _title {
    switch (widget.kind) {
      case DestructiveKind.forgetPhone:
        return 'Forget this phone';
      case DestructiveKind.clearBridgeHistory:
        return 'Clear history on the Bridge';
      case DestructiveKind.delete30:
        return 'Delete history older than 30 days';
      case DestructiveKind.delete90:
        return 'Delete history older than 90 days';
      case DestructiveKind.deleteAll:
        return 'Delete all history from this phone';
      case DestructiveKind.factoryReset:
        return 'Factory reset';
      case DestructiveKind.powerOff:
        return 'Power off';
    }
  }

  Future<void> _show() async {
    switch (widget.kind) {
      case DestructiveKind.forgetPhone:
        await showForgetFlow(context, widget.controller);
        break;
      case DestructiveKind.clearBridgeHistory:
        await clearBridgeHistory(context, widget.controller);
        break;
      case DestructiveKind.delete30:
      case DestructiveKind.delete90:
      case DestructiveKind.deleteAll:
        final deletionScope = switch (widget.kind) {
          DestructiveKind.delete30 => HistoryDeletionScope.olderThan30Days,
          DestructiveKind.delete90 => HistoryDeletionScope.olderThan90Days,
          _ => HistoryDeletionScope.all,
        };
        await deleteLocalData(context, widget.controller, deletionScope);
        break;
      case DestructiveKind.factoryReset:
        await factoryReset(context, widget.controller);
        break;
      case DestructiveKind.powerOff:
        await powerOff(context, widget.controller);
        break;
    }
  }
}

/// Runs one confirmed Bridge action and shows the neutral sending state until
/// the device result (or the expected disconnect) arrives.
///
/// The sheet result is the only signal the caller acts on; a GATT write on its
/// own never produces a success message.
Future<DestructiveOutcome?> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String intro,
  required List<String> bullets,
  String? keepNote,
  required String confirmLabel,
  required String sendingLabel,
  required Future<DestructiveOutcome> Function() action,
  bool destructive = true,
}) async {
  final confirmed = await showLossSheet(
    context,
    title: title,
    intro: intro,
    bullets: bullets,
    keepNote: keepNote,
    confirmLabel: confirmLabel,
    destructive: destructive,
  );
  if (confirmed != true || !context.mounted) return null;
  return showDialog<DestructiveOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SendingDialog(label: sendingLabel, action: action),
  );
}

void _openSetup(BuildContext context, BridgeController controller) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      builder: (_) => SetupScreen(
        controller: controller,
        initialStep: SetupStep.noBridge,
      ),
    ),
    (route) => route.isFirst,
  );
}

void _showFailure(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      key: const Key('destructive.failure'),
      content: Text(message),
    ),
  );
}

class _SendingDialog extends StatefulWidget {
  const _SendingDialog({required this.label, required this.action});

  final String label;
  final Future<DestructiveOutcome> Function() action;

  @override
  State<_SendingDialog> createState() => _SendingDialogState();
}

class _SendingDialogState extends State<_SendingDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run();
    });
  }

  Future<void> _run() async {
    final outcome = await widget.action();
    if (!mounted) return;
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('destructive.sending'),
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(widget.label)),
          ],
        ),
      ),
    );
  }
}

Future<void> showForgetFlow(
  BuildContext context,
  BridgeController controller,
) async {
  final outcome = await confirmDestructiveAction(
    context,
    title: 'Forget this phone?',
    intro: 'This removes the Bluetooth pairing for this phone. The Bridge keeps recording.',
    bullets: const [
      'The Bridge forgets this phone.',
      'This app forgets the Bridge.',
      'History on this phone stays until you delete it.',
    ],
    keepNote: 'You can pair again later. Other paired phones are not affected.',
    confirmLabel: 'Forget phone',
    sendingLabel: 'Forgetting this phone…',
    action: controller.forgetPhone,
  );
  if (outcome == null || !context.mounted) return;
  // Forget is local-first: return to Setup even when the Bridge could not
  // confirm the pairing removal. Setup names the pairing that may remain.
  _openSetup(context, controller);
}

Future<void> clearBridgeHistory(
  BuildContext context,
  BridgeController controller,
) async {
  final view = controller.settingsView;
  final outcome = await confirmDestructiveAction(
    context,
    title: 'Clear history on the Bridge?',
    intro: 'The Bridge erases its saved readings. This can’t be undone.',
    bullets: [
      '${view.bridgeRecordsLabel} readings in history on the Bridge',
      if (view.bridgeOldestReadingAt != null &&
          view.bridgeNewestReadingAt != null)
        'Date range: ${absoluteRangeLabel(view.bridgeOldestReadingAt!, view.bridgeNewestReadingAt!)}',
      'The Bridge keeps its pairings and settings',
      'History on this phone is kept',
    ],
    keepNote: 'The Bridge starts recording a new log.',
    confirmLabel: 'Clear history',
    sendingLabel: 'Clearing history on the Bridge…',
    action: controller.clearBridgeHistory,
  );
  if (outcome == null || !context.mounted) return;
  if (outcome == DestructiveOutcome.success) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        key: Key('destructive.clear.success'),
        content: Text(
          'History on the Bridge cleared. New readings start a new log.',
        ),
      ),
    );
  } else {
    _showFailure(
      context,
      'The Bridge didn’t clear its history. Nothing changed. Try again.',
    );
  }
}

Future<void> deleteLocalData(
  BuildContext context,
  BridgeController controller,
  HistoryDeletionScope scope, {
  HistoryDeletionPlan? plan,
}) async {
  final confirmedPlan = plan ?? await controller.planLocalDeletion(scope);
  if (!context.mounted) return;
  if (confirmedPlan.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('There are no readings to delete.')),
    );
    return;
  }
  final days = scope.age?.inDays;
  final confirmed = await showLossSheet(
    context,
    title: days == null
        ? 'Delete all history from this phone?'
        : 'Delete history older than $days days?',
    intro: days == null
        ? 'All readings stored on this phone will be deleted. This can’t be undone.'
        : 'Only readings older than $days days will be deleted. This can’t be undone.',
    bullets: [
      'Date range: ${_deletionRangeLabel(confirmedPlan)}',
      '${commaInt(confirmedPlan.count)} readings will be deleted',
      'This doesn’t change the Bridge',
      days == null
          ? 'All readings on this phone are deleted'
          : 'Only the selected readings are deleted',
    ],
    confirmLabel: 'Delete ${commaInt(confirmedPlan.count)} readings',
  );
  if (confirmed == true && context.mounted) {
    await controller.applyLocalDeletion(confirmedPlan);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('History deleted from this phone.')),
    );
  }
}

String _deletionRangeLabel(HistoryDeletionPlan plan) {
  final override = plan.rangeLabelOverride;
  if (override != null) return override;
  final first = plan.firstReadingAt;
  final last = plan.lastReadingAt;
  if (first == null || last == null) return 'No readings in this range';
  return absoluteRangeLabel(first, last);
}

Future<void> powerOff(BuildContext context, BridgeController controller) async {
  final outcome = await confirmDestructiveAction(
    context,
    title: 'Power off the Bridge?',
    intro: 'The Bridge stops recording until you turn it back on.',
    bullets: const [
      'Recording stops while the Bridge is off',
      'History on this phone is kept',
    ],
    keepNote: 'Hold PRG for 1.5 seconds to turn the Bridge back on.',
    confirmLabel: 'Power off',
    sendingLabel: 'Turning off the Bridge…',
    action: controller.powerOff,
    destructive: false,
  );
  if (outcome == null || !context.mounted) return;
  if (outcome.landed) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PowerOffScreen(controller: controller),
      ),
    );
  } else {
    _showFailure(
      context,
      'The Bridge didn’t turn off. Nothing changed. Try again.',
    );
  }
}

Future<void> factoryReset(
  BuildContext context,
  BridgeController controller,
) async {
  final outcome = await confirmDestructiveAction(
    context,
    title: 'Factory reset this Bridge?',
    intro: 'The Bridge erases its pairings, settings, and saved readings, then restarts.',
    bullets: const [
      'All paired phones, including this one',
      'Bridge settings and screen preferences',
      'Saved readings and the clock',
      'The Bridge becomes available to pair as a new device',
    ],
    keepNote: 'History on this phone is kept.',
    confirmLabel: 'Factory reset',
    sendingLabel: 'Resetting the Bridge…',
    action: controller.factoryReset,
  );
  if (outcome == null || !context.mounted) return;
  if (outcome.landed) {
    _openSetup(context, controller);
  } else {
    _showFailure(
      context,
      'The Bridge didn’t confirm the reset. Nothing changed. Try again.',
    );
  }
}
