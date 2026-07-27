/// A23.4 — finish + cross-cutting screens, and the hop-2/3/finish dispatcher
/// (design 13 §13.2.4, §13.5.1).
///
/// The landing and the two recovery backstops: name+units (units asked *once*,
/// here, not buried in Settings), the three-row summary with a skipped hop shown
/// as "— not set up", link-lost (reconnect-or-restart, never a strand), and the
/// R3 fault backstop that caught an un-modelled throw rather than letting it
/// reach the crash page.
///
/// [setupNetScreenFor] is the screen dispatcher for **this agent's** states
/// (hop 2, hop 3, finish). The hop-0/hop-1 states are the other agents' and fall
/// through to a shrink here — the route composes the two dispatchers. The done
/// screen's "See my probes" is a *navigation* action neither the machine nor a
/// pure screen can perform, so it is threaded in as the optional [onFinish]; a
/// two-argument call still works and simply renders the landing without a live
/// finish handler.
library;

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../ui/ui.dart';
import '../copy/setup_net_copy.dart';
import '../setup_machine.dart';
import 'hop2_screens.dart';
import 'hop3_screens.dart';

/// `SetupNameAndUnits` — asked once (§13.2.4): a name and the display unit.
class NameAndUnitsScreen extends StatefulWidget {
  const NameAndUnitsScreen({
    required this.state,
    required this.machine,
    super.key,
  });

  final SetupNameAndUnits state;
  final SetupMachine machine;

  @override
  State<NameAndUnitsScreen> createState() => _NameAndUnitsScreenState();
}

class _NameAndUnitsScreenState extends State<NameAndUnitsScreen> {
  late final TextEditingController _name;
  bool _celsius = false;

  static const _unitOptions = <ChipOption<bool>>[
    ChipOption(false, '°F'),
    ChipOption(true, '°C'),
  ];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.state.suggestedName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final typed = _name.text.trim();
    final name = typed.isEmpty ? widget.state.suggestedName : typed;
    widget.machine.submitNameAndUnits(name, celsius: _celsius);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SetupScaffold(
      hop: widget.state.hop,
      title: SetupFinishCopy.nameTitle,
      subtitle: SetupFinishCopy.nameSubtitle,
      onExit: () => widget.machine.cancel(),
      body: ListView(
        children: [
          Text(
            SetupFinishCopy.nameLabel.toUpperCase(),
            style: SmokeType.labelSm.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: SmokeTokens.s2),
          TextField(
            key: const Key('name-field'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: SetupFinishCopy.namePlaceholder,
            ),
          ),
          const SizedBox(height: SmokeTokens.s5),
          Text(
            SetupFinishCopy.unitsLabel.toUpperCase(),
            style: SmokeType.labelSm.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: SmokeTokens.s2),
          SegmentedChips<bool>(
            options: _unitOptions,
            value: _celsius,
            onChanged: (v) => setState(() => _celsius = v),
          ),
        ],
      ),
      primary: PrimaryAction(
        key: const Key('name-primary'),
        label: SetupFinishCopy.finishPrimary,
        onPressed: _submit,
      ),
    );
  }
}

/// `SetupDone` — the three-row summary (§13.2.4). A skipped hop reads "— not set
/// up" in `warning`, and the rail renders that hop as a dash.
class SetupDoneScreen extends StatelessWidget {
  const SetupDoneScreen({required this.summary, this.onSeeProbes, super.key});

  final SetupSummary summary;

  /// Route-supplied navigation to the Cook tab. Null in the bare dispatcher
  /// path (the route observes `SetupDone` and supplies it).
  final VoidCallback? onSeeProbes;

  @override
  Widget build(BuildContext context) {
    final baseSkipped = summary.baseDeviceId == null;
    final wifiSkipped = summary.wifiSsid == null && !summary.hosted;
    final skipped = <int>{if (baseSkipped) 2, if (wifiSkipped) 3};

    return SetupScaffold(
      hop: 3,
      skipped: skipped,
      title: SetupFinishCopy.doneTitle(summary.bridgeName),
      body: ListView(
        children: [
          const Center(
            child: Icon(
              Icons.check_circle_rounded,
              size: 56,
              color: StatusPalette.positive,
            ),
          ),
          const SizedBox(height: SmokeTokens.s6),
          _SummaryRow(
            label: SetupFinishCopy.doneBluetooth,
            value: summary.blePaired
                ? SetupFinishCopy.donePaired
                : SetupFinishCopy.doneNotSetUp,
            warn: !summary.blePaired,
          ),
          _SummaryRow(
            label: SetupFinishCopy.doneSmokeX,
            value: SetupFinishCopy.doneBaseValue(
              summary.baseDeviceId,
              summary.baseNumProbes,
            ),
            warn: baseSkipped,
          ),
          _SummaryRow(
            label: SetupFinishCopy.doneWifi,
            value: SetupFinishCopy.doneWifiValue(
              ssid: summary.wifiSsid,
              ip: summary.ip,
              hosted: summary.hosted,
            ),
            // Bluetooth-only is a chosen way to run (A25), not a gap — the
            // value string explains itself without amber.
            warn: false,
          ),
        ],
      ),
      primary: PrimaryAction(
        key: const Key('done-primary'),
        label: SetupFinishCopy.donePrimary,
        icon: Icons.thermostat_rounded,
        onPressed: onSeeProbes,
      ),
    );
  }
}

/// `SetupResetDone` — the bridge was wiped over Bluetooth (A24.2). It restarted
/// factory-fresh; the phone still holds a stale OS pairing to forget first.
class ResetDoneScreen extends StatelessWidget {
  const ResetDoneScreen({required this.state, required this.machine, super.key});

