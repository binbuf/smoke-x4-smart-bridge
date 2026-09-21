/// N14 — the eight-step onboarding wizard (`overlayOnboarding`).
///
/// [OnboardingBody] is the step content and [OnboardingFoot] the pinned
/// Back/Skip + primary row; [OnboardingSurface] mounts both on the gate that
/// takes over the screen when no bridge is known (N14.12). The named
/// `?overlay=onboarding` deep link renders the same pair inside the overlay
/// host.
///
/// Invariants encoded here:
/// * **The passkey is never rendered by the app** — the well is a fixed
///   elision, and there is no code field anywhere.
/// * **I6 / I5** — every step has a forward action; when it is disabled it
///   states why in the footer.
/// * **I14** — exactly one ember primary action.
/// * **I15** — a failure renders a named [SetupFault] card, never an error.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/model/app_settings.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import '../connection/mode_cards.dart';
import '../shell/overlay.dart';
import '../shell/shell.dart';
import 'onboarding_model.dart';
import 'setup_format.dart';

SmokeGlyph _glyph(String name) {
  for (final glyph in SmokeGlyph.values) {
    if (glyph.name == name) {
      return glyph;
    }
  }
  return SmokeGlyph.info;
}

/// Persist the finish and hand control back to the shell.
Future<void> finishOnboarding(
  BuildContext context,
  WidgetRef ref,
  VoidCallback onDone,
) async {
  final scope = ShellScope.maybeOf(context);
  final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
  final state = ref.read(setupStateProvider);
  final name = state.name.trim();
  await ref
      .read(prefsProvider)
      .write(
        settings.copyWith(
          units: state.units,
          bridgeName: name.isEmpty ? settings.bridgeName : name,
          onboardStatus: OnboardStatus.paired,
        ),
      );
  await ref.read(bridgeRepositoryProvider).connect();
  ref.read(setupStateProvider.notifier).reset();
  scope?.showToast('Welcome — you are connected');
  onDone();
}

/// Skip is allowed: the shell then offers a way to connect (N14.13).
Future<void> skipOnboarding(
  BuildContext context,
  WidgetRef ref,
  VoidCallback onSkip,
) async {
  final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
  await ref
      .read(prefsProvider)
      .write(settings.copyWith(onboardStatus: OnboardStatus.skipped));
  ref.read(setupStateProvider.notifier).reset();
  onSkip();
}

/// The gate surface: an opaque scrim with the wizard sheet. Used only while
/// [onboardingRequiredProvider] is true, so it cannot be dismissed into a dead
/// end — the close control skips, which lands on the connect empty state.
class OnboardingSurface extends ConsumerWidget {
  const OnboardingSurface({
    super.key,
    required this.onDone,
    required this.onSkip,
  });

  final VoidCallback onDone;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final state = ref.watch(setupStateProvider);
    final troubleshoot = state.troubleshoot;
    return Stack(
      key: const ValueKey<String>('onboarding-surface'),
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Not dismissible by a scrim tap: the wizard owns the screen until
            // the user finishes or explicitly skips.
            onTap: () {},
            child: ColoredBox(color: tokens.scrim),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
            child: ShellSheet(
              title: troubleshoot ? 'Let’s find it again' : state.step.title,
              sub: troubleshoot
                  ? 'A few things fix almost every pairing problem.'
                  : state.step.sub,
              body: OnboardingBody(onDone: onDone, onSkip: onSkip),
              foot: OnboardingFoot(onDone: onDone, onSkip: onSkip),
              onClose: () => skipOnboarding(context, ref, onSkip),
            ),
          ),
        ),
      ],
    );
  }
}

/// The step body (rail + the current step's content).
class OnboardingBody extends ConsumerWidget {
  const OnboardingBody({super.key, required this.onDone, required this.onSkip});

