import 'dart:async';

import 'package:flutter/material.dart';

import '../../prototype/formatters.dart';
import '../../app/bridge_controller.dart';
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

  final BridgeController controller;
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

  BridgeController get controller => widget.controller;

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
          appBar: prototypeAppBar(context, controller, 'Set up'),
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
          title: 'Connect your Bridge',
          message: 'Power it on. Press PRG to wake the screen. If the Bridge is off, hold PRG for 1.5 seconds to turn it on.',
          primaryLabel: 'Find bridge',
          onPrimary: () => _go(SetupStep.scanning),
          secondaryLabel: controller.hasSavedData
              ? 'View history on this phone'
              : null,
          onSecondary: controller.hasSavedData
              ? () => _go(SetupStep.savedData)
              : null,
          child: controller.hasSavedData
              ? InlineNotice(
                  icon: Icons.folder_open_outlined,
                  title: 'History on this phone',
                  message:
                      '${commaInt(controller.phoneRecords)} readings · ${controller.savedDataRange}',
                )
              : null,
        );
      case SetupStep.permissionPrimer:
        return _SetupPage(
          icon: Icons.bluetooth,
          eyebrow: 'PERMISSION',
          title: 'Allow Bluetooth to find your Bridge',
          message: 'Android 12 and newer use Nearby devices permission. Android 11 and older require location permission for Bluetooth scanning. The permission is only needed to find your Bridge.',
          primaryLabel: 'Continue',
          onPrimary: () => _go(SetupStep.scanning),
          secondaryLabel: 'Not now',
          onSecondary: () => Navigator.of(context).pop(),
          child: const _BulletList(
            items: [
              'Nearby devices on Android 12 and newer',
              'Location on Android 7–11 — required for Bluetooth scanning',
              'The Bridge keeps recording while you set up',
            ],
          ),
        );
      case SetupStep.bluetoothOff:
        return _SetupPage(
          icon: Icons.bluetooth_disabled,
          eyebrow: 'BLUETOOTH OFF',
          title: 'Bluetooth is off',
          message: 'Turn Bluetooth on so the app can find your Bridge. The Bridge keeps recording while you do.',
          primaryLabel: 'Open Bluetooth settings',
          onPrimary: () =>
              _simulateSettings(context, 'Opening Bluetooth settings.'),
          secondaryLabel: 'Check again',
          onSecondary: () => _go(SetupStep.scanning),
        );
      case SetupStep.permissionDenied:
        return _SetupPage(
          icon: Icons.lock_outline,
          eyebrow: 'PERMISSION',
          title: 'Bluetooth permission needed',
          message:
              'The app needs Nearby devices permission to scan for the Bridge.',
          primaryLabel: 'Grant permission',
          onPrimary: () => _go(SetupStep.scanning),
          secondaryLabel: 'Open app settings',
          onSecondary: () =>
              _simulateSettings(context, 'Opening app settings.'),
        );
      case SetupStep.permissionBlocked:
        return _SetupPage(
          icon: Icons.lock,
          eyebrow: 'BLOCKED',
          title: 'Bluetooth permission is blocked',
          message: 'Enable Nearby devices permission in Android settings, then come back.',
          primaryLabel: 'Open app settings',
          onPrimary: () => _simulateSettings(context, 'Opening app settings.'),
          secondaryLabel: 'Back',
          onSecondary: () => _go(SetupStep.noBridge),
        );
      case SetupStep.unsupportedPhone:
        return _SetupPage(
          icon: Icons.phonelink_erase,
          eyebrow: 'UNSUPPORTED',
          title: 'This phone doesn’t support Bluetooth LE',
          message: 'Try a different Android phone. The Bridge itself is unchanged and keeps recording.',
          primaryLabel: 'Close',
          onPrimary: () => Navigator.of(context).pop(),
          secondaryLabel: controller.hasSavedData
              ? 'View history on this phone'
              : null,
          onSecondary: controller.hasSavedData
              ? () => _go(SetupStep.savedData)
              : null,
        );
      case SetupStep.scanning:
        return _SetupPage(
          icon: Icons.radar,
          eyebrow: 'SCANNING',
          title: 'Looking for your Bridge…',
          message: 'Scanning stops after 10 seconds. We’ll check your last Bridge first.',
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
          title: 'No Bridge found',
          message: 'Make sure it’s on and within about 10 meters (30 feet). If it’s off, hold PRG for 1.5 seconds to turn it on.',
          primaryLabel: 'Try again',
          onPrimary: () => _go(SetupStep.scanning),
          secondaryLabel: 'Open Bluetooth settings',
          onSecondary: () =>
              _simulateSettings(context, 'Opening Bluetooth settings.'),
          footer: controller.hasSavedData
              ? TextButton(
                  onPressed: () => _go(SetupStep.savedData),
                  child: const Text('View history on this phone'),
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
          eyebrow: 'APP UPDATE REQUIRED',
          title: 'Update the app to use this Bridge',
          message: 'Install the latest version, then try again. The Bridge hasn’t been changed.',
          primaryLabel: 'Update app',
          onPrimary: () => _simulateSettings(context, 'Opening the app store.'),
          secondaryLabel: 'Close',
          onSecondary: () => Navigator.of(context).pop(),
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
          title: 'The code didn’t match',
          message: 'Try again. If it fails twice, forget the old pairing in Android settings and pair again.',
          primaryLabel: 'Try again',
          onPrimary: () => _go(SetupStep.passkey),
          secondaryLabel: 'Open Android settings',
          onSecondary: () =>
              _simulateSettings(context, 'Opening Bluetooth settings.'),
        );
      case SetupStep.bondTimeout:
        return _SetupPage(
          icon: Icons.notifications_off_outlined,
          eyebrow: 'PAIRING FAILED',
          title: 'No prompt appeared',
          message: 'Open your notifications and look for the Android pairing request, then try again.',
          primaryLabel: 'Try again',
          onPrimary: () => _go(SetupStep.passkey),
          secondaryLabel: 'Open Bluetooth settings',
          onSecondary: () =>
              _simulateSettings(context, 'Opening Bluetooth settings.'),
        );
      case SetupStep.bondStale:
        return _SetupPage(
          icon: Icons.link_off,
          eyebrow: 'PAIRING OUT OF DATE',
          title: 'This phone’s pairing is out of date',
          message: 'The Bridge was reset, so the old pairing no longer works. Forget the old pairing, then pair again.',
          primaryLabel: 'Forget and re-pair',
          onPrimary: () => _go(SetupStep.passkey),
          secondaryLabel: 'Cancel',
          onSecondary: () => _go(SetupStep.results),
        );
      case SetupStep.bondStoreFull:
        return _SetupPage(
          icon: Icons.people_outline,
          eyebrow: 'PHONE LIST FULL',
          title: 'This Bridge already has 4 phones paired',
          message: 'Open the app on a phone that’s already paired and choose Forget this phone. If none is available, the Bridge needs a USB reset.',
          primaryLabel: 'Try again',
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

  final BridgeController controller;
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
                'Your last Bridge is shown first.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _DeviceRow(
                name: 'SmokeX4-A4F2',
                detail: 'P4 225°F · 87%',
                rssi: 'Good signal',
                remembered: true,
                onTap: onSelect,
              ),
              const SizedBox(height: 10),
              _DeviceRow(
                name: 'SmokeX4-B91C',
                detail: 'P4 180°F · 64%',
                rssi: 'Weak signal',
                onTap: onSelect,
              ),
              const SizedBox(height: 10),
              _DeviceRow(
                name: 'SmokeX4-LEGACY',
                detail: 'Requires a newer app',
                rssi: 'Fair signal',
                warning: true,
                onTap: onProtocolMismatch,
              ),
              const SizedBox(height: 22),
              if (controller.hasSavedData)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_open_outlined),
                    title: const Text('History on this phone'),
                    subtitle: Text(
                      '${commaInt(controller.phoneRecords)} readings · ${controller.savedDataRange}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: onSavedData,
                  ),
                ),
              const SizedBox(height: 18),
              Text(
                'Scanning stops after 10 seconds. If your Bridge doesn’t appear, try again or open Bluetooth settings.',
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
              Pill(label: 'Last used', color: StatusColors.live(context)),
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
                'Pair with the Bridge',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              Text(
                'Enter the 6-digit code shown on the Bridge screen in the Android prompt.',
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 22),
              Text(
                'Look at the Bridge screen',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
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
                'Example: the code appears on the Bridge screen. Only the Bridge screen shows the real code.',
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
                'Enter the code shown on the Bridge when Android asks for it.',
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
                      _BondStep(label: 'Connecting to the Bridge', done: true),
                      _BondStep(label: 'Checking the code', active: true),
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

  final BridgeController controller;
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
                'Your latest readings are ready. Older readings will load in the background.',
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
                        '${controller.syncProgressPercent}% · last 24 hours',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 14),
                      const _SyncStep(label: 'Time set', done: true),
                      const _SyncStep(
                        label: 'Loading the last 24 hours',
                        active: true,
                      ),
                      const _SyncStep(label: 'Loading older readings'),
                      const _SyncStep(label: 'Live view ready'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onContinue,
                  child: const Text('View live readings'),
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

  final BridgeController controller;
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
                'History on this phone',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'History on this phone is separate from the Bridge. It is never deleted automatically.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
              ),
              const SizedBox(height: 20),
              if (empty)
                const EmptyState(
                  icon: Icons.folder_off_outlined,
                  title: 'No history on this phone',
                  message: 'There is no history on this phone yet. The Bridge records whenever it’s on and paired with the Smoke X4.',
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
                        label: 'Storage used',
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
                          label: const Text('Delete history from this phone…'),
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
                  child: const Text('Back'),
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
      title: 'Delete all history from this phone?',
      intro: 'This deletes every reading stored on this phone. It can’t be undone.',
      bullets: [
        '${commaInt(controller.phoneRecords)} readings',
        controller.savedDataRange,
        'The Bridge isn’t changed and keeps recording.',
      ],
      keepNote: 'This is the only copy of the history on this phone.',
      confirmLabel: 'Delete ${commaInt(controller.phoneRecords)} readings',
    );
    if (confirmed == true && context.mounted) {
      controller.deleteLocalData('all');
    }
  }
}
