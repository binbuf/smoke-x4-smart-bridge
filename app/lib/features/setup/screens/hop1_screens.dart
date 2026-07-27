/// A23.3 — the hop-1 screens: phone ↔ bridge over BLE (design 13 §13.2.1,
/// 14 §14.7.1/§14.7.4).
///
/// WHY hop 1 is ten screens and not one: today every BLE exception funnels to a
/// single "Pairing was declined" (`wizard.dart:306-318`), telling a user they
/// mistyped a code they were never shown, and offering "retry" on three
/// failures retrying can never fix (§13.2.1). Here the find list, the passkey
/// screen, the 3 s "Paired" payoff and the *four distinct* bond outcomes each
/// get their own words and their own honest next step, so the copy can name the
/// cause instead of collapsing six of them into one wrong sentence.
///
/// The passkey screen uses [PasskeyDisplay], which is *incapable* of rendering
/// a real code (§13.2.1): the six digits are generated on the bridge and this
/// phone never learns them, so the screen points at the glass, it does not host
/// a field. This file also exposes [setupScreenFor], the hop-0/hop-1 slice of
/// the `/setup` screen dispatcher.
library;

import 'package:flutter/material.dart';

import '../../../data/transport/ble_transport.dart';
import '../../../design/design.dart';
import '../../../ui/ui.dart';
import '../copy/setup_copy.dart';
import '../setup_machine.dart';
import 'preflight_screens.dart';

/// The `/setup` screen dispatcher for **hop 0 and hop 1** (§13.5.1). It is the
/// first link of a chain: the hop-2/hop-3/finish builders (other tasks) handle
/// what this returns `null` for, so a route composes them as
/// `setupScreenFor(s, m) ?? hop2ScreenFor(...) ?? …`. Pure — it reads the state
/// and returns a widget, nothing else.
Widget? setupScreenFor(
  SetupState state,
  SetupMachine machine, {
  SetupExternals externals = const SetupExternals(),
}) =>
    preflightScreenFor(state, machine, externals: externals) ??
    hop1ScreenFor(state, machine, externals: externals);

/// The hop-1 dispatcher, exhaustive over the sealed [Hop1State] tree so a new
/// hop-1 state with no screen fails analysis.
Widget? hop1ScreenFor(
  SetupState state,
  SetupMachine machine, {
  SetupExternals externals = const SetupExternals(),
}) {
  if (state is! Hop1State) {
    return null;
  }
  return switch (state) {
    SetupScanning() => _ScanningScreen(state, machine, externals),
    SetupNoBridges() => _NoBridgesScreen(machine, externals),
    SetupAddThisPhone() => _AddThisPhoneScreen(state, machine, externals),
    SetupPairing() => _PairingScreen(state, machine, externals),
    SetupPasskeyNotSeen() => _PasskeyNotSeenScreen(machine, externals),
    SetupBonded() => _BondedScreen(state, machine, externals),
    SetupPasskeyWrong() => _PasskeyWrongScreen(machine, externals),
    SetupRebondNeeded() => _RebondNeededScreen(machine, externals),
    SetupBondSlotsFull() => _BondSlotsFullScreen(machine, externals),
    SetupNotABridge() => _NotABridgeScreen(machine, externals),
  };
}

// ── the scan / find list (§13.2.1) ──────────────────────────────────────────

class _ScanningScreen extends StatelessWidget {
  const _ScanningScreen(this.state, this.machine, this.externals);

  final SetupScanning state;
  final SetupMachine machine;
  final SetupExternals externals;

  @override
  Widget build(BuildContext context) {
    // Strongest signal first (§13.2.1). The machine already sorts; re-sorting
    // here keeps the screen correct even if handed an unsorted list.
    final rows = [...state.found]..sort((a, b) => b.rssi.compareTo(a.rssi));
    final Widget body = rows.isEmpty
        ? const _SearchingPulse()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.scanning) const _SearchingBar(),
              Expanded(
                child: ListView.separated(
                  key: const Key('setup-scan-list'),
                  padding: const EdgeInsets.symmetric(vertical: SmokeTokens.s2),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: SmokeTokens.s3),
                  itemBuilder: (context, i) => _BridgeRow(
                    bridge: rows[i],
                    // NEEDS blob bits bonds_full/paired+net (13 §13.8.3): the
                    // parser is another task's, so both forks pass false for now
                    // and every row runs the full flow.
                    onTap: () => machine.select(rows[i]),
                  ),
                ),
              ),
            ],
          );
    return SetupScaffold(
      hop: 1,
      title: SetupCopy.scanningTitle,
      subtitle: SetupCopy.scanningBody,
      onExit: externals.onLeaveSetup,
      body: body,
      secondary: _TextAction(SetupCopy.scanningCancel, () => machine.cancel()),
    );
  }
}