  final VoidCallback onDone;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(setupStateProvider);
    return Column(
      key: const ValueKey<String>('onboarding-body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _StepRail(step: state.step, troubleshoot: state.troubleshoot),
        const SizedBox(height: 16),
        if (state.fault != SetupFault.none) ...<Widget>[
          _FaultCard(fault: state.fault),
          const SizedBox(height: 14),
        ],
        if (state.troubleshoot)
          const _TroubleshootPanel()
        else
          switch (state.step) {
            OnboardStep.welcome => const _WelcomeStep(),
            OnboardStep.preflight => const _PreflightStep(),
            OnboardStep.scan => const _ScanStep(),
            OnboardStep.passkey => const _PasskeyStep(),
            OnboardStep.sync => const _SyncStep(),
            OnboardStep.network => const _NetworkStep(),
            OnboardStep.name => const _NameStep(),
            OnboardStep.done => const _DoneStep(),
          },
      ],
    );
  }
}

/// The pinned footer: Back/Skip plus the one ember primary.
class OnboardingFoot extends ConsumerWidget {
  const OnboardingFoot({super.key, required this.onDone, required this.onSkip});

  final VoidCallback onDone;
  final VoidCallback onSkip;

  static bool _primaryEnabled(SetupState state) {
    if (state.troubleshoot) {
      return true;
    }
    return switch (state.step) {
      OnboardStep.passkey => true,
      OnboardStep.sync => true,
      OnboardStep.done => true,
      OnboardStep.scan => state.hopOf(SetupHop.bluetooth) == HopStatus.done,
      _ => state.canAdvance,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(setupStateProvider);
    final notifier = ref.read(setupStateProvider.notifier);
    final enabled = _primaryEnabled(state);

    void onPrimary() {
      if (state.troubleshoot) {
        notifier.stopTroubleshoot();
        return;
      }
      switch (state.step) {
        case OnboardStep.passkey:
          notifier.confirmPasskey();
        case OnboardStep.sync:
          notifier.heardBase();
        case OnboardStep.done:
          finishOnboarding(context, ref, onDone);
        default:
          notifier.next();
      }
    }

    void onGhost() {
      if (state.troubleshoot) {
        notifier.stopTroubleshoot();
      } else if (state.step == OnboardStep.welcome) {
        skipOnboarding(context, ref, onSkip);
      } else {
        notifier.back();
      }
    }

    final ghostLabel = state.troubleshoot
        ? 'Back'
        : state.step == OnboardStep.welcome
        ? 'Skip'
        : 'Back';
    final primaryLabel = state.troubleshoot
        ? 'Try again'
        : state.step.primaryLabel;
    final reason = enabled ? null : state.blockedReason;

    return Row(
      key: const ValueKey<String>('onboarding-foot'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: SmokeButton(
            key: ValueKey<String>(
              state.step == OnboardStep.welcome && !state.troubleshoot
                  ? 'onboarding-skip'
                  : 'onboarding-back',
            ),
            label: ghostLabel,
            variant: SmokeButtonVariant.ghost,
            onPressed: onGhost,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: PrimaryAction(
            key: const ValueKey<String>('onboarding-next'),
            label: primaryLabel,
            onPressed: enabled ? onPrimary : null,
            enabledReason: reason,
          ),
        ),
      ],
    );
  }
}

/// The eight-dot progress rail.
class _StepRail extends StatelessWidget {
  const _StepRail({required this.step, required this.troubleshoot});

  final OnboardStep step;
  final bool troubleshoot;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Row(
      key: const ValueKey<String>('onboarding-step-rail'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (final item in kOnboardSteps)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              key: ValueKey<String>('onboarding-step-dot-${item.index}'),
              width: item == step ? 10 : 7,
              height: item == step ? 10 : 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: item == step
                    ? tokens.pit
                    : item.index < step.index
                    ? tokens.tint(tokens.pit, 0.55)
                    : tokens.hairlineStrong,
              ),
            ),
          ),
      ],
    );
  }
}

/// The device illustration (`bridge-art`).
class _BridgeArt extends StatelessWidget {
  const _BridgeArt({required this.glyph, this.positive = false});

