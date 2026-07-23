/// A8.2 — the five onboarding screens (design 08 §8.6, 05 §5.7).
///
/// **Minimal chrome, deliberately.** M4 restyles these; it does not
/// rewire them. That is only true if they contain no logic, so they do
/// not: every widget here is a projection of [WizardState] and every
/// interaction dispatches straight to [OnboardingWizard]. If a decision
/// appears in this file, it is in the wrong file.
///
/// The pair screen is the one with a real design constraint rather than a
/// cosmetic one: on Android the BLE passkey dialog is **owned by the OS**
/// and appears over the app (A6 epic flag). So the app does not host a
/// six-digit field. It points at the bridge's OLED, explains what is about
/// to pop up, and watches bond state — and it renders sensibly whether or
/// not that dialog ever appears.
library;

import 'package:flutter/material.dart';

import '../../data/transport/ble_transport.dart';
import 'wizard.dart';

/// One screen, switching on the machine's state. Five steps, plus the
/// failure edges — which are screens too, because §5.7's whole point is
/// that there is always a next step.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({required this.wizard, this.onFinished, super.key});

  final OnboardingWizard wizard;

  /// Called when the user acknowledges the final screen. Onboarding does
  /// not navigate on its own: bouncing off a success screen the moment it
  /// appears makes success indistinguishable from failure.
  final VoidCallback? onFinished;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WizardState>(
      stream: wizard.states,
      initialData: wizard.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const WizardFind();
        return Scaffold(
          appBar: AppBar(title: Text(_titleFor(state))),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: switch (state) {
                WizardFind() => FindStep(state: state, wizard: wizard),
                WizardPair() => PairStep(state: state, wizard: wizard),
                WizardBondRejected() => _Problem(
                  key: const Key('onboarding-bond-rejected'),
                  headline: 'Pairing was declined',
                  body:
                      'The code on the bridge and the code you entered did '
                      'not match, or the request timed out.',
                  actionLabel: 'Try again',
                  onAction: wizard.connectAndBond,
                  secondaryLabel: 'Start over',
                  onSecondary: wizard.restart,
                ),
                WizardRebondNeeded() => _Problem(
                  key: const Key('onboarding-rebond'),
                  headline: 'This bridge has been reset',
                  // The distinction that stops "it just won't connect"
                  // (A6.4): retrying cannot fix this, re-pairing can.
                  body:
                      'It no longer recognises this phone. Forget "Smoke '
                      'Bridge" in your Bluetooth settings, then pair again.',
                  actionLabel: 'Start over',
                  onAction: wizard.restart,
                ),
                WizardSettingTime() => const _Busy(
                  key: Key('onboarding-time'),
                  label: 'Setting the clock…',
                ),
                WizardChooseMode() => ModeStep(wizard: wizard),
                WizardPickNetwork() => NetworkStep(
                  state: state,
                  wizard: wizard,
                ),
                WizardHandoff() => HandoffStep(state: state),
                WizardRecover() => RecoverStep(state: state, wizard: wizard),
                WizardLinkLost() => _Problem(
                  key: const Key('onboarding-link-lost'),
                  headline: 'Lost the Bluetooth connection',
                  body:
                      'Move closer to the bridge and reconnect, or start '
                      'again from the beginning.',
                  actionLabel: 'Reconnect',
                  onAction: wizard.connectAndBond,
                  secondaryLabel: 'Start over',
                  onSecondary: wizard.restart,
                ),
                WizardDone() => DoneStep(state: state, onDone: onFinished),
              },
            ),
          ),
        );
      },
    );
  }

  static String _titleFor(WizardState s) => switch (s) {
    WizardFind() => 'Find your bridge',
    WizardPair() || WizardBondRejected() || WizardRebondNeeded() => 'Pair',
    WizardSettingTime() || WizardChooseMode() => 'Set up',
    WizardPickNetwork() => 'Choose a network',
    WizardHandoff() || WizardRecover() => 'Connecting',
    WizardLinkLost() => 'Disconnected',
    WizardDone() => 'Ready',
  };
}

/// Step 1 — the find list, decorated from the advertising blob so it is
/// useful before any connection exists (ble-gatt §2.3).
class FindStep extends StatelessWidget {
  const FindStep({required this.state, required this.wizard, super.key});

  final WizardFind state;
  final OnboardingWizard wizard;