class _BridgeRow extends StatelessWidget {
  const _BridgeRow({required this.bridge, required this.onTap});

  final BridgeDiscovery bridge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SmokeCard(
      key: Key('setup-bridge-${bridge.deviceId}'),
      onTap: onTap,
      child: Row(
        children: [
          Icon(Icons.outdoor_grill_rounded, color: StatusPalette.pit, size: 28),
          const SizedBox(width: SmokeTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bridge.name,
                  style: SmokeType.title.copyWith(color: t.textHi),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: SmokeTokens.s1),
                Text(
                  _blobLine(bridge),
                  style: SmokeType.bodySm.copyWith(color: t.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: SmokeTokens.s2),
          Icon(Icons.chevron_right_rounded, color: t.textMuted),
        ],
      ),
    );
  }
}

// ── 10 s, nothing found — the checklist (§13.2.1) ────────────────────────────

class _NoBridgesScreen extends StatelessWidget {
  const _NoBridgesScreen(this.machine, this.externals);

  final SetupMachine machine;
  final SetupExternals externals;

  @override
  Widget build(BuildContext context) => SetupScaffold(
    hop: 1,
    title: SetupCopy.noBridgesTitle,
    onExit: externals.onLeaveSetup,
    body: const SingleChildScrollView(
      child: _Checklist([
        SetupCopy.noBridgesCheck1,
        SetupCopy.noBridgesCheck2,
        SetupCopy.noBridgesCheck3,
      ]),
    ),
    primary: PrimaryAction(
      label: SetupCopy.noBridgesLookAgain,
      icon: Icons.refresh_rounded,
      onPressed: () => machine.startScan(),
    ),
    secondary: _TextAction(
      SetupCopy.noBridgesManual,
      externals.enterAddressManually,
    ),
  );
}

// ── the already-provisioned fork (§13.2.1) ───────────────────────────────────

class _AddThisPhoneScreen extends StatelessWidget {
  const _AddThisPhoneScreen(this.state, this.machine, this.externals);

  final SetupAddThisPhone state;
  final SetupMachine machine;
  final SetupExternals externals;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SetupScaffold(
      hop: 1,
      title: SetupCopy.addPhoneTitle,
      subtitle: SetupCopy.addPhoneBody,
      onExit: externals.onLeaveSetup,
      body: Align(
        alignment: Alignment.topCenter,
        child: SmokeCard(
          accent: StatusPalette.pit,
          child: Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: StatusPalette.pit,
                size: 28,
              ),
              const SizedBox(width: SmokeTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.bridge.name,
                      style: SmokeType.title.copyWith(color: t.textHi),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: SmokeTokens.s1),
                    Text(
                      _blobLine(state.bridge),
                      style: SmokeType.bodySm.copyWith(color: t.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      primary: PrimaryAction(
        label: SetupCopy.addPhonePrimary,
        onPressed: () => machine.confirmAddThisPhone(),
      ),
      secondary: _TextAction(
        SetupCopy.addPhoneOther,
        () => machine.startScan(),
      ),
    );
  }
}

// ── the passkey screen (§13.2.1) ─────────────────────────────────────────────

class _PairingScreen extends StatelessWidget {
  const _PairingScreen(this.state, this.machine, this.externals);

  final SetupPairing state;
  final SetupMachine machine;
  final SetupExternals externals;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final status = state.passkeyShown
        ? SetupCopy.pairWaiting
        : SetupCopy.connectingTo(state.bridge.name);
    return SetupScaffold(
      hop: 1,
      title: SetupCopy.pairTitle,
      subtitle: SetupCopy.pairBody,
      onExit: externals.onLeaveSetup,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PasskeyDisplay(),
            const SizedBox(height: SmokeTokens.s6),
            Text(
              status,
              key: const Key('setup-pair-status'),
              textAlign: TextAlign.center,
              style: SmokeType.bodySm.copyWith(color: t.textMuted),
            ),
          ],
        ),
      ),
      // The 30 s watchdog fires this from the machine's own timer; the button
      // lets a user who is stuck reach the same "no prompt" help sooner.
      primary: PrimaryAction(
        label: SetupCopy.pairNoPrompt,
        onPressed: () => machine.passkeyNotSeen(),
      ),
      secondary: _TextAction(SetupCopy.pairCancel, () => machine.cancel()),
    );
  }
}

