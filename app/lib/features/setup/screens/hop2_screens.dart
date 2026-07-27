/// A23.4 — hop 2 screens: bridge ↔ Smoke X over LoRa (design 13 §13.2.2).
///
/// The largest gap in today's product (13 §13.1 #3), built as a screen per
/// `Hop2State`. WHY each state is its own screen and not a spinner with changing
/// text: the ~30 s `heard` wait is real and must be *narrated, not spun*
/// (§13.2.2), the four failure reasons must each say which cause
/// ([BaseSyncCopy.failureHeadline], §13.1 #5), and the confirmed reading is the
/// moment the product justifies itself — rendered as a real temperature with a
/// haptic and a count-up, never a checkmark (§13.2.2).
///
/// Every screen is a [SetupScaffold]: one primary, a named secondary, an exit —
/// the §13.5.1 contract made structural by the scaffold, not remembered here.
/// Gesture, listening and failure strings come from [BaseSyncCopy] (the single
/// hop-2 source shared with the machine); the payoff strings from
/// [BasePayoffCopy]. No screen holds flow scratch — it all lives on the machine.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/design.dart';
import '../../../ui/ui.dart';
import '../copy/base_sync_copy.dart';
import '../copy/setup_net_copy.dart';
import '../setup_machine.dart';

/// `SetupBaseIntro` — the illustrated SYNC-hold instruction (§13.2.2).
class BaseIntroScreen extends StatelessWidget {
  const BaseIntroScreen({
    required this.state,
    required this.machine,
    super.key,
  });

  final SetupBaseIntro state;
  final SetupMachine machine;

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      hop: state.hop,
      title: BaseSyncCopy.introHeadline,
      subtitle: BaseSyncCopy.introGesture,
      onExit: () => machine.cancel(),
      body: const Center(child: _SyncIllustration()),
      primary: PrimaryAction(
        key: const Key('base-intro-primary'),
        label: BaseSyncCopy.introPrimary,
        icon: Icons.hearing_rounded,
        onPressed: () => machine.startBaseListen(),
      ),
      secondary: TextButton(
        onPressed: () => machine.skipBase(),
        child: const Text(BaseSyncCopy.introSkip),
      ),
    );
  }
}

/// `SetupBaseListening` — a listen window is open (§13.2.2). A local count-up
/// ring (the phone counts from the state-change timestamp; a 1 Hz radio notify
/// for a ring is not worth it), plus the faint-signal sub-state.
class BaseListeningScreen extends StatelessWidget {
  const BaseListeningScreen({
    required this.state,
    required this.machine,
    super.key,
  });

  final SetupBaseListening state;
  final SetupMachine machine;

  @override
  Widget build(BuildContext context) {
    final faint = state.garbled > 0;
    return SetupScaffold(
      hop: state.hop,
      title: BaseSyncCopy.listening,
      subtitle: faint
          ? BaseSyncCopy.garbledFaint
          : BaseSyncCopy.listeningKeepClose,
      errorTint: false,
      onExit: () => machine.cancel(),
      body: Center(
        child: _ListeningRing(
          elapsed: state.elapsed,
          budget: BaseSyncTiming.listenBudget,
          faint: faint,
        ),
      ),
      secondary: TextButton(
        key: const Key('base-listen-cancel'),
        onPressed: () => machine.cancel(),
        child: const Text(SetupNetCopy.cancel),
      ),
    );
  }
}

/// `SetupBaseHeard` — the ACK landed; now the real ~30 s wait for the first
/// reading, narrated (§13.2.2).
class BaseHeardScreen extends StatelessWidget {
  const BaseHeardScreen({
    required this.state,
    required this.machine,
    super.key,
  });

  final SetupBaseHeard state;
  final SetupMachine machine;

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      hop: state.hop,
      title: BaseSyncCopy.heard(state.deviceId),
      subtitle: BasePayoffCopy.heardBody,
      onExit: () => machine.cancel(),
      body: const Center(child: _HeardPulse()),
      secondary: TextButton(
        onPressed: () => machine.cancel(),
        child: const Text(SetupNetCopy.cancel),
      ),
    );
  }
}