  @override
  Widget build(BuildContext context) {
    if (state.found.isEmpty) {
      return _Empty(
        key: const Key('onboarding-find-empty'),
        busy: state.scanning,
        headline: state.scanning
            ? 'Looking for your bridge…'
            : 'No bridges found',
        body: state.scanning
            ? 'Make sure the bridge is powered on and nearby.'
            : 'Check that it is powered on, then scan again.',
        actionLabel: state.scanning ? null : 'Scan again',
        onAction: wizard.startScan,
      );
    }
    return ListView.builder(
      key: const Key('onboarding-find-list'),
      itemCount: state.found.length,
      itemBuilder: (context, i) {
        final b = state.found[i];
        return ListTile(
          key: Key('bridge-${b.deviceId}'),
          leading: const Icon(Icons.outdoor_grill),
          title: Text(b.name),
          subtitle: Text(_blobLine(b)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => wizard.select(b),
        );
      },
    );
  }

  /// "pit 243 °F · 4 h 12 m" — and nothing at all rather than a made-up
  /// number when the probe is detached (null, never 0).
  static String _blobLine(BridgeDiscovery b) {
    final parts = <String>[];
    if (b.pitTempF10 != null) {
      parts.add('pit ${(b.pitTempF10! / 10).round()} °F');
    }
    if (b.sessionActive && b.sessionMinutes > 0) {
      final h = b.sessionMinutes ~/ 60;
      final m = b.sessionMinutes % 60;
      parts.add(h > 0 ? '$h h $m m' : '$m m');
    }
    if (parts.isEmpty) {
      parts.add(b.paired ? 'paired, idle' : 'not paired with a Smoke X');
    }
    return parts.join(' · ');
  }
}

/// Step 2 — pair. Instructs and observes; the OS owns the dialog.
class PairStep extends StatelessWidget {
  const PairStep({required this.state, required this.wizard, super.key});

  final WizardPair state;
  final OnboardingWizard wizard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('onboarding-pair'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Look at the bridge', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          'A six-digit code is on its screen. Android will ask you for it '
          'in a moment — type the code from the screen, not from here.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        // Copy that reads correctly whether or not the OEM's dialog has
        // appeared yet — some show it instantly, some after a beat, some
        // in the notification shade.
        Text(
          state.bonding
              ? "Waiting for Android's pairing prompt. If you do not see "
                    'it, check your notifications.'
              : 'Connecting to ${state.bridge.name}…',
          key: const Key('onboarding-pair-status'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        const LinearProgressIndicator(),
        const Spacer(),
        TextButton(onPressed: wizard.restart, child: const Text('Cancel')),
      ],
    );
  }
}

/// Step 4a — hosted or joined, with the honest trade-off stated.
class ModeStep extends StatelessWidget {
  const ModeStep({required this.wizard, super.key});

  final OnboardingWizard wizard;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('onboarding-mode'),
      children: [
        _ModeCard(
          key: const Key('mode-joined'),
          title: 'Join my Wi-Fi',
          body:
              'Best range and battery life. The bridge stays reachable from '
              'anywhere in the house. Needs your Wi-Fi password.',
          recommended: true,
          onTap: () => wizard.chooseMode(BridgeMode.joined),
        ),
        const SizedBox(height: 12),
        _ModeCard(
          key: const Key('mode-hosted'),
          title: 'Let the bridge host its own network',
          body:
              'Works anywhere, with no Wi-Fi at all. Uses more battery, and '
              'your phone has to be within range of the bridge.',
          onTap: () => wizard.chooseMode(BridgeMode.hosted),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.body,
    required this.onTap,
    this.recommended = false,
    super.key,
  });

