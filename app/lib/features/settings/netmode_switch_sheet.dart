/// The §E.3 mode-switch wizard, as a screen (newapp §E.3 step 4).
///
/// [NetModeSwitch] is the protocol and it is deliberately pure — no widgets, no
/// context, every seam injected — so the rollback path can be tested with no
/// radio. This file is the other half: the surface that renders its states, and
/// the reason the network page no longer has a fire-and-forget "Switch" button
/// on it.
///
/// The rule §E.3 states in one line — *"never leave a dead control or an
/// unexplained spinner"* — is the whole design brief here. So:
///
///  * every phase has **words**, not just a spinner. "Asking the bridge to
///    switch", then "Looking for it on the new network", with the attempt
///    counter visible because a number that moves is the difference between
///    "working" and "hung";
///  * the sheet **cannot be dismissed mid-switch**. Backing out of a switch
///    that is in flight is how somebody ends up with an uncommitted change and
///    no screen telling them the bridge is about to undo it;
///  * the rollback is presented as **the plan it is**, with the device's own
///    countdown on it — not as an error, and never as a failure the user has to
///    fix. Nobody has to walk over to the smoker.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/transport/bridge_transport.dart';
import '../../design/design.dart';
import '../../ui/ui.dart';
import 'netmode_switch.dart';

/// Runs [machine] inside a non-dismissible sheet and resolves with the state it
/// finished in — committed, rolled back, or refused.
Future<NetSwitchState?> showNetModeSwitchSheet(
  BuildContext context, {
  required NetModeSwitch machine,
  required NetworkMode mode,
  String ssid = '',
  String psk = '',
}) => showModalBottomSheet<NetSwitchState>(
  context: context,
  isScrollControlled: true,
  isDismissible: false,
  enableDrag: false,
  backgroundColor: Colors.transparent,
  builder: (_) => PopScope(
    canPop: false,
    child: NetModeSwitchSheet(
      machine: machine,
      mode: mode,
      ssid: ssid,
      psk: psk,
    ),
  ),
);

class NetModeSwitchSheet extends StatefulWidget {
  const NetModeSwitchSheet({
    required this.machine,
    required this.mode,
    this.ssid = '',
    this.psk = '',
    super.key,
  });

  final NetModeSwitch machine;
  final NetworkMode mode;
  final String ssid;
  final String psk;

  @override
  State<NetModeSwitchSheet> createState() => _NetModeSwitchSheetState();
}

class _NetModeSwitchSheetState extends State<NetModeSwitchSheet> {
  NetSwitchState _state = const NetSwitchState(
    phase: NetSwitchPhase.requesting,
  );
  StreamSubscription<NetSwitchState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.machine.states.listen((s) {
      if (mounted) {
        setState(() => _state = s);
      }
    });
    unawaited(_run());
  }

  Future<void> _run() async {
    final end = await widget.machine.run(
      mode: widget.mode,
      ssid: widget.ssid,
      psk: widget.psk,
    );
    if (mounted) {
      setState(() => _state = end);
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = _state;
    return SafeArea(
      top: false,
      child: Container(
        key: const Key('netmode-sheet'),
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.symmetric(horizontal: SmokeTokens.s2),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(SmokeTokens.radiusCard),
          ),
          border: Border.all(color: t.hairline),
        ),
        padding: const EdgeInsets.all(SmokeTokens.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.title,
              key: const Key('netmode-title'),
              style: SmokeType.displayS.copyWith(color: t.textHi),
            ),
            const SizedBox(height: SmokeTokens.s2),
            Text(
              s.body,
              key: const Key('netmode-body'),
              style: SmokeType.body.copyWith(color: t.textBody),
            ),
            if (!s.isTerminal) ...[
              const SizedBox(height: SmokeTokens.s4),
              LinearProgressIndicator(
                key: const Key('netmode-progress'),
                color: StatusPalette.pit,
                backgroundColor: t.cardSubtle,
              ),
              const SizedBox(height: SmokeTokens.s2),
              Text(
                // A counter that moves is the difference between "working" and
                // "hung", and it costs one line.
                s.attempt == 0
                    ? 'Sending the request'
                    : 'Attempt ${s.attempt} — Bluetooth is still connected',
                key: const Key('netmode-attempt'),
                style: SmokeType.bodySm.copyWith(color: t.textMuted),
              ),
            ],
            const SizedBox(height: SmokeTokens.s5),
            if (s.isTerminal)
              PrimaryAction(
                key: const Key('netmode-done'),
                label: switch (s.phase) {
                  NetSwitchPhase.committed => 'Done',
                  NetSwitchPhase.revertPending => 'Wait for it to come back',
                  _ => 'Close',
                },
                onPressed: () => Navigator.of(context).pop(s),
              )
            else
              TextButton(
                key: const Key('netmode-stop'),
                // Stops the app hunting. The device still rolls back on its
                // own, so this strands nothing — and the label says so rather
                // than implying the change is being undone here.
                onPressed: () {
                  widget.machine.cancel();
                },
                child: Text(
                  'Stop looking',
                  style: SmokeType.title.copyWith(color: t.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
