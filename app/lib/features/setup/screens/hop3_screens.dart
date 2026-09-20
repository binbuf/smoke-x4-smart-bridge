/// A23.4 — hop 3 screens: bridge ↔ network over Wi-Fi (design 13 §13.2.3).
///
/// The hop with the most failure branches, and the one where today's product
/// collapses six causes into "that password did not work" (13 §13.1 #5). Each
/// `Hop3State` is a screen that says which cause: the picker separates
/// open/secured/enterprise, the password screen validates length *before*
/// Connect and prefills on retry, applying narrates four phases with a cancel
/// (never a cancel-less spinner), each Wi-Fi failure states its reason, and
/// unreachable shows the IP it is hiding today. Hosted mode always shows the
/// SSID and PSK, because OEM join behaviour varies (05 §5.8.2).
///
/// Every screen is a [SetupScaffold]: one primary, a named secondary, an exit.
/// `ssid`/`psk`/`auth` live on the machine, not in widget state — which is what
/// makes the password prefill on retry possible (§13.2.3).
library;

import 'package:flutter/material.dart';

import '../../../data/dto/records.g.dart' show WifiScanResult;
import '../../../design/design.dart';
import '../../../ui/ui.dart';
import '../copy/setup_net_copy.dart';
import '../copy/setup_resume_copy.dart';
import '../setup_entry.dart';
import '../setup_machine.dart';

/// `SetupNetworkPick` — the picker (§13.2.3). Rows are RSSI-sorted by the
/// machine; open networks skip the password screen, enterprise rows are
/// disabled, and hosted is the primary after two failures.
class NetworkPickScreen extends StatelessWidget {
  const NetworkPickScreen({
    required this.state,
    required this.machine,
    super.key,
  });

  final SetupNetworkPick state;
  final SetupMachine machine;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hostedIsPrimary = state.failureCount >= 2;
    // Setup opened straight at hop 3 because hops 1 and 2 are already done
    // (§16.3). The picker then leads with why it is on screen — and says
    // whether this is adding a network or changing one, because getting that
    // wrong is how a returning user concludes the app forgot everything.
    final why = state.resume == SetupResumeKind.addNetwork
        ? (state.hasNetwork
              ? SetupResumeCopy.changeNetworkWhy
              : SetupResumeCopy.addNetworkWhy)
        : null;

    return SetupScaffold(
      hop: state.hop,
      title: SetupNetCopy.pickTitle,
      subtitle: why == null
          ? SetupNetCopy.pickSubtitle
          : '$why ${SetupNetCopy.pickBand}',
      onExit: () => machine.cancel(),
      body: ListView(
        children: [
          if (state.scanning) const _ScanningRow(),
          for (final net in state.networks)
            Padding(
              padding: const EdgeInsets.only(bottom: SmokeTokens.s2),
              child: _WifiRow(
                net: net,
                onTap: net.auth == 5 ? null : () => machine.pickNetwork(net),
              ),
            ),
          if (!hostedIsPrimary) ...[
            const SizedBox(height: SmokeTokens.s3),
            Center(
              child: TextButton(
                key: const Key('network-hosted-link'),
                onPressed: () => machine.chooseHosted(),
                child: Text(
                  '${SetupNetCopy.hostedLink} ${SetupNetCopy.hostedLinkAction}',
                  style: SmokeType.bodySm.copyWith(color: t.textMuted),
                ),
              ),
            ),
          ],
        ],
      ),
      // A25: Bluetooth already works by this point, so finishing WITHOUT
      // Wi-Fi is the default forward action — tapping a network row is how
      // Wi-Fi opts in. After repeated join failures, hosted takes the
      // primary as the recovery and Bluetooth-only moves to the secondary.
      primary: hostedIsPrimary
          ? PrimaryAction(
              key: const Key('network-pick-hosted-primary'),
              label: SetupNetCopy.useHosted,
              onPressed: () => machine.chooseHosted(),
            )
          : PrimaryAction(
              key: const Key('network-ble-only'),
              label: SetupNetCopy.bleOnly,
              icon: Icons.bluetooth_rounded,
              onPressed: () => machine.skipNetwork(),
            ),
      secondary: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hostedIsPrimary)
            TextButton(
              key: const Key('network-ble-only-link'),
              onPressed: () => machine.skipNetwork(),
              child: const Text(SetupNetCopy.bleOnly),
            ),
          TextButton(
            key: const Key('network-hidden-link'),
            onPressed: () => machine.openManualEntry(),
            child: const Text(SetupNetCopy.hiddenNetwork),
          ),
        ],
      ),
    );
  }
}

