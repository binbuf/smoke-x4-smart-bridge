import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'lab_gate.dart';
import '../features/setup/setup_screen.dart';
import '../features/shell/app_shell.dart';
import '../theme/app_theme.dart';
import 'bridge_controller.dart';

/// The production app widget: the approved Material 3 shell, driven by
/// [BridgeController].
class SmokeBridgeApp extends StatefulWidget {
  const SmokeBridgeApp({
    super.key,
    required this.controller,
    this.enableExperimentalLab = experimentalLabEnabled,
  });

  final BridgeController controller;
  final bool enableExperimentalLab;

  @override
  State<SmokeBridgeApp> createState() => _SmokeBridgeAppState();
}

class _SmokeBridgeAppState extends State<SmokeBridgeApp>
    with WidgetsBindingObserver {
  bool _alarmDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onControllerChanged);
    _syncPlatformFormatting();
  }

  void _onControllerChanged() {
    if (!mounted || _alarmDialogOpen) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (!widget.controller.consumeAlarmPopup()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _showAlarmDialog());
  }

  Future<void> _showAlarmDialog() async {
    if (!mounted || _alarmDialogOpen) return;
    final alarm = widget.controller.alarmView;
    if (alarm == null) return;
    _alarmDialogOpen = true;
    final acknowledge = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.notifications_active,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: Text(alarm.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(alarm.summary),
              const SizedBox(height: 12),
              for (final probe in alarm.probes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'P${probe.number}  ${probe.stateLabel}  ·  '
                    'High ${probe.highLabel}  Low ${probe.lowLabel}',
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                alarm.physicalHint,
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            key: const Key('alarm.dialog.acknowledge'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Acknowledge'),
          ),
        ],
      ),
    );
    _alarmDialogOpen = false;
    if (acknowledge == true) {
      await widget.controller.acknowledgeAlarm();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPlatformFormatting();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    super.didChangeLocales(locales);
    _syncPlatformFormatting();
  }

  /// The device locale and 12/24-hour setting drive the one formatter layer.
  /// A change repaints the controller's pre-formatted view states after the
  /// frame that delivered the change.
  void _syncPlatformFormatting() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final localeName = dispatcher.locale.toLanguageTag().replaceAll('-', '_');
    Intl.defaultLocale = localeName;
    final changed = widget.controller.applyPlatformFormatting(
      localeName: localeName,
      use24Hour: dispatcher.alwaysUse24HourFormat,
    );
    if (!changed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.repaintForFormatting();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On resume: health check + forward sync, or cut a reconnect wait short.
    // No background scanning or foreground service (06 §6.3).
    if (state == AppLifecycleState.resumed) {
      widget.controller.onAppResume();
      _onControllerChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final needsSetup =
            controller.phase == ConnectionPhase.setup ||
            !controller.hasSavedBridge;
        return MaterialApp(
          title: 'Smoke X Smart Bridge',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: controller.themeMode,
          home: needsSetup
              ? SetupScreen(controller: controller)
              : AppShell(
                  controller: controller,
                  enableExperimentalLab: widget.enableExperimentalLab,
                ),
        );
      },
    );
  }
}