  final SmokeGlyph glyph;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final hue = positive ? tokens.positive : tokens.pit;
    return Center(
      child: Container(
        width: 104,
        height: 104,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tokens.tint(hue, 0.12),
          border: Border.all(color: tokens.tint(hue, 0.30)),
        ),
        child: SmokeIcon(glyph, size: 48, color: hue),
      ),
    );
  }
}

/// Step 1 — welcome (N14.2).
class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) {
    return const Column(
      key: ValueKey<String>('onboarding-welcome'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _BridgeArt(glyph: SmokeGlyph.cpu),
        SizedBox(height: 16),
        Text(
          'Records with or without your phone.',
          key: ValueKey<String>('onboarding-welcome-copy'),
          textAlign: TextAlign.center,
          style: SmokeText.body,
        ),
      ],
    );
  }
}

/// Step 2 — preflight permissions (N14.3).
class _PreflightStep extends ConsumerWidget {
  const _PreflightStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(setupStateProvider);
    return Column(
      key: const ValueKey<String>('onboarding-preflight'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final permission in kOnboardPermissions)
          SettingsRow(
            key: ValueKey<String>('onboarding-perm-${permission.name}'),
            icon: _glyph(permission.glyph),
            name: permission.name,
            sub: permission.sub,
            onTap: state.permissionOf(permission) == PermissionState.granted
                ? null
                : () => ref.read(setupStateProvider.notifier).allow(permission),
            trailing: state.permissionOf(permission) == PermissionState.granted
                ? SmokeIcon(
                    SmokeGlyph.check,
                    color: SmokeTokens.of(context).positive,
                  )
                : SizedBox(
                    width: 84,
                    child: SmokeButton(
                      key: ValueKey<String>(
                        'onboarding-perm-allow-${permission.name}',
                      ),
                      label: 'Allow',
                      size: SmokeButtonSize.sm,
                      onPressed: () => ref
                          .read(setupStateProvider.notifier)
                          .allow(permission),
                    ),
                  ),
          ),
      ],
    );
  }
}

/// Step 3 — scan (N14.4).
class _ScanStep extends ConsumerWidget {
  const _ScanStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final state = ref.watch(setupStateProvider);
    final deviceName =
        ref.watch(snapshotProvider).value?.connection.deviceName ??
        'SmokeBridge-A4F2';
    final found = state.hopOf(SetupHop.bluetooth) == HopStatus.done;
    return Column(
      key: const ValueKey<String>('onboarding-scan'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _ScanRing(glyph: SmokeGlyph.bluetooth),
        const SizedBox(height: 16),
        SmokeCard(
          key: const ValueKey<String>('onboarding-found-bridge'),
          onTap: found
              ? null
              : () => ref.read(setupStateProvider.notifier).findBridge(),
          child: Row(
            children: <Widget>[
              SmokeIcon(SmokeGlyph.cpu, size: 20, color: tokens.textBody),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      deviceName,
                      style: SmokeText.bodyStrong.copyWith(
                        fontSize: 13.5,
                        color: tokens.textHi,
                      ),
                    ),
                    Text(
                      found
                          ? 'Found · ready to pair'
                          : 'Strong signal · ready to pair',
                      key: const ValueKey<String>('onboarding-found-sub'),
                      style: SmokeText.labelSm.copyWith(
                        fontSize: 11.5,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              SmokeIcon(
                found ? SmokeGlyph.check : SmokeGlyph.chevronRight,
                color: found ? tokens.positive : tokens.textMuted,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            key: const ValueKey<String>('onboarding-troubleshoot-link'),
            onPressed: () =>
                ref.read(setupStateProvider.notifier).startTroubleshoot(),
            style: TextButton.styleFrom(foregroundColor: tokens.pit),
            child: Text(
              'Can’t find it?',
              style: SmokeText.label.copyWith(color: tokens.pit),
            ),
          ),
        ),
      ],
    );
  }
}

/// The scan ring.
class _ScanRing extends StatelessWidget {
  const _ScanRing({required this.glyph});

  final SmokeGlyph glyph;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Center(
      child: Container(
        key: const ValueKey<String>('onboarding-scan-ring'),
        width: 96,
        height: 96,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: tokens.tint(tokens.pit, 0.35), width: 2),
          color: tokens.tint(tokens.pit, 0.08),
        ),
        child: SmokeIcon(glyph, size: 34, color: tokens.pit),
      ),
    );
  }
}

