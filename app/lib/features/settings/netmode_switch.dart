/// Switching the bridge's network mode, safely (newapp §E.3).
///
/// **The genuinely hard case in this whole app.** Telling the bridge to change
/// networks kills the very link that carried the command. Get the password
/// wrong and the bridge leaves, fails to join, and is reachable by nobody — the
/// phone cannot retract the instruction because the phone can no longer talk to
/// it, and the fix is a walk to the smoker with a USB cable.
///
/// The protocol, all four steps, and each one is load-bearing:
///
///  1. **The command is a request for a future state with a deadline.** The app
///     sends `revertAfterS` alongside the mode; the device snapshots what it is
///     running, applies the new config, and starts a timer.
///  2. **The device ACKs on the current transport before it switches.** That is
///     the firmware's existing 500 ms deferred apply — the reply flushes before
///     the interface it rode dies.
///  3. **The app races the expected new endpoint** — `192.168.4.1` for a hosted
///     AP, mDNS for a joined network — and commits on the first real
///     `GET /status` 200. Not on a ping, not on a socket connecting: a status
///     read, because that is the only evidence the bridge is actually serving.
///  4. **If nobody commits, the device puts back what worked.**
///
/// Throughout, **BLE stays up as the escape hatch**, which is why "keep
/// Bluetooth as backup" defaults on: even a Wi-Fi switch that fails completely
/// leaves a link that can carry the next attempt.
///
/// The UI rule that follows from all this: never a dead control and never an
/// unexplained spinner. Every state below either names what is happening or
/// names what went wrong and what the device will do about it — including the
/// countdown, so "it will come back on its own in 87 seconds" is a fact on
/// screen rather than something only the firmware knows.
library;

import 'dart:async';

import '../../data/transport/bridge_transport.dart';

/// How long the device waits for a commit before rolling back.
///
/// Two minutes is the span §E.3 specifies, and it is generous on purpose: it
/// has to cover the phone dropping the old network, the user tapping through
/// Android's "stay connected?" prompt, DHCP, and mDNS. A tighter window would
/// roll back cooks that were about to succeed.
const int kNetModeRevertS = 120;

/// Where a switch has got to. Each is a screen, and none of them is a spinner
/// with no words on it.
enum NetSwitchPhase {
  /// Sending the request down the link that is about to die.
  requesting,

  /// Sent and acknowledged. The device is switching; the app has torn down its
  /// transport and is looking for the bridge on the other side.
  reconnecting,

  /// Found and confirmed. The device has cancelled its rollback.
  committed,

  /// Not found in time. **This is not a failure state** — the device is about
  /// to put back what worked, and [revertInS] says when.
  revertPending,

  /// The device refused the request outright. Nothing changed.
  refused,
}

/// The whole switch, as a value, so the wizard is a pure render of it.
class NetSwitchState {
  const NetSwitchState({
    required this.phase,
    this.attempt = 0,
    this.revertInS = 0,
    this.detail = '',
  });

  final NetSwitchPhase phase;

  /// How many times the connection race has been round. Shown, because a
  /// counter that moves is the difference between "working" and "hung".
  final int attempt;

  /// Seconds until the device rolls back, in [NetSwitchPhase.revertPending].
  final int revertInS;

  /// Why, when there is a why. Never a status code.
  final String detail;

  String get title => switch (phase) {
    NetSwitchPhase.requesting => 'Asking the bridge to switch…',
    NetSwitchPhase.reconnecting => 'Switching — finding the bridge again',
    NetSwitchPhase.committed => 'Done',
    NetSwitchPhase.revertPending => 'Couldn’t reach the bridge',
    NetSwitchPhase.refused => 'The bridge said no',
  };

  String get body => switch (phase) {
    NetSwitchPhase.requesting =>
      'It answers before it switches, so this part is quick.',
    NetSwitchPhase.reconnecting =>
      'The app is looking for it on the new network. Bluetooth stays '
          'connected the whole time, so nothing is lost if this does not work.',
    NetSwitchPhase.committed => 'The bridge is on the new network.',
    NetSwitchPhase.revertPending =>
      'It will go back to the network that was working in '
          '${revertInS}s — nothing to undo, and nobody has to walk over to '
          'it.',
    NetSwitchPhase.refused =>
      detail.isEmpty ? 'Nothing changed.' : '$detail Nothing changed.',
  };