/// `SetupNetworkEmpty` — the scan found nothing (§13.2.3): hosted is the primary
/// automatically, look-again the secondary.
class NetworkEmptyScreen extends StatelessWidget {
  const NetworkEmptyScreen({
    required this.state,
    required this.machine,
    super.key,
  });

  final SetupNetworkEmpty state;
  final SetupMachine machine;

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      hop: state.hop,
      title: SetupNetCopy.emptyTitle,
      subtitle: SetupNetCopy.emptySubtitle,
      onExit: () => machine.cancel(),
      body: const Center(child: _CenteredGlyph(icon: Icons.wifi_find_rounded)),
      primary: PrimaryAction(
        key: const Key('network-empty-primary'),
        label: SetupNetCopy.useHosted,
        onPressed: () => machine.chooseHosted(),
      ),
      secondary: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A25: no Wi-Fi found is exactly where Bluetooth-only shines.
          TextButton(
            key: const Key('network-empty-ble-only'),
            onPressed: () => machine.skipNetwork(),
            child: const Text(SetupNetCopy.bleOnly),
          ),
          TextButton(
            onPressed: () => machine.startNetworkScan(),
            child: const Text(SetupNetCopy.emptyLookAgain),
          ),
        ],
      ),
    );
  }
}

/// `SetupNetworkManual` — a hidden SSID with its own auth (§13.2.3): a keystroke
/// must not downgrade WPA3, and a hidden open network must be joinable.
class NetworkManualScreen extends StatefulWidget {
  const NetworkManualScreen({
    required this.state,
    required this.machine,
    super.key,
  });

  final SetupNetworkManual state;
  final SetupMachine machine;

  @override
  State<NetworkManualScreen> createState() => _NetworkManualScreenState();
}

class _NetworkManualScreenState extends State<NetworkManualScreen> {
  final _ssid = TextEditingController();
  int _auth = 3;

  static const _authOptions = <ChipOption<int>>[
    ChipOption(0, 'Open'),
    ChipOption(3, 'WPA/WPA2'),
    ChipOption(6, 'WPA3'),
  ];

  @override
  void dispose() {
    _ssid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SetupScaffold(
      hop: widget.state.hop,
      title: SetupNetCopy.manualTitle,
      subtitle: SetupNetCopy.manualSubtitle,
      onExit: () => widget.machine.cancel(),
      body: ListView(
        children: [
          Text(
            SetupNetCopy.manualSsidLabel.toUpperCase(),
            style: SmokeType.labelSm.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: SmokeTokens.s2),
          TextField(
            key: const Key('manual-ssid-field'),
            controller: _ssid,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: SmokeTokens.s5),
          Text(
            SetupNetCopy.manualSecurityLabel.toUpperCase(),
            style: SmokeType.labelSm.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: SmokeTokens.s2),
          SegmentedChips<int>(
            options: _authOptions,
            value: _auth,
            onChanged: (v) => setState(() => _auth = v),
          ),
        ],
      ),
      primary: PrimaryAction(
        key: const Key('manual-primary'),
        label: SetupNetCopy.manualPrimary,
        onPressed: _ssid.text.trim().isEmpty
            ? null
            : () => widget.machine.submitManual(_ssid.text.trim(), auth: _auth),
      ),
    );
  }
}

/// `SetupNetworkPassword` — its own screen, one job (§13.2.3). Reveal toggle,
/// live length validation, and a prefilled+revealed field on retry with the
/// reason stated.
class NetworkPasswordScreen extends StatefulWidget {
  const NetworkPasswordScreen({
    required this.state,
    required this.machine,
    super.key,
  });

