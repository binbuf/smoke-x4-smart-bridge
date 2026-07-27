/// A23.5 — the interactive, hardware-free setup lab (design 13 §13.2, §13.5.1).
///
/// Runs a **real** [SetupMachine] wired to a chosen [SetupScript] over the fakes
/// in `fake_bridge.dart`, and renders each live state through the shipping
/// [SetupScaffold]/[SetupRail] and `ui/` components. What a reviewer clicks
/// through here is what ships — this is a driver, not a mock UI, exactly as
/// `cook_lab.dart` is for the Cook tab.
///
/// The flow steps two ways: the machine advances *itself* through the fakes for
/// the passive states (scanning, listening, applying — the "next scripted
/// event" arrives on the [LabClock]'s real pacing), and the reviewer advances
/// the interactive states by tapping their one [PrimaryAction] — the single
/// next step rail R2 guarantees every state has. A script picker sits at the
/// top, and a strip shows the current machine state's name and coordinate so a
/// reviewer always knows where the machine is.
///
/// Run it device-free:
///   flutter run -d chrome  -t lib/lab/main_lab.dart   (once wired in)
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../design/design.dart';
import '../features/setup/copy/base_sync_copy.dart';
import '../features/setup/setup_machine.dart';
import '../ui/ui.dart';
import 'fake_bridge.dart';

class SetupLab extends StatefulWidget {
  const SetupLab({super.key, this.clock});

  /// Injected only by tests — a [LabClock.manual] makes the whole screen
  /// timer-free and deterministic. Null in the shipping lab, where each script
  /// runs on real, capped delays so the flow is watchable.
  final LabClock? clock;

  @override
  State<SetupLab> createState() => _SetupLabState();
}

class _SetupLabState extends State<SetupLab> {
  late SetupScript _script;
  late FakeBridge _bridge;
  StreamSubscription<SetupState>? _sub;
  SetupState _state = const SetupPermissionPrimer();

  /// One shared field controller — only ever one text state is on screen at a
  /// time (SSID, password, or the bridge name), so a single controller reset on
  /// entry is enough.
  final _input = TextEditingController();
  bool _celsius = false;

  @override
  void initState() {
    super.initState();
    _script = labSetupScripts.first;
    _boot();
  }

  void _boot() {
    _bridge = FakeBridge(_script, clock: widget.clock);
    _state = _bridge.machine.state;
    _sub = _bridge.machine.states.listen(_onState);
    unawaited(_bridge.machine.start());
  }

  void _onState(SetupState s) {
    if (!mounted) {
      return;
    }
    setState(() {
      final changedType = s.runtimeType != _state.runtimeType;
      _state = s;
      // Seed the field when we first enter a text-bearing state.
      if (changedType) {
        if (s is SetupNetworkPassword) {
          _input.text = s.prefill;
        } else if (s is SetupNameAndUnits) {
          _input.text = s.suggestedName;
        } else if (s is SetupNetworkManual) {
          _input.text = '';
        }
      }
    });
  }

  Future<void> _pick(SetupScript s) async {
    await _teardown();
    setState(() {
      _script = s;
      _celsius = false;
      _boot();
    });
  }

  Future<void> _restart() async {
    await _teardown();
    setState(_boot);
  }

  Future<void> _teardown() async {
    await _sub?.cancel();
    _sub = null;
    await _bridge.dispose();
  }

  @override
  void dispose() {
    unawaited(_teardown());
    _input.dispose();
    super.dispose();
  }

