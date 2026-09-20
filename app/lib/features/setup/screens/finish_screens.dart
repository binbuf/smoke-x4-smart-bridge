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
import '../../../ui/setup/device_art.dart';
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
          // The finish gets the same subject the rest of the flow now has
          // (17 §17.3 C): the bridge, drawn, with the tick badged on it rather
          // than floating over black. Presence carries all the way through —
          // this is the frame the user leaves setup on.
          //
          // The one green in this file, and it survives the §16.5 audit on a
          // technicality worth writing down: this screen's entire subject *is*
          // transport — the three rows under the tick are BLE, LoRa and Wi-Fi,
          // and the phone is holding a live BLE link to the bridge at the
          // moment it renders. Green here is claiming that link, which is
          // exactly what green is allowed to claim. It is not claiming "wizard
          // finished" — a skipped hop still reads "— not set up" beneath it.
          // It stays an `Icon` on purpose: a hue painted into a `CustomPainter`
          // is invisible to the colour-rule audit that walks the element tree.
          const Center(child: _DoneMark()),
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
      // **Not `positive`.** "The bridge is factory-fresh" is the opposite of a
      // healthy link — the wipe dropped it, and the next screen asks the user
      // to forget the OS pairing and start over. Green means transport health
      // and nothing else (16 §16.5); `pit` is the accent that says "this is
      // the app's own state", and the glyph and the title still carry the
      // meaning.
      body: Center(
        child: Icon(
          Icons.restart_alt_rounded,
          size: 56,
          color: StatusPalette.pit,
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

/// The landing's hero: the bridge, with the link tick badged on it.
///
/// The badge is deliberately *on* the device and not beside it — the sentence
/// the screen is making is "this bridge is connected", and a tick with nothing
/// under it is the app congratulating itself. The `surface` ring around the
/// glyph is what keeps it legible where it overlaps the board's own edge.
class _DoneMark extends StatelessWidget {
  const _DoneMark();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const BridgeIllustration(
            key: Key('setup-done-art'),
            mood: BridgeMood.ready,
            size: 160,
          ),
          Positioned(
            right: 6,
            bottom: 32,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: t.bg, shape: BoxShape.circle),
              child: const Icon(
                Icons.check_circle_rounded,
                size: 34,
                color: StatusPalette.positive,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the §13.2.4 summary: what a hop ended up as.
///
/// **A status hue never carries the words.** [warn] used to be spent on the
/// value's text colour, which is the half of the rule that does not work: on
/// the amber's own weight the string reads quieter than the `textHi` beside it,
/// and a reader who cannot see amber gets no signal at all. §14.6.5 puts the
/// hue on the icon and the border and the words at 13:1, so that is where it
/// goes — a 16 dp caution glyph ahead of the value, the value at `textHi` in
/// both states. The signal is now stated three ways: the glyph, the string
/// ("— not set up"), and the rail drawing that hop as a dash.
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (warn) ...[
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: StatusPalette.warning,
                  ),
                  const SizedBox(width: SmokeTokens.s1),
                ],
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: SmokeType.body.copyWith(
                      color: t.textHi,
                      fontWeight: FontWeight.w600,
                    ),
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