  final SetupResetDone state;
  final SetupMachine machine;

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      hop: state.hop,
      title: SetupNetCopy.resetDoneTitle,
      subtitle: SetupNetCopy.resetDoneSubtitle,
      body: const Center(
        child: Icon(
          Icons.restart_alt_rounded,
          size: 56,
          color: StatusPalette.positive,
        ),
      ),
      primary: PrimaryAction(
        key: const Key('reset-done-primary'),
        label: SetupNetCopy.resetDoneStartOver,
        icon: Icons.refresh_rounded,
        onPressed: () => machine.restart(),
      ),
    );
  }
}

/// `SetupLinkLost` — the BLE link died mid-flow (§13.2.0 / §13.2.3): always
/// reconnect-or-restart, never a dead end.
class LinkLostScreen extends StatelessWidget {
  const LinkLostScreen({required this.state, required this.machine, super.key});

  final SetupLinkLost state;
  final SetupMachine machine;

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      hop: state.hop,
      errorTint: true,
      title: SetupFinishCopy.linkLostTitle,
      subtitle: SetupFinishCopy.linkLostSubtitle,
      body: const Center(
        child: _RecoveryGlyph(icon: Icons.bluetooth_disabled_rounded),
      ),
      primary: PrimaryAction(
        key: const Key('link-lost-primary'),
        label: SetupFinishCopy.linkLostReconnect,
        icon: Icons.refresh_rounded,
        onPressed: () => machine.reconnect(),
      ),
      secondary: TextButton(
        onPressed: () => machine.restart(),
        child: const Text(SetupFinishCopy.linkLostRestart),
      ),
    );
  }
}

/// `SetupFault` — the R3 backstop (§13.5.1): an un-modelled throw was caught
/// here instead of reaching the full-screen crash page.
class FaultScreen extends StatelessWidget {
  const FaultScreen({required this.state, required this.machine, super.key});

  final SetupFault state;
  final SetupMachine machine;

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      hop: state.hop,
      errorTint: true,
      title: SetupFinishCopy.faultTitle,
      subtitle: SetupFinishCopy.faultSubtitle,
      body: ListView(
        children: [
          const Center(child: _RecoveryGlyph(icon: Icons.report_rounded)),
          if (state.detail.isNotEmpty) ...[
            const SizedBox(height: SmokeTokens.s6),
            MonoWell(
              value: state.detail,
              label: SetupFinishCopy.faultDetailLabel,
            ),
          ],
        ],
      ),
      primary: PrimaryAction(
        key: const Key('fault-primary'),
        label: SetupFinishCopy.faultRestart,
        icon: Icons.refresh_rounded,
        onPressed: () => machine.restart(),
      ),
    );
  }
}

// ── local presentation pieces ─────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.warn,
  });

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SmokeTokens.s3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: SmokeType.title.copyWith(color: t.textBody)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: SmokeType.body.copyWith(
                color: warn ? StatusPalette.warning : t.textHi,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecoveryGlyph extends StatelessWidget {
  const _RecoveryGlyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: 64, color: StatusPalette.critical);
}

// ══ the dispatcher ═════════════════════════════════════════════════════════

/// The screen for a hop-2, hop-3 or finish [SetupState] (this agent's states).
///
/// hop-0/hop-1 states are the other agents' and return a shrink here; the route
/// composes this with the hop-1 agent's `setupScreenFor`. [onFinish] is the
/// route's navigation-to-Cook handler for `SetupDone` — a two-argument call is
/// valid and renders the landing without it.
Widget setupNetScreenFor(
  SetupState state,
  SetupMachine machine, {
  VoidCallback? onFinish,
}) => switch (state) {
  final SetupBaseIntro s => BaseIntroScreen(state: s, machine: machine),
  final SetupBaseListening s => BaseListeningScreen(state: s, machine: machine),
  final SetupBaseHeard s => BaseHeardScreen(state: s, machine: machine),
  final SetupBaseConfirmed s => BaseConfirmedScreen(state: s, machine: machine),
  final SetupBaseSkipped s => BaseSkippedScreen(state: s, machine: machine),
  final SetupBaseFailed s => BaseFailedScreen(state: s, machine: machine),
  final SetupNetworkPick s => NetworkPickScreen(state: s, machine: machine),
  final SetupNetworkEmpty s => NetworkEmptyScreen(state: s, machine: machine),
  final SetupNetworkManual s => NetworkManualScreen(state: s, machine: machine),
  final SetupNetworkPassword s => NetworkPasswordScreen(
    state: s,
    machine: machine,
  ),
  final SetupApplying s => ApplyingScreen(state: s, machine: machine),
  final SetupWifiFailed s => WifiFailedScreen(state: s, machine: machine),
  final SetupUnreachable s => UnreachableScreen(state: s, machine: machine),
  final SetupHostedJoin s => HostedJoinScreen(state: s, machine: machine),
  final SetupHostedRefused s => HostedRefusedScreen(state: s, machine: machine),
  final SetupNameAndUnits s => NameAndUnitsScreen(state: s, machine: machine),
  final SetupDone s => SetupDoneScreen(
    summary: s.summary,
    onSeeProbes: onFinish,
  ),
  final SetupResetDone s => ResetDoneScreen(state: s, machine: machine),
  final SetupLinkLost s => LinkLostScreen(state: s, machine: machine),
  final SetupFault s => FaultScreen(state: s, machine: machine),
  _ => const SizedBox.shrink(),
};
