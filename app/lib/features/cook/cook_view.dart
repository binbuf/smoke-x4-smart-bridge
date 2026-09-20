/// The body of `/live` — **the reader** (design 16 §16.6; newapp §B.3, §C.1).
///
/// One question: *"What is everything at, and can I trust it?"* Everything on
/// this screen either answers it or is not here.
///
/// ## The shape, top to bottom, and why it is that order
///
/// ```
///   Live readings                              [End cook]   ← masthead, no card
///   Updated just now.                                          the trust line
///   ── situation ─────────────────────────────────────────   ← one, never a list
///   ┌ the well ────────────────────────────────────────┐    ← deepest surface
///   │▎PIT      ▲ +18°/hr    ╱╲__            254.2°F  › │      in the app
///   │▎BRISKET  ▲ +12°/hr    ___╱            163.2°F  › │
///   └──────────────────────────────────────────────────┘
///   [ Mark │ Set a target │ Export │ Test alarm ]        ← one strip, fixed
///   On Bluetooth — live readings only.                   ← footnotes, below
/// ```
///
/// **The masthead is not a card.** It was: a `SmokeCard` carrying a title, a
/// sentence and a "Set up a cook" button, ~112 dp of chrome sitting between the
/// user and the numbers, on the one screen whose contract says *nothing may
/// push the temperatures below the fold at any width* (§16.6). The title is now
/// type on the background, the button moved into the action strip where §16.6
/// says it lives, and the sentence became the **trust line** — the answer to
/// the half of the screen's question that no element on it used to answer.
///
/// **The readouts sit in the deepest surface, and everything else on `card`.**
/// The four rows are the content; the rest is chrome. Inverting the usual
/// "content is lighter than the page" gives the numbers a well to sit in, which
/// is what §H.2 asks for with *"a near-black surface, tuned for OLED and
/// sunlight"* — and on an OLED it is also the cheapest surface to hold lit for
/// fourteen hours.
///
/// **Detached probes render in place**, at 45 %, showing `—` and *unplugged*.
/// Even with all four out, the rows stay and the explanation appears *above*
/// them rather than replacing them: §16.6 says the probes render in place, and
/// a jack that vanishes reads as an app bug rather than as an empty jack.
///
/// **Derived values are removed when stale, not greyed** (§16.7) — and that now
/// reaches the rows themselves, which used to keep drawing a sparkline and a
/// rate at four hours old under nothing but an opacity change.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/entities/entities.dart';
import '../../domain/plan/plan.dart';
import '../../domain/situation/situation.dart';
import '../../ui/probe/food_avatar.dart';
import '../../ui/ui.dart';
import '../dashboard/dashboard_snapshot.dart';
import '../live/reader_actions.dart';
import '../live/situation_banner.dart';

class CookView extends StatelessWidget {
  const CookView({
    super.key,
    required this.snapshot,
    required this.plan,
    required this.freshness,
    this.celsius = false,
    this.paired = true,
    this.situation = Situation.ok,
    this.onSituationAction,
    this.onSetupCook,
    this.onStop,
    this.onAddMark,
    this.onTestAlarm,
    this.onExport,
    this.onProbeTap,
    this.onAck,
    this.onPair,
    this.onRefresh,
    this.showChrome = true,
    this.pulledAtUnixMs,
    this.nowUnixMs,
    this.onPulled,
  });

  /// Whether to draw this screen's own transport chip and alarm bar.
  ///
  /// False inside the shell, which owns one of each for all three tabs — with
  /// the reader drawing its own, the transport indicator changed position and
  /// scroll behaviour depending on the tab, and a ringing alarm raised two bars
  /// (§13.5.7). Defaults true so this widget still stands alone in its own
  /// tests, goldens and the lab.
  final bool showChrome;

  final DashboardSnapshot snapshot;

  /// Null → instrument mode. Non-null → guided mode.
  final CookPlan? plan;
  final ProbeFreshness freshness;
  final bool celsius;

  /// The bridge is linked to a Smoke X base station. False raises situation #8
  /// (§16.3) — whose copy is *not* "plug a probe".
  final bool paired;

