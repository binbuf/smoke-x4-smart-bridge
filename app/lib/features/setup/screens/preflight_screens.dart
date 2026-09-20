/// A23.3 — the hop-0 preflight screens (design 13 §13.2.0, 14 §14.7.1/§14.7.4).
///
/// WHY these exist: `grep -rn "adapterState|permission_handler"` returns zero
/// hits in the shipping app (§13.2.0), which is the root of failure #5 — a
/// phone with Bluetooth off, permission denied, or no BLE radio all collapse
/// into "No bridges found". These five screens are the gate the product never
/// had. Each projects one preflight [SetupState] onto a [SetupScaffold] with a
/// single [PrimaryAction] and an honest next step; the copy is [SetupCopy]'s,
/// and every branch of the §13.2.0 truth table gets its own words.
///
/// **The platform deep-links are an injected seam.** "Open Bluetooth settings",
/// "Open app settings", "Open location settings" reach through
/// `platform/system_settings.dart` (§13.2.0), which this task does not own and
/// which is not wired yet. They arrive as [SetupExternals] callbacks so the
/// screens stay pump-testable with no MethodChannel; when a link is absent its
/// button disables rather than lying, and a machine-backed secondary ("I turned
/// it on", "I've allowed it") always keeps a live next step (rail R2, §13.2).
library;

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../ui/ui.dart';
import '../copy/setup_copy.dart';
import '../setup_machine.dart';

/// The out-of-machine actions the setup screens offer — platform deep-links and
/// the route-level exit — injected because none of them is a [SetupMachine]
/// method: they open OS settings (`platform/system_settings.dart`, §13.2.0),
/// pop the `/setup` route, or reach ops this task does not own (op 15 phone
/// removal, §13.8.3; manual address entry, §13.2.1). A `null` callback disables
/// its control; the machine-backed action beside it stays live.
class SetupExternals {
  const SetupExternals({
    this.onLeaveSetup,
    this.openBluetoothSettings,
    this.openAppSettings,
    this.openLocationSettings,
    this.openNotificationSettings,
    this.enterAddressManually,
    this.removeAPairedPhone,
  });

  /// The scaffold exit (the ✕): leaves the `/setup` route entirely. Distinct
  /// from [SetupMachine.cancel], which rests at a stable state *within* setup.
  final VoidCallback? onLeaveSetup;

  final VoidCallback? openBluetoothSettings;
  final VoidCallback? openAppSettings;
  final VoidCallback? openLocationSettings;
  final VoidCallback? openNotificationSettings;

  /// The returning-user escape from "no bridges" — manual address entry, which
  /// lives in `/recover` (§13.2.1), not on the machine.
  final VoidCallback? enterAddressManually;

  /// `SetupBondSlotsFull`'s "Remove a phone" — needs `device_control{op 15}`,
  /// which does not exist yet (§13.8.3). Deferred; the button disables until it
  /// lands, and "Choose a different bridge" carries the state meanwhile.
  final VoidCallback? removeAPairedPhone;
}

/// The hop-0 dispatcher: a preflight [SetupState] to its screen, or `null` for
/// anything outside hop 0. Exhaustive over the sealed [PreflightState] tree, so
/// a new preflight state that has no screen fails analysis rather than shipping
/// a blank.
Widget? preflightScreenFor(
  SetupState state,
  SetupMachine machine, {
  SetupExternals externals = const SetupExternals(),
}) {
  if (state is! PreflightState) {
    return null;
  }
  return switch (state) {
    SetupPermissionPrimer() => _PrimerScreen(machine, externals),
    SetupBluetoothOff() => _BluetoothOffScreen(machine, externals),
    SetupBluetoothUnsupported() => _UnsupportedScreen(externals),
    SetupPermissionDenied() => _PermissionDeniedScreen(
      state,
      machine,
      externals,
    ),
    SetupLocationServicesOff() => _LocationOffScreen(machine, externals),
  };
}

// ── check 2: the permission primer (§13.2.0) ────────────────────────────────

class _PrimerScreen extends StatelessWidget {
  const _PrimerScreen(this.machine, this.externals);

  final SetupMachine machine;
  final SetupExternals externals;

