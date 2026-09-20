/// The §E.3 mode switch, as a surface — the UI over [NetModeSwitch].
///
/// The protocol is already written and already tested (`netmode_switch.dart`):
/// request a *future* state with a rollback timer, let the device ACK before it
/// tears down the interface the command rode in on, race the expected new
/// endpoint, commit on a real `GET /status` 200, and let the device put back
/// what worked if nobody ever commits. **Nothing here re-implements any of
/// that.** This file is the four screens that protocol needs and the two
/// pieces of information only the UI can carry:
///
///  * the **consequence, before it runs** — a switch drops the link that is
///    carrying it, and on a fourteen-hour cook that is worth one sentence;
///  * the **AP key the device generates**, which `applyNetwork` hands back
///    exactly once and which the user has to read to rejoin. A wizard that
///    threw it away would strand somebody in the yard.
///
/// The UI rule §E.3 ends on, restated because it is the one that gets broken:
/// **never a dead control and never an unexplained spinner.** Every state below
/// names what is happening or names what went wrong *and what the device will
/// do about it* — including the countdown, so "it comes back on its own in 87
/// seconds" is a fact on the screen rather than something only the firmware
/// knows.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/transport/bridge_transport.dart';
import '../../design/design.dart';
import '../../ui/ui.dart';
import '../settings/netmode_switch.dart';

/// Opens the sheet. Resolves to the terminal phase, or null if the user backed
/// out before anything was sent.
Future<NetSwitchPhase?> showNetModeSheet(
  BuildContext context, {
  required NetworkMode target,
  required Future<String> Function(NetworkMode mode, String ssid, String psk)
  apply,
  required Future<bool> Function() probe,
  required Future<void> Function() commit,
  String knownSsid = '',
  Duration attemptDelay = const Duration(seconds: 3),
  int maxAttempts = 12,
}) {
  return showModalBottomSheet<NetSwitchPhase>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => NetModeSheet(
      target: target,
      apply: apply,
      probe: probe,
      commit: commit,
      knownSsid: knownSsid,
      attemptDelay: attemptDelay,
      maxAttempts: maxAttempts,
    ),
  );
}

class NetModeSheet extends StatefulWidget {
  const NetModeSheet({
    required this.target,
    required this.apply,
    required this.probe,
    required this.commit,
    this.knownSsid = '',
    this.attemptDelay = const Duration(seconds: 3),
    this.maxAttempts = 12,
    super.key,
  });

  /// Where the bridge should end up.
  final NetworkMode target;

  /// Sends the request; returns the AP key when the device generated one.
  final Future<String> Function(NetworkMode mode, String ssid, String psk)
  apply;

  /// One attempt at a real `GET /status` on the **new** network.
  final Future<bool> Function() probe;
  final Future<void> Function() commit;

  /// The network the bridge is on now, prefilled when we are re-entering the
  /// same one. Never a guess — empty when nothing said so.
  final String knownSsid;

  final Duration attemptDelay;
  final int maxAttempts;

  @override
  State<NetModeSheet> createState() => _NetModeSheetState();
}

class _NetModeSheetState extends State<NetModeSheet> {
  late final TextEditingController _ssid = TextEditingController(
    text: widget.knownSsid,
  );
  final TextEditingController _psk = TextEditingController();

  NetModeSwitch? _run;
  NetSwitchState? _state;
  StreamSubscription<NetSwitchState>? _sub;

  /// The key the device generated for its own network. Held here because
  /// [NetModeSwitch] has no use for it and the user has no other copy.
  String _apKey = '';