  /// §16.3 — the one named situation, or [Situation.ok]. Rendered above the
  /// temperatures and never over them. The reconciling is the caller's; this
  /// widget only draws the verdict.
  final Situation situation;
  final VoidCallback? onSituationAction;

  final VoidCallback? onSetupCook;
  final VoidCallback? onStop;
  final VoidCallback? onAddMark;
  final VoidCallback? onTestAlarm;
  final VoidCallback? onExport;
  final void Function(int jack)? onProbeTap;

  /// Acknowledge the ringing alarm. Given the [Alarm] so the caller can ack the
  /// exact id — the view picks which alarm is loudest, the caller silences it.
  final void Function(Alarm alarm)? onAck;

  /// Start pairing the base station. Absent (no button) when there is no
  /// pairing flow to run.
  final VoidCallback? onPair;

  /// A26 — pull-to-refresh: ask the unit for a new value now (13 §13.5.2).
  /// Failure is **not** this widget's to report — the future must complete
  /// either way or the spinner never stops, and the shell carries the reason.
  final Future<void> Function()? onRefresh;

  /// newapp §D.5 — when the user said the food came off the heat, and the clock
  /// to measure the rest against.
  final int? pulledAtUnixMs;
  final int? nowUnixMs;

  /// Tapping "I pulled it". **The one input the phase engine may not infer.**
  final VoidCallback? onPulled;

  bool get _guided => plan != null;

  /// §17.5 — whether this reader is allowed the **rich** register.
  ///
  /// The test is not "is the link up" and not "is the app fresh". It is
  /// *"is anything on this screen claiming a temperature?"* — because that is
  /// the only thing §16.5's austerity was ever guarding against. No cook, and
  /// not one jack reading: nothing here can misstate a temperature, so the
  /// guard buys nothing and the app may look like an app about cooking.
  ///
  /// The instant a probe reports, or a cook is set up, this flips and the
  /// screen **cools** — saturated identity colour steps down to marks over
  /// `SmokeMotion.standard` and the ink-and-chrome discipline takes over. That
  /// is the app changing register from *choosing* to *watching*, and §17.5 asks
  /// for it to be a designed moment rather than an accident.
  bool get _warm => plan == null && !snapshot.anyAttached;

  // ── the situation ───────────────────────────────────────────────────

  /// The situation actually rendered.
  ///
  /// The caller reconciles and normally wins. The one thing this widget adds is
  /// a fact only it holds: `paired == false` **is** situation #8, and a caller
  /// that did not reconcile (a golden, the lab, a bare test) must still not
  /// leave "plug a probe" as the advice for a bridge that has never met a base
  /// station (§16.3, 13 §13.5.2).
  Situation get _situation {
    if (situation.showsBanner) {
      return situation;
    }
    if (!paired) {
      return Situation(
        kind: SituationKind.bridgeNotPairedToBase,
        headline: 'Your bridge hasn’t met your Smoke X yet',
        detail:
            'It is working — it just has nothing to listen to. Hold SYNC on '
            'the base station and the two introduce themselves.',
        actionLabel: 'Pair the base station',
      );
    }
    return situation;
  }

  /// What is on one jack (17 §17.3 A).
  ///
  /// Resolved here rather than inside the row, because this is the layer that
  /// holds the cook: a plan carries a preset, a per-jack hazard and the name the
  /// user typed into the setup sheet, and all three are better evidence than the
  /// device's probe name on its own. The row's own fallback handles instrument
  /// mode, where there is no cook and the name is all there is.
  ///
  /// **It never consults freshness, the alarm list or the link.** The identity
  /// channel exists precisely because it cannot lie about state (§17.2), and it
  /// can only keep that promise if nothing about state reaches it.
  FoodGlyph _glyphFor(ProbeView view) {
    final planProbe = plan?.probes
        .where((p) => p.jack == view.probe)
        .firstOrNull;
    final named = planProbe?.name ?? '';
    return FoodGlyph.forProbe(
      role: view.role,
      name: named.isEmpty ? view.name : named,
      presetId: plan?.presetId,
      hazard: planProbe?.hazard ?? plan?.hazard,
    );
  }