/// `SetupBaseConfirmed` — the payoff (§13.2.2). A real temperature per probe,
/// a `mediumImpact` haptic on entry, and `AnimatedTemp`'s count-up.
class BaseConfirmedScreen extends StatefulWidget {
  const BaseConfirmedScreen({
    required this.state,
    required this.machine,
    super.key,
  });

  final SetupBaseConfirmed state;
  final SetupMachine machine;

  @override
  State<BaseConfirmedScreen> createState() => _BaseConfirmedScreenState();
}

class _BaseConfirmedScreenState extends State<BaseConfirmedScreen> {
  @override
  void initState() {
    super.initState();
    // The payoff earns a haptic — the one place in setup a reading appears.
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final t = context.tokens;
    return SetupScaffold(
      hop: s.hop,
      title: BasePayoffCopy.confirmedHeadline,
      onExit: () => widget.machine.cancel(),
      body: ListView(
        children: [
          Text(
            BasePayoffCopy.confirmedEyebrow(
              s.deviceId,
              s.numProbes,
            ).toUpperCase(),
            style: SmokeType.label.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: SmokeTokens.s4),
          for (var i = 0; i < s.temps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: SmokeTokens.s2),
              child: _ProbeReadingRow(index: i, tempF10: s.temps[i]),
            ),
        ],
      ),
      primary: PrimaryAction(
        key: const Key('base-confirmed-primary'),
        label: BasePayoffCopy.confirmedPrimary,
        onPressed: () => widget.machine.continueFromConfirmed(),
      ),
    );
  }
}

/// `SetupBaseSkipped` — the non-punitive skip (§13.2.2). Finishes hop 2 unpaired
/// and states the consequence; Wi-Fi is still ahead.
class BaseSkippedScreen extends StatelessWidget {
  const BaseSkippedScreen({
    required this.state,
    required this.machine,
    super.key,
  });

  final SetupBaseSkipped state;
  final SetupMachine machine;

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      hop: state.hop,
      title: BasePayoffCopy.skippedHeadline,
      onExit: () => machine.cancel(),
      body: const Center(
        child: InsightBanner(
          kind: InsightKind.advisory,
          label: BaseSyncCopy.skippedCard,
        ),
      ),
      primary: PrimaryAction(
        key: const Key('base-skipped-primary'),
        label: BasePayoffCopy.skippedPrimary,
        onPressed: () => machine.continueToNetwork(),
      ),
      secondary: TextButton(
        onPressed: () => machine.retryBaseListen(),
        child: const Text(BaseSyncCopy.introPrimary),
      ),
    );
  }
}

/// `SetupBaseFailed` — a window ended without a confirm (§13.2.2). The copy says
/// which of the four causes; `ack_failed` is auto-retried by the machine and so
/// never reaches a user-facing dead end here.
class BaseFailedScreen extends StatelessWidget {
  const BaseFailedScreen({
    required this.state,
    required this.machine,
    super.key,
  });

  final SetupBaseFailed state;
  final SetupMachine machine;

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      hop: state.hop,
      title: BaseSyncCopy.failureHeadline(state.reason),
      errorTint: true,
      onExit: () => machine.cancel(),
      body: const Center(child: _FailureGlyph(icon: Icons.sensors_off_rounded)),
      primary: PrimaryAction(
        key: const Key('base-failed-primary'),
        label: SetupNetCopy.wifiRetry,
        icon: Icons.refresh_rounded,
        onPressed: () => machine.retryBaseListen(),
      ),
      secondary: TextButton(
        onPressed: () => machine.skipBase(),
        child: const Text(BaseSyncCopy.introSkip),
      ),
    );
  }
}

// ── local presentation pieces (no flow logic) ─────────────────────────────