// ── 30 s, no OS prompt (§13.2.1) ─────────────────────────────────────────────

class _PasskeyNotSeenScreen extends StatelessWidget {
  const _PasskeyNotSeenScreen(this.machine, this.externals);

  final SetupMachine machine;
  final SetupExternals externals;

  @override
  Widget build(BuildContext context) => SetupScaffold(
    hop: 1,
    title: SetupCopy.notSeenTitle,
    subtitle: SetupCopy.notSeenBody,
    onExit: externals.onLeaveSetup,
    body: const _Glyph(Icons.notifications_active_rounded),
    primary: PrimaryAction(
      label: SetupCopy.notSeenCheckNotifications,
      icon: Icons.open_in_new_rounded,
      onPressed: externals.openNotificationSettings,
    ),
    secondary: _TextAction(
      SetupCopy.notSeenRetry,
      () => machine.retryPasskey(),
    ),
  );
}

// ── bond succeeded — the 3 s payoff (§13.2.1) ────────────────────────────────

class _BondedScreen extends StatelessWidget {
  const _BondedScreen(this.state, this.machine, this.externals);

  final SetupBonded state;
  final SetupMachine machine;
  final SetupExternals externals;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SetupScaffold(
      hop: 1,
      title: SetupCopy.bondedTitle,
      subtitle: SetupCopy.bondedBody,
      onExit: externals.onLeaveSetup,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Glyph(Icons.check_circle_rounded, tone: _Tone.pit),
            const SizedBox(height: SmokeTokens.s4),
            Text(
              state.bridge.name,
              style: SmokeType.body.copyWith(color: t.textBody),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      primary: PrimaryAction(
        label: SetupCopy.bondedContinue,
        onPressed: () => machine.startHop2(),
      ),
    );
  }
}

// ── bond outcome 1 of 4: wrong passkey (§13.2.1) ─────────────────────────────

class _PasskeyWrongScreen extends StatelessWidget {
  const _PasskeyWrongScreen(this.machine, this.externals);

  final SetupMachine machine;
  final SetupExternals externals;

  @override
  Widget build(BuildContext context) => SetupScaffold(
    hop: 1,
    title: SetupCopy.wrongTitle,
    subtitle: SetupCopy.wrongBody,
    errorTint: true,
    onExit: externals.onLeaveSetup,
    body: const _Glyph(Icons.password_rounded, tone: _Tone.critical),
    // "Try again" is a five-step re-bond choreography shown as one action
    // (§13.2.1); the user sees one button.
    primary: PrimaryAction(
      label: SetupCopy.wrongRetry,
      onPressed: () => machine.retryPasskey(),
    ),
    secondary: _TextAction(SetupCopy.wrongStartOver, () => machine.restart()),
  );
}

// ── bond outcome 2 of 4: the bridge was reset (§13.2.1) ──────────────────────

class _RebondNeededScreen extends StatelessWidget {
  const _RebondNeededScreen(this.machine, this.externals);

  final SetupMachine machine;
  final SetupExternals externals;

  @override
  Widget build(BuildContext context) => SetupScaffold(
    hop: 1,
    title: SetupCopy.rebondTitle,
    subtitle: SetupCopy.rebondBody,
    errorTint: true,
    onExit: externals.onLeaveSetup,
    body: const _Glyph(Icons.bluetooth_disabled_rounded, tone: _Tone.critical),
    primary: PrimaryAction(
      label: SetupCopy.rebondOpenSettings,
      icon: Icons.open_in_new_rounded,
      onPressed: externals.openBluetoothSettings,
    ),
    secondary: _TextAction(SetupCopy.rebondRetry, () => machine.retryPasskey()),
  );
}

// ── bond outcome 3 of 4: bond slots full (§13.2.1) ───────────────────────────

class _BondSlotsFullScreen extends StatelessWidget {
  const _BondSlotsFullScreen(this.machine, this.externals);

  final SetupMachine machine;
  final SetupExternals externals;