  /// The phase for one food jack, or null where there is nothing to progress
  /// through (the pit, no plan, no clock).
  CookPhaseState? _phaseFor(ProbeView view) {
    final p = plan;
    final now = nowUnixMs;
    if (p == null || now == null || view.role == ProbeRole.pit) {
      return null;
    }
    final planProbe = p.probes.where((pp) => pp.jack == view.probe).firstOrNull;
    if (planProbe == null || planProbe.isPit) {
      return null;
    }
    return cookPhaseFor(
      tempF10: view.tempF10,
      targetF10: planProbe.targetF10 ?? view.targetF10,
      pullF10: planProbe.pullF10,
      nowUnixMs: now,
      pulledAtUnixMs: pulledAtUnixMs,
      safetyRestS: (p.floor?.restMinutes ?? 0) * 60,
    );
  }

  /// The single loudest alarm still ringing — highest severity, device-scope
  /// (`probe == 0`) included. Ties keep device order (the first seen).
  Alarm? get _topAlarm {
    Alarm? best;
    for (final a in snapshot.alarms) {
      if (a.acked) {
        continue;
      }
      if (best == null || a.severity.index > best.severity.index) {
        best = a;
      }
    }
    return best;
  }

  TransportState get _transportState => switch (snapshot.link) {
    LinkKind.http => TransportState.wifiSta,
    LinkKind.ble => TransportState.ble,
    LinkKind.offline => TransportState.none,
  };

  String get _transportLabel => switch (snapshot.link) {
    LinkKind.http => 'Wi-Fi',
    LinkKind.ble => 'Bluetooth',
    LinkKind.offline => 'Offline',
  };

  /// The pulse dot animates only while readings are actually arriving; a dead
  /// link or a stale stream stops it.
  bool get _linkLive =>
      snapshot.link != LinkKind.offline &&
      (freshness == ProbeFreshness.live || freshness == ProbeFreshness.aging);

  @override
  Widget build(BuildContext context) {
    final motion = SmokeMotion.of(context);
    final list = ListView(
      padding: const EdgeInsets.all(SmokeTokens.s4),
      // A page that cannot scroll cannot be pulled — and the short branches
      // are exactly where a manual refresh matters most.
      physics: onRefresh == null ? null : const AlwaysScrollableScrollPhysics(),
      children: [
        if (showChrome) _standaloneChrome(context),
        _masthead(context, motion),
        ..._situationSlot(context),
        ..._content(context, motion),
        ..._footnotes(context),
      ],
    );
    final refresh = onRefresh;
    return refresh == null
        ? list
        : RefreshIndicator(onRefresh: refresh, child: list);
  }

