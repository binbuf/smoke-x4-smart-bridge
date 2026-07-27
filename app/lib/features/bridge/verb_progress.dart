/// A24.9 — the completion surface every disruptive verb runs inside.
///
/// The bridge answers *before* it acts and then drops the link (D15), so the
/// send's return value alone cannot say "it worked" — the board-found gap was a
/// factory reset that plainly succeeded while the app showed nothing. This
/// sheet closes it by **verifying by behaviour**: send, then probe `status()`
/// until the bridge stops answering — the drop *is* the confirmation for a
/// restart, a factory reset, and a power-off — and only then show a done state
/// that says what happened and what to do next.
///
/// Pure over injected [send] / [probe] / [delay] seams, so the whole
/// choreography runs in a widget test with no radio.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/design.dart';

enum DisruptiveVerb { restart, factoryReset, powerOff }

/// One stage of the choreography, exposed for tests.
enum VerbStage { sending, confirming, done, stillAnswering, cantReach }

/// Runs [verb]'s full send-and-verify inside a non-dismissible sheet.
///
/// [send] issues the command (resolving once the bridge ANSWERED — the BLE
/// result frame or the HTTP 200). [probe] must complete when the bridge still
/// answers and throw when it does not. [onCompleted] fires once, the moment the
/// drop confirms the verb worked — factory reset uses it to forget the bridge
/// on this phone, so the app never claims a bridge the reset just erased.
/// [onSetUpAgain] (factory reset only) routes to guided setup.
Future<void> showVerbProgressSheet(
  BuildContext context, {
  required DisruptiveVerb verb,
  required Future<void> Function() send,
  required Future<void> Function() probe,
  VoidCallback? onCompleted,
  VoidCallback? onSetUpAgain,
  Duration pollEvery = const Duration(seconds: 1),
  int maxPolls = 15,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => VerbProgressSheet(
      verb: verb,
      send: send,
      probe: probe,
      onCompleted: onCompleted,
      onSetUpAgain: onSetUpAgain,
      pollEvery: pollEvery,
      maxPolls: maxPolls,
    ),
  );
}

class VerbProgressSheet extends StatefulWidget {
  const VerbProgressSheet({
    required this.verb,
    required this.send,
    required this.probe,
    this.onCompleted,
    this.onSetUpAgain,
    this.pollEvery = const Duration(seconds: 1),
    this.maxPolls = 15,
    super.key,
  });

  final DisruptiveVerb verb;
  final Future<void> Function() send;
  final Future<void> Function() probe;
  final VoidCallback? onCompleted;
  final VoidCallback? onSetUpAgain;
  final Duration pollEvery;
  final int maxPolls;

  @override
  State<VerbProgressSheet> createState() => _VerbProgressSheetState();
}

class _VerbProgressSheetState extends State<VerbProgressSheet> {
  VerbStage _stage = VerbStage.sending;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _to(VerbStage s) {
    if (!_disposed && mounted) {
      setState(() => _stage = s);
    }
  }

  Future<void> _run() async {
    var sendFailed = false;
    try {
      await widget.send();
    } on Object {
      // Either the reply raced the link drop (the answer-first discipline
      // makes this rare) or the bridge was never reachable. The probe below
      // decides which.
      sendFailed = true;
    }
    _to(VerbStage.confirming);

    // The drop is the confirmation. A probe that times out is the same
    // answer as one that throws: nobody home.
    for (var i = 0; i < widget.maxPolls; i++) {
      try {
        await widget.probe().timeout(const Duration(seconds: 2));
      } on Object {
        if (i == 0 && sendFailed) {
          // The send failed AND the bridge was already unreachable: nothing
          // was delivered. "Done" here would be a lie.
          _to(VerbStage.cantReach);
          return;
        }
        widget.onCompleted?.call();
        _to(VerbStage.done);
        return;
      }
      if (_disposed) {
        return;
      }
      await Future<void>.delayed(widget.pollEvery);
    }
    // Still answering after the budget: whatever happened, "done" would be
    // a lie — say so and offer the exit.
    _to(VerbStage.stillAnswering);
  }

  // ── copy ─────────────────────────────────────────────────────────────

  String get _busyLabel => switch (widget.verb) {
    DisruptiveVerb.restart => 'Restarting the bridge…',
    DisruptiveVerb.factoryReset => 'Erasing the bridge…',
    DisruptiveVerb.powerOff => 'Powering off…',
  };

  String get _busyDetail => switch (_stage) {
    VerbStage.sending => 'Sending the command…',
    _ => 'Waiting for the bridge to go down — that’s how we know it worked.',
  };

  String get _doneTitle => switch (widget.verb) {
    DisruptiveVerb.restart => 'The bridge restarted',
    DisruptiveVerb.factoryReset => 'Factory reset complete',
    DisruptiveVerb.powerOff => 'The bridge is off',
  };

