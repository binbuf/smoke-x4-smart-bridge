import 'dart:async';

import 'package:flutter/material.dart';

import '../../prototype/formatters.dart';
import '../../prototype/prototype_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/prototype_app_bar.dart';
import '../../widgets/prototype_widgets.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.controller,
    this.initialStep = SetupStep.noBridge,
    this.autoAdvance = true,
  });

  final PrototypeController controller;
  final SetupStep initialStep;

  /// Product review uses a simulated 1.2 s scan and 1.6 s pairing. The
  /// scenario lab sets this to false so every state can be inspected.
  final bool autoAdvance;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late SetupStep _step;
  Timer? _autoTimer;

  PrototypeController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleAutoAdvance());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  void _go(SetupStep step) {
    _autoTimer?.cancel();
    setState(() => _step = step);
    _scheduleAutoAdvance();
  }

  void _scheduleAutoAdvance() {
    _autoTimer?.cancel();
    if (!widget.autoAdvance) return;
    if (_step == SetupStep.scanning) {
      _autoTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted && _step == SetupStep.scanning) {
          setState(() => _step = SetupStep.results);
        }
      });
    } else if (_step == SetupStep.bonding) {
      _autoTimer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted && _step == SetupStep.bonding) {
          setState(() => _step = SetupStep.firstSync);
        }
      });
    }
  }

  void _finish() {
    controller.completeSetup();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: prototypeAppBar(context, controller, 'Connect bridge'),
          body: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: KeyedSubtree(key: ValueKey(_step), child: _bodyFor(_step)),
            ),
          ),
        );
      },
    );
  }

  Widget _bodyFor(SetupStep step) {
    switch (step) {
      case SetupStep.noBridge:
        return _SetupPage(
          icon: Icons.bluetooth_searching,
          eyebrow: 'SETUP',
          title: 'Connect your bridge',
          message:
              'Power it on. If the screen is off, hold PRG for 1.5 seconds.',
          primaryLabel: 'Find bridge',
          onPrimary: () => _go(SetupStep.scanning),
          secondaryLabel: controller.hasSavedData ? 'View phone history' : null,
          onSecondary: controller.hasSavedData
              ? () => _go(SetupStep.savedData)
              : null,
          child: controller.hasSavedData
              ? InlineNotice(
                  icon: Icons.folder_open_outlined,
                  title: 'Phone history',
                  message:
                      '${commaInt(controller.phoneRecords)} readings · ${controller.savedDataRange}',
                )
              : null,
        );
      case SetupStep.permissionPrimer:
        return _SetupPage(
          icon: Icons.bluetooth,
          eyebrow: 'PERMISSION',
          title: 'Allow Bluetooth to find your bridge',
          message: 'The app uses Bluetooth only to find and connect to your bridge. It does not use location, and there is no cloud account.',
          primaryLabel: 'Allow Bluetooth',
          onPrimary: () => _go(SetupStep.scanning),
          secondaryLabel: 'Not now',
          onSecondary: () => Navigator.of(context).pop(),
          child: const _BulletList(
            items: [
              'Nearby devices permission on Android 12+',
              'No location is read or stored',
              'The bridge keeps recording while you set up',
            ],
          ),
        );
      case SetupStep.bluetoothOff:
        return _SetupPage(
          icon: Icons.bluetooth_disabled,
          eyebrow: 'BLUETOOTH OFF',
          title: 'Bluetooth is off.',
          message: 'Turn Bluetooth on so the app can find your bridge. The bridge keeps recording while you do.',
          primaryLabel: 'Open Bluetooth settings',
          onPrimary: () => _simulateSettings(
            context,
            'Android Bluetooth settings would open here.',
          ),
          secondaryLabel: 'Check again',
          onSecondary: () => _go(SetupStep.scanning),
        );
      case SetupStep.permissionDenied:
        return _SetupPage(
          icon: Icons.lock_outline,
          eyebrow: 'PERMISSION',
          title: 'Bluetooth permission needed.',
          message:
              'The app needs Nearby devices permission to scan for the bridge.',
          primaryLabel: 'Grant permission',
          onPrimary: () => _go(SetupStep.scanning),
          secondaryLabel: 'Open settings',
          onSecondary: () => _simulateSettings(
            context,
            'Android app settings would open here.',
          ),
        );
      case SetupStep.permissionBlocked:
        return _SetupPage(
          icon: Icons.lock,
          eyebrow: 'BLOCKED',
          title: 'Bluetooth permission is blocked.',
          message: 'Enable Nearby devices permission in Android settings, then come back.',
          primaryLabel: 'Open app settings',
          onPrimary: () => _simulateSettings(
            context,
            'Android app settings would open here.',
          ),
          secondaryLabel: 'Back',
          onSecondary: () => _go(SetupStep.noBridge),
        );
      case SetupStep.unsupportedPhone:
        return _SetupPage(
          icon: Icons.phonelink_erase,
          eyebrow: 'UNSUPPORTED',
          title: 'This phone can’t scan for Bluetooth LE.',
          message: 'Try a different Android phone. The bridge itself is unchanged and keeps recording.',
          primaryLabel: 'Close',
          onPrimary: () => Navigator.of(context).pop(),
        );
      case SetupStep.scanning:
        return _SetupPage(
          icon: Icons.radar,
          eyebrow: 'SCANNING',
          title: 'Looking for your bridge…',
          message: 'Scanning stops after 10 seconds. Your remembered bridge is preferred.',
          primaryLabel: 'Cancel',
          onPrimary: () => _go(SetupStep.noBridge),
          child: const Column(
            children: [SizedBox(height: 8), CircularProgressIndicator()],
          ),
        );
      case SetupStep.noResults:
        return _SetupPage(
          icon: Icons.search_off,
          eyebrow: 'NO RESULTS',
          title: 'No bridge found.',
          message: 'Make sure it is on, then hold PRG for 1.5 s if it is asleep. Bluetooth range is usually about 10 m indoors.',
          primaryLabel: 'Retry',
          onPrimary: () => _go(SetupStep.scanning),
          secondaryLabel: 'Open Bluetooth settings',
          onSecondary: () => _simulateSettings(
            context,
            'Android Bluetooth settings would open here.',
          ),
          footer: controller.hasSavedData
              ? TextButton(
                  onPressed: () => _go(SetupStep.savedData),
                  child: const Text('View phone history instead'),
                )
              : null,
        );
      case SetupStep.results:
        return _ScanResults(
          controller: controller,
          onSelect: () => _go(SetupStep.passkey),
          onProtocolMismatch: () => _go(SetupStep.protocolMismatch),
          onRescan: () => _go(SetupStep.scanning),
          onSavedData: () => _go(SetupStep.savedData),
        );
      case SetupStep.protocolMismatch:
        return _SetupPage(
          icon: Icons.system_update_alt,
          eyebrow: 'APP UPDATE NEEDED',
          title: 'This bridge needs a newer app.',
          message: 'Update the app before pairing. The bridge is not changed.',
          primaryLabel: 'Close',
          onPrimary: () => Navigator.of(context).pop(),
        );
      case SetupStep.passkey:
        return _PasskeyPage(
          onPair: () => _go(SetupStep.bonding),
          onCancel: () => _go(SetupStep.results),
        );
      case SetupStep.bonding:
        return const _BondingPage();
      case SetupStep.bondWrongCode:
        return _SetupPage(
          icon: Icons.pin_outlined,
          eyebrow: 'PAIRING FAILED',
          title: 'The code didn’t match.',
          message: 'Try again. After two failures, remove the old pairing in Android settings and pair again.',
          primaryLabel: 'Try again',
          onPrimary: () => _go(SetupStep.passkey),
          secondaryLabel: 'Open Bluetooth settings',
          onSecondary: () => _simulateSettings(
            context,
            'Android Bluetooth settings would open here.',
          ),
        );
      case SetupStep.bondTimeout:
        return _SetupPage(
          icon: Icons.notifications_off_outlined,
          eyebrow: 'PAIRING FAILED',
          title: 'No prompt appeared.',
          message: 'Check the notification shade for the Android pairing prompt, then try again.',
          primaryLabel: 'Retry',
          onPrimary: () => _go(SetupStep.passkey),
          secondaryLabel: 'Open Bluetooth settings',
          onSecondary: () => _simulateSettings(
            context,
            'Android Bluetooth settings would open here.',
          ),
        );
      case SetupStep.bondStale:
        return _SetupPage(
          icon: Icons.link_off,
          eyebrow: 'PAIRING OUT OF DATE',
          title: 'This phone’s pairing is out of date.',
          message: 'The bridge was reset, so the old pairing no longer works. Remove it and pair again. The bridge’s new identity is safe to trust.',
          primaryLabel: 'Forget pairing and re-pair',
          onPrimary: () => _go(SetupStep.passkey),
          secondaryLabel: 'Cancel',
          onSecondary: () => _go(SetupStep.results),
        );
      case SetupStep.bondStoreFull:
        return _SetupPage(
          icon: Icons.people_outline,
          eyebrow: 'PHONE LIST FULL',
          title: 'This bridge already has 4 phones paired.',
          message: 'Forget one phone from a paired phone, then try again. The app checks this before showing the Android prompt.',
          primaryLabel: 'I’ve freed a slot',
          onPrimary: () => _go(SetupStep.passkey),
          secondaryLabel: 'Cancel',
          onSecondary: () => _go(SetupStep.results),
        );
      case SetupStep.firstSync:
        return _FirstSyncPage(controller: controller, onContinue: _finish);
      case SetupStep.savedData:
        return _SavedDataStep(
          controller: controller,
          onBack: () => _go(SetupStep.noBridge),
        );
    }
  }

  void _simulateSettings(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SetupPage extends StatelessWidget {
  const _SetupPage({
    required this.icon,
    required this.title,
    required this.message,
    this.eyebrow,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.child,
    this.footer,
  });

  final IconData icon;
  final String? eyebrow;
  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final Widget? child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        ContentWidth(
          maxWidth: 560,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 30, color: scheme.primary),
              ),
              if (eyebrow != null) ...[
                const SizedBox(height: 22),
                Text(
                  eyebrow!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 10),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
              ),
              if (child != null) ...[const SizedBox(height: 22), child!],
              const SizedBox(height: 28),
              if (primaryLabel != null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onPrimary,
                    child: Text(primaryLabel!),
                  ),
                ),
              if (secondaryLabel != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onSecondary,
                    child: Text(secondaryLabel!),
                  ),
                ),
              ],
              if (footer != null) ...[
                const SizedBox(height: 8),
                Center(child: footer!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 17,
                    color: StatusColors.live(context),
                  ),
                  const SizedBox(width: 9),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ScanResults extends StatelessWidget {
  const _ScanResults({
    required this.controller,
    required this.onSelect,
    required this.onProtocolMismatch,
    required this.onRescan,
    required this.onSavedData,
  });

  final PrototypeController controller;
  final VoidCallback onSelect;
  final VoidCallback onProtocolMismatch;
  final VoidCallback onRescan;
  final VoidCallback onSavedData;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        ContentWidth(
          maxWidth: 560,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Nearby bridges',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onRescan,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Rescan'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Remembered bridges are shown first.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _DeviceRow(
                name: 'SmokeX4-A4F2',
                detail: 'P4 225 °F · 87%',
                rssi: '-71 dBm',
                remembered: true,
                onTap: onSelect,
              ),
              const SizedBox(height: 10),
              _DeviceRow(
                name: 'SmokeX4-B91C',
                detail: 'P4 180 °F · 64%',
                rssi: '-88 dBm',
                onTap: onSelect,
              ),
              const SizedBox(height: 10),
              _DeviceRow(
                name: 'SmokeX4-LEGACY',
                detail: 'Protocol 2.x · needs a newer app',
                rssi: '-82 dBm',
                warning: true,
                onTap: onProtocolMismatch,
              ),
              const SizedBox(height: 22),
              if (controller.hasSavedData)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_open_outlined),
                    title: const Text('Phone history'),
                    subtitle: Text(
                      '${commaInt(controller.phoneRecords)} readings · ${controller.savedDataRange}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: onSavedData,
                  ),
                ),
              const SizedBox(height: 18),
              Text(
                'The scan stops after 10 seconds. If nothing appears, retry or open Bluetooth settings.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.name,
    required this.detail,
    required this.rssi,
    required this.onTap,
    this.remembered = false,
    this.warning = false,
  });

  final String name;
  final String detail;
  final String rssi;
  final VoidCallback onTap;
  final bool remembered;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: (warning ? scheme.error : scheme.primary).withValues(
              alpha: 0.12,
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            warning ? Icons.warning_amber_rounded : Icons.bluetooth,
            color: warning ? scheme.error : scheme.primary,
          ),
        ),
        title: Row(
          children: [
            Flexible(child: Text(name)),
            if (remembered) ...[
              const SizedBox(width: 8),
              Pill(label: 'Remembered', color: StatusColors.live(context)),
            ],
          ],
        ),
        subtitle: Text('$detail · $rssi'),
        trailing: Icon(
          warning ? Icons.error_outline : Icons.chevron_right,
          color: warning ? scheme.error : null,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _PasskeyPage extends StatelessWidget {
  const _PasskeyPage({required this.onPair, required this.onCancel});

  final VoidCallback onPair;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        ContentWidth(
          maxWidth: 560,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.pin_outlined,
                  size: 30,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Pair with the bridge',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              Text(
                'The bridge’s screen shows a 6-digit code. Enter it in the phone’s prompt.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 22),
              Text(
                'LOOK AT THE BRIDGE OLED',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 22,
                  horizontal: 18,
                ),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: Color(0xFFE8E2D9),
                    fontFamily: 'Roboto',
                    fontSize: 13,
                    height: 1.4,
                    letterSpacing: 1.2,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  child: Column(
                    children: const [
                      Text('PAIR WITH PHONE'),
                      SizedBox(height: 10),
                      Text(
                        '418 302',
                        style: TextStyle(
                          fontSize: 30,
                          letterSpacing: 5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text('enter this code'),
                      Text('on your phone'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Android will ask for this code. The app never shows it; it is only on the bridge OLED.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onPair,
                  child: const Text('Pair'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BondingPage extends StatelessWidget {
  const _BondingPage();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        ContentWidth(
          maxWidth: 560,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 24),
              Text(
                'Pairing…',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the code shown on the bridge when Android asks for it.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: const [
                      _BondStep(label: 'Connecting to the bridge', done: true),
                      _BondStep(label: 'Pairing with the code', active: true),
                      _BondStep(label: 'Syncing recent history'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BondStep extends StatelessWidget {
  const _BondStep({
    required this.label,
    this.done = false,
    this.active = false,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: done
                ? Icon(
                    Icons.check_circle,
                    size: 18,
                    color: StatusColors.live(context),
                  )
                : active
                ? const CircularProgressIndicator(strokeWidth: 2)
                : Icon(Icons.circle_outlined, size: 18, color: scheme.outline),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirstSyncPage extends StatelessWidget {
  const _FirstSyncPage({required this.controller, required this.onContinue});

  final PrototypeController controller;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        ContentWidth(
          maxWidth: 560,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.cloud_sync_outlined,
                  size: 30,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Loading history',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              Text(
                'Recent history is ready first. Older readings continue in the background.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 22),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: controller.syncProgressPercent / 100,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${controller.syncProgressPercent}% · recent 24 hours',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 14),
                      const _SyncStep(label: 'Phone clock set', done: true),
                      const _SyncStep(
                        label: 'Reading the last 24 hours',
                        active: true,
                      ),
                      const _SyncStep(label: 'Loading older history'),
                      const _SyncStep(label: 'Live readings'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onContinue,
                  child: const Text('Start monitoring'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SyncStep extends StatelessWidget {
  const _SyncStep({
    required this.label,
    this.done = false,
    this.active = false,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: done
                ? Icon(
                    Icons.check_circle,
                    size: 18,
                    color: StatusColors.live(context),
                  )
                : active
                ? const CircularProgressIndicator(strokeWidth: 2)
                : Icon(Icons.circle_outlined, size: 18, color: scheme.outline),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedDataStep extends StatelessWidget {
  const _SavedDataStep({required this.controller, required this.onBack});

  final PrototypeController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = controller.savedDataEmpty || controller.phoneRecords == 0;
    return ListView(
      children: [
        ContentWidth(
          maxWidth: 560,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Phone history',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'History on this phone is separate from the bridge. It is never deleted automatically.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
              ),
              const SizedBox(height: 20),
              if (empty)
                const EmptyState(
                  icon: Icons.folder_off_outlined,
                  title: 'No phone history',
                  message: 'There is no history on this phone yet. The bridge records whenever it is on and synced.',
                )
              else
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: scheme.error,
                            side: BorderSide(color: scheme.error),
                          ),
                          onPressed: () => _deleteSavedData(context),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete phone history'),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onBack,
                  child: const Text('Back to setup'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _deleteSavedData(BuildContext context) async {
    final confirmed = await showLossSheet(
      context,
      title: 'Delete all phone history?',
      intro: 'This deletes every reading stored on this phone. It cannot be undone.',
      bullets: [
        '${commaInt(controller.phoneRecords)} readings',
        controller.savedDataRange,
        'The bridge is not changed and keeps recording.',
      ],
      keepNote: 'This is the only copy of the history on this phone.',
      confirmLabel: 'Delete ${commaInt(controller.phoneRecords)} readings',
    );
    if (confirmed == true && context.mounted) {
      controller.deleteLocalData('all');
    }
  }
}
