/// N14 — the onboarding wizard's pure state machine and copy.
///
/// Everything here is a plain value over the N1/N2 enums: no Flutter, no
/// repository, no provider. That lets the eight-step flow, the preflight gate,
/// the recovery paths and the monotonic generation guard be tested without a
/// binding, and keeps the widget a view over one immutable [SetupState].
///
/// Invariants encoded here (research notes §12, `tasks/N14-onboarding.md`):
///
/// * **The passkey is never rendered by the app.** There is no code field on
///   [SetupState] and no code parameter anywhere; the wizard only coaches the
///   user before Android's own dialog.
/// * **I6 — no state without a next step.** [SetupState.canAdvance] is the one
///   answer to "is there a forward action here?", and the footer states why
///   when the answer is no.
/// * **I15 — no raw exception escapes.** Failures become a named [SetupFault]
///   with copy and a recovery label, never a stringified error.
/// * **A superseded flow cannot drag the user backwards.** [SetupState.async]
///   bumps a monotonic [SetupState.generation]; [SetupState.resolve] drops a
///   completion whose token belongs to an older generation.
library;

import '../../domain/domain.dart';

/// The passkey placeholder the wizard renders.
///
/// The app **never** renders a real code — this is a fixed elision, not a
/// reading (N14.6 invariant). It lives here so the pure tests can pin it.
const String kPasskeyPlaceholder = '••••••';

/// The eight named steps, in order.
enum OnboardStep {
  welcome,
  preflight,
  scan,
  passkey,
  sync,
  network,
  name,
  done;

  /// The sheet title for this step.
  String get title => switch (this) {
    OnboardStep.welcome => 'Meet your SmokeBridge',
    OnboardStep.preflight => 'A couple of permissions',
    OnboardStep.scan => 'Looking for your bridge',
    OnboardStep.passkey => 'Enter the code from the bridge',
    OnboardStep.sync => 'Listening for your Smoke X4',
    OnboardStep.network => 'How should we stay in touch?',
    OnboardStep.name => 'Almost there',
    OnboardStep.done => 'You’re all set',
  };

  /// The one-line sub copy under the title.
  String get sub => switch (this) {
    OnboardStep.welcome =>
      'This little box listens to your Smoke X4 and records every reading — '
          'with or without your phone. Let’s connect it.',
    OnboardStep.preflight =>
      'Bluetooth to reach the bridge, and notifications so an alarm can '
          'find you at 3 a.m.',
    OnboardStep.scan =>
      'Hold your phone near the bridge. Its screen shows a 6-digit code '
          'when it is ready.',
    OnboardStep.passkey =>
      'The bridge’s own screen shows six digits. Type them here — not the '
          '“0000 or 1234” your phone suggests.',
    OnboardStep.sync =>
      'Put the Smoke X4 into sync mode. The bridge pairs with it silently.',
    OnboardStep.network =>
      'You can change this any time from Settings. Switching happens over '
          'Bluetooth.',
    OnboardStep.name => 'Name this bridge and pick your units.',
    OnboardStep.done =>
      'Your bridge is paired, listening, and recording. Start a cook or '
          'just watch the numbers.',
  };

  /// The primary action's label (`overlayOnboarding`).
  String get primaryLabel => switch (this) {
    OnboardStep.scan => 'Pair this bridge',
    OnboardStep.passkey => 'Confirm',
    OnboardStep.done => 'Go to Live',
    _ => 'Continue',
  };
}

/// The eight steps, in order (the rail).
const List<OnboardStep> kOnboardSteps = OnboardStep.values;

/// One preflight permission row (`permRow`).
enum OnboardPermission {
  bluetooth,
  notifications,
  location;

  /// The row name.
  String get name => switch (this) {
    OnboardPermission.bluetooth => 'Bluetooth',
    OnboardPermission.notifications => 'Notifications',
    OnboardPermission.location => 'Location',
  };

  /// The row sub copy.
  String get sub => switch (this) {
    OnboardPermission.bluetooth => 'To find and pair with the bridge',
    OnboardPermission.notifications => 'For temperature alarms',
    OnboardPermission.location => 'Only needed on older Android',
  };