/// The "Can't find it?" sub-flow (N14.5).
class _TroubleshootPanel extends StatelessWidget {
  const _TroubleshootPanel();

  static const List<(SmokeGlyph, String, String)> _checks =
      <(SmokeGlyph, String, String)>[
        (
          SmokeGlyph.cpu,
          'Is the bridge powered?',
          'Its screen should show a heartbeat',
        ),
        (
          SmokeGlyph.bluetooth,
          'Bluetooth on?',
          'And the phone is within a few metres',
        ),
        (
          SmokeGlyph.refresh,
          'Restart the bridge',
          'Hold the button until the screen blinks',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('onboarding-troubleshoot'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < _checks.length; i++)
          SettingsRow(
            key: ValueKey<String>('onboarding-ts-$i'),
            icon: _checks[i].$1,
            name: _checks[i].$2,
            sub: _checks[i].$3,
          ),
      ],
    );
  }
}

/// Step 4 — passkey coaching (N14.6).
class _PasskeyStep extends StatelessWidget {
  const _PasskeyStep();

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Column(
      key: const ValueKey<String>('onboarding-passkey'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const MonoWell(value: kPasskeyPlaceholder),
        const SizedBox(height: 8),
        Text(
          'Shown only on the device. The app never stores it.',
          key: const ValueKey<String>('onboarding-passkey-note'),
          textAlign: TextAlign.center,
          style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }
}

/// Step 5 — sync / pure listener (N14.7).
class _SyncStep extends ConsumerWidget {
  const _SyncStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    return Column(
      key: const ValueKey<String>('onboarding-sync'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _ScanRing(glyph: SmokeGlyph.wifi),
        const SizedBox(height: 16),
        const CapabilityNotice(
          key: ValueKey<String>('onboarding-listener-notice'),
          message:
              'This keeps the bridge a pure listener. It cannot interfere '
              'with your base station.',
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            key: const ValueKey<String>('onboarding-skip-base'),
            onPressed: () {
              ref.read(setupStateProvider.notifier).skipBase();
            },
            style: TextButton.styleFrom(foregroundColor: tokens.textMuted),
            child: Text(
              'Skip — set it up later',
              style: SmokeText.label.copyWith(color: tokens.textMuted),
            ),
          ),
        ),
      ],
    );
  }
}

/// Step 6 — network mode (N14.8).
class _NetworkStep extends ConsumerWidget {
  const _NetworkStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(setupStateProvider);
    final modes = ref.watch(bridgeRepositoryProvider).connectionModes;
    final scope = ShellScope.maybeOf(context);
    return Column(
      key: const ValueKey<String>('onboarding-network'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final mode in modes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ConnectionModeCard(
              key: ValueKey<String>('onboarding-mode-${mode.id}'),
              mode: mode,
              active: mode.id == state.modeId,
              onTap: () =>
                  ref.read(setupStateProvider.notifier).selectMode(mode.id),
              onInfo: () =>
                  scope?.openOverlay(DevOverlay.modesRef, {'mode': mode.id}),
            ),
          ),
      ],
    );
  }
}

/// Step 7 — name + units (N14.9).
class _NameStep extends ConsumerStatefulWidget {
  const _NameStep();

  @override
  ConsumerState<_NameStep> createState() => _NameStepState();
}

