import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/formatters.dart';
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
                            label: 'Set temp',
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
                      key: const Key('billows.connectionLog'),
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
                            'Billows events appear here with the Bridge’s connection events.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
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
                        KeyValueRow(
                          label: 'Firmware',
                          value: view.firmware,
                        ),
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

class RePairScreen extends StatelessWidget {
  const RePairScreen({super.key, required this.controller});

  final BridgeController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: prototypeAppBar(context, controller, 'Re-pair Smoke X4'),
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
                        'Re-pair the Smoke X4',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 14),
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
                      Text(
                        'This clears the old radio pairing only. History on the Bridge, phone pairings, and settings are kept.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () {
                    controller.startRePair();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Re-pairing started. Put the Smoke X4 in SYNC mode.',
                        ),
                      ),
                    );
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.sync),
                  label: const Text('Start re-pairing'),
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
    final view = controller.settingsView;
    final confirmed = await showLossSheet(
      context,
      title: 'Delete all history from this phone?',
      intro: 'This deletes every reading stored on this phone. It can’t be undone.',
      bullets: [
        '${view.phoneRecordsLabel} readings',
        view.savedDataRange,
        'The Bridge isn’t changed and keeps recording.',
      ],
      keepNote: 'This is the only copy of this history.',
      confirmLabel: 'Delete ${view.phoneRecordsLabel} readings',
    );
    if (confirmed == true && context.mounted) {
      controller.deleteLocalData('all');
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
                'The confirmation sheet is shown as it would appear in the app. No device is contacted.',
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
    final view = widget.controller.settingsView;
    switch (widget.kind) {
      case DestructiveKind.forgetPhone:
        final confirmed = await showLossSheet(
          context,
          title: 'Forget this phone?',
          intro: 'This removes the Bluetooth pairing for this phone. The Bridge keeps recording.',
          bullets: const [
            'The Bridge forgets this phone.',
            'This app forgets the Bridge.',
            'History on this phone stays until you delete it.',
          ],
          keepNote:
              'You can pair again later. Other paired phones are not affected.',
          confirmLabel: 'Forget phone',
        );
        if (confirmed == true && mounted) {
          widget.controller.forgetPhone();
          _openSetup();
        }
        break;
      case DestructiveKind.clearBridgeHistory:
        final confirmed = await showLossSheet(
          context,
          title: 'Clear history on the Bridge?',
          intro: 'The Bridge erases its saved readings. This can’t be undone.',
          bullets: [
            '${view.bridgeRecordsLabel} readings in history on the Bridge',
            'The Bridge keeps its pairings and settings',
            'History on this phone is kept',
          ],
          keepNote: 'The Bridge starts recording a new log.',
          confirmLabel: 'Clear history',
        );
        if (confirmed == true && mounted) {
          widget.controller.clearBridgeHistory();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('History on the Bridge cleared.')),
          );
        }
        break;
      case DestructiveKind.delete30:
      case DestructiveKind.delete90:
      case DestructiveKind.deleteAll:
        final scope = switch (widget.kind) {
          DestructiveKind.delete30 => '30',
          DestructiveKind.delete90 => '90',
          _ => 'all',
        };
        final count = switch (scope) {
          '30' => 12430,
          '90' => 128430,
          _ => view.phoneRecords,
        };
        final range = switch (scope) {
          '30' => 'Sep 25 – Oct 24, 2026',
          '90' => 'Jul 27 – Oct 24, 2026',
          _ => view.savedDataRange,
        };
        final confirmed = await showLossSheet(
          context,
          title: scope == 'all'
              ? 'Delete all history from this phone?'
              : 'Delete history older than $scope days?',
          intro: scope == 'all'
              ? 'All readings stored on this phone will be deleted. This can’t be undone.'
              : 'Only readings older than $scope days will be deleted. This can’t be undone.',
          bullets: [
            'Date range: $range',
            'This doesn’t change the Bridge',
            scope == 'all'
                ? 'All readings on this phone are deleted'
                : 'Only the selected readings are deleted',
          ],
          confirmLabel: 'Delete ${commaInt(count)} readings',
        );
        if (confirmed == true && mounted) {
          widget.controller.deleteLocalData(scope);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('History deleted from this phone.')),
          );
        }
        break;
      case DestructiveKind.factoryReset:
        final confirmed = await showLossSheet(
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
        );
        if (confirmed == true && mounted) {
          widget.controller.factoryReset();
          _openSetup();
        }
        break;
      case DestructiveKind.powerOff:
        final confirmed = await showLossSheet(
          context,
          title: 'Power off the Bridge?',
          intro: 'The Bridge stops recording until you turn it back on.',
          bullets: const [
            'Recording stops while the Bridge is off',
            'History on this phone is kept',
          ],
          keepNote: 'Hold PRG for 1.5 seconds to turn the Bridge back on.',
          confirmLabel: 'Power off',
          destructive: false,
        );
        if (confirmed == true && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PowerOffScreen(controller: widget.controller),
            ),
          );
        }
        break;
    }
  }

  void _openSetup() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => SetupScreen(
          controller: widget.controller,
          initialStep: SetupStep.noBridge,
        ),
      ),
      (route) => route.isFirst,
    );
  }
}