  /// Whether the step blocks on this permission. Location is optional.
  bool get required => this != OnboardPermission.location;

  /// The icon name (`SmokeGlyph`) — kept as a string so this file stays pure.
  String get glyph => switch (this) {
    OnboardPermission.bluetooth => 'bluetooth',
    OnboardPermission.notifications => 'bell',
    OnboardPermission.location => 'mapPin',
  };
}

/// The three permissions, in the prototype's order.
const List<OnboardPermission> kOnboardPermissions = OnboardPermission.values;

/// A permission's state. [denied] is resumable: Allow re-grants it (N14.3).
enum PermissionState { unknown, granted, denied }

/// The three hops the wizard walks (research notes §11.5).
enum SetupHop {
  bluetooth,
  baseStation,
  network;

  /// The hop's short name.
  String get name => switch (this) {
    SetupHop.bluetooth => 'Bluetooth',
    SetupHop.baseStation => 'Base station',
    SetupHop.network => 'Network',
  };
}

/// A hop's completion. A skipped hop reads "— not set up" (N14.11).
enum HopStatus {
  notSetUp,
  done,
  skipped;

  /// The status word rendered next to the hop.
  String get label => switch (this) {
    HopStatus.done => 'Paired',
    HopStatus.skipped => 'Skipped',
    HopStatus.notSetUp => '— not set up',
  };
}

/// A named failure with copy and a recovery action (I15).
enum SetupFault {
  none,
  permissionDenied,
  bluetoothOff,
  unsupported,
  noBridges,
  passkeyWrong,
  linkLost,
  heardNothing,
  wifiFailed,
  unreachable;

  /// Whether the fault has no recovery inside the wizard.
  bool get terminal => this == SetupFault.unsupported;

  /// The named title.
  String get title => switch (this) {
    SetupFault.none => '',
    SetupFault.permissionDenied => 'A permission was denied',
    SetupFault.bluetoothOff => 'Bluetooth looks off',
    SetupFault.unsupported => 'This phone cannot pair over Bluetooth',
    SetupFault.noBridges => 'No bridge answered',
    SetupFault.passkeyWrong => 'That code did not match',
    SetupFault.linkLost => 'The bridge went quiet',
    SetupFault.heardNothing => 'We have not heard the base station',
    SetupFault.wifiFailed => 'That network did not work',
    SetupFault.unreachable => 'The bridge could not reach the router',
  };

  /// The named body copy.
  String get body => switch (this) {
    SetupFault.none => '',
    SetupFault.permissionDenied =>
      'The app needs this to reach the bridge. You can allow it now and carry '
          'on where you left off.',
    SetupFault.bluetoothOff =>
      'Turn Bluetooth on in your phone settings, then try again. Nothing has '
          'been lost.',
    SetupFault.unsupported =>
      'This phone has no Bluetooth radio, so it cannot pair with the bridge. '
          'Try another phone.',
    SetupFault.noBridges =>
      'Nothing answered. Check the bridge is powered and close to the phone, '
          'then scan again.',
    SetupFault.passkeyWrong =>
      'The digits did not match the bridge’s screen. Read them again and '
          're-enter.',
    SetupFault.linkLost =>
      'The connection dropped while we were setting up. Move closer and pick '
          'up where you left off.',
    SetupFault.heardNothing =>
      'We have not heard from the Smoke X4 yet. You can wait, or set it up '
          'later — the bridge still records.',
    SetupFault.wifiFailed =>
      'The bridge could not join that network. Bluetooth still works, so '
          'nothing is lost.',
    SetupFault.unreachable =>
      'The bridge reached the network but not the router. Check the network '
          'name and that the router is on.',
  };

  /// The recovery action's label (I6).
  String get recoverLabel => switch (this) {
    SetupFault.none => 'Continue',
    SetupFault.permissionDenied => 'Allow and resume',
    SetupFault.bluetoothOff => 'Try again',
    SetupFault.unsupported => 'Close',
    SetupFault.noBridges => 'Scan again',
    SetupFault.passkeyWrong => 'Re-enter the code',
    SetupFault.linkLost => 'Resume',
    SetupFault.heardNothing => 'Keep listening',
    SetupFault.wifiFailed => 'Use Bluetooth',
    SetupFault.unreachable => 'Try another network',
  };
}