class _NameStepState extends ConsumerState<_NameStep> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(setupStateProvider).name,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final state = ref.watch(setupStateProvider);
    return Column(
      key: const ValueKey<String>('onboarding-name'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'BRIDGE NAME',
          style: SmokeText.labelSm.copyWith(
            letterSpacing: 0.9,
            color: tokens.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey<String>('onboarding-name-field'),
          controller: _controller,
          onChanged: (value) =>
              ref.read(setupStateProvider.notifier).setName(value),
          style: SmokeText.body.copyWith(color: tokens.textHi),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Backyard Bridge',
            hintStyle: SmokeText.body.copyWith(color: tokens.textMuted),
            filled: true,
            fillColor: tokens.well,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(tokens.radii.control),
              borderSide: BorderSide(color: tokens.hairlineStrong),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'UNITS',
          style: SmokeText.labelSm.copyWith(
            letterSpacing: 0.9,
            color: tokens.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        SegmentedChips<TempUnit>(
          key: const ValueKey<String>('onboarding-units'),
          segments: const <SmokeSegment<TempUnit>>[
            SmokeSegment<TempUnit>(
              value: TempUnit.fahrenheit,
              label: '° Fahrenheit',
            ),
            SmokeSegment<TempUnit>(value: TempUnit.celsius, label: '° Celsius'),
          ],
          value: state.units,
          onChanged: (unit) =>
              ref.read(setupStateProvider.notifier).setUnits(unit),
        ),
      ],
    );
  }
}

/// Step 8 — done (N14.10), with the hop summary.
class _DoneStep extends ConsumerWidget {
  const _DoneStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final state = ref.watch(setupStateProvider);
    return Column(
      key: const ValueKey<String>('onboarding-done'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _BridgeArt(glyph: SmokeGlyph.check, positive: true),
        const SizedBox(height: 16),
        Text(
          'Your bridge is paired, listening, and recording.',
          key: const ValueKey<String>('onboarding-done-copy'),
          textAlign: TextAlign.center,
          style: SmokeText.body.copyWith(color: tokens.textBody),
        ),
        const SizedBox(height: 16),
        Text(
          'SET UP',
          style: SmokeText.labelSm.copyWith(
            letterSpacing: 0.9,
            color: tokens.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        for (final row in state.hopSummary)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              key: ValueKey<String>('onboarding-hop-${row.hop.name}'),
              children: <Widget>[
                Expanded(
                  child: Text(
                    row.hop.name,
                    style: SmokeText.body.copyWith(color: tokens.textBody),
                  ),
                ),
                Text(
                  row.statusLabel,
                  key: ValueKey<String>(
                    'onboarding-hop-status-${row.hop.name}',
                  ),
                  style: SmokeText.labelSm.copyWith(
                    color: row.status == HopStatus.notSetUp
                        ? tokens.textMuted
                        : tokens.positive,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The named failure card (I15).
class _FaultCard extends ConsumerWidget {
  const _FaultCard({required this.fault});

  final SetupFault fault;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    return SmokeCard(
      key: const ValueKey<String>('onboarding-fault'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              SmokeIcon(
                SmokeGlyph.alertTriangle,
                size: 17,
                color: tokens.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fault.title,
                  key: const ValueKey<String>('onboarding-fault-title'),
                  style: SmokeText.cardTitle.copyWith(color: tokens.textHi),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            fault.body,
            key: const ValueKey<String>('onboarding-fault-body'),
            style: SmokeText.sub.copyWith(color: tokens.textBody),
          ),
          const SizedBox(height: 12),
          SmokeButton(
            key: const ValueKey<String>('onboarding-fault-recover'),
            label: fault.recoverLabel,
            onPressed: () => _recover(ref),
          ),
        ],
      ),
    );
  }

  void _recover(WidgetRef ref) =>
      ref.read(setupStateProvider.notifier).recoverFault();
}

/// The named `?overlay=onboarding` presentation, reusing [OnboardingBody] and
/// [OnboardingFoot] so the dev panel and the gate can never drift.
Widget onboardingOverlayBody(VoidCallback dismiss) =>
    OnboardingBody(onDone: dismiss, onSkip: dismiss);

/// The named overlay's footer.
Widget onboardingOverlayFoot(VoidCallback dismiss) =>
    OnboardingFoot(onDone: dismiss, onSkip: dismiss);

/// Kept for the shell's deep-link path.
const String kOnboardingOverlayTitle = 'Welcome to Smoke';
const String kOnboardingOverlaySub = 'Pair your bridge';