  /// Chip and alarm bar, for the standalone case only — inside the shell these
  /// belong to the shell, once, for every tab.
  Widget _standaloneChrome(BuildContext context) {
    final alarm = _topAlarm;
    final ack = onAck;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TransportChip(
            state: _transportState,
            label: _transportLabel,
            live: _linkLive,
          ),
        ),
        const SizedBox(height: SmokeTokens.s3),
        // AlarmBar collapses to zero height when null and animates its own
        // entrance, so it is always mounted rather than conditionally built.
        AlarmBar(
          alarm: alarm,
          celsius: celsius,
          onAck: (ack == null || alarm == null) ? null : () => ack(alarm),
        ),
        const SizedBox(height: SmokeTokens.s4),
      ],
    );
  }

  // ── masthead ────────────────────────────────────────────────────────

  /// Title, trust line, elapsed — as type on the background, not as a card.
  ///
  /// The trust line is the half of this screen's question that nothing used to
  /// answer. A number with no age beside it is a claim; a number that says how
  /// old it is is information, and §16.2's whole thesis is that the second one
  /// is what keeps a fourteen-hour cook from failing silently.
  Widget _masthead(BuildContext context, SmokeMotionValues motion) {
    final t = context.tokens;
    final trust = _trust;
    return Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedSize(
              duration: motion.standard,
              curve: motion.curve,
              alignment: Alignment.topLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    // Instrument mode is never named after a cook — there is
                    // no cook. It is always "Live readings".
                    plan?.title ?? 'Live readings',
                    style: SmokeType.displayS.copyWith(color: t.textHi),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (trust != null) ...[
                    const SizedBox(height: 2),
                    // Two weights, on purpose. "Updated just now" is a
                    // reassurance and reads as one — muted, small. "Can't
                    // reach your bridge" is the answer to the question the
                    // user came here with, so it takes full ink and the body
                    // size, with the last-seen underneath it.
                    Text(
                      trust.$1,
                      style: trust.$2 == null
                          ? SmokeType.bodySm.copyWith(color: t.textMuted)
                          : SmokeType.body.copyWith(color: t.textHi),
                    ),
                    if (trust.$2 != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        trust.$2!,
                        style: SmokeType.bodySm.copyWith(color: t.textMuted),
                      ),
                    ],
                  ],
                  if (_guided) ...[
                    const SizedBox(height: SmokeTokens.s2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 15,
                          color: t.textMuted,
                        ),
                        const SizedBox(width: SmokeTokens.s1),
                        // Flexible: the "End cook" button beside this column
                        // takes its own width first, and at 360 dp with a
                        // large text scale what is left is narrower than an
                        // eight-glyph clock.
                        Flexible(
                          child: Text(
                            formatElapsed(snapshot.elapsedS),
                            style: SmokeType.mono.copyWith(color: t.textBody),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_guided) ...[
            const SizedBox(width: SmokeTokens.s3),
            // "Stop" read as *stop recording*, which this has never done — the
            // bridge logs regardless. What it ends is the guided overlay, so
            // that is what it says, and the caller puts a cost sheet behind it.
            OutlinedButton(
              onPressed: onStop,
              style: OutlinedButton.styleFrom(foregroundColor: t.textHi),
              child: const Text('End cook'),
            ),
          ],
        ],
      ),
    );
  }

  /// `(line, secondLine)` — the trust statement, or null when something louder
  /// is already carrying it.
  ///
  /// Precedence is deliberate. An unreachable bridge outranks an age, because
  /// "3 minutes old" is the wrong thing to read when the real answer is "and it
  /// is not coming". And from `stale` down this returns nothing at all: the
  /// [StaleVeil] pins the age over a desaturated body, which is louder than a
  /// subtitle and is the component the whole app's honesty rests on. Two
  /// elements saying one thing is how people learn to read neither.
  (String, String?)? get _trust {
    final s = _situation;
    if (s.kind == SituationKind.bridgeOutOfRange) {
      return (s.headline, s.detail.isEmpty ? null : s.detail);
    }
    if (freshness.isDim) {
      return null;
    }
    if (freshness == ProbeFreshness.unknown) {
      return ('No readings yet.', null);
    }
    return (_updated, null);
  }

  /// Seconds since the reading on screen reached **this phone**.
  ///
  /// Null when nothing has arrived and nothing was dated. Deliberately not
  /// `snapshot.lastPacketSAgo`: that is the device's count of the *base
  /// station's* silence, it is re-read only when an alarm/session/pairing
  /// frame happens to arrive, and it is null on the Bluetooth lane — so a
  /// quiet cook reported "Updated just now." for hours. Same class of bug as
  /// the frozen freshness ladder, on the reader's own copy.
  int? get _readingAgeS {
    final at = snapshot.readingAtUnixMs;
    if (at == null) {
      return null;
    }
    final s = (DateTime.now().millisecondsSinceEpoch - at) ~/ 1000;
    return s < 0 ? 0 : s;
  }

  String get _updated {
    final sAgo = _readingAgeS;
    if (sAgo == null || sAgo < 10) {
      return 'Updated just now.';
    }
    if (sAgo < 60) {
      return 'Updated ${sAgo}s ago.';
    }
    return 'Updated ${formatDuration(sAgo)} ago.';
  }

  // ── the situation slot ──────────────────────────────────────────────

  List<Widget> _situationSlot(BuildContext context) {
    final s = _situation;
    if (!s.showsBanner) {
      return const [];
    }
    return [
      SituationBanner(
        situation: s,
        // Pairing has a dedicated handler when the host has a flow to run;
        // otherwise the generic remedy (which routes to the device screen)
        // stands in. A situation that names a remedy and offers no way to
        // reach it is the dead control §16.7 forbids.
        onAction: s.kind == SituationKind.bridgeNotPairedToBase
            ? (onPair ?? onSituationAction)
            : onSituationAction,
      ),
      const SizedBox(height: SmokeTokens.s4),
    ];
  }

  // ── content ─────────────────────────────────────────────────────────

  List<Widget> _content(BuildContext context, SmokeMotionValues motion) => [
    // Paired, reachable, and nothing is plugged in. The rows still render —
    // the notice goes *above* them, it does not replace them (§16.6).
    //
    // **The reachability guard is not belt-and-braces.** "No probes plugged
    // in" is a claim about the *base station*, and the only way to know it is
    // to have asked the bridge and been answered. On the bench this rendered
    // over a bridge the app could not reach at all: the masthead said "Can't
    // reach your bridge — last seen 3 minutes ago" and this notice sat two
    // lines below telling the user to go and plug a probe in, on a cooker
    // that had four of them connected and reading. Absent evidence is not
    // evidence of absence (§16.4 rule 9), and a screen that contradicts
    // itself teaches people to trust neither half.
    //
    // Unreachable is already named by the situation above; this stays quiet.
    if (paired && !snapshot.anyAttached && _readingsAreCurrent) ...[
      _noProbes(context),
      const SizedBox(height: SmokeTokens.s4),
    ],
    _veiled(
      AnimatedSize(
        duration: motion.standard,
        curve: motion.curve,
        alignment: Alignment.topCenter,
        child: _guided ? _guidedBody(context) : _instrumentBody(context),
      ),
    ),
    ..._actionSlot(context),
  ];

  /// The action strip, or nothing.
  ///
  /// §16.6 names all four and says the row is real. A cell whose handler is
  /// absent is not rendered as a dead button; a cell whose *precondition* has
  /// failed is rendered dimmed with its reason underneath (§16.7), because a
  /// control that can still be honoured tomorrow should not disappear today.
  List<Widget> _actionSlot(BuildContext context) {
    final offline = snapshot.link == LinkKind.offline;
    final nothingRecorded = snapshot.samples.isEmpty;
    final actions = <ReaderAction>[
      if (onAddMark != null)
        ReaderAction(
          icon: Icons.bookmark_add_outlined,
          label: 'Mark',
          onTap: offline ? null : onAddMark,
          reason:
              'A mark is written on the bridge, so marking needs a connection.',
        ),
      if (onSetupCook != null)
        ReaderAction(
          icon: _guided ? Icons.tune_rounded : Icons.flag_outlined,
          // A verb that names the outcome, and it changes with what is
          // running: you set a target once, then you edit the cook.
          label: _guided ? 'Edit cook' : 'Set a target',
          onTap: onSetupCook,
        ),
      if (onExport != null)
        ReaderAction(
          icon: Icons.ios_share_rounded,
          label: 'Export',
          onTap: nothingRecorded ? null : onExport,
          reason: 'There are no readings on this phone to export yet.',
        ),
      if (onTestAlarm != null)
        ReaderAction(
          icon: Icons.notifications_active_outlined,
          label: 'Test alarm',
          onTap: onTestAlarm,
        ),
    ];
    if (actions.isEmpty) {
      return const [];
    }
    return [
      const SizedBox(height: SmokeTokens.s4),
      ReaderActionRow(actions: actions),
    ];
  }

  /// Below the numbers, never above them: what the current lane cannot do is a
  /// footnote to a reading, not a header over it.
  ///
  /// **Gated on the capability, not on the lane.** "On Bluetooth — live
  /// readings only" was rendered for every BLE link, and since firmware v1.1
  /// Bluetooth carries whole cooks (ble-gatt §5.10) — `BleTransport` reads
  /// `fullHistory` straight out of the device's capability bits. The notice was
  /// telling a v1.1 owner their bridge cannot do the thing it was doing, which
  /// is a false claim in the one direction §16.4 cares about least generously:
  /// the app being wrong about the device. [CookChart] has always gated its own
  /// copy on `fullHistory`; this reads the same fact, so the two can never
  /// disagree on one screen.
  List<Widget> _footnotes(BuildContext context) => [
    if (snapshot.link == LinkKind.ble && !snapshot.fullHistory) ...[
      const SizedBox(height: SmokeTokens.s4),
      const CapabilityNotice(
        message: 'On Bluetooth — live readings only.',
        icon: Icons.bluetooth_rounded,
      ),
    ],
  ];

  /// Wraps the probe area in a [StaleVeil] once readings age past `stale`, so a
  /// four-hour-old temperature cannot read as fresh (13 §13.6.1).
  Widget _veiled(Widget child) {
    if (!freshness.isDim) {
      return child;
    }
    final frozen = freshness == ProbeFreshness.frozen;
    return StaleVeil(
      ageLabel: _ageLabel(frozen: frozen),
      frozen: frozen,
      child: child,
    );
  }

  String _ageLabel({required bool frozen}) {
    final sAgo = _readingAgeS;
    if (sAgo == null) {
      return frozen ? 'No recent readings.' : 'Reading age unknown.';
    }
    final age = formatDuration(sAgo);
    return frozen ? 'No readings for $age.' : 'Readings are $age old.';
  }

  /// Whether the app has a live link **and** a reading recent enough to speak
  /// for the base station right now.
  ///
  /// The freshness rung is the test rather than `link != offline`, because a
  /// link can be up while the stream is dead — the exact failure this app
  /// exists to catch — and a jack that stopped reporting an hour ago says
  /// nothing about what is plugged in this minute.
  bool get _readingsAreCurrent =>
      snapshot.link != LinkKind.offline && freshness.showsDerived;

  /// Nothing is plugged in and nothing is being watched.
  ///
  /// §17.5 licenses this one explicitly: *"the empty reader may carry a warm
  /// illustrated empty state rather than a grey glyph."* This is the screen a
  /// new owner sees first, and an `info`-grey slab with a sensor icon was a
  /// correct sentence delivered by a lab instrument. The cluster is `Meater-1`'s
  /// pattern — big saturated category circles — and it is safe here for exactly
  /// the reason §17.5 gives: there is no temperature on this screen to misstate.
  ///
  /// The words do not change. They were written against §16.4 — what happened,
  /// then what it means, then the reassurance that matters most — and warmth is
  /// not a licence to rewrite reviewed copy.
  ///
  /// With a cook running it falls back to the disciplined notice: a plan on
  /// screen means the app is watching, and the register goes with it.
  Widget _noProbes(BuildContext context) {
    const title = 'No probes plugged in';
    const message =
        'Plug a probe into the base station and it will appear here. The '
        'bridge keeps recording either way.';
    if (!_warm) {
      return const _Notice(
        icon: Icons.sensors_rounded,
        title: title,
        message: message,
      );
    }
    return const _WarmEmpty(title: title, message: message);
  }

  // ── bodies ──────────────────────────────────────────────────────────

  /// Four equal rows in jack order, in the deepest surface the app has.
  Widget _instrumentBody(BuildContext context) {
    final t = context.tokens;
    return SmokeCard(
      key: const ValueKey('instrument'),
      inset: true,
      padding: const EdgeInsets.symmetric(horizontal: SmokeTokens.s3),
      child: Column(
        children: [
          for (var i = 0; i < snapshot.probes.length; i++) ...[
            if (i > 0) Divider(height: 1, color: t.hairline),
            ProbeStripRow(
              view: snapshot.probes[i],
              freshness: freshness,
              glyph: _glyphFor(snapshot.probes[i]),
              vivid: _warm,
              celsius: celsius,
              onTap: () => onProbeTap?.call(snapshot.probes[i].probe),
            ),
          ],
        ],
      ),
    );
  }

  Widget _guidedBody(BuildContext context) {
    final pit = snapshot.headlinePit;
    final food = snapshot.headlineFood;
    final secondary = snapshot.secondary;
    return Column(
      key: const ValueKey('guided'),
      children: [
        if (pit != null)
          ProbeHeroCard(
            view: pit,
            phase: _phaseFor(pit),
            onPulled: onPulled,
            plan: plan,
            freshness: freshness,
            glyph: _glyphFor(pit),
            celsius: celsius,
            onTap: () => onProbeTap?.call(pit.probe),
          ),
        if (pit != null && food != null) const SizedBox(height: SmokeTokens.s3),
        if (food != null)
          ProbeHeroCard(
            view: food,
            phase: _phaseFor(food),
            onPulled: onPulled,
            plan: plan,
            freshness: freshness,
            glyph: _glyphFor(food),
            celsius: celsius,
            onTap: () => onProbeTap?.call(food.probe),
          ),
        if (secondary.isNotEmpty) ...[
          const SizedBox(height: SmokeTokens.s3),
          _compactGrid(secondary),
        ],
      ],
    );
  }

  Widget _compactGrid(List<ProbeView> probes) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < probes.length; i++) ...[
        if (i > 0) const SizedBox(width: SmokeTokens.s3),
        Expanded(
          child: ProbeCompactCard(
            view: probes[i],
            freshness: freshness,
            glyph: _glyphFor(probes[i]),
            celsius: celsius,
            onTap: () => onProbeTap?.call(probes[i].probe),
          ),
        ),
      ],
      // Pad an odd count so a single secondary probe does not stretch full
      // width and read as a hero.
      if (probes.length.isOdd) const Expanded(child: SizedBox()),
    ],
  );
}