  @override
  Widget build(BuildContext context) => SetupScaffold(
    hop: 1,
    title: SetupCopy.fullTitle,
    subtitle: SetupCopy.fullBody,
    errorTint: true,
    onExit: externals.onLeaveSetup,
    body: const _Glyph(Icons.phonelink_lock_rounded, tone: _Tone.critical),
    // "Choose a different bridge" is the always-live route; "Remove a phone"
    // needs op 15 (§13.8.3) and disables until it lands.
    primary: PrimaryAction(
      label: SetupCopy.fullChooseOther,
      onPressed: () => machine.startScan(),
    ),
    secondary: _TextAction(
      SetupCopy.fullRemovePhone,
      externals.removeAPairedPhone,
    ),
  );
}

// ── bond outcome 4 of 4: not a bridge — terminal, no retry (§13.2.1) ─────────

class _NotABridgeScreen extends StatelessWidget {
  const _NotABridgeScreen(this.machine, this.externals);

  final SetupMachine machine;
  final SetupExternals externals;

  @override
  Widget build(BuildContext context) => SetupScaffold(
    hop: 1,
    title: SetupCopy.notBridgeTitle,
    subtitle: SetupCopy.notBridgeBody,
    errorTint: true,
    onExit: externals.onLeaveSetup,
    body: const _Glyph(Icons.device_unknown_rounded, tone: _Tone.critical),
    // No retry — retrying an unretryable failure can only lie. Only "pick
    // another device" (§13.2.1), which restarts the scan.
    primary: PrimaryAction(
      label: SetupCopy.notBridgeChoose,
      onPressed: () => machine.startScan(),
    ),
  );
}

// ── the §2.3 blob line, unchanged from `onboarding_screens.dart:157-171` ─────

/// "pit 243 °F · 4 h 12 m" — and nothing at all rather than a made-up number
/// when the pit probe is detached (`pitTempF10` is null, never 0).
String _blobLine(BridgeDiscovery b) {
  final parts = <String>[];
  if (b.pitTempF10 != null) {
    parts.add('pit ${(b.pitTempF10! / 10).toStringAsFixed(1)} °F');
  }
  if (b.sessionActive && b.sessionMinutes > 0) {
    final h = b.sessionMinutes ~/ 60;
    final m = b.sessionMinutes % 60;
    parts.add(h > 0 ? '$h h $m m' : '$m m');
  }
  if (parts.isEmpty) {
    parts.add(b.paired ? SetupCopy.rowPairedIdle : SetupCopy.rowNotPaired);
  }
  return parts.join(' · ');
}

// ── shared presentation, internal to hop 1 ───────────────────────────────────

/// The tint of a [_Glyph] anchor icon: neutral, a failure red, or the ember of
/// a success payoff.
enum _Tone { muted, critical, pit }

class _Glyph extends StatelessWidget {
  const _Glyph(this.icon, {this.tone = _Tone.muted});

  final IconData icon;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = switch (tone) {
      _Tone.muted => t.textMuted,
      _Tone.critical => StatusPalette.critical,
      _Tone.pit => StatusPalette.pit,
    };
    return Center(child: Icon(icon, size: 64, color: color));
  }
}

/// The "nothing found" checklist — ticked tells of the bridge, not a bare
/// "is it on?" (§13.2.1).
class _Checklist extends StatelessWidget {
  const _Checklist(this.lines);

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const SizedBox(height: SmokeTokens.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 20,
                color: t.textMuted,
              ),
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
    );
  }
}

/// The searching cue while the list is still empty.
class _SearchingPulse extends StatelessWidget {
  const _SearchingPulse();

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 28,
      height: 28,
      child: CircularProgressIndicator(
        strokeWidth: 3,
        valueColor: AlwaysStoppedAnimation<Color>(StatusPalette.pit),
        backgroundColor: context.tokens.cardSubtle,
      ),
    ),
  );
}

/// A thin "still searching" bar above a list that already has a row or two.
class _SearchingBar extends StatelessWidget {
  const _SearchingBar();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SmokeTokens.radiusPill),
        child: LinearProgressIndicator(
          minHeight: 2,
          valueColor: AlwaysStoppedAnimation<Color>(StatusPalette.pit),
          backgroundColor: t.cardSubtle,
        ),
      ),
    );
  }
}

/// The named secondary — a plain text action under the primary. A `null`
/// callback disables it in place, so the layout stays stable and the control
/// reads as "not available here" rather than vanishing.
class _TextAction extends StatelessWidget {
  const _TextAction(this.label, this.onPressed);

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: t.textBody,
        disabledForegroundColor: t.textMuted,
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}
