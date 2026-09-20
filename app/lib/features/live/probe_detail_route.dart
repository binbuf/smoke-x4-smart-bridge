/// `/live/probe/:jack` — per-probe detail (newapp §C.2).
///
/// **The chevron used to go nowhere.** `ProbeStripRow` drew one unconditionally
/// and `onProbeTap` was never passed, so every probe row on the reader looked
/// tappable, rippled when tapped, and did nothing — which is worse than a row
/// that does not look tappable at all. This is where it goes.
///
/// It answers one question: *"what is this one probe doing over time, and what
/// should it alarm on?"* — the big current reading and its trend, the chart with
/// its window chips and crosshair, this probe's role and target, and its alarm
/// rules with inline edit.
///
/// **§C.2's open question, settled: the chart affordances converge.** Window
/// chips, the "Now" pill and the crosshair existed only in History; the live
/// chart had gestures and no controls. Two different chart experiences for the
/// same data is a seam a user feels and cannot name. This screen uses the same
/// [CookChart] + [ChartControls] pair History does, over the live samples.
///
/// ## What this pass fixed, and why it mattered here most
///
/// This was the weakest screen in the app, and every one of its faults was a
/// house rule broken in the one place the rule is loudest.
///
/// **The veil was unconditional.** The hero was wrapped in a [StaleVeil] with
/// no freshness guard, so a *live* reading rendered at 55 % opacity, through a
/// 25 %-saturation filter, under an empty advisory strip. The component whose
/// entire job is to make a stale number look stale was making every number look
/// stale — which teaches a reader to ignore it, on the screen where ignoring it
/// costs the most. It is now `freshness.isDim ? veil : card`.
///
/// **A device fact was rendered from a default.** The pinned age read
/// `formatElapsed(snapshot.lastPacketSAgo ?? 0)`, so an unknown age printed
/// **"Last reading 00:00:00 ago"** — §16.4 rule 9's exact prohibition (absent is
/// "—" or a sentence, never 0), in a clock format nothing else in the app uses,
/// off a counter that measures the *base station's* silence rather than ours.
/// The age now comes from `readingAtUnixMs` — the phone's own clock, the thing
/// the freshness ladder itself runs on — and unknown says so in words.
///
/// **The hero took the OS text scale.** A bare `Text(formatTemp(...))` at
/// [SmokeType.bigTemp], no [TempReadout], no `maxLines`, and the unit letter
/// dropped (`254.2°`, not `254.2°F`). §H.1 calls *never scale a temperature*
/// the single most important glanceable rule; at 200 % this screen's whole
/// point overflowed its card. [TempReadout] has done this correctly everywhere
/// else since the reader pass.
///
/// **The chart was frozen at mount.** `_viewport ??= …` initialised once and
/// never extended, so the screen whose one question is *"what is this probe
/// doing over time"* stopped advancing the instant you opened it: the "Now"
/// pill never appeared and `clipData` hid every sample that arrived after. It
/// mirrors `LiveTab._viewportFor` now — extend on every build, follow until the
/// user pans.
///
/// **The state ladder collapsed into one dead end.** Empty, loading, offline
/// and error all rendered *"Open this from the live screen once the bridge is
/// connected"* — advice to do the thing the reader had just done, about a
/// screen that renders **without** a connection (§B.3). It renders the same
/// cache-first shape the reader does, keyed to this jack; the empty state is
/// reserved for the one genuinely empty case, a jack that does not exist.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';
import '../../domain/plan/plan.dart';
import '../../ui/probe/food_avatar.dart';
import '../../ui/probe/jack_badge.dart';
import '../../ui/probe/temp_readout.dart';
import '../../ui/ui.dart';
import '../chart/chart_viewport.dart';
import '../chart/cook_chart.dart';
import '../dashboard/dashboard_snapshot.dart';
import '../shell/shell_scope.dart';
import '../shell/shell_session.dart';

/// The jacks a Smoke X has. A path parameter is a string a user can type, so
/// "does this probe exist" is a real question with a real answer.
const int _jacks = 4;

class ProbeDetailRoute extends StatefulWidget {
  const ProbeDetailRoute({required this.jack, super.key});