  String get _doneDetail => switch (widget.verb) {
    DisruptiveVerb.restart =>
      'It’s rebooting now and the app reconnects on its own — readings '
          'resume in under a minute.',
    DisruptiveVerb.factoryReset =>
      'It wiped everything and restarted as if it just shipped, and this '
          'phone has forgotten it too. To use it again: forget '
          '“Smoke Bridge” in your phone’s Bluetooth settings, then run setup.',
    DisruptiveVerb.powerOff =>
      'Nothing in this app can wake it now. Hold the PRG button on the '
          'bridge for about five seconds to turn it back on.',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SafeArea(
      top: false,
      child: Container(
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
          children: switch (_stage) {
            VerbStage.sending || VerbStage.confirming => _busy(t),
            VerbStage.done => _done(t),
            VerbStage.stillAnswering => _stillAnswering(t),
            VerbStage.cantReach => _cantReach(t),
          },
        ),
      ),
    );
  }

  List<Widget> _busy(SmokeTokens t) => [
    Row(
      children: [
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(width: SmokeTokens.s3),
        Expanded(
          child: Text(
            _busyLabel,
            key: const Key('verb-busy'),
            style: SmokeType.displayS.copyWith(color: t.textHi),
          ),
        ),
      ],
    ),
    const SizedBox(height: SmokeTokens.s2),
    Text(_busyDetail, style: SmokeType.body.copyWith(color: t.textBody)),
  ];

  List<Widget> _done(SmokeTokens t) => [
    Row(
      children: [
        const Icon(
          Icons.check_circle_rounded,
          size: 28,
          color: StatusPalette.positive,
        ),
        const SizedBox(width: SmokeTokens.s3),
        Expanded(
          child: Text(
            _doneTitle,
            key: const Key('verb-done'),
            style: SmokeType.displayS.copyWith(color: t.textHi),
          ),
        ),
      ],
    ),
    const SizedBox(height: SmokeTokens.s2),
    Text(_doneDetail, style: SmokeType.body.copyWith(color: t.textBody)),
    const SizedBox(height: SmokeTokens.s5),
    if (widget.verb == DisruptiveVerb.factoryReset &&
        widget.onSetUpAgain != null) ...[
      FilledButton(
        key: const Key('verb-setup-again'),
        onPressed: () {
          Navigator.of(context).pop();
          widget.onSetUpAgain!.call();
        },
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
          ),
        ),
        child: const Text('Set it up again', style: SmokeType.title),
      ),
      const SizedBox(height: SmokeTokens.s2),
      TextButton(
        key: const Key('verb-close'),
        onPressed: () => Navigator.of(context).pop(),
        child: Text('Close', style: SmokeType.title.copyWith(color: t.textMuted)),
      ),
    ] else
      FilledButton(
        key: const Key('verb-close'),
        onPressed: () => Navigator.of(context).pop(),
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
          ),
        ),
        child: const Text('Done', style: SmokeType.title),
      ),
  ];

  List<Widget> _cantReach(SmokeTokens t) => [
    Row(
      children: [
        const Icon(
          Icons.cloud_off_rounded,
          size: 28,
          color: StatusPalette.critical,
        ),
        const SizedBox(width: SmokeTokens.s3),
        Expanded(
          child: Text(
            'Can’t reach the bridge',
            key: const Key('verb-cant-reach'),
            style: SmokeType.displayS.copyWith(color: t.textHi),
          ),
        ),
      ],
    ),
    const SizedBox(height: SmokeTokens.s2),
    Text(
      'The command was not delivered — the bridge was already unreachable. '
      'Nothing changed. Get closer or reconnect, then try again.',
      style: SmokeType.body.copyWith(color: t.textBody),
    ),
    const SizedBox(height: SmokeTokens.s5),
    FilledButton(
      key: const Key('verb-close'),
      onPressed: () => Navigator.of(context).pop(),
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
        ),
      ),
      child: const Text('Close', style: SmokeType.title),
    ),
  ];

  List<Widget> _stillAnswering(SmokeTokens t) => [
    Row(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 28,
          color: StatusPalette.critical,
        ),
        const SizedBox(width: SmokeTokens.s3),
        Expanded(
          child: Text(
            'The bridge is still answering',
            key: const Key('verb-still-answering'),
            style: SmokeType.displayS.copyWith(color: t.textHi),
          ),
        ),
      ],
    ),
    const SizedBox(height: SmokeTokens.s2),
    Text(
      'It never went down, so the command may not have taken. Check the '
      'bridge’s screen, then try again.',
      style: SmokeType.body.copyWith(color: t.textBody),
    ),
    const SizedBox(height: SmokeTokens.s5),
    FilledButton(
      key: const Key('verb-close'),
      onPressed: () => Navigator.of(context).pop(),
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
        ),
      ),
      child: const Text('Close', style: SmokeType.title),
    ),
  ];
}