  final SetupNetworkPassword state;
  final SetupMachine machine;

  @override
  State<NetworkPasswordScreen> createState() => _NetworkPasswordScreenState();
}

class _NetworkPasswordScreenState extends State<NetworkPasswordScreen> {
  late final TextEditingController _psk;
  late bool _reveal;

  @override
  void initState() {
    super.initState();
    _psk = TextEditingController(text: widget.state.prefill);
    // Retry (a prefill or a stated error) opens revealed — the user is fixing a
    // typo, not entering a secret for the first time.
    _reveal = widget.state.prefill.isNotEmpty || widget.state.error != null;
  }

  @override
  void dispose() {
    _psk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final t = context.tokens;
    final valid = SetupNetCopy.passwordValid(s.auth, _psk.text);

    return SetupScaffold(
      hop: s.hop,
      title: SetupNetCopy.passwordTitle,
      subtitle: SetupNetCopy.passwordSubtitle(s.ssid),
      errorTint: s.error != null,
      onExit: () => widget.machine.cancel(),
      body: ListView(
        children: [
          if (s.error != null) ...[
            InsightBanner(
              kind: InsightKind.alarm,
              icon: Icons.error_outline_rounded,
              label: s.error!,
            ),
            const SizedBox(height: SmokeTokens.s4),
          ],
          Text(
            SetupNetCopy.passwordLabel.toUpperCase(),
            style: SmokeType.labelSm.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: SmokeTokens.s2),
          TextField(
            key: const Key('password-field'),
            controller: _psk,
            obscureText: !_reveal,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            onSubmitted: valid ? (v) => widget.machine.submitPassword(v) : null,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                key: const Key('password-reveal'),
                icon: Icon(
                  _reveal
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: t.textMuted,
                ),
                onPressed: () => setState(() => _reveal = !_reveal),
              ),
            ),
          ),
          const SizedBox(height: SmokeTokens.s2),
          Text(
            SetupNetCopy.passwordHint(s.auth),
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          ),
        ],
      ),
      primary: PrimaryAction(
        key: const Key('password-primary'),
        label: SetupNetCopy.passwordPrimary,
        onPressed: valid
            ? () => widget.machine.submitPassword(_psk.text)
            : null,
      ),
    );
  }
}

/// `SetupApplying` — four narrated phases with a cancel (§13.2.3), never one
/// line of text and no actions.
class ApplyingScreen extends StatelessWidget {
  const ApplyingScreen({required this.state, required this.machine, super.key});

  final SetupApplying state;
  final SetupMachine machine;

  @override
  Widget build(BuildContext context) {
    final steps = SetupNetCopy.applyingSteps(state.hosted);
    var active = steps.indexOf(state.phase);
    if (active < 0) {
      active = state.phase == ApplyingPhase.checking ? steps.length - 1 : 1;
    }

    return SetupScaffold(
      hop: state.hop,
      title: SetupNetCopy.applyingTitle(state.ssid, state.hosted),
      onExit: () => machine.cancel(),
      body: ListView(
        children: [
          for (var i = 0; i < steps.length; i++)
            _PhaseRow(
              label: SetupNetCopy.applyingPhase(
                steps[i],
                state.ssid,
                state.hosted,
              ),
              status: i < active
                  ? _PhaseStatus.done
                  : (i == active ? _PhaseStatus.active : _PhaseStatus.pending),
            ),
        ],
      ),
      secondary: TextButton(
        key: const Key('applying-cancel'),
        onPressed: () => machine.cancel(),
        child: const Text(SetupNetCopy.cancel),
      ),
    );
  }
}

/// `SetupWifiFailed` — a stated reason, never "wrong password" for all six
/// causes (§13.2.3). After two attempts hosted becomes the primary.
class WifiFailedScreen extends StatelessWidget {
  const WifiFailedScreen({
    required this.state,
    required this.machine,
    super.key,
  });

  final SetupWifiFailed state;
  final SetupMachine machine;

