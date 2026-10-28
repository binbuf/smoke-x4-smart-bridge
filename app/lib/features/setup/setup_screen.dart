import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/formatters.dart';
import '../../app/view_state.dart';
import '../../data/ble/bridge_codecs.dart';
import '../../data/history/history_deletion.dart';
import '../../theme/app_theme.dart';
import '../../widgets/prototype_app_bar.dart';
import '../../widgets/prototype_widgets.dart';
import 'setup_flow.dart';

/// The approved setup route. Production renders it from [SetupScreen]'s real
/// flow; the Experimental lab freezes it on one state for review.
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.controller,
    this.initialStep = SetupStep.noBridge,
    this.autoAdvance = true,
    this.previewBridges,
  });

  final BridgeController controller;
  final SetupStep initialStep;

  /// The lab sets this to false. Production always runs the real flow.
  final bool autoAdvance;

  /// Lab-only sample rows for the results state.
  final List<ScannedBridge>? previewBridges;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late SetupFlow _flow;

  BridgeController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _createFlow();
  }

  @override
  void didUpdateWidget(covariant SetupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.initialStep != widget.initialStep) {
      _flow.dispose();
      _createFlow();
    }
  }

  void _createFlow() {
    final frozen =
        !widget.autoAdvance || widget.initialStep != SetupStep.noBridge;
    _flow = frozen
        ? SetupFlow.frozen(
            controller: widget.controller,
            step: widget.initialStep,
            bridges: widget.previewBridges,
          )
        : SetupFlow(controller: widget.controller);
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  void _finish() {
    controller.completeSetup();
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  void _close() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      _flow.backToStart();
    }
  }

  void _showSettingsHelp(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showLearnMore({required bool protocol}) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          protocol ? 'Update the app to use this Bridge' : 'This phone',
        ),
        content: Text(
          protocol
              ? 'The Bridge speaks a newer protocol than this version of the app. Install the latest app to connect. The Bridge hasn’t been changed and keeps recording.'
              : 'Smoke X4 Smart Bridge needs a phone with Bluetooth LE. This phone cannot scan for the Bridge. The Bridge itself is unchanged and keeps recording.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return ListenableBuilder(
          listenable: _flow,
          builder: (context, _) {
            final view = controller.setupView;
            return Scaffold(
              appBar: prototypeAppBar(context, controller, 'Set up'),
              body: SafeArea(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: KeyedSubtree(
                    key: ValueKey(_flow.step),
                    child: _bodyFor(_flow.step, view),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _bodyFor(SetupStep step, SetupViewState view) {
    switch (step) {
      case SetupStep.noBridge:
        return _SetupPage(
          icon: Icons.bluetooth_searching,
          title: 'Connect your Bridge',
          message: 'Power it on. Press PRG to wake the screen. If the Bridge is off, hold PRG for 1.5 seconds to turn it on.',
          primaryLabel: 'Find bridge',
          onPrimary: _flow.findBridge,
          secondaryLabel: view.hasSavedData
              ? 'View history on this phone'
              : null,
          onSecondary: view.hasSavedData ? _flow.showSavedData : null,
          child: view.hasSavedData || view.destructiveNotice != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (view.hasSavedData)
                      InlineNotice(
                        icon: Icons.folder_open_outlined,
                        title: 'History on this phone',
                        message: view.historyOrphaned
                            ? '${view.phoneRecordsLabel} readings · ${view.savedDataRange} · from your previous Bridge.'
                            : '${view.phoneRecordsLabel} readings · ${view.savedDataRange}',
                      ),
                    if (view.destructiveNotice != null) ...[
                      if (view.hasSavedData) const SizedBox(height: 10),
                      InlineNotice(
                        key: const Key('setup.destructiveNotice'),
                        icon: Icons.info_outline,
                        title: 'Pairing not confirmed',
                        message: view.destructiveNotice!,
                      ),
                    ],
                  ],
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
          onPrimary: _flow.requestPermissionAndScan,
          secondaryLabel: 'Not now',
          onSecondary: _flow.backToStart,
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
          onPrimary: () => _showSettingsHelp(
            'Turn Bluetooth on in Android settings, then come back.',
          ),
          secondaryLabel: 'Check again',
          onSecondary: _flow.checkAgain,
        );
      case SetupStep.permissionDenied:
        return _SetupPage(
          icon: Icons.lock_outline,
          eyebrow: 'PERMISSION',
          title: 'Bluetooth permission needed',
          message:
              'The app needs Nearby devices permission to scan for the Bridge.',
          primaryLabel: 'Grant permission',
          onPrimary: _flow.requestPermissionAndScan,
          secondaryLabel: 'Open app settings',
          onSecondary: () => _showSettingsHelp(
            'Allow Nearby devices for this app in Android settings, then come back.',
          ),
        );
      case SetupStep.permissionBlocked:
        return _SetupPage(
          icon: Icons.lock,
          eyebrow: 'BLOCKED',
          title: 'Bluetooth permission is blocked',
          message: 'Enable Nearby devices permission in Android settings, then come back.',
          primaryLabel: 'Open app settings',
          onPrimary: () => _showSettingsHelp(
            'Enable Nearby devices for this app in Android settings, then come back.',
          ),
          secondaryLabel: 'Back',
          onSecondary: _flow.backToStart,
        );
      case SetupStep.unsupportedPhone:
        return _SetupPage(
          icon: Icons.phonelink_erase,
          eyebrow: 'UNSUPPORTED',
          title: 'This phone doesn’t support Bluetooth LE',
          message: 'Try a different Android phone. The Bridge itself is unchanged and keeps recording.',
          primaryLabel: 'Close',
          onPrimary: _close,
          secondaryLabel: view.hasSavedData
              ? 'View history on this phone'
              : null,
          onSecondary: view.hasSavedData ? _flow.showSavedData : null,
          footer: TextButton(
            onPressed: () => _showLearnMore(protocol: false),
            child: const Text('Learn more'),
          ),
        );
      case SetupStep.scanning:
        return _SetupPage(
          icon: Icons.radar,
          eyebrow: 'SCANNING',
          title: 'Looking for your Bridge…',
          message: 'Scanning stops after 10 seconds. We’ll check your last Bridge first.',
          primaryLabel: 'Cancel',
          onPrimary: _flow.cancelScan,
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
          onPrimary: _flow.findBridge,
          secondaryLabel: 'Open Bluetooth settings',
          onSecondary: () => _showSettingsHelp(
            'Turn Bluetooth on in Android settings, then come back.',
          ),
          footer: view.hasSavedData
              ? TextButton(
                  onPressed: _flow.showSavedData,
                  child: const Text('View history on this phone'),
                )
              : null,
        );
      case SetupStep.connectionFailed:
        return _SetupPage(
          icon: Icons.bluetooth_disabled,
          eyebrow: 'CONNECTION FAILED',
          title: 'Couldn’t connect to the Bridge',
          message: 'The Bridge was found but the Bluetooth connection didn’t finish. Keep it nearby and try again. It keeps recording while you do.',
          primaryLabel: 'Try again',
          onPrimary: _flow.retryConnection,
          secondaryLabel: 'Find another Bridge',
          onSecondary: _flow.findBridge,
        );
      case SetupStep.results:
        return _ScanResults(
          view: view,
          flow: _flow,
          connecting: _flow.connecting,
          onSelect: _flow.select,
          onRescan: _flow.findBridge,
          onSavedData: _flow.showSavedData,
        );
      case SetupStep.protocolMismatch:
        return _SetupPage(
          icon: Icons.system_update_alt,
          eyebrow: 'APP UPDATE REQUIRED',
          title: 'Update the app to use this Bridge',
          message: 'Install the latest version, then try again. The Bridge hasn’t been changed.',
          primaryLabel: 'Update app',
          onPrimary: () => _showSettingsHelp('Open your app store to update.'),
          secondaryLabel: view.hasSavedData
              ? 'View history on this phone'
              : null,
          onSecondary: view.hasSavedData ? _flow.showSavedData : null,
          footer: Wrap(
            spacing: 6,
            children: [
              TextButton(
                onPressed: () => _showLearnMore(protocol: true),
                child: const Text('Learn more'),
              ),
              TextButton(
                onPressed: _flow.backToStart,
                child: const Text('Back'),
              ),
            ],
          ),
        );
      case SetupStep.passkey:
        return _PasskeyPage(onPair: _flow.pair, onCancel: _flow.backToStart);
      case SetupStep.bonding:
        return _BondingPage(progress: _flow.isFrozen ? 1 : _flow.bondProgress);
      case SetupStep.bondWrongCode:
        final repeated = _flow.wrongCodeFailures >= 2;
        return _SetupPage(
          icon: Icons.pin_outlined,
          eyebrow: 'PAIRING FAILED',
          title: 'The code didn’t match',
          message: repeated
              ? 'Remove this Bridge’s pairing in Android settings, then try again.'
              : 'Check the Bridge screen and enter the 6-digit code in the Android prompt.',
          primaryLabel: repeated ? 'Open Android settings' : 'Try again',
          onPrimary: repeated
              ? () => _showSettingsHelp(
                  'Remove the pairing for this Bridge in Android settings, then try again.',
                )
              : _flow.pair,
          secondaryLabel: repeated ? 'Try again' : null,
          onSecondary: repeated ? _flow.pair : null,
        );
      case SetupStep.bondTimeout:
        return _SetupPage(
          icon: Icons.notifications_off_outlined,
          eyebrow: 'PAIRING FAILED',
          title: 'No prompt appeared',
          message: 'Open your notifications and look for the Android pairing request, then try again.',
          primaryLabel: 'Try again',
          onPrimary: _flow.pair,
          secondaryLabel: 'Open Bluetooth settings',
          onSecondary: () => _showSettingsHelp(
            'Open Android settings to check Bluetooth, then come back.',
          ),
        );
      case SetupStep.bondStale:
        return _SetupPage(
          icon: Icons.link_off,
          eyebrow: 'PAIRING OUT OF DATE',
          title: 'This phone’s pairing is out of date',
          message: 'The Bridge was reset, so the old pairing no longer works. Forget the old pairing, then pair again.',
          primaryLabel: 'Forget and re-pair',
          onPrimary: _flow.forgetAndRepair,
          secondaryLabel: 'Cancel',
          onSecondary: _flow.backToStart,
        );
      case SetupStep.bondStoreFull:
        return _SetupPage(
          icon: Icons.people_outline,
          eyebrow: 'PHONE LIST FULL',
          title: 'This Bridge already has 4 phones paired',
          message: 'Open the app on a phone that’s already paired and choose Forget this phone. If none is available, the Bridge needs a USB reset.',
          primaryLabel: 'Try again',
          onPrimary: _flow.findBridge,
          secondaryLabel: 'Cancel',
          onSecondary: _flow.backToStart,
        );
      case SetupStep.firstSync:
        return _FirstSyncPage(view: view, onContinue: _finish);
      case SetupStep.savedData:
        return _SavedDataStep(
          view: view,
          controller: controller,
          onBack: _flow.backToStart,
        );
    }
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
    required this.view,
    required this.flow,
    required this.connecting,
    required this.onSelect,
    required this.onRescan,
    required this.onSavedData,
  });

  final SetupViewState view;
  final SetupFlow flow;
  final bool connecting;
  final ValueChanged<ScannedBridge> onSelect;
  final VoidCallback onRescan;
  final VoidCallback onSavedData;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bridges = flow.bridges;
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
                    onPressed: connecting ? null : onRescan,
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
              if (connecting) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 3),
              ],
              const SizedBox(height: 16),
              if (bridges.isEmpty)
                Text(
                  'Looking for your Bridge…',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                )
              else
                for (final bridge in bridges) ...[
                  _DeviceRow(
                    key: ValueKey('setup.result.${bridge.id}'),
                    bridge: bridge,
                    remembered: flow.isRemembered(bridge),
                    onTap: connecting ? null : () => onSelect(bridge),
                  ),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 12),
              if (view.hasSavedData)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_open_outlined),
                    title: const Text('History on this phone'),
                    subtitle: Text(
                      '${view.phoneRecordsLabel} readings · ${view.savedDataRange}',
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
    super.key,
    required this.bridge,
    required this.remembered,
    required this.onTap,
  });

  final ScannedBridge bridge;
  final bool remembered;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final warning = bridge.requiresNewerApp;
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
            Flexible(child: Text(bridge.name)),
            if (remembered) ...[
              const SizedBox(width: 8),
              Pill(label: 'Last used', color: StatusColors.live(context)),
            ],
          ],
        ),
        subtitle: Text(bridge.detail),
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
  const _BondingPage({required this.progress});

  /// 0 connecting, 1 checking, 2 syncing, 3 done.
  final int progress;

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
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _BondStep(
                        label: 'Connecting to the Bridge',
                        done: progress > 0,
                        active: progress == 0,
                      ),
                      _BondStep(
                        label: 'Checking the code',
                        done: progress > 1,
                        active: progress == 1,
                      ),
                      _BondStep(
                        label: 'Syncing recent history',
                        done: progress > 2,
                        active: progress == 2,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Keep the Bridge nearby while it finishes.',
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
  const _FirstSyncPage({required this.view, required this.onContinue});

  final SetupViewState view;
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
                view.syncComplete
                    ? 'Your latest readings are ready. Older readings will load in the background.'
                    : 'Loading the latest readings from the Bridge. Keep it nearby.',
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
                        value: view.syncProgressPercent / 100,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${view.syncProgressLabel} · last 15 minutes',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 14),
                      const _SyncStep(label: 'Time set', done: true),
                      _SyncStep(
                        label: 'Loading recent readings',
                        done: view.syncComplete,
                        active: !view.syncComplete,
                      ),
                      // V0 loads the recent window only. This step becomes an
                      // active background task on Live in T39-T41.
                      const _SyncStep(label: 'Loading older readings'),
                      _SyncStep(
                        label: 'Live view ready',
                        done: view.syncComplete,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Stay here for the recent pass. Once it is done the user can
              // enter Live; any older-history backfill continues there in the
              // existing sync card and does not gate this button.
              if (view.syncComplete)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onContinue,
                    child: const Text('View live readings'),
                  ),
                )
              else
                Text(
                  'Keep the Bridge nearby while it finishes.',
                  textAlign: TextAlign.center,
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
  const _SavedDataStep({
    required this.view,
    required this.controller,
    required this.onBack,
  });

  final SetupViewState view;
  final BridgeController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = view.savedDataEmpty || view.phoneRecords == 0;
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
    final plan = await controller.planLocalDeletion(HistoryDeletionScope.all);
    if (!context.mounted) return;
    if (plan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no readings to delete.')),
      );
      return;
    }
    final first = plan.firstReadingAt;
    final last = plan.lastReadingAt;
    final range = first == null || last == null
        ? view.savedDataRange
        : absoluteRangeLabel(first, last);
    final confirmed = await showLossSheet(
      context,
      title: 'Delete all history from this phone?',
      intro: 'This deletes every reading stored on this phone. It can’t be undone.',
      bullets: [
        '${commaInt(plan.count)} readings',
        range,
        'The Bridge isn’t changed and keeps recording.',
      ],
      keepNote: 'This is the only copy of the history on this phone.',
      confirmLabel: 'Delete ${commaInt(plan.count)} readings',
    );
    if (confirmed == true && context.mounted) {
      await controller.applyLocalDeletion(plan);
    }
  }
}