  /// Fire a machine method and forget — the resulting state arrives on the
  /// stream. Guarded double-taps and un-modelled throws are the machine's job.
  void _do(Future<void> Function() action) => unawaited(action());

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: const Text('Setup Lab'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: t.hairline),
        ),
      ),
      body: Column(
        children: [
          _scriptBar(context),
          _stateBar(context),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _screenFor(context, _state),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── the review chrome (not part of what ships) ────────────────────────

  Widget _scriptBar(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final s in labSetupScripts)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(s.title),
                  selected: s.id == _script.id,
                  onSelected: (_) => unawaited(_pick(s)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stateBar(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      color: t.cardSubtle,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _script.blurb,
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.memory_rounded, size: 16, color: StatusPalette.pit),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${_state.runtimeType}  ·  hop ${_state.hop}  ·  '
                  '${_state.stage.name}',
                  style: SmokeType.mono.copyWith(color: t.textHi),
                ),
              ),
              IconButton(
                tooltip: 'Restart script',
                onPressed: () => unawaited(_restart()),
                icon: Icon(Icons.replay_rounded, color: t.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── the state → shipping-screen dispatcher ────────────────────────────

  Widget _screenFor(BuildContext context, SetupState s) {
    final m = _bridge.machine;
    switch (s) {
      // ── hop 0 — preflight ───────────────────────────────────────────
      case SetupPermissionPrimer():
        return _scaffold(
          s,
          title: 'Before we begin',
          subtitle:
              'The app needs Bluetooth to find and pair with your bridge. '
              'Your phone will ask next.',
          body: _note(
            context,
            'Nearby-devices permission is used only to talk '
            'to the bridge over Bluetooth — never for location.',
          ),
          primary: _primary('Continue', () => _do(m.continueFromPrimer)),
        );
      case SetupBluetoothOff():
        return _scaffold(
          s,
          title: 'Turn on Bluetooth',
          subtitle: 'Your bridge is found over Bluetooth first.',
          body: _note(context, 'Enable Bluetooth to continue.'),
          errorTint: true,
          primary: _primary('Enable Bluetooth', () => _do(m.enableBluetooth)),
        );
      case SetupBluetoothUnsupported():
        return _scaffold(
          s,
          title: 'No Bluetooth on this phone',
          body: const ProblemState(
            title: 'Read it off the screen',
            message:
                'This phone has no Bluetooth, so it cannot learn the network '
                'name and password automatically. Read them off the bridge OLED.',
          ),
          exit: false,
        );
      case SetupPermissionDenied(:final permanent):
        return _scaffold(
          s,
          title: 'Permission needed',
          errorTint: true,
          body: _note(
            context,
            permanent
                ? 'Nearby-devices permission was turned off for good — open app '
                      'settings to grant it.'
                : 'The app cannot find your bridge without the nearby-devices '
                      'permission.',
          ),
          primary: _primary('Try again', () => _do(m.continueFromPrimer)),
        );
      case SetupLocationServicesOff():
        return _scaffold(
          s,
          title: 'Turn on location',
          errorTint: true,
          body: _note(
            context,
            'On this Android version, a Bluetooth scan needs '
            'location services switched on.',
          ),
          primary: _primary('I turned it on', () => _do(m.recheckPreflight)),
        );

      // ── hop 1 — find + pair ─────────────────────────────────────────
      case SetupScanning(:final found, :final scanning):
        return _scaffold(
          s,
          title: 'Find your bridge',
          subtitle: scanning
              ? 'Looking for nearby bridges…'
              : 'Pick your bridge.',
          body: found.isEmpty
              ? _centered(context, scanning ? 'Scanning…' : 'Nothing yet.')
              : ListView(
                  children: [
                    for (final b in found)
                      _tapCard(
                        context,
                        leading: Icons.router_rounded,
                        title: b.name,
                        trailing: '${b.rssi} dBm',
                        onTap: () => _do(() => m.select(b)),
                      ),
                  ],
                ),
        );
      case SetupNoBridges():
        return _scaffold(
          s,
          title: 'No bridges found',
          errorTint: true,
          body: const EmptyState(
            icon: Icons.wifi_tethering_off_rounded,
            title: 'Is the bridge powered on?',
            message:
                'Its screen should be lit and within a few metres. Then look '
                'again.',
          ),
          primary: _primary('Look again', () => _do(m.startScan)),
        );
      case SetupAddThisPhone(:final bridge):
        return _scaffold(
          s,
          title: 'Add this phone',
          subtitle: '${bridge.name} is already set up.',
          body: _note(
            context,
            'Pair this phone to it — about fifteen seconds.',
          ),
          primary: _primary('Add this phone', () => _do(m.confirmAddThisPhone)),
        );
      case SetupPairing(:final passkeyShown):
        return _scaffold(
          s,
          title: 'Check the bridge screen',
          subtitle: passkeyShown
              ? 'Confirm the code shown on the bridge matches your phone.'
              : 'Connecting…',
          body: const Center(child: PasskeyDisplay()),
          secondary: _secondary(
            context,
            "I don't see a prompt",
            () => m.passkeyNotSeen(),
          ),
        );
      case SetupPasskeyNotSeen():
        return _scaffold(
          s,
          title: 'No prompt yet?',
          errorTint: true,
          body: _note(
            context,
            'Some phones tuck the pairing prompt in the '
            'notification shade. Check there, then try again.',
          ),
          primary: _primary('Try again', () => _do(m.retryPasskey)),
        );
      case SetupBonded(:final bridge):
        return _scaffold(
          s,
          title: 'Paired',
          subtitle: 'This phone and ${bridge.name} are now bonded.',
          body: Center(
            child: Icon(
              Icons.check_circle_rounded,
              size: 64,
              color: StatusPalette.pit,
            ),
          ),
          primary: _primary('Continue', () => _do(m.startHop2)),
        );
      case SetupPasskeyWrong():
        return _scaffold(
          s,
          title: "That code didn't match",
          errorTint: true,
          body: _note(
            context,
            'Retrying restarts the pairing cleanly — one tap, '
            'a fresh code on the bridge.',
          ),
          primary: _primary('Try again', () => _do(m.retryPasskey)),
        );
      case SetupRebondNeeded():
        return _scaffold(
          s,
          title: 'Re-pair needed',
          errorTint: true,
          body: _note(
            context,
            'The bridge was reset since you last paired. '
            'Forget it in Bluetooth settings, then try again.',
          ),
          primary: _primary('Try again', () => _do(m.retryPasskey)),
        );
      case SetupBondSlotsFull():
        return _scaffold(
          s,
          title: 'This bridge is full',
          errorTint: true,
          body: _note(
            context,
            'All three phone slots are taken. Remove a phone '
            'from the bridge, or choose a different one.',
          ),
          primary: _primary('Choose another', () => _do(m.startScan)),
        );
      case SetupNotABridge():
        return _scaffold(
          s,
          title: 'Not a bridge',
          body: const ProblemState(
            title: "That device isn't a Smoke Bridge",
            message:
                'It does not speak the bridge protocol. Pick another device.',
          ),
          primary: _primary('Choose another device', () => _do(m.startScan)),
          exit: false,
        );

      // ── hop 2 — bridge ↔ Smoke X ────────────────────────────────────
      case SetupBaseIntro():
        return _scaffold(
          s,
          title: BaseSyncCopy.introHeadline,
          body: _note(context, BaseSyncCopy.introGesture),
          primary: _primary(
            BaseSyncCopy.introPrimary,
            () => _do(m.startBaseListen),
          ),
          secondary: _secondary(
            context,
            BaseSyncCopy.introSkip,
            () => _do(m.skipBase),
          ),
        );
      case SetupBaseListening(:final elapsed, :final garbled):
        return _scaffold(
          s,
          title: BaseSyncCopy.listening,
          subtitle: '${elapsed.inSeconds}s',
          body: garbled > 0
              ? InsightBanner(
                  kind: InsightKind.advisory,
                  label: BaseSyncCopy.garbledFaint,
                )
              : _centered(context, BaseSyncCopy.listeningKeepClose),
          secondary: _secondary(context, 'Cancel', () => _do(m.cancel)),
        );
      case SetupBaseHeard(:final deviceId):
        return _scaffold(
          s,
          title: 'Found it',
          body: _centered(context, BaseSyncCopy.heard(deviceId)),
        );
      case SetupBaseConfirmed(:final deviceId, :final numProbes, :final temps):
        return _scaffold(
          s,
          title: 'Your Smoke X is talking',
          subtitle: 'Smoke X $deviceId · $numProbes probes',
          body: _centered(context, _tempsLine(temps)),
          primary: _primary('Continue', () => _do(m.continueFromConfirmed)),
        );
      case SetupBaseSkipped():
        return _scaffold(
          s,
          title: 'Skipped for now',
          skipped: const {2},
          body: _note(context, BaseSyncCopy.skippedCard),
          primary: _primary('Continue', () => _do(m.continueToNetwork)),
        );
      case SetupBaseFailed(:final reason):
        return _scaffold(
          s,
          title: 'No pairing yet',
          errorTint: true,
          body: _note(context, BaseSyncCopy.failureHeadline(reason)),
          primary: _primary('Try again', () => _do(m.retryBaseListen)),
          secondary: _secondary(context, 'Skip for now', () => _do(m.skipBase)),
        );

      // ── hop 3 — bridge ↔ Wi-Fi ──────────────────────────────────────
      case SetupNetworkPick(:final networks, :final scanning):
        return _scaffold(
          s,
          title: 'Choose a network',
          subtitle: scanning ? 'Scanning…' : 'Pick the Wi-Fi for the bridge.',
          body: networks.isEmpty
              ? _centered(context, 'Scanning…')
              : ListView(
                  children: [
                    for (final n in networks)
                      _tapCard(
                        context,
                        leading: n.auth == 0
                            ? Icons.lock_open_rounded
                            : Icons.lock_rounded,
                        title: n.ssid,
                        trailing: '${n.rssi} dBm',
                        onTap: () => _do(() => m.pickNetwork(n)),
                      ),
                  ],
                ),
          secondary: _secondary(
            context,
            'Join a hidden network',
            () => _do(m.openManualEntry),
          ),
        );
      case SetupNetworkEmpty():
        return _scaffold(
          s,
          title: 'No networks found',
          errorTint: true,
          body: _note(
            context,
            'Let the bridge host its own network instead — '
            'your phone joins that directly.',
          ),
          primary: _primary('Use hosted mode', () => _do(m.chooseHosted)),
          secondary: _secondary(
            context,
            'Scan again',
            () => _do(m.startNetworkScan),
          ),
        );
      case SetupNetworkManual():
        return _scaffold(
          s,
          title: 'Hidden network',
          body: _field(context, 'Network name (SSID)'),
          primary: _primary(
            'Next',
            () => _do(() => m.submitManual(_input.text)),
          ),
        );
      case SetupNetworkPassword(:final ssid, :final error):
        return _scaffold(
          s,
          title: ssid,
          subtitle: 'Enter the Wi-Fi password.',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) ...[
                InsightBanner(kind: InsightKind.alarm, label: error),
                const SizedBox(height: SmokeTokens.s3),
              ],
              _field(context, 'Password', obscure: true),
            ],
          ),
          primary: _primary(
            'Connect',
            () => _do(() => m.submitPassword(_input.text)),
          ),
        );
      case SetupApplying(:final phase, :final ssid, :final hosted):
        return _scaffold(
          s,
          title: hosted ? 'Setting up hosted mode' : 'Joining $ssid',
          body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: StatusPalette.pit),
              const SizedBox(height: SmokeTokens.s4),
              _centered(context, _phaseLine(phase, ssid)),
            ],
          ),
          secondary: _secondary(context, 'Cancel', () => _do(m.cancel)),
        );
      case SetupWifiFailed(:final reason, :final ssid):
        return _scaffold(
          s,
          title: "Couldn't join $ssid",
          errorTint: true,
          body: _note(context, _wifiReason(reason)),
          primary: _primary('Try again', () => _do(m.retryWifi)),
          secondary: _secondary(
            context,
            'Use hosted mode',
            () => _do(m.chooseHosted),
          ),
        );
      case SetupUnreachable(:final ip):
        return _scaffold(
          s,
          title: "Can't reach the bridge",
          errorTint: true,
          body: _note(
            context,
            'The bridge joined at $ip, but this phone cannot '
            'see it yet. Make sure the phone is on the same network.',
          ),
          primary: _primary('Try again', () => _do(m.retryVerify)),
          secondary: _secondary(
            context,
            'Use hosted mode',
            () => _do(m.chooseHosted),
          ),
        );
      case SetupHostedJoin(:final ssid, :final psk):
        return _scaffold(
          s,
          title: 'Join the bridge network',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MonoWell(label: 'Network', value: ssid),
              const SizedBox(height: SmokeTokens.s3),
              MonoWell(label: 'Password', value: psk),
            ],
          ),
          primary: _primary('Join it for me', () => _do(m.joinHostedAp)),
          secondary: _secondary(
            context,
            "I'll join it myself",
            () => _do(m.hostedJoinedManually),
          ),
        );
      case SetupHostedRefused(:final ssid, :final psk):
        return _scaffold(
          s,
          title: 'Join it manually',
          errorTint: true,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MonoWell(label: 'Network', value: ssid),
              const SizedBox(height: SmokeTokens.s3),
              MonoWell(label: 'Password', value: psk),
            ],
          ),
          primary: _primary('Try again', () => _do(m.joinHostedAp)),
          secondary: _secondary(
            context,
            "I've joined it",
            () => _do(m.hostedJoinedManually),
          ),
        );

      // ── finish + cross-cutting ──────────────────────────────────────
      case SetupNameAndUnits():
        return _scaffold(
          s,
          title: 'Name your bridge',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(context, 'Name'),
              const SizedBox(height: SmokeTokens.s4),
              SegmentedChips<bool>(
                value: _celsius,
                onChanged: (v) => setState(() => _celsius = v),
                options: const [
                  ChipOption(false, '°F'),
                  ChipOption(true, '°C'),
                ],
              ),
            ],
          ),
          primary: _primary(
            'Finish',
            () =>
                _do(() => m.submitNameAndUnits(_input.text, celsius: _celsius)),
          ),
        );
      case SetupDone(:final summary):
        return _scaffold(
          s,
          title: 'All set',
          subtitle: summary.bridgeName,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _summaryRow(context, 'Bridge', summary.bridgeName),
              _summaryRow(
                context,
                'Smoke X',
                summary.baseDeviceId ?? '— not set up',
              ),
              _summaryRow(context, 'Wi-Fi', summary.wifiSsid ?? '— not set up'),
            ],
          ),
          primary: _primary('Run again', () => unawaited(_restart())),
          exit: false,
        );
      case SetupResetDone():
        return _scaffold(
          s,
          title: 'The bridge is factory-fresh',
          subtitle: 'Wiped over Bluetooth (A24.2).',
          body: _note(
            context,
            "Forget 'Smoke Bridge' in the phone's Bluetooth settings, "
            'then set it up from scratch.',
          ),
          primary: _primary('Run again', () => unawaited(_restart())),
          exit: false,
        );
      case SetupLinkLost():
        return _scaffold(
          s,
          title: 'Connection lost',
          errorTint: true,
          body: _note(
            context,
            'The link to the bridge dropped. Reconnect to '
            'pick up where you left off, or start over.',
          ),
          primary: _primary('Reconnect', () => _do(m.reconnect)),
          secondary: _secondary(context, 'Start over', () => _do(m.restart)),
        );
      case SetupFault(:final detail):
        return _scaffold(
          s,
          title: 'Something went wrong',
          errorTint: true,
          body: _note(context, detail.isEmpty ? 'Unexpected error.' : detail),
          primary: _primary('Start over', () => _do(m.restart)),
        );
    }
  }

  // ── small builders ────────────────────────────────────────────────────

  SetupScaffold _scaffold(
    SetupState s, {
    required String title,
    String? subtitle,
    required Widget body,
    Widget? primary,
    Widget? secondary,
    bool errorTint = false,
    Set<int> skipped = const {},
    bool exit = true,
  }) {
    return SetupScaffold(
      hop: s.hop,
      title: title,
      subtitle: subtitle,
      body: body,
      primary: primary,
      secondary: secondary,
      errorTint: errorTint,
      skipped: skipped,
      onExit: exit ? () => unawaited(_restart()) : null,
    );
  }

  Widget _primary(String label, VoidCallback onPressed) =>
      PrimaryAction(label: label, onPressed: onPressed);

  Widget _secondary(
    BuildContext context,
    String label,
    VoidCallback onPressed,
  ) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: SmokeType.body.copyWith(color: context.tokens.textMuted),
      ),
    );
  }

  Widget _note(BuildContext context, String text) => Text(
    text,
    style: SmokeType.body.copyWith(color: context.tokens.textBody),
  );

  Widget _centered(BuildContext context, String text) => Center(
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: SmokeType.body.copyWith(color: context.tokens.textBody),
    ),
  );

  Widget _field(BuildContext context, String label, {bool obscure = false}) {
    final t = context.tokens;
    return TextField(
      controller: _input,
      obscureText: obscure,
      style: SmokeType.body.copyWith(color: t.textHi),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: SmokeType.bodySm.copyWith(color: t.textMuted),
        filled: true,
        fillColor: t.cardSubtle,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
          borderSide: BorderSide(color: t.hairline),
        ),
      ),
    );
  }

  Widget _tapCard(
    BuildContext context, {
    required IconData leading,
    required String title,
    required String trailing,
    required VoidCallback onTap,
  }) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
      child: SmokeCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(leading, size: 22, color: StatusPalette.pit),
            const SizedBox(width: SmokeTokens.s3),
            Expanded(
              child: Text(
                title,
                style: SmokeType.title.copyWith(color: t.textHi),
              ),
            ),
            Text(
              trailing,
              style: SmokeType.bodySm.copyWith(color: t.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: SmokeType.label.copyWith(color: t.textMuted),
            ),
          ),
          Expanded(
            child: Text(value, style: SmokeType.body.copyWith(color: t.textHi)),
          ),
        ],
      ),
    );
  }

  String _tempsLine(List<int?> temps) {
    final live = <String>[
      for (final v in temps)
        if (v != null) '${(v / 10).toStringAsFixed(1)}°F',
    ];
    return live.isEmpty ? 'Waiting for a reading…' : live.join('   ');
  }

  String _phaseLine(ApplyingPhase phase, String ssid) => switch (phase) {
    ApplyingPhase.sent => 'Sent your network to the bridge.',
    ApplyingPhase.joining => 'The bridge is joining $ssid.',
    ApplyingPhase.gettingAddress => 'Getting an address…',
    ApplyingPhase.joiningAp => 'Joining the bridge network…',
    ApplyingPhase.checking => 'Checking this phone can reach it…',
  };

  String _wifiReason(WifiFailure reason) => switch (reason) {
    WifiFailure.wrongPassword => 'The password was not accepted.',
    WifiFailure.notFound => "The bridge couldn't find that network.",
    WifiFailure.assocRefused => 'The router turned the bridge away.',
    WifiFailure.noIp => 'The bridge joined but never got an address.',
    WifiFailure.weakSignal => 'The signal is too weak where the bridge is.',
  };
}