/// A vector stand-in for the X4 base with its SYNC control lit — the design's
/// "full-bleed illustration" without a bundled asset. `pit` glow on the control
/// is the one thing the eye should land on.
class _SyncIllustration extends StatelessWidget {
  const _SyncIllustration();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 200,
      padding: const EdgeInsets.all(SmokeTokens.s5),
      decoration: BoxDecoration(
        color: t.cardSubtle,
        borderRadius: BorderRadius.circular(SmokeTokens.radiusCard),
        border: Border.all(color: t.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.thermostat_rounded, size: 40, color: t.textMuted),
          const SizedBox(height: SmokeTokens.s4),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: SmokeTokens.s4,
              vertical: SmokeTokens.s2,
            ),
            decoration: BoxDecoration(
              color: StatusPalette.fill(StatusRole.pit),
              borderRadius: BorderRadius.circular(SmokeTokens.radiusPill),
              border: Border.all(color: StatusPalette.border(StatusRole.pit)),
              boxShadow: [?t.glowTight(StatusPalette.pit)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.touch_app_rounded,
                  size: 18,
                  color: StatusPalette.pit,
                ),
                const SizedBox(width: SmokeTokens.s2),
                Text('SYNC', style: SmokeType.label.copyWith(color: t.textHi)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The count-up progress ring for [BaseListeningScreen]. A single self-disposing
/// tween from the captured elapsed to the budget — no manual timer, so no
/// pending-timer surprises, and it advances live between machine emissions.
class _ListeningRing extends StatelessWidget {
  const _ListeningRing({
    required this.elapsed,
    required this.budget,
    required this.faint,
  });

  final Duration elapsed;
  final Duration budget;
  final bool faint;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final totalMs = budget.inMilliseconds == 0 ? 1 : budget.inMilliseconds;
    final startFrac = (elapsed.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final remaining = budget - elapsed;
    final color = faint ? StatusPalette.warning : StatusPalette.pit;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: startFrac, end: 1),
      duration: remaining.isNegative ? Duration.zero : remaining,
      curve: Curves.linear,
      builder: (context, frac, _) {
        final shownSecs = (frac * budget.inSeconds).round();
        return SizedBox(
          width: 132,
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 132,
                height: 132,
                child: CircularProgressIndicator(
                  value: frac,
                  strokeWidth: 6,
                  backgroundColor: t.cardSubtle,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              Text(
                _mmss(Duration(seconds: shownSecs)),
                style: SmokeType.monoBig.copyWith(color: t.textHi),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A calm indeterminate pulse for the narrated `heard` wait — a ring, not a
/// spinner racing to nowhere.
class _HeardPulse extends StatelessWidget {
  const _HeardPulse();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 132,
            height: 132,
            child: CircularProgressIndicator(
              strokeWidth: 6,
              backgroundColor: t.cardSubtle,
              valueColor: AlwaysStoppedAnimation<Color>(StatusPalette.pit),
            ),
          ),
          Icon(Icons.thermostat_rounded, size: 40, color: StatusPalette.pit),
        ],
      ),
    );
  }
}

/// One probe row of the payoff: a colour-coded reading with an attached/detached
/// dot. The pit row (index 0) wears the reference weight and a lit dot.
class _ProbeReadingRow extends StatelessWidget {
  const _ProbeReadingRow({required this.index, required this.tempF10});

  final int index;
  final int? tempF10;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final attached = tempF10 != null;
    final hue = ProbePalette.hue(index + 1);
    final color = attached ? hue : t.textMuted;
    final label = BasePayoffCopy.probeLabel(index);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SmokeTokens.s4,
        vertical: SmokeTokens.s3,
      ),
      decoration: BoxDecoration(
        color: t.cardSubtle,
        borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
        border: Border.all(color: t.hairline),
      ),
      child: Row(
        children: [
          _ProbeDot(color: hue, attached: attached, lit: index == 0),
          const SizedBox(width: SmokeTokens.s3),
          Text(label, style: SmokeType.title.copyWith(color: t.textBody)),
          const Spacer(),
          AnimatedTemp(
            tempF10: tempF10,
            celsius: false,
            style: SmokeType.midTemp,
            unitStyle: SmokeType.displayS,
            color: color,
            semanticName: label,
          ),
        ],
      ),
    );
  }
}

class _ProbeDot extends StatelessWidget {
  const _ProbeDot({
    required this.color,
    required this.attached,
    required this.lit,
  });

  final Color color;
  final bool attached;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: attached ? color : Colors.transparent,
        border: Border.all(color: attached ? color : t.chromeDim, width: 2),
        boxShadow: attached && lit ? [?t.glowTight(color)] : const [],
      ),
    );
  }
}

/// The centred glyph a hop-2 failure shows in its body, in the critical hue that
/// [SetupScaffold.errorTint] carries on the rail and title chrome.
class _FailureGlyph extends StatelessWidget {
  const _FailureGlyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: 64, color: StatusPalette.critical);
}

String _mmss(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