  @override
  Widget build(BuildContext context) {
    final copy = SetupNetCopy.wifiFailure(state.reason, state.ssid);
    final hostedIsPrimary = state.attempts >= 2;

    return SetupScaffold(
      hop: state.hop,
      title: copy.headline,
      subtitle: copy.body,
      errorTint: true,
      onExit: () => machine.cancel(),
      body: const Center(child: _CenteredGlyph(icon: Icons.wifi_off_rounded)),
      primary: hostedIsPrimary
          ? PrimaryAction(
              key: const Key('wifi-failed-primary'),
              label: SetupNetCopy.useHosted,
              onPressed: () => machine.chooseHosted(),
            )
          : PrimaryAction(
              key: const Key('wifi-failed-primary'),
              label: SetupNetCopy.wifiRetry,
              icon: Icons.refresh_rounded,
              onPressed: () => machine.retryWifi(),
            ),
      secondary: hostedIsPrimary
          ? TextButton(
              onPressed: () => machine.retryWifi(),
              child: const Text(SetupNetCopy.wifiRetryPassword),
            )
          : TextButton(
              onPressed: () => machine.chooseHosted(),
              child: const Text(SetupNetCopy.useHosted),
            ),
    );
  }
}

/// `SetupUnreachable` — joined, but this phone can't see it (§13.2.3). The IP is
/// shown, never hidden.
class UnreachableScreen extends StatelessWidget {
  const UnreachableScreen({
    required this.state,
    required this.machine,
    super.key,
  });

  final SetupUnreachable state;
  final SetupMachine machine;

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      hop: state.hop,
      title: SetupNetCopy.unreachableTitle,
      subtitle: SetupNetCopy.unreachableSubtitle(state.ip),
      errorTint: true,
      onExit: () => machine.cancel(),
      body: Center(
        child: state.ip.isEmpty
            ? const _CenteredGlyph(icon: Icons.wifi_tethering_error_rounded)
            : MonoWell(value: state.ip, label: SetupNetCopy.unreachableAddress),
      ),
      primary: PrimaryAction(
        key: const Key('unreachable-primary'),
        label: SetupNetCopy.unreachableRetry,
        icon: Icons.refresh_rounded,
        onPressed: () => machine.retryVerify(),
      ),
      secondary: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => machine.chooseHosted(),
            child: const Text(SetupNetCopy.useHosted),
          ),
          // A24.2 — the phone is bonded over BLE right here, so it can wipe a
          // bridge stuck in a stale state with no USB and no reset button.
          TextButton(
            key: const Key('unreachable-reset'),
            onPressed: () => _confirmReset(context),
            child: const Text(SetupNetCopy.resetBridge),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(SetupNetCopy.resetConfirmTitle),
        content: const Text(SetupNetCopy.resetConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('unreachable-reset-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(SetupNetCopy.resetConfirm),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await machine.factoryResetBridge();
    }
  }
}

/// `SetupHostedJoin` — hosted mode is up (§13.2.3): SSID + PSK on screen because
/// OEM join behaviour varies.
class HostedJoinScreen extends StatelessWidget {
  const HostedJoinScreen({
    required this.state,
    required this.machine,
    super.key,
  });

  final SetupHostedJoin state;
  final SetupMachine machine;

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      hop: state.hop,
      title: SetupNetCopy.hostedTitle,
      subtitle: SetupNetCopy.hostedSubtitle,
      onExit: () => machine.cancel(),
      body: _HostedCreds(ssid: state.ssid, psk: state.psk),
      primary: PrimaryAction(
        key: const Key('hosted-join-primary'),
        label: SetupNetCopy.hostedJoinForMe,
        icon: Icons.wifi_rounded,
        onPressed: () => machine.joinHostedAp(),
      ),
      secondary: TextButton(
        onPressed: () => machine.hostedJoinedManually(),
        child: const Text(SetupNetCopy.hostedJoinMyself),
      ),
    );
  }
}

/// `SetupHostedRefused` — the AP join was refused or the switch never came up
/// (§13.2.3). The credentials stay on screen so the user can join manually.
class HostedRefusedScreen extends StatelessWidget {
  const HostedRefusedScreen({
    required this.state,
    required this.machine,
    super.key,
  });

