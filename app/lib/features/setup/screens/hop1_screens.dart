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
///
/// ## What 17 §17.3 C added, and why
///
/// A bench run found hop 1 *correct and empty*: a rail, a title, one sentence,
/// one device row, on black. 17 §17.1 #4 names that as the fourth gap against
/// the competitors — *"`Meater-1` and `Meater-3` sell the product on the setup
/// screen"* — so hop 1 now has a **subject** ([BridgeIllustration], drawn not
/// bundled) and a found-device row substantial enough to be the moment of
/// contact it is: the device drawn small, its name, its signal as bars **and a
/// word** (never a dBm figure — 16 §16.4 rule 3), and its pairing state.
///
/// And it added the one thing on this hop that was actively misleading. Tapping
/// a row used to start bonding immediately, at which point the *platform* puts
/// up its own pairing dialog hinting **"Usually 0000 or 1234"**. That is wrong
/// for this device and cannot be changed from here, so the last thing a user
/// read before being asked for six digits was a wrong guess at them. There is
/// now a step between the tap and the bond — [_ScanningScreenState._coach] —
/// that says what is about to happen and corrects the hint *before* the dialog
/// can appear. It is screen state, not machine state: the flow, its guards and
/// its persistence are untouched.
///
/// **On the palette:** 17 §17.5 makes the colour discipline proportional to
/// live state — §16.5 guards against a hue lying about how a cook is going, and
/// hop 1 has no session, no probes and no readings for a hue to lie about. So
/// these screens are warm: a lit illustration, ember-accented device cards,
/// ember-filled step markers, an ember progress rail. The two clauses that hold
/// in every state hold here too — no colour is the *sole* carrier of anything
/// (every warm mark is paired with a glyph, a numeral or a word), and there is
/// no green anywhere on this hop, because green means transport health and a
/// bond is not a celebration to spend it on.
library;

import 'package:flutter/material.dart';

import '../../../core/signal.dart';
import '../../../data/transport/ble_transport.dart';
import '../../../design/design.dart';
import '../../../ui/setup/device_art.dart';
import '../../../ui/setup/setup_steps.dart';
import '../../../ui/ui.dart';
import '../copy/setup_copy.dart';
import '../copy/setup_resume_copy.dart';
import '../setup_entry.dart';
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
    SetupRebondNeeded() => _RebondNeededScreen(state, machine, externals),
    SetupBondSlotsFull() => _BondSlotsFullScreen(machine, externals),
    SetupNotABridge() => _NotABridgeScreen(machine, externals),
  };
}

// ── the scan / find list (§13.2.1) ──────────────────────────────────────────

class _ScanningScreen extends StatefulWidget {
  const _ScanningScreen(this.state, this.machine, this.externals);

  final SetupScanning state;
  final SetupMachine machine;
  final SetupExternals externals;

  @override
  State<_ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends State<_ScanningScreen> {
  /// The row the user tapped, held while the coach is on screen.
  ///
  /// **Screen state, deliberately not machine state.** The `SetupMachine` is
  /// the flow's single source of truth and is not this task's to extend; what
  /// sits here is a page of the *find* step, not a new step, and it owns
  /// nothing the machine persists. It survives the machine re-emitting
  /// `SetupScanning` as more devices arrive (same widget type, same position →
  /// same `State`), and it is disposed the instant the machine moves on,
  /// because the dispatcher then returns a different widget type.
  BridgeDiscovery? _pending;

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    return pending == null ? _list(context) : _coach(context, pending);
  }

