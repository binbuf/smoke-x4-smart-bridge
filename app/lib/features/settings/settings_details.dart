import 'package:flutter/material.dart';

import '../../prototype/formatters.dart';
import '../../prototype/prototype_controller.dart';
import '../../theme/app_theme.dart';
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
        final enabled = controller.canEdit;
        final controlAvailable = controller.billowsControlCapability;
        return Scaffold(
          appBar: prototypeAppBar(context, controller, 'Billows'),
          body: ListView(
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!enabled)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: InlineNotice(
                          icon: Icons.lock_outline,
                          title: 'Connect to edit',
                          message: 'The last observed Billows state is shown read-only.',
                        ),
                      ),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mode',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          SegmentedButton<BillowsMode>(
                            showSelectedIcon: false,
                            segments: [
                              const ButtonSegment(
                                value: BillowsMode.disabled,
                                label: Text('Off'),
                              ),
                              const ButtonSegment(
                                value: BillowsMode.observe,
                                label: Text('Monitor only'),
                              ),
                              ButtonSegment(
                                value: BillowsMode.control,
                                label: const Text('Control'),
                                enabled: controlAvailable,
                              ),
                            ],
                            selected: {controller.billowsMode},
                            onSelectionChanged: enabled
                                ? (selection) =>
                                      controller.setBillowsMode(selection.first)
                                : null,
                          ),
                          const SizedBox(height: 10),
                          if (!controlAvailable)
                            Text(
                              'Monitor only. Set the target on the Smoke X4.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            )
                          else
                            Text(
                              'This bridge can control the fan from the app.',
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
                            label: 'Target',
                            value: controller.billowsTargetKnown
                                ? controller.tempFor(
                                    controller.billowsTargetF.toDouble(),
                                  )
                                : '— (not validated)',
                          ),
                          KeyValueRow(
                            label: 'Source',
                            value: controller.billowsSourceLabel,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Connected means Billows is linked to the Smoke X4. The fan may not be running.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (controller.billowsMode == BillowsMode.control) ...[
                      const SizedBox(height: 16),
                      SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Target temperature',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Valid range ${controller.tempFor(32)}–${controller.tempFor(572)}. The bridge controls the fan in this mode.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: Text(
                                controller.tempFor(
                                  controller.billowsTargetF.toDouble(),
                                ),
                                style: Theme.of(context).textTheme.displaySmall,
                              ),
                            ),
                            Slider(
                              value: controller.billowsTargetF.toDouble(),
                              min: 32,
                              max: 572,
                              divisions: 540,
                              label: controller.tempFor(
                                controller.billowsTargetF.toDouble(),
                              ),
                              onChanged: enabled
                                  ? (value) => controller.setBillowsTarget(
                                      value.round(),
                                    )
                                  : null,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(controller.tempFor(32)),
                                Text(controller.tempFor(572)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (controller.billowsMode == BillowsMode.observe) ...[
                      const SizedBox(height: 16),
                      InlineNotice(
                        icon: Icons.info_outline,
                        title: 'Set the target on the Smoke X4',
                        message:
                            'Monitor only. The app shows the target read-only.',
                      ),
                    ],
                    if (controller.billowsMode == BillowsMode.disabled) ...[
                      const SizedBox(height: 16),
                      InlineNotice(
                        icon: Icons.power_off,
                        title: 'Billows is off',
                        message: 'The bridge still records Billows data, but Live hides the Billows card.',
                      ),
                    ],
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
                        'No cloud, no account. Data stays on this phone and the bridge.',
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
                        text: 'The bridge scans 915/920 MHz and confirms the pairing.',
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'This clears the old radio pairing only. The bridge log, phone pairings, and settings are kept.',
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
          appBar: prototypeAppBar(context, controller, 'Phone history'),
          body: ListView(
            children: [
              ContentWidth(
                child: empty
                    ? const EmptyState(
                        icon: Icons.folder_off_outlined,
                        title: 'No phone history',
                        message: 'There is no history stored on this phone yet. The bridge records whenever it is on and synced.',
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
                                  'This data is not tied to a live bridge. It stays until you delete it.',
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
                            title: 'The bridge is not required',
                            message: 'You can review or delete this history even after forgetting the bridge or resetting it.',
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: scheme.error,
                              side: BorderSide(color: scheme.error),
                            ),
                            onPressed: () => deleteSavedData(context),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete all phone history'),
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
      title: 'Delete all phone history?',
      intro: 'This deletes every reading stored on this phone. It cannot be undone.',
      bullets: [
        '${commaInt(controller.phoneRecords)} readings',
        controller.savedDataRange,
        'The bridge is not changed and keeps recording.',
      ],
      keepNote: 'This is the only copy of the phone history.',
      confirmLabel: 'Delete ${commaInt(controller.phoneRecords)} readings',
    );
    if (confirmed == true && context.mounted) {
      controller.deleteLocalData('all');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone history deleted (simulated).')),
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
                'Recording stops while the bridge sleeps. Hold PRG for 1.5 s to turn it back on.',
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
        return 'Clear bridge log';
      case DestructiveKind.delete30:
        return 'Delete phone history older than 30 days';
      case DestructiveKind.delete90:
        return 'Delete phone history older than 90 days';
      case DestructiveKind.deleteAll:
        return 'Delete all phone history';
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
          intro: 'This removes the Bluetooth pairing for this phone. The bridge keeps recording.',
          bullets: const [
            'This phone is removed from the bridge’s paired phones.',
            'The bridge is removed from this app.',
            'Phone history stays on this phone until you delete it.',
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
          title: 'Clear bridge log?',
          intro: 'The bridge erases its rolling log. This cannot be undone on the bridge.',
          bullets: [
            '${commaInt(widget.controller.bridgeRecords)} readings in the bridge log',
            'The bridge keeps its pairings and settings',
            'Phone history is kept',
          ],
          keepNote: 'The bridge starts a new log segment.',
          confirmLabel: 'Clear bridge log',
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
              ? 'Delete all phone history?'
              : 'Delete phone history older than $scope days?',
          intro:
              'This deletes ${commaInt(count)} readings from this phone. It cannot be undone.',
          bullets: [
            'Date range: $range',
            'This does not change the bridge',
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
          title: 'Factory reset bridge?',
          intro:
              'The bridge wipes its pairings, settings, and log, then reboots.',
          bullets: const [
            'All paired phones, including this one',
            'Bridge settings and display preferences',
            'The bridge log and its clock',
            'The bridge starts advertising as new',
          ],
          keepNote: 'Phone history is kept. Delete it from Phone history on the setup screen.',
          confirmLabel: 'Factory reset bridge',
        );
        if (confirmed == true && mounted) {
          widget.controller.factoryReset();
          _openSetup();
        }
        break;
      case DestructiveKind.powerOff:
        final confirmed = await showLossSheet(
          context,
          title: 'Power off bridge?',
          intro: 'The bridge stops recording until you hold PRG for 1.5 s to wake it.',
          bullets: const [
            'Recording stops while the bridge sleeps',
            'The bridge stops recording while it is off',
            'This phone keeps its history',
          ],
          keepNote: 'Hold PRG for 1.5 s to turn the bridge back on.',
          confirmLabel: 'Power off bridge',
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
    intro: 'This removes the Bluetooth pairing for this phone. The bridge keeps recording.',
    bullets: const [
      'This phone is removed from the bridge’s paired phones.',
      'The bridge is removed from this app.',
      'Phone history stays on this phone until you delete it.',
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
    title: 'Clear bridge log?',
    intro: 'The bridge erases its rolling log. This cannot be undone on the bridge.',
    bullets: [
      '${commaInt(controller.bridgeRecords)} readings in the bridge log',
      'The bridge keeps its pairings and settings',
      'Phone history is kept',
    ],
    keepNote: 'The bridge starts a new log segment.',
    confirmLabel: 'Clear bridge log',
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
        ? 'Delete all phone history?'
        : 'Delete phone history older than $scope days?',
    intro:
        'This deletes ${commaInt(count)} readings from this phone. It cannot be undone.',
    bullets: [
      'Date range: $range',
      'This does not change the bridge',
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
    title: 'Power off bridge?',
    intro:
        'The bridge stops recording until you hold PRG for 1.5 s to wake it.',
    bullets: const [
      'Recording stops while the bridge sleeps',
      'The bridge stops recording while it is off',
      'This phone keeps its history',
    ],
    keepNote: 'Hold PRG for 1.5 s to turn the bridge back on.',
    confirmLabel: 'Power off bridge',
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
    title: 'Factory reset bridge?',
    intro: 'The bridge wipes its pairings, settings, and log, then reboots.',
    bullets: const [
      'All paired phones, including this one',
      'Bridge settings and display preferences',
      'The bridge log and its clock',
      'The bridge starts advertising as new',
    ],
    keepNote: 'Phone history is kept. Delete it from Phone history on the setup screen.',
    confirmLabel: 'Factory reset bridge',
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