/// The immutable wizard value.
///
/// [generation] is the monotonic guard: [async] bumps it and returns a token;
/// [resolve] applies a completion only while its token is still current.
class SetupState {
  const SetupState({
    this.step = OnboardStep.welcome,
    this.troubleshoot = false,
    this.permissions = const <OnboardPermission, PermissionState>{},
    this.passkeyConfirmed = false,
    this.hops = const <SetupHop, HopStatus>{},
    this.modeId = 'ble',
    this.name = 'Backyard Bridge',
    this.units = TempUnit.fahrenheit,
    this.fault = SetupFault.none,
    this.generation = 0,
  });

  final OnboardStep step;

  /// The "Can't find it?" sub-flow (N14.5).
  final bool troubleshoot;

  final Map<OnboardPermission, PermissionState> permissions;

  /// Whether the (masked) passkey step was confirmed.
  final bool passkeyConfirmed;

  final Map<SetupHop, HopStatus> hops;

  /// The network mode the wizard picked; `ble` is the shipped default.
  final String modeId;

  final String name;
  final TempUnit units;
  final SetupFault fault;
  final int generation;

  /// The permission's state, defaulting to [PermissionState.unknown].
  PermissionState permissionOf(OnboardPermission permission) =>
      permissions[permission] ?? PermissionState.unknown;

  /// The hop's state, defaulting to [HopStatus.notSetUp].
  HopStatus hopOf(SetupHop hop) => hops[hop] ?? HopStatus.notSetUp;

  /// Every required permission is granted.
  bool get requiredPermissionsGranted => kOnboardPermissions
      .where((permission) => permission.required)
      .every(
        (permission) => permissionOf(permission) == PermissionState.granted,
      );

  /// Whether the current step has a forward action (I6).
  bool get canAdvance => switch (step) {
    OnboardStep.welcome => true,
    OnboardStep.preflight => requiredPermissionsGranted && !fault.terminal,
    OnboardStep.scan =>
      hopOf(SetupHop.bluetooth) == HopStatus.done && !fault.terminal,
    OnboardStep.passkey => passkeyConfirmed,
    OnboardStep.sync => hopOf(SetupHop.baseStation) != HopStatus.notSetUp,
    OnboardStep.network => true,
    OnboardStep.name => name.trim().isNotEmpty,
    OnboardStep.done => true,
  };

  /// The reason the forward action is unavailable (I5), or null.
  String? get blockedReason {
    if (canAdvance) {
      return null;
    }
    return switch (step) {
      OnboardStep.preflight =>
        fault == SetupFault.permissionDenied
            ? fault.body
            : 'Allow the two permissions to continue',
      OnboardStep.scan => 'Waiting for a bridge to answer',
      OnboardStep.passkey => 'Read the six digits off the bridge and confirm',
      OnboardStep.sync => 'Listen for the base station, or set it up later',
      OnboardStep.name => 'Give this bridge a name to continue',
      _ => null,
    };
  }

  SetupState copyWith({
    OnboardStep? step,
    bool? troubleshoot,
    Map<OnboardPermission, PermissionState>? permissions,
    bool? passkeyConfirmed,
    Map<SetupHop, HopStatus>? hops,
    String? modeId,
    String? name,
    TempUnit? units,
    SetupFault? fault,
    int? generation,
  }) => SetupState(
    step: step ?? this.step,
    troubleshoot: troubleshoot ?? this.troubleshoot,
    permissions: permissions ?? this.permissions,
    passkeyConfirmed: passkeyConfirmed ?? this.passkeyConfirmed,
    hops: hops ?? this.hops,
    modeId: modeId ?? this.modeId,
    name: name ?? this.name,
    units: units ?? this.units,
    fault: fault ?? this.fault,
    generation: generation ?? this.generation,
  );