  Widget _list(BuildContext context) {
    final state = widget.state;
    // Strongest signal first (§13.2.1). The machine already sorts; re-sorting
    // here keeps the screen correct even if handed an unsorted list.
    final rows = [...state.found]..sort((a, b) => b.rssi.compareTo(a.rssi));
    // A finished scan with nothing in it is not a spinner. It used to be —
    // `cancel()` at hop 1 rests here — and a pulse that never resolves is the
    // one outcome the rails forbid (R2). Give it the same next step the
    // checklist has.
    final settledEmpty = rows.isEmpty && !state.scanning;

    return SetupScaffold(
      hop: 1,
      title: SetupCopy.scanningTitle,
      // A returning user is told why setup is open before being asked to look
      // at a radar (§16.4). Adoption is the case that needs it most: the code
      // they remember typing will not be asked for again.
      subtitle: state.resume == SetupResumeKind.adoptBridge
          ? SetupResumeCopy.adoptScanBody
          : SetupCopy.scanningBody,
      onExit: widget.externals.onLeaveSetup,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.scanning && rows.isNotEmpty) const _SearchingBar(),
          Expanded(
            // The header rides *inside* the list rather than above it, so the
            // one arrangement is correct whether the body slot is 500 dp or
            // 180 dp at 200 % text scale — it scrolls instead of overflowing.
            child: ListView(
              key: const Key('setup-scan-list'),
              padding: const EdgeInsets.symmetric(vertical: SmokeTokens.s2),
              children: [
                // The subject (§17.3 C). It is present while the screen is
                // still a search, and it steps aside once there is a list to
                // read — by then every row carries the same drawing small, so
                // the object never actually leaves the screen.
                if (rows.length <= 1) ...[
                  Center(
                    child: BridgeIllustration(
                      key: const Key('setup-scan-art'),
                      mood: state.scanning
                          ? BridgeMood.scanning
                          : BridgeMood.ready,
                    ),
                  ),
                  const SizedBox(height: SmokeTokens.s6),
                ],
                for (final bridge in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
                    child: _BridgeRow(
                      bridge: bridge,
                      // The tap no longer starts bonding. It opens the coach,
                      // which is the only place the platform's wrong passkey
                      // hint can still be contradicted (§17.3 C).
                      onTap: () => setState(() => _pending = bridge),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      primary: settledEmpty
          ? PrimaryAction(
              key: const Key('setup-scan-look-again'),
              label: SetupCopy.noBridgesLookAgain,
              icon: Icons.refresh_rounded,
              onPressed: () => widget.machine.startScan(),
            )
          : null,
      secondary: SetupTextAction(
        SetupCopy.scanningCancel,
        () => widget.machine.cancel(),
      ),
    );
  }

  /// "What happens next" — the step between the tap and the bond (§17.3 C).
  ///
  /// It exists for one sentence: [SetupCopy.coachStep3]. Everything after this
  /// screen belongs to the platform's pairing dialog, which draws over us and
  /// tells the user the code is *"usually 0000 or 1234"*. This is the last
  /// frame the app owns, so this is where that gets corrected — and the
  /// correction is chrome, not a sentence in a paragraph, so a tired reader
  /// cannot skim it.
  ///
  /// Still exactly one primary and one named secondary (rail R1/R2).
  Widget _coach(BuildContext context, BridgeDiscovery bridge) => SetupScaffold(
    hop: 1,
    title: SetupCopy.coachTitle,
    subtitle: SetupCopy.coachBody(bridge.name),
    onExit: widget.externals.onLeaveSetup,
    body: const SetupBodyCenter(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BridgeIllustration(
            key: Key('setup-coach-art'),
            mood: BridgeMood.passkey,
            size: 152,
          ),
          SizedBox(height: SmokeTokens.s5),
          SetupSteps(
            steps: [
              SetupStep(SetupCopy.coachStep1),
              SetupStep(SetupCopy.coachStep2),
              SetupStep(SetupCopy.coachStep3, caution: true),
            ],
          ),
        ],
      ),
    ),
    primary: PrimaryAction(
      key: const Key('setup-coach-pair'),
      label: SetupCopy.coachPrimary,
      icon: Icons.bluetooth_rounded,
      onPressed: () => widget.machine.select(bridge),
    ),
    secondary: SetupTextAction(
      SetupCopy.coachBack,
      () => setState(() => _pending = null),
    ),
  );
}

/// The moment of contact (§17.3 C). It used to be an icon, a name and a line of
/// blob text; it is now the four things a person actually decides on — *is this
/// mine* (the drawing and the name), *am I close enough* (bars **and** a word),
/// and *what state is it in* (the blob line, kept verbatim because "not paired
/// with a Smoke X yet" is honest and useful).
///
/// **Bars plus a word, never a number.** `BridgeDiscovery.rssi` is parsed and
/// was rendered nowhere; 16 §16.4 rule 3 keeps dBm inside Diagnostics, so the
/// figure is spent on [SignalBars] and one of `core/signal.dart`'s four words.
/// The bars are drawn in neutrals — a bar glyph carries no icon and no word of
/// its own, so a status hue on it would break the separation rule and duplicate
/// what the word beside it already says.
class _BridgeRow extends StatelessWidget {
  const _BridgeRow({required this.bridge, required this.onTap});

  final BridgeDiscovery bridge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final level = signalLevel(bridge.rssi, kind: SignalKind.bluetooth);
    final signal = SetupCopy.rowSignal(signalLabel(level));
    final detail = _blobLine(bridge);

    return Semantics(
      button: true,
      // One sentence, not four fragments: a drawing, a bar glyph and two lines
      // of text read out in order is a list, not a row.
      label: SetupCopy.rowSemantics(bridge.name, signal, detail),
      excludeSemantics: true,
      onTap: onTap,
      child: SmokeCard(
        key: Key('setup-bridge-${bridge.deviceId}'),
        onTap: onTap,
        // Ember-accented: the border, the shadow and the bloom (17 §17.5 —
        // there is no session and no reading on this screen, so a warm card
        // cannot misstate one, and finding your bridge should feel like an
        // arrival rather than like a row in a list). The accent is on every
        // row, so it is identity — "these are bridges" — and never a ranking.
        accent: StatusPalette.pit,
        child: Row(
          children: [
            const _DeviceGlyph(),
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: SignalBars(
                          bars: signalBars(
                            bridge.rssi,
                            kind: SignalKind.bluetooth,
                          ),
                          size: 14,
                        ),
                      ),
                      const SizedBox(width: SmokeTokens.s2),
                      Expanded(
                        child: Text(
                          '$signal · $detail',
                          style: SmokeType.bodySm.copyWith(color: t.textMuted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: SmokeTokens.s2),
            Icon(Icons.chevron_right_rounded, color: t.textMuted),
          ],
        ),
      ),
    );
  }
}

/// The row's leading mark: the same bridge drawing, small, in a well.
///
/// 17 §17.3 C asks for *"a food-neutral device glyph"* here, and reusing the
/// hero drawing rather than picking an icon is what makes the list feel like it
/// is looking at the object above it: the thing that was 168 dp while we
/// searched is 56 dp once it is found.
class _DeviceGlyph extends StatelessWidget {
  const _DeviceGlyph();

  @override
  Widget build(BuildContext context) => Container(
    width: 56,
    height: 56,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: StatusPalette.fill(StatusRole.pit),
      borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
      border: Border.all(color: StatusPalette.border(StatusRole.pit)),
    ),
    child: const BridgeIllustration(mood: BridgeMood.ready, size: 56),
  );
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The first check is *"is its screen lit?"*, so the screen shows a
          // lit one. The checklist asks the user to compare the object in
          // front of them with something; giving them the something is the
          // whole job (§17.3 C).
          Center(child: BridgeIllustration(mood: BridgeMood.ready, size: 132)),
          SizedBox(height: SmokeTokens.s6),
          _Checklist([
            SetupCopy.noBridgesCheck1,
            SetupCopy.noBridgesCheck2,
            SetupCopy.noBridgesCheck3,
          ]),
        ],
      ),
    ),
    primary: PrimaryAction(
      label: SetupCopy.noBridgesLookAgain,
      icon: Icons.refresh_rounded,
      onPressed: () => machine.startScan(),
    ),
    secondary: SetupTextAction(
      SetupCopy.noBridgesManual,
      externals.enterAddressManually,
      reason: SetupCopy.noManualAddress,
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
    // The same three reads, two reasons for doing them: a second phone
    // joining a household bridge, or this phone reconnecting to one it lost
    // its record of (§16.3 #4). "Add this phone" is the wrong sentence for the
    // second, so it is not used there.
    final adopting = state.resume == SetupResumeKind.adoptBridge;
    return SetupScaffold(
      hop: 1,
      title: adopting
          ? SetupResumeCopy.relinkTitle(state.bridge.name)
          : SetupCopy.addPhoneTitle,
      subtitle: adopting
          ? SetupResumeCopy.relinkBody(
              SetupResumeKind.adoptBridge,
              state.bridge.name,
            )
          : SetupCopy.addPhoneBody,
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
      secondary: SetupTextAction(
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
    final resume = state.resume;
    if (resume != null) {
      return _relink(context, resume);
    }
    final t = context.tokens;
    final status = state.passkeyShown
        ? SetupCopy.pairWaiting
        : SetupCopy.connectingTo(state.bridge.name);
    return SetupScaffold(
      hop: 1,
      title: SetupCopy.pairTitle,
      subtitle: SetupCopy.pairBody,
      onExit: externals.onLeaveSetup,
      // Object, then detail, then the correction. The drawing says *where* to
      // look, `PasskeyDisplay` says *what it looks like* at a size that reads
      // across a kitchen, and the caution is the last thing on screen before
      // the platform's dialog covers all of it (§17.3 C).
      body: SetupBodyCenter(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BridgeIllustration(
              key: Key('setup-pair-art'),
              mood: BridgeMood.passkey,
              size: 144,
            ),
            const SizedBox(height: SmokeTokens.s3),
            Text(
              SetupCopy.pairCallout,
              textAlign: TextAlign.center,
              style: SmokeType.bodySm.copyWith(color: t.textMuted),
            ),
            const SizedBox(height: SmokeTokens.s4),
            const PasskeyDisplay(),
            const SizedBox(height: SmokeTokens.s5),
            const SetupSteps(
              steps: [SetupStep(SetupCopy.pairIgnoreHint, caution: true)],
            ),
            const SizedBox(height: SmokeTokens.s5),
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
      secondary: SetupTextAction(SetupCopy.pairCancel, () => machine.cancel()),
    );
  }

  /// The re-link (§16.3): a bond that already exists is being reused, so no
  /// code is coming.
  ///
  /// **This is why [PasskeyDisplay] is absent rather than blank.** The passkey
  /// screen's whole job is to point at six digits on the bridge's glass; a
  /// bridge that recognises this phone never generates them, so showing the
  /// frame and pointing at an empty screen would be the same broken promise
  /// the state exists to end. There is nothing for the user to do while the
  /// link comes back, so there is no primary — only a way out (R2).
  Widget _relink(BuildContext context, SetupResumeKind resume) {
    final name = state.bridge.name;
    return SetupScaffold(
      hop: 1,
      title: SetupResumeCopy.relinkTitle(name),
      subtitle: SetupResumeCopy.relinkBody(resume, name),
      onExit: externals.onLeaveSetup,
      body: const SetupBodyCenter(
        child: SizedBox(
          key: Key('setup-relink'),
          width: 150,
          height: 150,
          // Reaching back out to a bridge we already know — the same drawing,
          // the same outward rings as the first search. A spinner here said
          // "something is happening"; this says *what*.
          child: BridgeIllustration(mood: BridgeMood.scanning),
        ),
      ),
      secondary: SetupTextAction(
        SetupResumeCopy.relinkCancel,
        () => machine.restart(),
      ),
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
    primary: Builder(
      builder: (context) => disabledReason(
        context,
        PrimaryAction(
          label: SetupCopy.notSeenCheckNotifications,
          icon: Icons.open_in_new_rounded,
          onPressed: externals.openNotificationSettings,
        ),
        enabled: externals.openNotificationSettings != null,
        reason: SetupCopy.noDeepLinkNotifications,
      ),
    ),
    secondary: SetupTextAction(
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
      // The payoff shows the *device*, with the tick on its own glass — the
      // same thing the bridge's OLED is displaying at this instant (§13.2.1's
      // `PAIRED ✓` stance). A checkmark floating on black would have been the
      // app congratulating itself; this is the two screens agreeing.
      body: SetupBodyCenter(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BridgeIllustration(
              key: Key('setup-bonded-art'),
              mood: BridgeMood.linked,
              size: 150,
            ),
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
    secondary: SetupTextAction(
      SetupCopy.wrongStartOver,
      () => machine.restart(),
    ),
  );
}

// ── bond outcome 2 of 4: the bridge was reset (§13.2.1) ──────────────────────

class _RebondNeededScreen extends StatelessWidget {
  const _RebondNeededScreen(this.state, this.machine, this.externals);

  final SetupRebondNeeded state;
  final SetupMachine machine;
  final SetupExternals externals;

  @override
  Widget build(BuildContext context) {
    // Two shapes of one situation (§16.3 #7), told apart by whether the two
    // identities are known to disagree.
    if (state.identityChanged) {
      return SetupScaffold(
        hop: 1,
        title: SetupResumeCopy.resetTitle,
        subtitle: SetupResumeCopy.resetBody(
          reachedId: state.reachedBridgeId ?? '',
          rememberedId: state.rememberedBridgeId ?? '',
        ),
        errorTint: true,
        onExit: externals.onLeaveSetup,
        body: const _Glyph(Icons.restart_alt_rounded, tone: _Tone.critical),
        // Retrying cannot make a different device into the old one, so it is
        // not offered. Setting it up as new is the only honest next step —
        // and it is the user's decision, never the app's (§16.3).
        primary: PrimaryAction(
          key: const Key('setup-reset-as-new'),
          label: SetupResumeCopy.resetPrimary,
          icon: Icons.refresh_rounded,
          onPressed: () => machine.restart(),
        ),
        secondary: SetupTextAction(
          SetupResumeCopy.resetLeave,
          externals.onLeaveSetup,
        ),
      );
    }
    return SetupScaffold(
      hop: 1,
      title: SetupCopy.rebondTitle,
      subtitle: SetupCopy.rebondBody,
      errorTint: true,
      onExit: externals.onLeaveSetup,
      body: const _Glyph(
        Icons.bluetooth_disabled_rounded,
        tone: _Tone.critical,
      ),
      // Without the deep-link the shortcut cannot work, so it says what to do
      // by hand instead of looking live and doing nothing (16 §16.5).
      primary: Builder(
        builder: (context) => disabledReason(
          context,
          PrimaryAction(
            label: SetupCopy.rebondOpenSettings,
            icon: Icons.open_in_new_rounded,
            onPressed: externals.openBluetoothSettings,
          ),
          enabled: externals.openBluetoothSettings != null,
          reason: SetupCopy.noDeepLinkBluetoothSettings,
        ),
      ),
      secondary: SetupTextAction(
        SetupCopy.rebondRetry,
        () => machine.retryPasskey(),
      ),
    );
  }
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
    secondary: SetupTextAction(
      SetupCopy.fullRemovePhone,
      externals.removeAPairedPhone,
      reason: SetupCopy.noRemovePhone,
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

/// The tint of a [_Glyph] anchor icon: neutral, or a failure red. There is no
/// success tone — a payoff draws the *device* (see `_BondedScreen`), not a
/// coloured tick on black.
enum _Tone { muted, critical }

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

// The 28 dp `_SearchingPulse` spinner that used to fill the empty scan body and
// the re-link body is gone: both now show the bridge itself, with the ripple
// carrying "still looking" (§17.3 C). A spinner says *something is happening*;
// a lit board with rings coming off it says *what*.

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