  @override
  Widget build(BuildContext context) => SetupScaffold(
    hop: 0,
    title: SetupCopy.primerTitle,
    subtitle: SetupCopy.primerBody,
    onExit: externals.onLeaveSetup,
    body: const _Reassurance([
      SetupCopy.primerReassure1,
      SetupCopy.primerReassure2,
      SetupCopy.primerReassure3,
    ]),
    primary: PrimaryAction(
      label: SetupCopy.primerPrimary,
      onPressed: () => machine.continueFromPrimer(),
    ),
    secondary: SetupTextAction(SetupCopy.primerNotNow, externals.onLeaveSetup),
  );
}

// ── check 4: Bluetooth off (§13.2.0) ────────────────────────────────────────

class _BluetoothOffScreen extends StatelessWidget {
  const _BluetoothOffScreen(this.machine, this.externals);

  final SetupMachine machine;
  final SetupExternals externals;

  @override
  Widget build(BuildContext context) {
    // Prefer the OS deep-link; fall back to a re-check the user can always run.
    final open = externals.openBluetoothSettings;
    final secondary = open != null
        ? SetupTextAction(SetupCopy.btOffOpenSettings, open)
        : SetupTextAction(
            SetupCopy.btOffTurnedOn,
            () => machine.recheckPreflight(),
          );
    return SetupScaffold(
      hop: 0,
      title: SetupCopy.btOffTitle,
      subtitle: SetupCopy.btOffBody,
      onExit: externals.onLeaveSetup,
      body: const _Glyph(Icons.bluetooth_disabled_rounded),
      primary: PrimaryAction(
        label: SetupCopy.btOffPrimary,
        icon: Icons.bluetooth_rounded,
        onPressed: () => machine.enableBluetooth(),
      ),
      secondary: secondary,
    );
  }
}

// ── check 0: no BLE hardware — terminal (§13.2.0) ────────────────────────────

class _UnsupportedScreen extends StatelessWidget {
  const _UnsupportedScreen(this.externals);

  final SetupExternals externals;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Terminal: no primary, no exit — the instruction *is* the screen, because
    // a button that leads nowhere is worse than an admitted dead end (§14.7.1).
    return SetupScaffold(
      hop: 0,
      title: SetupCopy.unsupportedTitle,
      errorTint: true,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Glyph(
              Icons.bluetooth_disabled_rounded,
              tone: _Tone.critical,
            ),
            const SizedBox(height: SmokeTokens.s5),
            Text(
              SetupCopy.unsupportedBody,
              style: SmokeType.body.copyWith(color: t.textBody),
            ),
          ],
        ),
      ),
    );
  }
}

// ── check 3: permission denied (§13.2.0) ────────────────────────────────────

class _PermissionDeniedScreen extends StatelessWidget {
  const _PermissionDeniedScreen(this.state, this.machine, this.externals);

  final SetupPermissionDenied state;
  final SetupMachine machine;
  final SetupExternals externals;

  @override
  Widget build(BuildContext context) {
    if (state.permanent) {
      // The OS will never prompt again: the only route is app settings, with a
      // re-check beside it once the user has toggled it there.
      return SetupScaffold(
        hop: 0,
        title: SetupCopy.deniedPermanentTitle,
        subtitle: SetupCopy.deniedPermanentBody,
        errorTint: true,
        onExit: externals.onLeaveSetup,
        body: const _Glyph(Icons.settings_rounded),
        primary: PrimaryAction(
          label: SetupCopy.deniedOpenAppSettings,
          icon: Icons.open_in_new_rounded,
          onPressed: externals.openAppSettings,
        ),
        secondary: SetupTextAction(
          SetupCopy.deniedAllowed,
          () => machine.recheckPreflight(),
        ),
      );
    }
    // A soft denial: "Allow" can prompt again.
    return SetupScaffold(
      hop: 0,
      title: SetupCopy.deniedTitle,
      subtitle: SetupCopy.deniedBody,
      onExit: externals.onLeaveSetup,
      body: const _Glyph(Icons.bluetooth_searching_rounded),
      primary: PrimaryAction(
        label: SetupCopy.deniedAllow,
        onPressed: () => machine.continueFromPrimer(),
      ),
      secondary: SetupTextAction(
        SetupCopy.deniedNotNow,
        externals.onLeaveSetup,
      ),
    );
  }
}