  final String title;
  final String body;
  final VoidCallback onTap;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleMedium),
                  ),
                  if (recommended)
                    Chip(
                      label: const Text('Recommended'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(body, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// Step 4b — the scan-fed picker, with manual SSID entry for hidden
/// networks and for the case where the scan comes back empty.
class NetworkStep extends StatefulWidget {
  const NetworkStep({required this.state, required this.wizard, super.key});

  final WizardPickNetwork state;
  final OnboardingWizard wizard;

  @override
  State<NetworkStep> createState() => _NetworkStepState();
}

class _NetworkStepState extends State<NetworkStep> {
  final _ssid = TextEditingController();
  final _psk = TextEditingController();
  String? _picked;

  @override
  void dispose() {
    _ssid.dispose();
    _psk.dispose();
    super.dispose();
  }

  void _choose(String ssid, int auth) {
    setState(() => _picked = ssid);
    widget.wizard.pickNetwork(ssid, auth: auth);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.state;
    return ListView(
      key: const Key('onboarding-network'),
      children: [
        if (s.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              s.error!,
              key: const Key('onboarding-network-error'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (s.scanning) const LinearProgressIndicator(),
        if (s.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'The bridge did not see any networks. Type the name in below.',
              key: const Key('onboarding-network-empty'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        // Plain selectable tiles rather than RadioGroup/RadioListTile.
        // BOARD-FOUND: with RadioGroup in this list the whole screen —
        // AppBar included — painted nothing on the test phone, with no
        // exception logged and the build method completing normally. A
        // list of tiles is the older, duller, and entirely sufficient
        // way to express "pick one", and it renders.
        for (final ap in s.networks)
          ListTile(
            key: Key('ap-${ap.ssid}'),
            title: Text(ap.ssid),
            subtitle: Text('${ap.rssi} dBm · channel ${ap.channel}'),
            leading: Icon(
              _picked == ap.ssid
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            selected: _picked == ap.ssid,
            onTap: () => _choose(ap.ssid, ap.auth),
          ),
        const Divider(),
        TextField(
          key: const Key('onboarding-ssid-field'),
          controller: _ssid,
          decoration: const InputDecoration(
            labelText: 'Or type a network name',
          ),
          onChanged: (v) => _choose(v, 3),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('onboarding-psk-field'),
          controller: _psk,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('onboarding-network-submit'),
          onPressed: _picked == null || _picked!.isEmpty
              ? null
              : () => widget.wizard.submitCredentials(_psk.text),
          child: const Text('Connect'),
        ),
      ],
    );
  }
}

/// Step 5 — the live handoff. It says what is happening, because "please
/// wait" over a 20-second transition is how a user decides it has hung.
class HandoffStep extends StatelessWidget {
  const HandoffStep({required this.state, super.key});

  final WizardHandoff state;

  @override
  Widget build(BuildContext context) => _Busy(
    key: const Key('onboarding-handoff'),
    label: switch (state.phase) {
      HandoffPhase.applying => 'Sending the settings to the bridge…',
      HandoffPhase.connecting => 'The bridge is joining the network…',
      HandoffPhase.joiningAp => "Joining the bridge's own network…",
      HandoffPhase.verifying => 'Checking that we can reach it…',
    },
  );
}

/// The escape hatch, as a screen. Bluetooth is still connected, which is
/// why both offers are real (05 §5.7).
class RecoverStep extends StatelessWidget {
  const RecoverStep({required this.state, required this.wizard, super.key});

  final WizardRecover state;
  final OnboardingWizard wizard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (headline, body) = switch (state.reason) {
      RecoveryReason.wifiFailed => (
        'That password did not work',
        'The bridge could not join the network. You can try again with a '
            'different password — no need to touch the bridge.',
      ),
      RecoveryReason.httpUnreachable => (
        'The bridge joined, but we cannot reach it',
        'It is on the network, but this phone cannot see it — often a '
            'guest network or client isolation. You can have the bridge '
            'host its own network instead.',
      ),
      RecoveryReason.configRefused => (
        'The bridge refused those settings',
        state.detail.isEmpty
            ? 'Check the network name and try again.'
            : state.detail,
      ),
    };
    return Column(
      key: const Key('onboarding-recover'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(headline, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(body, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 8),
        Text(
          'Still connected over Bluetooth.',
          key: const Key('onboarding-recover-ble'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        FilledButton(
          key: const Key('onboarding-recover-retry'),
          onPressed: wizard.retryCredentials,
          child: const Text('Try a different network'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('onboarding-recover-host'),
          onPressed: wizard.revertToHosting,
          child: const Text('Let the bridge host its own network'),
        ),
      ],
    );
  }
}

class DoneStep extends StatelessWidget {
  const DoneStep({required this.state, this.onDone, super.key});

  final WizardDone state;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('onboarding-done'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text('Your bridge is ready', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          state.mode == BridgeMode.hosted
              ? 'The bridge is hosting its own network, and your phone is '
                    'on it.'
              : 'The bridge is on your Wi-Fi.',
          style: theme.textTheme.bodyLarge,
        ),
        if (state.baseUrl.isNotEmpty) ...[
          const SizedBox(height: 8),
          // The address we actually got a 200 from. Shown because "it
          // worked" is worth more when it names what worked.
          Text(
            'Reached it at ${state.baseUrl}',
            key: const Key('onboarding-done-url'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const Spacer(),
        FilledButton(
          key: const Key('onboarding-done-action'),
          onPressed: onDone,
          child: const Text('Done'),
        ),
      ],
    );
  }
}

// ── shared, deliberately dull ────────────────────────────────────────

class _Busy extends StatelessWidget {
  const _Busy({required this.label, super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const CircularProgressIndicator(),
      const SizedBox(height: 20),
      Text(label, textAlign: TextAlign.center),
    ],
  );
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.headline,
    required this.body,
    this.busy = false,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String headline;
  final String body;
  final bool busy;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy) const CircularProgressIndicator(),
        if (busy) const SizedBox(height: 20),
        Text(headline, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(body, textAlign: TextAlign.center),
        if (actionLabel != null) ...[
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('onboarding-empty-action'),
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
        ],
      ],
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({
    required this.headline,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  final String headline;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(headline, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(body, style: theme.textTheme.bodyLarge),
        const Spacer(),
        FilledButton(
          key: const Key('onboarding-problem-action'),
          onPressed: onAction,
          child: Text(actionLabel),
        ),
        if (secondaryLabel != null) ...[
          const SizedBox(height: 12),
          TextButton(
            key: const Key('onboarding-problem-secondary'),
            onPressed: onSecondary,
            child: Text(secondaryLabel!),
          ),
        ],
      ],
    );
  }
}