  final int jack;

  @override
  State<ProbeDetailRoute> createState() => _ProbeDetailRouteState();
}

class _ProbeDetailRouteState extends State<ProbeDetailRoute> {
  ChartViewport? _viewport;
  int? _crosshairT;

  /// Initialise, then keep extending, the chart viewport as samples arrive —
  /// lifted from `LiveTab._viewportFor`, because a live chart that does not
  /// follow is a screenshot.
  ///
  /// [ChartViewport.extendTo] is what makes "follow until the user pans"
  /// possible: it grows `sessionToT` on every build and only re-anchors the
  /// window while `following` is still true, so a pan or a pinch keeps its
  /// place and the "Now" pill appears to offer the way back.
  ChartViewport? _viewportFor(DashboardSnapshot s, ChartViewport? current) {
    if (s.samples.isEmpty) {
      return current;
    }
    final toT = s.samples.last.t;
    return current == null
        ? ChartViewport.forSession(
            fromT: s.samples.first.t,
            toT: toT,
            window: ChartWindow.all,
          )
        : current.extendTo(toT);
  }

  /// This screen's first frame (§B.3, mirrored from the reader).
  ///
  /// A detail route opened before the cache has answered — or mounted with no
  /// shell above it at all — is not an empty screen. It is *this* screen with
  /// no value in it yet, and it must be the shape the value will land into, so
  /// nothing reflows when it does.
  static DashboardSnapshot _firstFrame(int jack) =>
      DashboardSnapshot(probes: [_blankView(jack)], link: LinkKind.offline);

  /// One jack, no reading. The role follows the device's own convention — and
  /// `buildDashboard`'s fallback — that **jack 1 is the pit**, so a first frame
  /// and the real snapshot never disagree about what this probe is for.
  static ProbeView _blankView(int jack) => ProbeView(
    probe: jack,
    role: jack == 1 ? ProbeRole.pit : ProbeRole.food,
    name: 'Probe $jack',
  );

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final jack = widget.jack;

    // The one genuinely empty state on this route: a path parameter naming a
    // jack this hardware does not have. Everything else — no session, no
    // cache, no link — is a *reading* state, and reading states render the
    // reader (§16.6).
    if (jack < 1 || jack > _jacks) {
      return Scaffold(
        backgroundColor: t.bg,
        appBar: AppBar(title: const Text('Probe')),
        body: const SafeArea(
          child: EmptyState(
            icon: Icons.sensors_off_rounded,
            title: 'No such probe',
            message:
                'This bridge has four probe jacks, numbered 1 to 4. Pick one '
                'from the live screen.',
          ),
        ),
      );
    }