Future<void> showForgetFlow(
  BuildContext context,
  BridgeController controller,
) async {
  final confirmed = await showLossSheet(
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
  );
  if (confirmed == true && context.mounted) {
    controller.forgetPhone();
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
}

Future<void> clearBridgeHistory(
  BuildContext context,
  BridgeController controller,
) async {
  final view = controller.settingsView;
  final confirmed = await showLossSheet(
    context,
    title: 'Clear history on the Bridge?',
    intro: 'The Bridge erases its saved readings. This can’t be undone.',
    bullets: [
      '${view.bridgeRecordsLabel} readings in history on the Bridge',
      'The Bridge keeps its pairings and settings',
      'History on this phone is kept',
    ],
    keepNote: 'The Bridge starts recording a new log.',
    confirmLabel: 'Clear history',
  );
  if (confirmed == true && context.mounted) {
    controller.clearBridgeHistory();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('History on the Bridge cleared.')),
    );
  }
}

Future<void> deleteLocalData(
  BuildContext context,
  BridgeController controller,
  String scope,
) async {
  final view = controller.settingsView;
  final count = switch (scope) {
    '30' => 12430,
    '90' => 128430,
    _ => view.phoneRecords,
  };
  final range = switch (scope) {
    '30' => 'Sep 25 – Oct 24, 2026',
    '90' => 'Jul 27 – Oct 24, 2026',
    _ => view.savedDataRange,
  };
  final confirmed = await showLossSheet(
    context,
    title: scope == 'all'
        ? 'Delete all history from this phone?'
        : 'Delete history older than $scope days?',
    intro: scope == 'all'
        ? 'All readings stored on this phone will be deleted. This can’t be undone.'
        : 'Only readings older than $scope days will be deleted. This can’t be undone.',
    bullets: [
      'Date range: $range',
      'This doesn’t change the Bridge',
      scope == 'all'
          ? 'All readings on this phone are deleted'
          : 'Only the selected readings are deleted',
    ],
    confirmLabel: 'Delete ${commaInt(count)} readings',
  );
  if (confirmed == true && context.mounted) {
    controller.deleteLocalData(scope);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('History deleted from this phone.')),
    );
  }
}

Future<void> powerOff(BuildContext context, BridgeController controller) async {
  final confirmed = await showLossSheet(
    context,
    title: 'Power off the Bridge?',
    intro: 'The Bridge stops recording until you turn it back on.',
    bullets: const [
      'Recording stops while the Bridge is off',
      'History on this phone is kept',
    ],
    keepNote: 'Hold PRG for 1.5 seconds to turn the Bridge back on.',
    confirmLabel: 'Power off',
    destructive: false,
  );
  if (confirmed == true && context.mounted) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PowerOffScreen(controller: controller),
      ),
    );
  }
}

Future<void> factoryReset(
  BuildContext context,
  BridgeController controller,
) async {
  final confirmed = await showLossSheet(
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
  );
  if (confirmed == true && context.mounted) {
    controller.factoryReset();
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
}
