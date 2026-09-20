/// The guided-mode headline card (design 16 §16.5, §16.6; newapp §H.2).
///
/// The pit and the primary food probe, each with the 96 pt reading, its radial
/// [TargetGauge], and — for food — where it is in the guided progression.
///
/// ## What this pass changed, and why
///
/// **The number is no longer inside a `FittedBox`.** §16.5 is unambiguous: *"a
/// hero number is 96 pt fixed, tabular, never scaled — the gauge is the
/// flexible child."* The old card said so in a comment and then wrapped the
/// number in a scale-down box "as a safety", which is the same thing as
/// scaling it, just less often. The card now **measures** the readout
/// ([TempReadout.measure]) and spends what is left on the gauge, shrinking it
/// 84 → 56 dp; when even 56 dp will not fit, the gauge moves to its own line
/// under the number instead of the number giving way. Nothing ever squeezes
/// the temperature.
///
/// **The fixed 176/202 dp height is gone.** It was sized around one phase row
/// of one line of text, so a longer sentence or a larger text scale clipped
/// silently. The card is intrinsic now.
///
/// **The name is `textMuted`, not the series hue.** A hue may be a mark and
/// never a word (§16.5). Identity is carried by the 10 dp dot, by the 3 dp rule
/// under the number, and — on the pit — by the card's accent border.
///
/// **The phase is a track, not a pill.** A pill says where you are; a
/// progression needs to say how far through. See [PhaseTrack]. At *Pull now*
/// the one action the app may not infer becomes a full-width button rather than
/// a `TextButton` wedged between a pill and an ellipsised sentence.
///
/// The pit reads its gauge in **band mode**; a food probe reads it in **sweep
/// mode**, with a pull tick. Reaching target closes the ring and flips the pill
/// to "Reached" — there is no green (§16.5).
///
/// ## And what this pass changed
///
/// **An ETA refusal is no longer rendered as an ETA.** See [_insights].
///
/// **"Reached" now dies with the reading it was derived from.** See [_header].
///
/// **The pit says when it leaves its band, in words.** The gauge went amber
/// and red and nothing anywhere said so; see [_bandVerdict].
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/analysis/analysis.dart' show EtaRange, EtaUnavailable;
import '../../domain/entities/entities.dart' show ProbeRole;
import '../../domain/plan/plan.dart';
import '../../features/dashboard/dashboard_snapshot.dart';
import '../insight/insight_banner.dart' show InsightBanner, InsightKind;
import '../surface/smoke_card.dart';
import 'food_avatar.dart';
import 'jack_badge.dart';
import 'phase_track.dart';
import 'probe_freshness.dart';
import 'probe_pills.dart';
import 'target_gauge.dart';
import 'temp_readout.dart';
import '../state/stale_veil.dart';

class ProbeHeroCard extends StatelessWidget {
  const ProbeHeroCard({
    super.key,
    required this.view,
    required this.plan,
    required this.freshness,
    this.celsius = false,
    this.onTap,
    this.phase,
    this.onPulled,
    this.glyph,
  });

  final ProbeView view;

  /// What is on this jack (17 §17.3 A). Null resolves it from the plan, the
  /// role and the name — see [_glyph]. Never a function of state.
  ///
  /// There is deliberately **no `vivid`** here, unlike [ProbeStripRow] and
  /// [ProbeCompactCard]. §17.5's rich register is for surfaces where nothing is
  /// claiming a temperature, and this card exists only when a cook is running:
  /// it *is* the watching state. A hero with a saturated avatar over a 96 pt
  /// reading is the exact composition §17.4 rejects.
  final FoodGlyph? glyph;

  /// The active cook plan, or null in instrument mode. Supplies the pit band
  /// and the food pull temperature.
  final CookPlan? plan;
  final ProbeFreshness freshness;
  final bool celsius;
  final VoidCallback? onTap;

  /// newapp §D.5 — where this probe is in the guided progression. Null renders
  /// no progression at all, which is what the pit and instrument mode want.
  final CookPhaseState? phase;

  /// The user saying they took it off the heat — **the one input the phase
  /// engine may not infer**. Absent means no button, which is correct
  /// everywhere except at [CookPhase.pullNow].
  final VoidCallback? onPulled;

  /// The biggest the gauge is ever drawn, and the smallest it is allowed to
  /// shrink to before it moves to its own line instead.
  static const double _gaugeMax = 84;
  static const double _gaugeMin = 56;

  bool get _isPit => view.role == ProbeRole.pit;

  PlanProbe? get _planProbe {
    final p = plan;
    if (p == null) {
      return null;
    }
    for (final pp in p.probes) {
      if (pp.jack == view.probe) {
        return pp;
      }
    }
    return null;
  }

  /// The effective target for a food probe: the plan installs it, falling back
  /// to whatever the device reported.
  int? get _foodTargetF10 => _planProbe?.targetF10 ?? view.targetF10;