    final session = ShellScope.maybeOf(context);
    final snapshot = session?.snapshot ?? _firstFrame(jack);
    final probe =
        snapshot.probes.where((p) => p.probe == jack).firstOrNull ??
        _blankView(jack);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: Text(probe.name)),
      body: SafeArea(child: _body(context, session, snapshot, probe)),
    );
  }

  Widget _body(
    BuildContext context,
    ShellSession? session,
    DashboardSnapshot snapshot,
    ProbeView probe,
  ) {
    final t = context.tokens;
    final celsius = session?.celsius ?? false;
    final freshness = session?.freshness ?? ProbeFreshness.unknown;
    final plan = session?.plan;
    final planProbe = plan?.probes
        .where((p) => p.jack == widget.jack)
        .firstOrNull;

    // How old the number on screen is, on the phone's own clock — the same
    // fact the freshness ladder ages against, so the veil and the sentence
    // under it can never contradict each other. Null is *unknown*, and unknown
    // is said in words rather than shown as zero.
    final at = snapshot.readingAtUnixMs;
    final ageS = at == null
        ? null
        : ((DateTime.now().millisecondsSinceEpoch - at) ~/ 1000).clamp(
            0,
            1 << 30,
          );

    _viewport = _viewportFor(snapshot, _viewport);
    final viewport = _viewport;

    return ListView(
      key: const Key('probe-detail'),
      padding: const EdgeInsets.all(SmokeTokens.s4),
      children: [
        // The hero number, under the same freshness rule as the reader: a
        // stale reading is veiled and its derived values are REMOVED, not
        // greyed, wherever it appears — and a fresh one is not veiled at all.
        _veiled(
          _hero(context, probe, plan, freshness, ageS, celsius: celsius),
          freshness,
          ageS,
        ),
        const SizedBox(height: SmokeTokens.s3),

        // §17.3 B — High / Avg / Low for the window on screen, as `FireBoard-2`
        // does. Deliberately **outside** the veil above: see [_windowStats].
        ..._windowStats(context, snapshot, viewport, celsius: celsius),

        // §C.2 — the converged chart: the live series with History's controls.
        if (viewport == null)
          const CapabilityNotice(
            key: Key('probe-detail-no-history'),
            icon: Icons.show_chart_rounded,
            message:
                'No readings on this phone yet for this probe. The chart '
                'appears as they arrive.',
          )
        else
          _chart(context, snapshot, probe, viewport, celsius: celsius),
        const SizedBox(height: SmokeTokens.s3),

        // What this probe is for, and what it will alarm on.
        SmokeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'THIS PROBE',
                style: SmokeType.label.copyWith(color: t.textMuted),
              ),
              const SizedBox(height: SmokeTokens.s2),
              _row(t, 'Role', _roleLabel(probe.role)),
              if (probe.role == ProbeRole.pit &&
                  plan?.pitBandMinF10 != null &&
                  plan?.pitBandMaxF10 != null)
                // A pit is held in a band, not driven at a target, and
                // rendering "Target — Not set" against one was a true
                // statement that read as a missing setting.
                _row(
                  t,
                  'Target band',
                  '${formatSetpoint(plan!.pitBandMinF10, celsius: celsius)}–'
                  '${formatSetpoint(plan.pitBandMaxF10, celsius: celsius)}',
                )
              else
                _row(
                  t,
                  'Target',
                  probe.targetF10 == null
                      // Absent ≠ zero, all the way to the pixels.
                      ? 'Not set'
                      : formatSetpoint(probe.targetF10, celsius: celsius),
                ),
              if (planProbe?.pullF10 != null)
                _row(
                  t,
                  'Pull at',
                  formatSetpoint(planProbe!.pullF10, celsius: celsius),
                ),
            ],
          ),
        ),
        const SizedBox(height: SmokeTokens.s3),

        // The rules live in one editor, and this is a link to it rather than a
        // second, divergent editing surface.
        SmokeCard(
          key: const Key('probe-detail-alarms'),
          onTap: () => context.push(AppRoutes.deviceAlarms),
          child: Row(
            children: [
              Icon(Icons.notifications_outlined, color: t.textBody),
              const SizedBox(width: SmokeTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alarm rules',
                      style: SmokeType.title.copyWith(color: t.textHi),
                    ),
                    // **The copy is what changed, not the destination.** It
                    // promised "that probe's section" and opened the editor at
                    // the top, which takes no argument — a small lie that
                    // costs a moment of hunting at 3 a.m. `/device/alarms` is
                    // a whole-bridge editor, so this says so.
                    Text(
                      'Every rule on this bridge, in one editor.',
                      style: SmokeType.bodySm.copyWith(color: t.textMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.chromeDim),
            ],
          ),
        ),
      ],
    );
  }

  // ── the hero ────────────────────────────────────────────────────────

  /// The number, its trend, and whatever the analysis layer can honestly say.
  ///
  /// The temperature is on its **own line**, full width, and that is the
  /// layout doing the work rather than a comment claiming it: with nothing
  /// beside it, no chip, no text scale and no window width can squeeze it, so
  /// [TempReadout]'s `scaleDown` safety valve never has to fire.
  Widget _hero(
    BuildContext context,
    ProbeView probe,
    CookPlan? plan,
    ProbeFreshness freshness,
    int? ageS, {
    required bool celsius,
  }) {
    final t = context.tokens;
    final derived = freshness.showsDerived;
    final planProbe = plan?.probes
        .where((p) => p.jack == widget.jack)
        .firstOrNull;
    return SmokeCard(
      spine: ProbePalette.hue(widget.jack),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // §17.3 — the identity row, and *only* identity.
          //
          // The AppBar already carries the probe's *name*, so this row does not
          // repeat it (§16.5: the title is not rendered twice on a pushed
          // route). What it adds is what a title cannot: which jack this is, in
          // the hue the chart below draws it in, and a picture of what is on it.
          //
          // **A target pill was here and has been removed.** It duplicated the
          // "Target"/"Target band" row in the facts card six lines further down,
          // and at a 200 % text scale on a 360 dp phone `Band 225°–275°` had
          // nowhere to go — the row overflowed by 186 px. Two statements of one
          // setting on one screen is the redundancy §16.5 rejects in row
          // subtitles, so the fix and the design agree: this row is identity,
          // everything below it is state.
          Row(
            children: [
              JackBadge(jack: widget.jack, size: 22),
              const SizedBox(width: SmokeTokens.s2),
              FoodAvatar(
                glyph: FoodGlyph.forProbe(
                  role: probe.role,
                  name: (planProbe?.name ?? '').isEmpty
                      ? probe.name
                      : planProbe!.name,
                  presetId: plan?.presetId,
                  hazard: planProbe?.hazard ?? plan?.hazard,
                ),
                size: 26,
                // §17.5 — rich only where nothing on this screen is claiming a
                // temperature: an unplugged jack with no cook behind it. The
                // moment a reading lands the card cools, which is the same
                // moment the hero stops saying `—`.
                vivid: plan == null && !probe.attached,
              ),
              const SizedBox(width: SmokeTokens.s2),
              Expanded(
                child: Text(
                  _roleLabel(probe.role).toUpperCase(),
                  style: SmokeType.label.copyWith(color: t.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: SmokeTokens.s3),
          TempReadout(
            tempF10: probe.tempF10,
            celsius: celsius,
            style: SmokeType.heroTemp,
            unitStyle: SmokeType.heroUnit,
            hue: ProbePalette.hue(widget.jack),
            semanticName: probe.name,
          ),
          // The trust line, in the one state the veil is not already carrying
          // it. Two elements saying one thing is how people learn to read
          // neither (the reader's masthead makes the same call).
          if (!freshness.isDim) ...[
            const SizedBox(height: SmokeTokens.s2),
            Text(
              _trustLine(freshness, ageS),
              style: SmokeType.bodySm.copyWith(color: t.textMuted),
            ),
          ],
          if (derived) ..._insights(probe, plan, celsius: celsius),
        ],
      ),
    );
  }

  /// The trend chip and the one strip worth a full width — the same shapes,
  /// the same words and the same refusal handling as `ProbeHeroCard`, because
  /// two surfaces describing one probe differently is a seam a user feels and
  /// cannot name.
  ///
  /// The rows this replaced were *"Estimate — not at this pit temperature"*
  /// and *"Stall — In a stall, the estimate is paused"*, sitting in the facts
  /// table between "Role" and "Pull at". A refusal is not a fact about the
  /// probe's configuration, and a label promising a duration is not the place
  /// to explain there is not one (§D.5, §16.4 rules 3 and 5).
  List<Widget> _insights(
    ProbeView probe,
    CookPlan? plan, {
    required bool celsius,
  }) {
    final out = <Widget>[];
    if (probe.stalled) {
      out.add(
        const InsightBanner(
          kind: InsightKind.stall,
          label: 'Stalled',
          trailing: 'Estimate paused',
        ),
      );
    } else if (probe.role == ProbeRole.pit) {
      final band = _bandVerdict(probe, plan, celsius: celsius);
      if (band != null) {
        out.add(band);
      }
    } else {
      switch (probe.eta) {
        case final EtaRange eta:
          out.add(
            InsightBanner(
              kind: InsightKind.eta,
              label: 'Ready in',
              trailing: formatEtaSpan(eta),
            ),
          );
        case final EtaUnavailable eta:
          out.add(
            InsightBanner(kind: InsightKind.eta, label: formatEtaRefusal(eta)),
          );
        case null:
          break;
      }
    }
    if (probe.rateFPerHr != null) {
      out.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TrendChip(rateFPerHr: probe.rateFPerHr),
        ),
      );
    }
    return [
      for (final w in out) ...[const SizedBox(height: SmokeTokens.s3), w],
    ];
  }

  /// The pit's band verdict in words — §16.5's colour rule, which the gauge
  /// on the reader breaks by painting `warning` and `critical` with nothing
  /// saying so. This screen has no gauge, so it has no hue to caption; it says
  /// it anyway, because the two surfaces have to agree.
  InsightBanner? _bandVerdict(
    ProbeView probe,
    CookPlan? plan, {
    required bool celsius,
  }) {
    final min = plan?.pitBandMinF10;
    final max = plan?.pitBandMaxF10;
    final temp = probe.tempF10;
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

  // ── High / Avg / Low, for the window on screen ──────────────────────

  /// `FireBoard-2`'s per-channel statistics, which §17.3 B asks for by name.
  ///
  /// FireBoard prints High / Avg / Low over 24 hours beside every reading, and
  /// it is the one thing on that screen genuinely better than what we had: a
  /// number on its own says where a probe is, and these three say what it has
  /// been doing — which is most of what a person opens a per-probe screen to
  /// find out.
  ///
  /// **Computed by `cookStats`, not re-derived.** §17.3 is explicit about
  /// reuse, and the mean is the value with somewhere to go wrong. `cookStats`
  /// only computes a mean, a σ and min/max for the probe carrying the **pit
  /// role** — that slot is *"the reference probe"*, not a claim about the
  /// hardware — so this screen names its own jack as the reference for the
  /// length of one call. The alternative was a fourth place in this codebase
  /// that knows how to average a temperature series.
  ///
  /// **Outside the [StaleVeil], and that is a decision rather than an
  /// oversight.** §16.7 removes *derived* values when the reading behind them
  /// goes stale, because a derived value inherits the claim "this is true now".
  /// These do not make that claim: they are explicitly labelled with the span
  /// they cover, and *"the high over the six hours on screen was 274°"* is
  /// exactly as true when the link has been down for an hour. What would be
  /// dishonest is an unlabelled average, so the label carries the span and is
  /// not optional.
  List<Widget> _windowStats(
    BuildContext context,
    DashboardSnapshot snapshot,
    ChartViewport? viewport, {
    required bool celsius,
  }) {
    if (viewport == null) {
      return const [];
    }
    final t = context.tokens;
    final window = [
      for (final s in snapshot.samples)
        if (s.t >= viewport.minX && s.t <= viewport.maxX) s,
    ];
    final stats = cookStats(
      window,
      probeConfig: [Probe(n: widget.jack, role: ProbeRole.pit)],
    );
    final high = stats.pitMaxF;
    final avg = stats.pitMeanF;
    final low = stats.pitMinF;

    String temp(double? f) =>
        f == null ? noValue : formatTemp((f * 10).round(), celsius: celsius);

    return [
      SmokeCard(
        key: const Key('probe-window-stats'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              // The span, not the chip: the user may have panned, and a card
              // headed "6H" over a window that no longer ends at now would be
              // the kind of small lie §16.4 rule 9 is written against.
              'ON SCREEN · ${formatDuration(viewport.spanS)}',
              style: SmokeType.label.copyWith(color: t.textMuted),
            ),
            const SizedBox(height: SmokeTokens.s3),
            if (high == null)
              // Absent is a sentence, never a row of dashes and never a 0.
              Text(
                'Nothing recorded for this probe in the stretch on screen.',
                style: SmokeType.bodySm.copyWith(color: t.textBody),
              )
            else
              // A Wrap, not a Row: three tabular temperatures at a 200 % text
              // scale on a 360 dp phone do not fit on one line, and reflowing
              // beats ellipsing the answer.
              Wrap(
                spacing: SmokeTokens.s7,
                runSpacing: SmokeTokens.s3,
                children: [
                  _windowStat(t, 'HIGH', temp(high)),
                  _windowStat(t, 'AVG', temp(avg)),
                  _windowStat(t, 'LOW', temp(low)),
                ],
              ),
          ],
        ),
      ),
      const SizedBox(height: SmokeTokens.s3),
    ];
  }

  Widget _windowStat(SmokeTokens t, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        // Ink, never a hue — the same rule the hero above it keeps (§H.1).
        style: SmokeType.monoBig.copyWith(color: t.textHi),
        maxLines: 1,
      ),
      const SizedBox(height: SmokeTokens.s1),
      Text(label, style: SmokeType.labelSm.copyWith(color: t.textMuted)),
    ],
  );

  // ── the chart ───────────────────────────────────────────────────────

  Widget _chart(
    BuildContext context,
    DashboardSnapshot snapshot,
    ProbeView probe,
    ChartViewport viewport, {
    required bool celsius,
  }) {
    // One model, shared by the chart and the crosshair readout, so the two can
    // never disagree about what is under the finger.
    final model = buildChartSeries(
      snapshot.samples,
      fromT: viewport.minX,
      toT: viewport.maxX,
      probes: [widget.jack],
    );
    return SmokeCard(
      child: Column(
        children: [
          ChartControls(
            viewport: viewport,
            onViewport: (v) => setState(() => _viewport = v),
          ),
          const SizedBox(height: SmokeTokens.s2),
          SizedBox(
            height: 240,
            child: CookChart(
              model: model,
              viewport: viewport,
              probes: [
                Probe(
                  n: widget.jack,
                  name: probe.name,
                  role: probe.role,
                  targetF10: probe.targetF10,
                ),
              ],
              marks: snapshot.marks,
              startedUnixMs: snapshot.startedUnixMs,
              celsius: celsius,
              onViewport: (v) => setState(() => _viewport = v),
              onCrosshair: (v) => setState(() => _crosshairT = v),
              fullHistory: snapshot.fullHistory,
            ),
          ),
          if (_crosshairT != null)
            CrosshairReadout(
              readings: crosshairAt(model, _crosshairT!),
              atT: _crosshairT!,
              startedUnixMs: snapshot.startedUnixMs,
              probes: [
                Probe(n: widget.jack, name: probe.name, role: probe.role),
              ],
              celsius: celsius,
            ),
        ],
      ),
    );
  }

  // ── freshness copy ──────────────────────────────────────────────────

  /// Veils the hero once readings age past `stale`, and **only** then.
  Widget _veiled(Widget child, ProbeFreshness freshness, int? ageS) {
    if (!freshness.isDim) {
      return child;
    }
    final frozen = freshness == ProbeFreshness.frozen;
    return StaleVeil(
      ageLabel: _ageLabel(ageS, frozen: frozen),
      frozen: frozen,
      child: child,
    );
  }

  /// The pinned age over a veiled reading — the reader's words, verbatim, so
  /// the two screens sound like one app.
  String _ageLabel(int? ageS, {required bool frozen}) {
    if (ageS == null) {
      return frozen ? 'No recent readings.' : 'Reading age unknown.';
    }
    final age = formatDuration(ageS);
    return frozen ? 'No readings for $age.' : 'Readings are $age old.';
  }

  /// The age of a reading that is *not* veiled — a reassurance, and it reads
  /// as one.
  String _trustLine(ProbeFreshness freshness, int? ageS) {
    if (freshness == ProbeFreshness.unknown) {
      return 'No readings yet.';
    }
    if (ageS == null || ageS < 10) {
      return 'Updated just now.';
    }
    return ageS < 60
        ? 'Updated ${ageS}s ago.'
        : 'Updated ${formatDuration(ageS)} ago.';
  }

  String _roleLabel(ProbeRole r) => switch (r) {
    ProbeRole.pit => 'Pit',
    ProbeRole.food => 'Food',
    ProbeRole.ambient => 'Ambient',
    ProbeRole.unused => 'Not used',
  };

  /// Label left, value right (§16.5) — and **both sides wrap.**
  ///
  /// The value used to be a bare `Text` beside an `Expanded` label, which in a
  /// `Row` means unbounded width: at a 200 % text scale on a 360 dp phone
  /// "Not set" had nowhere to go but over the edge.
  Widget _row(SmokeTokens t, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          ),
        ),
        const SizedBox(width: SmokeTokens.s3),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: SmokeType.body.copyWith(color: t.textHi),
          ),
        ),
      ],
    ),
  );
}