/// The warm empty reader (17 §17.5).
///
/// Five saturated category circles over the same two sentences the grey notice
/// carried. It answers the one criticism the teardown could not answer with
/// spacing or copy — *"looking nothing like the 3 big apps"* — on the screen
/// where a new owner forms their whole impression, and it does it without
/// touching a single rule, because **there is no temperature on this screen**.
///
/// Five, and these five: the beef/pork/poultry/fish spread is what a protein
/// picker looks like everywhere, and ribs is the fifth because this is a
/// barbecue product rather than a sous-vide one. They are pure decoration in
/// the strict sense — no probe wears these — which is precisely why they are
/// legal: decoration cannot lie about a reading.
class _WarmEmpty extends StatelessWidget {
  const _WarmEmpty({required this.title, required this.message});

  final String title;
  final String message;

  static const List<FoodGlyph> _cluster = [
    FoodGlyph.beef,
    FoodGlyph.pork,
    FoodGlyph.poultry,
    FoodGlyph.fish,
    FoodGlyph.ribs,
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SmokeCard(
      key: const Key('reader-warm-empty'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A Wrap, not a Row: at 200 % text scale on a 360 dp phone five 44 dp
          // discs plus their gaps still fit, but a future sixth would not, and
          // reflowing beats clipping the illustration.
          Wrap(
            spacing: SmokeTokens.s2,
            runSpacing: SmokeTokens.s2,
            children: [
              for (final g in _cluster)
                FoodAvatar(glyph: g, size: 44, vivid: true),
            ],
          ),
          const SizedBox(height: SmokeTokens.s4),
          Text(title, style: SmokeType.displayS.copyWith(color: t.textHi)),
          const SizedBox(height: SmokeTokens.s1),
          Text(message, style: SmokeType.bodySm.copyWith(color: t.textBody)),
        ],
      ),
    );
  }
}

/// A titled advisory in `info` chrome — [CapabilityNotice] with room for the
/// two-part copy §16.4 asks for: what happened, then what it means.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const role = StatusRole.info;
    return Container(
      padding: const EdgeInsets.all(SmokeTokens.s3),
      decoration: BoxDecoration(
        color: StatusPalette.fill(role),
        borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
        border: Border.all(color: StatusPalette.border(role)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: StatusPalette.hue(role)),
          const SizedBox(width: SmokeTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The hue is the icon and the border; the words are ink.
                Text(title, style: SmokeType.title.copyWith(color: t.textHi)),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: SmokeType.bodySm.copyWith(color: t.textBody),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