  /// The identity mark, resolved in order of how much each source knows: an
  /// explicit override, then this jack's own name, then the plan's preset and
  /// per-jack hazard, then the role.
  FoodGlyph get _glyph =>
      glyph ??
      FoodGlyph.forProbe(
        role: view.role,
        name: _planProbe?.name.isNotEmpty ?? false
            ? _planProbe!.name
            : view.name,
        presetId: plan?.presetId,
        hazard: _planProbe?.hazard ?? plan?.hazard,
      );

  bool get _reached {
    final target = _foodTargetF10;
    final temp = view.tempF10;
    return !_isPit && target != null && temp != null && temp >= target;
  }

  @override
  Widget build(BuildContext context) {
    final hue = ProbePalette.hue(view.probe);
    final derived = freshness.showsDerived;

    return Opacity(
      // Skip our own dim when a `StaleVeil` above is already applying it —
      // opacity multiplies, and the two together put the hero number at 16%
      // ink instead of 40%.
      opacity: veilAlreadyDims(context) ? 1.0 : freshness.ink,
      child: SmokeCard(
        accent: _isPit ? hue : null,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context, derived: derived),
            const SizedBox(height: SmokeTokens.s3),
            _readout(context, hue, showGauge: derived),
            if (derived && phase != null) ..._progression(context, hue),
            if (derived) ..._insights(context),
          ],
        ),
      ),
    );
  }

  // ── the number, and whatever room is left over ──────────────────────

  /// Lays the readout out against the width it actually has.
  ///
  /// The measurement is the point: the temperature's width is a *given*, and
  /// the gauge is what adapts to it — first by shrinking, then by moving to its
  /// own line. That is §16.5's flexible-child rule executed rather than
  /// asserted.
  Widget _readout(BuildContext context, Color hue, {required bool showGauge}) {
    final number = TempReadout(
      tempF10: view.tempF10,
      celsius: celsius,
      style: SmokeType.heroTemp,
      unitStyle: SmokeType.heroUnit,
      hue: hue,
      semanticName: view.name,
    );
    if (!showGauge) {
      return number;
    }

    final numberWidth = TempReadout.measure(
      tempF10: view.tempF10,
      celsius: celsius,
      style: SmokeType.heroTemp,
      unitStyle: SmokeType.heroUnit,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final spare = constraints.maxWidth - numberWidth - SmokeTokens.s4;
        final gauge = _gauge(size: spare.clamp(_gaugeMin, _gaugeMax));
        if (gauge == null) {
          return number;
        }
        if (spare >= _gaugeMin) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [number, const Spacer(), gauge],
          );
        }
        // Too narrow for both on one line — a four-digit °F on a 360 dp phone
        // at a large text scale. The gauge moves; the number never does.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            number,
            const SizedBox(height: SmokeTokens.s3),
            Align(alignment: Alignment.centerRight, child: gauge),
          ],
        );
      },
    );
  }

  Widget? _gauge({required double size}) {
    final pit = _isPit;
    final bandMin = pit ? plan?.pitBandMinF10 : null;
    final bandMax = pit ? plan?.pitBandMaxF10 : null;
    final target = pit ? null : _foodTargetF10;
    if ((bandMin == null || bandMax == null) && target == null) {
      return null; // never an empty ring on screen
    }
    return TargetGauge(
      hue: ProbePalette.hue(view.probe),
      reached: _reached,
      tempF10: view.tempF10,
      targetF10: target,
      pullF10: pit ? null : _planProbe?.pullF10,
      bandMinF10: bandMin,
      bandMaxF10: bandMax,
      size: size,
      centerIcon: pit
          ? Icons.local_fire_department_rounded
          : Icons.restaurant_rounded,
    );
  }

  // ── the progression ─────────────────────────────────────────────────

  /// The four-phase track, its sentence, and — only at `Pull now` — the button
  /// that moves it on.
  ///
  /// The rest countdown is labelled as an estimate wherever it appears, because
  /// carryover is not measurable from one interior point and this app does not
  /// present a physics guess as a reading.
  List<Widget> _progression(BuildContext context, Color hue) {
    final t = context.tokens;
    final state = phase!;
    return [
      const SizedBox(height: SmokeTokens.s4),
      Divider(height: 1, color: t.hairline),
      const SizedBox(height: SmokeTokens.s3),
      PhaseTrack(state: state, hue: hue),
      if (state.phase == CookPhase.pullNow && onPulled != null) ...[
        const SizedBox(height: SmokeTokens.s3),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonal(
            key: const Key('phase-pulled'),
            onPressed: onPulled,
            child: const Text('I pulled it'),
          ),
        ),
      ],
    ];
  }

  // ── header and insights ─────────────────────────────────────────────

  /// The dot, the name, and the target pill.
  ///
  /// **`derived` reaches the pill, and it did not.** The gauge, the phase track
  /// and the insight strips are all removed the moment a reading goes stale
  /// (§16.7: *"every derived value disappears when stale rather than
  /// greying"*), and "Reached" is as derived as any of them — it is a
  /// comparison of a temperature against a target. It sat outside every guard,
  /// so at `frozen` the ring was gone from the card and a ✓ **Reached 203°**
  /// still asserted, in the present tense, from a four-hour-old number. That is
  /// the exact failure §16.2 names: a stale claim that looks live.
  Widget _header(BuildContext context, {required bool derived}) {
    final t = context.tokens;
    final reached = derived && _reached;
    return Row(
      children: [
        // §17.3 B — the badge replaces the 10 dp dot. It says the same thing
        // (which jack) at a size a tired reader can find, and §17.2 sanctions
        // the fill: the numeral names what the hue already named.
        JackBadge(jack: view.probe, size: 22),
        const SizedBox(width: SmokeTokens.s2),
        // §17.3 A — and the avatar says *what is cooking*, on the card whose
        // whole job is to be the one thing you look at.
        FoodAvatar(glyph: _glyph, size: 26, announce: false),
        const SizedBox(width: SmokeTokens.s2),
        Expanded(
          child: Text(
            view.name.toUpperCase(),
            // The hue is the badge and the rule; the word is ink (§16.5).
            style: SmokeType.label.copyWith(color: t.textHi),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_isPit)
          TargetPill(
            targetF10: null,
            reached: false,
            celsius: celsius,
            bandMinF10: plan?.pitBandMinF10,
            bandMaxF10: plan?.pitBandMaxF10,
          )
        else if (_foodTargetF10 != null)
          TargetPill(
            targetF10: _foodTargetF10,
            reached: reached,
            celsius: celsius,
          ),
      ],
    );
  }

  /// The one strip under the number — or the trend chip, when nothing is worth
  /// a full-width one.
  ///
  /// **A refusal is an answer, and it is not a value.** This handed every ETA,
  /// refusals included, to a `trailing` under the label *"Ready in"* — so a
  /// probe the estimator had declined to guess at read *"Ready in · ETA
  /// unavailable — holding steady"*: a promise of a duration answered by a
  /// sentence explaining there is not one, and "ETA" said twice whenever there
  /// was. §D.5 requires a refusal to **state its reason**, and it does that as
  /// the strip's own sentence rather than as the value of the question it is
  /// declining to answer. The `eta != noValue` guard that was supposed to
  /// catch this could never fire: the old formatter returned `''` for null and
  /// a sentence for every refusal, and neither is an em dash.
  List<Widget> _insights(BuildContext context) {
    final out = <Widget>[];
    if (view.stalled) {
      // The trailing is the half that was missing: "Stalled" on its own says
      // what is happening and not what it costs, and what it costs is the
      // estimate that was on this strip a moment ago. A value that vanishes
      // without a word is the disappearance §16.2 is written against.
      out.add(
        const InsightBanner(
          kind: InsightKind.stall,
          label: 'Stalled',
          trailing: 'Estimate paused',
        ),
      );
    } else if (_isPit) {
      final band = _bandVerdict();
      if (band != null) {
        out.add(band);
      }
    } else {
      switch (view.eta) {
        case final EtaRange eta:
          out.add(
            InsightBanner(
              kind: InsightKind.eta,
              label: 'Ready in',
              trailing: formatEtaSpan(eta),
            ),
          );
        case final EtaUnavailable eta:
          // Still the clock icon: this is the estimate slot, saying what it
          // knows. An `info` glyph here would read as a different subject.
          out.add(
            InsightBanner(
              kind: InsightKind.eta,
              label: formatEtaRefusal(eta),
            ),
          );
        case null:
          break;
      }
    }
    if (out.isEmpty) {
      // Trend rides under the number rather than as a banner, except where an
      // insight is genuinely worth a full strip.
      out.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TrendChip(rateFPerHr: view.rateFPerHr),
        ),
      );
    }
    return [const SizedBox(height: SmokeTokens.s3), ...out];
  }

  /// §16.5's colour rule, closed on the pit.
  ///
  /// [TargetGauge]'s band mode paints its arc `warning` and its current-value
  /// dot `critical` the moment the pit leaves the band — and **nothing
  /// anywhere said so in words.** There was no `InsightKind.band` call site in
  /// the app: a status hue carrying a verdict on its own, which is the single
  /// thing §16.5 forbids outright ("always with an icon *and* a word"). A
  /// reader who cannot separate amber from red, or who is looking at a
  /// sunlit OLED, got nothing at all. This is the word.
  InsightBanner? _bandVerdict() {
    final min = plan?.pitBandMinF10;
    final max = plan?.pitBandMaxF10;
    final temp = view.tempF10;
    if (min == null ||
        max == null ||
        temp == null ||
        (temp >= min && temp <= max)) {
      return null;
    }
    return InsightBanner(
      kind: InsightKind.band,
      label: temp > max ? 'Pit is above the band' : 'Pit is below the band',
      trailing:
          '${formatSetpoint(min, celsius: celsius)}–'
          '${formatSetpoint(max, celsius: celsius)}',
    );
  }
}