  /// Move to the next step when [canAdvance], clearing the "missing bridge"
  /// fault that belonged to the scan step.
  SetupState next() {
    if (!canAdvance) {
      return this;
    }
    final index = step.index;
    if (index >= kOnboardSteps.length - 1) {
      return this;
    }
    return copyWith(
      step: kOnboardSteps[index + 1],
      fault: fault == SetupFault.noBridges ? SetupFault.none : fault,
    );
  }

  /// Move back one step, never past the first.
  SetupState back() {
    final index = step.index;
    if (index <= 0) {
      return this;
    }
    return copyWith(step: kOnboardSteps[index - 1]);
  }

  /// Grant [permission] and clear a matching denial fault (N14.3).
  SetupState allow(OnboardPermission permission) => copyWith(
    permissions: <OnboardPermission, PermissionState>{
      ...permissions,
      permission: PermissionState.granted,
    },
    fault: fault == SetupFault.permissionDenied ? SetupFault.none : fault,
  );

  /// Deny [permission]: a resumable, named state (N14.3).
  SetupState deny(OnboardPermission permission) => copyWith(
    permissions: <OnboardPermission, PermissionState>{
      ...permissions,
      permission: PermissionState.denied,
    },
    fault: SetupFault.permissionDenied,
  );

  /// The scan found the bridge.
  SetupState foundBridge() => copyWith(
    hops: <SetupHop, HopStatus>{...hops, SetupHop.bluetooth: HopStatus.done},
    fault: fault == SetupFault.noBridges ? SetupFault.none : fault,
  );

  /// Open the "Can't find it?" sub-flow.
  SetupState startTroubleshoot() => copyWith(troubleshoot: true);

  /// Leave the sub-flow without moving (Back/Try again).
  SetupState stopTroubleshoot() => copyWith(troubleshoot: false);

  /// The (masked) passkey was confirmed. No code is ever stored (invariant).
  SetupState confirmPasskey() => copyWith(passkeyConfirmed: true);

  /// The base station was heard.
  SetupState heardBase() => copyWith(
    hops: <SetupHop, HopStatus>{...hops, SetupHop.baseStation: HopStatus.done},
    fault: fault == SetupFault.heardNothing ? SetupFault.none : fault,
  );

  /// Set the base station up later: the hop then reads "— not set up".
  SetupState skipBase() => copyWith(
    hops: <SetupHop, HopStatus>{
      ...hops,
      SetupHop.baseStation: HopStatus.skipped,
    },
  );

  /// Pick a network mode and stamp the network hop.
  SetupState selectMode(String id) => copyWith(
    modeId: id,
    hops: <SetupHop, HopStatus>{...hops, SetupHop.network: HopStatus.done},
  );

  SetupState setName(String value) => copyWith(name: value);
  SetupState setUnits(TempUnit value) => copyWith(units: value);

  /// Enter a named failure state (I15).
  SetupState fail(SetupFault value) => copyWith(fault: value);

  /// A superseded flow cannot drag the user backwards: bump the generation and
  /// return the new state. Its [token] is what a completion must present.
  SetupState beginAsync() => copyWith(generation: generation + 1);

  /// The token for the current generation.
  SetupToken get token => SetupToken._(generation);

  /// Apply [transform] only when [token] is still the current generation.
  SetupState resolve(
    SetupToken token,
    SetupState Function(SetupState) transform,
  ) => token.generation == generation ? transform(this) : this;

  /// The hop summary the done step prints. A skipped hop reads "— not set up".
  List<SetupHopRow> get hopSummary => <SetupHopRow>[
    for (final hop in SetupHop.values)
      SetupHopRow(hop, switch (hop) {
        SetupHop.bluetooth => hopOf(hop),
        SetupHop.baseStation => hopOf(hop),
        SetupHop.network => hopOf(hop),
      }),
  ];
}

/// A completion token bound to one generation of [SetupState].
class SetupToken {
  SetupToken._(this.generation);

  final int generation;
}

/// One row of the done step's hop summary.
class SetupHopRow {
  const SetupHopRow(this.hop, this.status);

  final SetupHop hop;
  final HopStatus status;

  /// The status word; [HopStatus.notSetUp] renders "— not set up" (N14.11).
  String get statusLabel => status.label;
}
