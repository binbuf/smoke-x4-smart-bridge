/// A19.6 — ProbeHeroCard (design 14 §14.7.2).
///
/// The 208 dp headline card for the pit and the primary food probe. Anatomy,
/// top to bottom:
///
///   dot(10) · LABEL · [TargetPill]
///   [heroTemp][°unit]        [spacer]        [TargetGauge 84]
///   0–2 InsightBanner
///
/// The temperature is **never scaled to fit** — the gauge is the flexible child
/// of the middle row, so a four-digit reading pushes the gauge, never resizes
/// the number (§14.5.1).
///
/// The pit reads its gauge in **band mode** (a target band); a food probe reads
/// it in **sweep mode** (fills toward its target, with a pull tick). When a food
/// probe reaches its target the ring closes and the pill flips to "Reached" —
/// there is no green (§14.6.6).
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/entities/entities.dart' show ProbeRole;
import '../../domain/plan/plan.dart';
import '../../features/dashboard/dashboard_snapshot.dart';
import '../insight/insight_banner.dart' show InsightBanner, InsightKind;
import '../surface/smoke_card.dart';
import 'animated_temp.dart';
import 'probe_freshness.dart';
import 'probe_pills.dart';
import 'target_gauge.dart';

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
  });

  final ProbeView view;

  /// The active cook plan, or null in instrument mode. Supplies the pit band
  /// and the food pull temperature.
  final CookPlan? plan;
  final ProbeFreshness freshness;
  final bool celsius;
  final VoidCallback? onTap;

  /// newapp §D.5 — where this probe is in the guided progression. Null keeps
  /// the card exactly as it was, which is what instrument mode and the
  /// existing goldens want.
  final CookPhaseState? phase;

  /// The user saying they took it off the heat — **the one input the phase
  /// engine may not infer**. Absent means no button, which is correct
  /// everywhere except at [CookPhase.pullNow].
  final VoidCallback? onPulled;

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
  /// to whatever the device reported. This is how confirming a cook "installs
  /// targets" (§13.3.1) — the plan, not the live projection, is the source.
  int? get _foodTargetF10 => _planProbe?.targetF10 ?? view.targetF10;

  bool get _reached {
    final target = _foodTargetF10;
    final temp = view.tempF10;
    return !_isPit && target != null && temp != null && temp >= target;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hue = ProbePalette.hue(view.probe);
    final ink = freshness.ink;

    final int? bandMin = _isPit ? plan?.pitBandMinF10 : null;
    final int? bandMax = _isPit ? plan?.pitBandMaxF10 : null;
    final pull = _planProbe?.pullF10;

    final gauge = TargetGauge(
      hue: hue,
      reached: _reached,
      tempF10: view.tempF10,
      targetF10: _isPit ? null : _foodTargetF10,
      pullF10: _isPit ? null : pull,
      bandMinF10: bandMin,
      bandMaxF10: bandMax,
      centerIcon: _isPit
          ? Icons.local_fire_department_rounded
          : Icons.restaurant_rounded,
    );

    return Opacity(
      opacity: ink,
      child: SmokeCard(
        accent: _isPit ? hue : null,
        onTap: onTap,
        child: SizedBox(
          // The phase row costs ~22 dp and must not squeeze the 96 pt number,
          // which is the one thing on this card that may never be scaled.
          height: phase == null ? 176 : 202,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context, hue),
              const SizedBox(height: SmokeTokens.s2),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // The number renders at full 96 pt for every value it can
                    // actually show at a supported width (≤ 3 digits + unit) —
                    // no frame-to-frame jitter (§14.5.1). The FittedBox is a
                    // safety that only engages in the corner cases a fixed
                    // layout cannot survive (a 5-char negative °F, large text
                    // scale), where a 14 px throw is worse than a 4 % shrink.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: AnimatedTemp(
                          tempF10: view.tempF10,
                          celsius: celsius,
                          style: SmokeType.heroTemp.copyWith(color: t.textHi),
                          unitStyle: SmokeType.heroUnit,
                          color: t.textHi,
                          semanticName: view.name,
                        ),
                      ),
                    ),
                    const SizedBox(width: SmokeTokens.s3),
                    if (freshness.showsDerived) gauge,
                  ],
                ),
              ),
              // §D.5 — the phase rides under the number as a MARK, never as a
              // colour: green is transport health, and target-reached closes
              // the gauge ring rather than turning it green (§14.6).
              if (freshness.showsDerived && phase != null) _phaseRow(context),
              if (freshness.showsDerived) ..._insights(context),
            ],
          ),
        ),
      ),
    );
  }

  /// The phase pill plus its one sentence, and — only at `Pull now` — the
  /// button that moves it on.
  ///
  /// The rest countdown is labelled as an estimate wherever it appears, because
  /// carryover is not measurable from one interior point and this app does not
  /// present a physics guess as a reading.
  Widget _phaseRow(BuildContext context) {
    final t = context.tokens;
    final state = phase!;
    return Padding(
      padding: const EdgeInsets.only(top: SmokeTokens.s1),
      child: Row(
        children: [
          Container(
            key: Key('phase-${state.phase.name}'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: t.cardSubtle,
              borderRadius: BorderRadius.circular(SmokeTokens.radiusPill),
              border: Border.all(color: t.hairlineStrong),
            ),
            child: Text(
              state.phase == CookPhase.resting && state.restRemainingS != null
                  ? '${state.phase.label} · '
                        '${formatDuration(state.restRemainingS!)} left'
                  : state.phase.label,
              style: SmokeType.labelSm.copyWith(color: t.textHi),
            ),
          ),
          const SizedBox(width: SmokeTokens.s2),
          Expanded(
            child: Text(
              state.estimated ? '${state.detail} (estimate)' : state.detail,
              style: SmokeType.labelSm.copyWith(color: t.textMuted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (state.phase == CookPhase.pullNow && onPulled != null)
            TextButton(
              key: const Key('phase-pulled'),
              onPressed: onPulled,
              child: const Text('I pulled it'),
            ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, Color hue) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: hue, shape: BoxShape.circle),
        ),
        const SizedBox(width: SmokeTokens.s2),
        Expanded(
          child: Text(
            view.name.toUpperCase(),
            style: SmokeType.label.copyWith(color: hue),
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
            reached: _reached,
            celsius: celsius,
          ),
      ],
    );
  }

  List<Widget> _insights(BuildContext context) {
    final out = <Widget>[];
    // Trend rides under the number rather than as a banner, except where an
    // insight is genuinely worth a full strip.
    if (view.stalled) {
      out.add(const InsightBanner(kind: InsightKind.stall, label: 'Stalled'));
    } else if (!_isPit && view.eta != null) {
      final eta = formatEta(view.eta);
      if (eta != noValue) {
        out.add(
          InsightBanner(
            kind: InsightKind.eta,
            label: 'Ready in',
            trailing: eta,
          ),
        );
      }
    }
    if (out.isEmpty) {
      out.add(_trendRow(context));
    }
    return [const SizedBox(height: SmokeTokens.s2), ...out];
  }

  Widget _trendRow(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TrendChip(rateFPerHr: view.rateFPerHr),
  );
}