  final SetupHostedRefused state;
  final SetupMachine machine;

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      hop: state.hop,
      title: SetupNetCopy.hostedRefusedTitle,
      subtitle: SetupNetCopy.hostedRefusedSubtitle,
      errorTint: true,
      onExit: () => machine.cancel(),
      body: _HostedCreds(ssid: state.ssid, psk: state.psk),
      primary: PrimaryAction(
        key: const Key('hosted-refused-primary'),
        label: SetupNetCopy.hostedRetry,
        icon: Icons.refresh_rounded,
        onPressed: () => machine.joinHostedAp(),
      ),
      secondary: TextButton(
        onPressed: () => machine.hostedJoinedManually(),
        child: const Text(SetupNetCopy.hostedJoinedAlready),
      ),
    );
  }
}

// ── local presentation pieces (no flow logic) ─────────────────────────────

class _HostedCreds extends StatelessWidget {
  const _HostedCreds({required this.ssid, required this.psk});

  final String ssid;
  final String psk;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        MonoWell(value: ssid, label: SetupNetCopy.hostedNetworkLabel),
        const SizedBox(height: SmokeTokens.s4),
        MonoWell(value: psk, label: SetupNetCopy.hostedPasswordLabel),
      ],
    );
  }
}

class _ScanningRow extends StatelessWidget {
  const _ScanningRow();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: SmokeTokens.s3),
          Text(
            SetupNetCopy.scanning,
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          ),
        ],
      ),
    );
  }
}

class _WifiRow extends StatelessWidget {
  const _WifiRow({required this.net, required this.onTap});

  final WifiScanResult net;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enterprise = net.auth == 5;
    final ink = enterprise ? t.textMuted : t.textHi;

    return SmokeCard(
      key: Key('wifi-${net.ssid}'),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: SmokeTokens.s4,
        vertical: SmokeTokens.s3,
      ),
      child: Row(
        children: [
          Icon(_wifiIcon(net.rssi), size: 22, color: t.textMuted),
          const SizedBox(width: SmokeTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  net.ssid,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SmokeType.title.copyWith(color: ink),
                ),
                if (enterprise)
                  Text(
                    SetupNetCopy.enterpriseDisabled,
                    style: SmokeType.bodySm.copyWith(color: t.textMuted),
                  ),
              ],
            ),
          ),
          if (net.auth != 0)
            Icon(
              enterprise ? Icons.block_rounded : Icons.lock_outline_rounded,
              size: 16,
              color: t.textMuted,
            ),
          if (!enterprise) ...[
            const SizedBox(width: SmokeTokens.s2),
            Icon(Icons.chevron_right_rounded, color: t.textMuted),
          ],
        ],
      ),
    );
  }
}

class _CenteredGlyph extends StatelessWidget {
  const _CenteredGlyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: 64, color: StatusPalette.critical);
}

enum _PhaseStatus { done, active, pending }

class _PhaseRow extends StatelessWidget {
  const _PhaseRow({required this.label, required this.status});

  final String label;
  final _PhaseStatus status;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final leading = switch (status) {
      _PhaseStatus.done => const Icon(
        Icons.check_circle_rounded,
        size: 22,
        color: StatusPalette.positive,
      ),
      _PhaseStatus.active => SizedBox(
        width: 22,
        height: 22,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(StatusPalette.pit),
          ),
        ),
      ),
      _PhaseStatus.pending => Icon(
        Icons.circle_outlined,
        size: 22,
        color: t.chromeDim,
      ),
    };
    final ink = status == _PhaseStatus.pending ? t.textMuted : t.textBody;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SmokeTokens.s3),
      child: Row(
        children: [
          leading,
          const SizedBox(width: SmokeTokens.s3),
          Expanded(
            child: Text(label, style: SmokeType.body.copyWith(color: ink)),
          ),
        ],
      ),
    );
  }
}

IconData _wifiIcon(int rssi) {
  if (rssi >= -60) {
    return Icons.wifi_rounded;
  }
  if (rssi >= -75) {
    return Icons.wifi_2_bar_rounded;
  }
  return Icons.wifi_1_bar_rounded;
}