  /// Whether this is a resting state the sheet can be dismissed from.
  bool get isTerminal =>
      phase == NetSwitchPhase.committed ||
      phase == NetSwitchPhase.revertPending ||
      phase == NetSwitchPhase.refused;
}

/// Runs §E.3's protocol and emits the states above.
///
/// Pure over its seams — [apply], [probe] and [commit] are injected, so the
/// whole wizard including the rollback path is testable with no radio (§I.2
/// asks for exactly this integration test).
class NetModeSwitch {
  NetModeSwitch({
    required this.apply,
    required this.probe,
    required this.commit,
    this.revertAfterS = kNetModeRevertS,
    this.attemptDelay = const Duration(seconds: 3),
    this.maxAttempts = 12,
  });

  /// Sends the request. Returns the AP PSK when switching to hosted mode.
  final Future<String> Function(NetworkMode mode, String ssid, String psk)
  apply;

  /// One attempt at reaching the bridge on the **new** network. True means a
  /// real `GET /status` 200 — never a socket that merely opened.
  final Future<bool> Function() probe;

  /// Tells the device to keep the new config. Throws if it will not.
  final Future<void> Function() commit;

  final int revertAfterS;
  final Duration attemptDelay;
  final int maxAttempts;

  final _states = StreamController<NetSwitchState>.broadcast();
  Stream<NetSwitchState> get states => _states.stream;

  bool _cancelled = false;

  /// The user backed out. The device still rolls back on its own — cancelling
  /// here only stops the app hunting, it does not strand anything.
  void cancel() => _cancelled = true;

  /// Runs the switch. Returns the final state; never throws.
  Future<NetSwitchState> run({
    required NetworkMode mode,
    String ssid = '',
    String psk = '',
  }) async {
    var state = const NetSwitchState(phase: NetSwitchPhase.requesting);
    _emit(state);

    try {
      await apply(mode, ssid, psk);
    } on BridgeRefusal catch (e) {
      return _finish(
        NetSwitchState(phase: NetSwitchPhase.refused, detail: e.message),
      );
    } on Object {
      // The reply may have been lost while the interface came down, which is
      // indistinguishable from a refusal at this layer — so we do NOT report a
      // failure. We go looking, exactly as if it had been accepted, and the
      // device's own rollback covers the case where it never was.
    }

    var tried = 0;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (_cancelled) {
        break;
      }
      tried = attempt;
      _emit(
        state = NetSwitchState(
          phase: NetSwitchPhase.reconnecting,
          attempt: attempt,
        ),
      );
      var found = false;
      try {
        found = await probe();
      } on Object {
        found = false;
      }
      if (found) {
        try {
          await commit();
          return _finish(
            NetSwitchState(phase: NetSwitchPhase.committed, attempt: attempt),
          );
        } on Object {
          // Reached it but could not confirm. Keep trying rather than
          // reporting success — an uncommitted switch is one the device is
          // still going to undo, and saying "Done" would be a lie with a
          // two-minute fuse on it.
          found = false;
        }
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(attemptDelay);
      }
    }

    // Out of attempts (or cancelled). Report the rollback as the plan it is,
    // with a real number on it — not as an error.
    //
    // The number is **derived from the attempts actually made**, not measured
    // off a wall clock: this is a countdown the DEVICE owns, and the app's job
    // is to show a defensible estimate of it rather than to race a second
    // timer against the first. Once the phone re-finds the bridge,
    // `GET /config/wifi` reports the device's own `revert_in_s`, which is the
    // authoritative value and replaces this one.
    final spent = tried * attemptDelay.inSeconds;
    final left = revertAfterS - spent;
    return _finish(
      NetSwitchState(
        phase: NetSwitchPhase.revertPending,
        attempt: tried,
        revertInS: left < 0 ? 0 : left,
      ),
    );
  }

  NetSwitchState _finish(NetSwitchState s) {
    _emit(s);
    unawaited(_states.close());
    return s;
  }

  void _emit(NetSwitchState s) {
    if (!_states.isClosed) {
      _states.add(s);
    }
  }
}
