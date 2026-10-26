import 'package:flutter/material.dart';

import '../../prototype/formatters.dart';
import '../../prototype/prototype_controller.dart';
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

  final PrototypeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
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
                      title: controller.isConnected
                          ? 'Read-only fan status'
                          : 'Last observed Billows state',
                      message: controller.isConnected
                          ? 'Billows is detected automatically through the Smoke X4. Its set temperature is the channel 4 set temp on the Smoke X4; the app never changes it.'
                          : 'Reconnect to refresh the channel 4 set temp from the Smoke X4.',
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
                                  'Current state',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              Pill(
                                label: controller.billowsAttachmentLabel,
                                color:
                                    controller.billowsAttachment ==
                                        BillowsAttachment.attached
                                    ? StatusColors.live(context)
                                    : StatusColors.stale(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          KeyValueRow(
                            label: 'Last seen',
                            value: controller.billowsDetected
                                ? '12s ago'
                                : controller.billowsLostThisSession
                                ? 'Earlier this session'
                                : 'Not this session',
                          ),
                          KeyValueRow(
                            label: 'CH 4 set temp',
                            value: controller.smokeXChannel4SetKnown
                                ? controller.tempFor(
                                    controller.smokeXChannel4SetF.toDouble(),
                                  )
                                : '— (not validated)',
                          ),
                          KeyValueRow(
                            label: 'Source',
                            value: controller.billowsSourceLabel,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Detected means the Smoke X4 is receiving Billows data. The target is simply the Smoke X4 channel 4 set temp, so it can be changed only on the Smoke X4. It does not mean the fan is running.',
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
                            'Billows is paired through the Smoke X4, so detection and drops sit in the same timeline as the Bridge.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          ConnectionLogList(
                            controller: controller,
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

  final PrototypeController controller;
  final VoidCallback? onOpenLab;

  @override
  Widget build(BuildContext context) {
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
                        KeyValueRow(label: 'App version', value: '0.1.0'),
                        KeyValueRow(
                          label: 'Bridge firmware',
                          value: controller.firmware,
                        ),
                        KeyValueRow(
                          label: 'Protocol',
                          value: controller.protocol,
                        ),
                        KeyValueRow(
                          label: 'Bridge ID',
                          value: controller.deviceId,
                        ),
                        KeyValueRow(
                          label: 'Bluetooth name',
                          value: 'SmokeX4-${controller.deviceId}',
                        ),
                        KeyValueRow(label: 'Model', value: 'heltec3'),
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
                        'Firmware updates are USB only in this build. There is no OTA path.',
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
                        'Smoke X protocol decoding derives from G-Two/smoke-x-receiver (MIT © 2022 G-Two). Not affiliated with or endorsed by ThermoWorks. Smoke X is a trademark of its owner.',
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

  final PrototypeController controller;

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
                        'Put the Smoke X4 in SYNC',
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
                        text: 'The Bridge scans 915/920 MHz and confirms the pairing.',
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'This clears the old radio pairing only. The Bridge log, phone pairings, and settings are kept.',
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
                        content: Text('Re-pairing started (simulated).'),
                      ),
                    );
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.sync),
                  label: const Text('Start re-pair'),
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

  final PrototypeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final empty = controller.savedDataEmpty || controller.phoneRecords == 0;
        return Scaffold(
          appBar: prototypeAppBar(context, controller, 'Device log'),
          body: ListView(
            children: [
              ContentWidth(
                child: empty
                    ? const EmptyState(
                        icon: Icons.folder_off_outlined,
                        title: 'No device log',
                        message: 'There is no history stored on this device yet. The Bridge records whenever it is on and synced.',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'On this device',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall,
                                ),
                                const SizedBox(height: 12),
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
                                const SizedBox(height: 8),
                                Text(
                                  'This data is not tied to a live Bridge. It stays until you delete it.',
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
                            title: 'The Bridge is not required',
                            message: 'You can review or delete this history even after forgetting the Bridge or resetting it.',
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: scheme.error,
                              side: BorderSide(color: scheme.error),
                            ),
                            onPressed: () => deleteSavedData(context),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete all device log readings'),
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
    final confirmed = await showLossSheet(
      context,
      title: 'Delete all device log readings?',
      intro: 'This deletes every reading stored on this device. It cannot be undone.',
      bullets: [
        '${commaInt(controller.phoneRecords)} readings',
        controller.savedDataRange,
        'The Bridge is not changed and keeps recording.',
      ],
      keepNote: 'This is the only copy of the device log.',
      confirmLabel: 'Delete ${commaInt(controller.phoneRecords)} readings',
    );
    if (confirmed == true && context.mounted) {
      controller.deleteLocalData('all');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device log deleted (simulated).')),
      );
    }
  }
}

class PowerOffScreen extends StatelessWidget {
  const PowerOffScreen({super.key, required this.controller});

  final PrototypeController controller;

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
                'Recording stops while the Bridge sleeps. Hold PRG for 1.5 s to turn it back on.',
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
                label: const Text('Simulate hold PRG to wake'),
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

  final PrototypeController controller;
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
        return 'Clear Bridge log';
      case DestructiveKind.delete30:
        return 'Delete device log older than 30 days';
      case DestructiveKind.delete90:
        return 'Delete device log older than 90 days';
      case DestructiveKind.deleteAll:
        return 'Delete all device log readings';
      case DestructiveKind.factoryReset:
        return 'Factory reset';
      case DestructiveKind.powerOff:
        return 'Power off';
    }
  }

  Future<void> _show() async {
    switch (widget.kind) {
      case DestructiveKind.forgetPhone:
        final confirmed = await showLossSheet(
          context,
          title: 'Forget this phone?',
          intro: 'This removes the Bluetooth pairing for this phone. The Bridge keeps recording.',
          bullets: const [
            'This phone is removed from the Bridge’s paired phones.',
            'The Bridge is removed from this app.',
            'Device log stays on this phone until you delete it.',
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
          title: 'Clear Bridge log?',
          intro: 'The Bridge erases its rolling log. This cannot be undone on the Bridge.',
          bullets: [
            '${commaInt(widget.controller.bridgeRecords)} readings in the Bridge log',
            'The Bridge keeps its pairings and settings',
            'Device log is kept',
          ],
          keepNote: 'The Bridge starts a new log segment.',
          confirmLabel: 'Clear Bridge log',
        );
        if (confirmed == true && mounted) {
          widget.controller.clearBridgeHistory();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bridge log cleared (simulated).')),
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
          _ => widget.controller.phoneRecords,
        };
        final range = switch (scope) {
          '30' => 'Sep 25 – Oct 24, 2026',
          '90' => 'Jul 27 – Oct 24, 2026',
          _ => widget.controller.savedDataRange,
        };
        final confirmed = await showLossSheet(
          context,
          title: scope == 'all'
              ? 'Delete all device log readings?'
              : 'Delete device log older than $scope days?',
          intro:
              'This deletes ${commaInt(count)} readings from this phone. It cannot be undone.',
          bullets: [
            'Date range: $range',
            'This does not change the Bridge',
            'No data is deleted automatically',
          ],
          confirmLabel: 'Delete ${commaInt(count)} readings',
        );
        if (confirmed == true && mounted) {
          widget.controller.deleteLocalData(scope);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Data deleted (simulated).')),
          );
        }
        break;
      case DestructiveKind.factoryReset:
        final confirmed = await showLossSheet(
          context,
          title: 'Factory reset Bridge?',
          intro:
              'The Bridge wipes its pairings, settings, and log, then reboots.',
          bullets: const [
            'All paired phones, including this one',
            'Bridge settings and display preferences',
            'The Bridge log and its clock',
            'The Bridge starts advertising as new',
          ],
          keepNote: 'Device log is kept. Delete it from Device log on the setup screen.',
          confirmLabel: 'Factory reset Bridge',
        );
        if (confirmed == true && mounted) {
          widget.controller.factoryReset();
          _openSetup();
        }
        break;
      case DestructiveKind.powerOff:
        final confirmed = await showLossSheet(
          context,
          title: 'Power off Bridge?',
          intro: 'The Bridge stops recording until you hold PRG for 1.5 s to wake it.',
          bullets: const [
            'Recording stops while the Bridge sleeps',
            'The Bridge stops recording while it is off',
            'This phone keeps its history',
          ],
          keepNote: 'Hold PRG for 1.5 s to turn the Bridge back on.',
          confirmLabel: 'Power off Bridge',
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
  PrototypeController controller,
) async {
  final confirmed = await showLossSheet(
    context,
    title: 'Forget this phone?',
    intro: 'This removes the Bluetooth pairing for this phone. The Bridge keeps recording.',
    bullets: const [
      'This phone is removed from the Bridge’s paired phones.',
      'The Bridge is removed from this app.',
      'Device log stays on this phone until you delete it.',
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
  PrototypeController controller,
) async {
  final confirmed = await showLossSheet(
    context,
    title: 'Clear Bridge log?',
    intro: 'The Bridge erases its rolling log. This cannot be undone on the Bridge.',
    bullets: [
      '${commaInt(controller.bridgeRecords)} readings in the Bridge log',
      'The Bridge keeps its pairings and settings',
      'Device log is kept',
    ],
    keepNote: 'The Bridge starts a new log segment.',
    confirmLabel: 'Clear Bridge log',
  );
  if (confirmed == true && context.mounted) {
    controller.clearBridgeHistory();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bridge log cleared (simulated).')),
    );
  }
}

Future<void> deleteLocalData(
  BuildContext context,
  PrototypeController controller,
  String scope,
) async {
  final count = switch (scope) {
    '30' => 12430,
    '90' => 128430,
    _ => controller.phoneRecords,
  };
  final range = switch (scope) {
    '30' => 'Sep 25 – Oct 24, 2026',
    '90' => 'Jul 27 – Oct 24, 2026',
    _ => controller.savedDataRange,
  };
  final confirmed = await showLossSheet(
    context,
    title: scope == 'all'
        ? 'Delete all device log readings?'
        : 'Delete device log older than $scope days?',
    intro:
        'This deletes ${commaInt(count)} readings from this phone. It cannot be undone.',
    bullets: [
      'Date range: $range',
      'This does not change the Bridge',
      'No data is deleted automatically',
    ],
    confirmLabel: 'Delete ${commaInt(count)} readings',
  );
  if (confirmed == true && context.mounted) {
    controller.deleteLocalData(scope);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Data deleted (simulated).')));
  }
}

Future<void> powerOff(
  BuildContext context,
  PrototypeController controller,
) async {
  final confirmed = await showLossSheet(
    context,
    title: 'Power off Bridge?',
    intro:
        'The Bridge stops recording until you hold PRG for 1.5 s to wake it.',
    bullets: const [
      'Recording stops while the Bridge sleeps',
      'The Bridge stops recording while it is off',
      'This phone keeps its history',
    ],
    keepNote: 'Hold PRG for 1.5 s to turn the Bridge back on.',
    confirmLabel: 'Power off Bridge',
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
  PrototypeController controller,
) async {
  final confirmed = await showLossSheet(
    context,
    title: 'Factory reset Bridge?',
    intro: 'The Bridge wipes its pairings, settings, and log, then reboots.',
    bullets: const [
      'All paired phones, including this one',
      'Bridge settings and display preferences',
      'The Bridge log and its clock',
      'The Bridge starts advertising as new',
    ],
    keepNote:
        'Device log is kept. Delete it from Device log on the setup screen.',
    confirmLabel: 'Factory reset Bridge',
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