  bool get _joining => widget.target == NetworkMode.sta;
  bool get _started => _state != null;

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _run?.cancel();
    _ssid.dispose();
    _psk.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final ssid = _ssid.text.trim();
    if (_joining && ssid.isEmpty) {
      return;
    }
    final sw = NetModeSwitch(
      apply: (mode, s, p) async {
        final key = await widget.apply(mode, s, p);
        if (mounted && key.isNotEmpty) {
          setState(() => _apKey = key);
        }
        return key;
      },
      probe: widget.probe,
      commit: widget.commit,
      attemptDelay: widget.attemptDelay,
      maxAttempts: widget.maxAttempts,
    );
    _run = sw;
    _sub = sw.states.listen((s) {
      if (mounted) {
        setState(() => _state = s);
      }
    });
    setState(
      () => _state = const NetSwitchState(phase: NetSwitchPhase.requesting),
    );
    final end = await sw.run(
      mode: widget.target,
      ssid: ssid,
      psk: _psk.text,
    );
    if (mounted) {
      setState(() => _state = end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SafeArea(
      top: false,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.symmetric(horizontal: SmokeTokens.s2),
        padding: EdgeInsets.only(
          left: SmokeTokens.s5,
          right: SmokeTokens.s5,
          top: SmokeTokens.s5,
          bottom: SmokeTokens.s5 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(SmokeTokens.radiusCard),
          ),
          border: Border.all(color: t.hairline),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _started ? _running(t) : _form(t),
          ),
        ),
      ),
    );
  }

  // ── before: what it costs, and what it needs ─────────────────────────

  List<Widget> _form(SmokeTokens t) => [
    Text(
      _joining ? 'Put the bridge on your Wi-Fi' : 'Let the bridge host',
      key: const Key('netmode-title'),
      style: SmokeType.displayS.copyWith(color: t.textHi),
    ),
    const SizedBox(height: SmokeTokens.s2),
    Text(
      _joining
          ? 'The bridge joins the network you name, so you can check the cook '
                'from anywhere in the house.'
          : 'The bridge makes its own network and your phone joins that. '
                'Longer range than Bluetooth, no router needed.',
      style: SmokeType.body.copyWith(color: t.textBody),
    ),
    const SizedBox(height: SmokeTokens.s3),
    // The cost, before it runs. This is the sentence that stops a switch
    // being frightening: whatever happens, it undoes itself.
    Text(
      'Changing this drops the connection carrying the change. The app looks '
      'for the bridge on the other side, and if it cannot find it the bridge '
      'puts back what was working — nobody has to walk over to it.',
      key: const Key('netmode-cost'),
      style: SmokeType.bodySm.copyWith(color: t.textMuted),
    ),
    if (_joining) ...[
      const SizedBox(height: SmokeTokens.s4),
      TextField(
        key: const Key('netmode-ssid'),
        controller: _ssid,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Network name',
          hintText: 'The Wi-Fi the bridge should join',
        ),
      ),
      const SizedBox(height: SmokeTokens.s3),
      TextField(
        key: const Key('netmode-psk'),
        controller: _psk,
        obscureText: true,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'Wi-Fi password'),
      ),
      const SizedBox(height: SmokeTokens.s2),
      Text(
        'The password goes straight to the bridge and is never stored on this '
        'phone.',
        style: SmokeType.bodySm.copyWith(color: t.textMuted),
      ),
    ],
    const SizedBox(height: SmokeTokens.s5),
    ValueListenableBuilder<TextEditingValue>(
      valueListenable: _ssid,
      builder: (context, value, _) => PrimaryAction(
        key: const Key('netmode-go'),
        label: _joining ? 'Join this network' : 'Host its own network',
        // Disabled, not hidden, and the reason is the empty field above it:
        // a bridge cannot join a network nobody named.
        onPressed: _joining && value.text.trim().isEmpty
            ? null
            : () => unawaited(_start()),
      ),
    ),
    const SizedBox(height: SmokeTokens.s2),
    TextButton(
      key: const Key('netmode-cancel'),
      onPressed: () => Navigator.of(context).pop(),
      child: Text(
        'Leave it as it is',
        style: SmokeType.title.copyWith(color: t.textMuted),
      ),
    ),
  ];

  // ── during and after: the four phases, each with words on it ─────────

  List<Widget> _running(SmokeTokens t) {
    final s = _state!;
    final terminal = s.isTerminal;
    return [
      Row(
        children: [
          if (!terminal)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            Icon(
              switch (s.phase) {
                NetSwitchPhase.committed => Icons.check_circle_rounded,
                NetSwitchPhase.revertPending => Icons.history_rounded,
                _ => Icons.error_outline_rounded,
              },
              size: 26,
              color: switch (s.phase) {
                NetSwitchPhase.committed => StatusPalette.positive,
                NetSwitchPhase.revertPending => StatusPalette.warning,
                _ => StatusPalette.critical,
              },
            ),
          const SizedBox(width: SmokeTokens.s3),
          Expanded(
            child: Text(
              s.title,
              key: const Key('netmode-phase-title'),
              style: SmokeType.displayS.copyWith(color: t.textHi),
            ),
          ),
        ],
      ),
      const SizedBox(height: SmokeTokens.s2),
      Text(
        s.body,
        key: const Key('netmode-phase-body'),
        style: SmokeType.body.copyWith(color: t.textBody),
      ),
      // A counter that moves is the difference between "working" and "hung".
      if (s.phase == NetSwitchPhase.reconnecting && s.attempt > 0) ...[
        const SizedBox(height: SmokeTokens.s2),
        Text(
          'Try ${s.attempt} of ${widget.maxAttempts}',
          key: const Key('netmode-attempt'),
          style: SmokeType.bodySm.copyWith(color: t.textMuted),
        ),
      ],
      if (_apKey.isNotEmpty) ...[
        const SizedBox(height: SmokeTokens.s4),
        MonoWell(key: const Key('netmode-ap-key'), value: _apKey, label: 'Wi-Fi password'),
        const SizedBox(height: SmokeTokens.s2),
        Text(
          'Write this down — it is the key to the bridge’s own network, and '
          'the bridge is the only other place it exists.',
          style: SmokeType.bodySm.copyWith(color: t.textMuted),
        ),
      ],
      if (terminal) ...[
        const SizedBox(height: SmokeTokens.s5),
        PrimaryAction(
          key: const Key('netmode-done'),
          label: switch (s.phase) {
            NetSwitchPhase.committed => 'Done',
            NetSwitchPhase.revertPending => 'Wait for it to come back',
            _ => 'Close',
          },
          onPressed: () => Navigator.of(context).pop(s.phase),
        ),
      ],
    ];
  }
}