// ── check 1: location services off (§13.2.0) ────────────────────────────────

class _LocationOffScreen extends StatelessWidget {
  const _LocationOffScreen(this.machine, this.externals);

  final SetupMachine machine;
  final SetupExternals externals;

  @override
  Widget build(BuildContext context) => SetupScaffold(
    hop: 0,
    title: SetupCopy.locationTitle,
    subtitle: SetupCopy.locationBody,
    onExit: externals.onLeaveSetup,
    body: const _Glyph(Icons.location_on_rounded),
    primary: Builder(
      builder: (context) => disabledReason(
        context,
        PrimaryAction(
          label: SetupCopy.locationOpenSettings,
          icon: Icons.open_in_new_rounded,
          onPressed: externals.openLocationSettings,
        ),
        enabled: externals.openLocationSettings != null,
        reason: SetupCopy.noDeepLinkLocation,
      ),
    ),
    secondary: SetupTextAction(
      SetupCopy.locationTurnedOn,
      () => machine.recheckPreflight(),
    ),
  );
}

// ── shared presentation, kept internal to the setup feature ──────────────────

/// The tint of a [_Glyph] anchor icon.
enum _Tone { muted, critical }

/// A centred anchor glyph — the single visual on a mostly-textual gate screen.
class _Glyph extends StatelessWidget {
  const _Glyph(this.icon, {this.tone = _Tone.muted});

  final IconData icon;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = tone == _Tone.critical ? StatusPalette.critical : t.textMuted;
    return Center(child: Icon(icon, size: 64, color: color));
  }
}

/// The primer's three plain-language promises, as a card of ticked rows — the
/// trust screen (§13.2.0 check 2) earns the OS prompt, so it states plainly
/// what the permission is and is not for.
class _Reassurance extends StatelessWidget {
  const _Reassurance(this.lines);

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Align(
      alignment: Alignment.topCenter,
      child: SmokeCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) const SizedBox(height: SmokeTokens.s3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A bullet, not a status. These three lines are promises
                  // about what the app does *not* do; nothing here has passed,
                  // connected or recovered. Green means transport health and
                  // nothing else (16 §16.5), and this screen is the first one
                  // a new user reads — whatever green means here is what it
                  // will seem to mean on the transport chip afterwards. So the
                  // tick is ink: the words carry the content, the glyph just
                  // marks the row.
                  Icon(Icons.check_rounded, size: 18, color: t.textHi),
                  const SizedBox(width: SmokeTokens.s2),
                  Expanded(
                    child: Text(
                      lines[i],
                      style: SmokeType.body.copyWith(color: t.textBody),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The named secondary — a plain text action under the primary. A `null`
/// callback renders it disabled rather than hiding it, so the layout is stable
/// and the control reads as "not available here" (§13.2.0's deep-links).
///
/// A disabled control **must carry its reason** (16 §16.5). Pass [reason] and
/// it renders directly beneath, dimmed; a control with no reason and no
/// callback would be the dead control the rules forbid.
class SetupTextAction extends StatelessWidget {
  const SetupTextAction(this.label, this.onPressed, {this.reason, super.key});

  final String label;
  final VoidCallback? onPressed;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final button = TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: t.textBody,
        disabledForegroundColor: t.textMuted,
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
    return disabledReason(
      context,
      button,
      enabled: onPressed != null,
      reason: reason,
    );
  }
}

/// Renders [control], and — when it cannot work — the reason directly beneath
/// it (16 §16.5's disabled row, and the hard rule that a control which cannot
/// work is absent or disabled with its reason).
///
/// Shared by the preflight and hop-1 screens because the same four platform
/// deep-links are missing on both, and a reason shown on one screen and
/// swallowed on the next is worse than neither.
Widget disabledReason(
  BuildContext context,
  Widget control, {
  required bool enabled,
  String? reason,
}) {
  if (enabled || reason == null || reason.isEmpty) {
    return control;
  }
  final t = context.tokens;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      control,
      const SizedBox(height: SmokeTokens.s2),
      Text(
        reason,
        textAlign: TextAlign.center,
        style: SmokeType.bodySm.copyWith(color: t.textMuted),
      ),
    ],
  );
}
