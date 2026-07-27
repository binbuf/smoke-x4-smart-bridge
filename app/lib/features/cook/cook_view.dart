/// A22.2 — the Cook view (design 13 §13.3.1).
///
/// One scaffold, two modes, switched by a single nullable — the [CookPlan].
/// With no plan the screen is an **instrument**: four equal probe rows in jack
/// order, each wearing a sparkline, and the whole thing works with no cook
/// started (the owner's requirement — "see temps without starting a cook").
/// With a plan it is a **guided cook**: the pit and the primary food become
/// hero cards wearing target gauges, the rest go compact, and the header turns
/// ember.
///
/// The switch is animated, not a rebuild: confirming a cook visibly *installs*
/// its targets as the gauges sweep in (§13.3.1). Instrument mode is never
/// called "raw" in the UI.
///
/// This widget renders a [DashboardSnapshot] (the existing pure projection) plus
/// an optional plan. It holds no state and reaches no provider — the shell (a
/// later wave) feeds it and wires the callbacks.
///
/// A22.7 wires it toward MVP (13 §13.5.2, §13.5.7): the highest-severity unacked
/// alarm rides an [AlarmBar] at the top, a [TransportChip] admits the lane, a
/// [StaleVeil] makes a stale reading *look* stale, and the degraded/empty
/// branches render the correct advice instead of leaving inert controls or the
/// wrong "plug a probe" copy on screen. Every new control here is optional and
/// absent when its callback is null — no dead buttons.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/entities/entities.dart';
import '../../domain/plan/plan.dart';
import '../../ui/ui.dart';
import '../dashboard/dashboard_snapshot.dart';

class CookView extends StatelessWidget {
  const CookView({
    super.key,
    required this.snapshot,
    required this.plan,
    required this.freshness,
    this.celsius = false,
    this.paired = true,
    this.onSetupCook,
    this.onStop,
    this.onAddMark,
    this.onTestAlarm,
    this.onExport,
    this.onProbeTap,
    this.onAck,
    this.onPair,
  });

  final DashboardSnapshot snapshot;

  /// Null → instrument mode. Non-null → guided mode.
  final CookPlan? plan;
  final ProbeFreshness freshness;
  final bool celsius;

  /// The bridge is linked to a Smoke X base station. False drives the
  /// `unpaired` state (13 §13.5.2) — whose copy is *not* "plug a probe".
  final bool paired;

  final VoidCallback? onSetupCook;
  final VoidCallback? onStop;
  final VoidCallback? onAddMark;
  final VoidCallback? onTestAlarm;
  final VoidCallback? onExport;
  final void Function(int jack)? onProbeTap;

  /// Acknowledge the ringing alarm. Given the [Alarm] so the caller can ack the
  /// exact id — the view picks which alarm is loudest, the caller silences it.
  final void Function(Alarm alarm)? onAck;

  /// Start pairing the base station, from the `unpaired` empty state. Absent
  /// (no button) when there is no pairing flow to run.
  final VoidCallback? onPair;

  bool get _guided => plan != null;

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
  /// link or a stale stream stops it (the chip's staleness signal).
  bool get _linkLive =>
      snapshot.link != LinkKind.offline &&
      (freshness == ProbeFreshness.live || freshness == ProbeFreshness.aging);

  @override
  Widget build(BuildContext context) {
    final motion = SmokeMotion.of(context);
    return ListView(
      padding: const EdgeInsets.all(SmokeTokens.s4),
      children: [_topChrome(context), _content(context, motion)],
    );
  }

  // ── chrome ──────────────────────────────────────────────────────────

  /// Transport chip, the alarm strip, and — on BLE — the capability notice.
  /// Mounted on every branch: an alarm can ring with no probes plugged in.
  Widget _topChrome(BuildContext context) {
    final alarm = _topAlarm;
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
          onAck: (onAck == null || alarm == null) ? null : () => onAck!(alarm),
        ),
        if (snapshot.link == LinkKind.ble)
          const Padding(
            padding: EdgeInsets.only(top: SmokeTokens.s3),
            child: CapabilityNotice(
              message: 'On Bluetooth — live readings only.',
              icon: Icons.bluetooth_rounded,
            ),
          ),
        const SizedBox(height: SmokeTokens.s4),
      ],
    );
  }

  // ── content ─────────────────────────────────────────────────────────

  Widget _content(BuildContext context, SmokeMotionValues motion) {
    // The base station was never linked: "plug a probe" is the wrong advice
    // here (13 §13.5.2), so this branch owns the body entirely.
    if (!paired) {
      return _unpaired(context);
    }
    // Paired, but nothing is plugged in — today's correct "no probes" copy.
    if (!snapshot.anyAttached) {
      return _noProbes(context);
    }
    return Column(
      children: [
        AnimatedSwitcher(
          duration: motion.standard,
          child: _guided ? _cookHeader(context) : _bridgeHeader(context),
        ),
        const SizedBox(height: SmokeTokens.s4),
        _veiled(
          AnimatedSize(
            duration: motion.standard,
            curve: motion.curve,
            alignment: Alignment.topCenter,
            child: _guided ? _guidedBody(context) : _instrumentBody(context),
          ),
        ),
        if (_actions.isNotEmpty) ...[
          const SizedBox(height: SmokeTokens.s4),
          ActionRow(items: _actions),
        ],
      ],
    );
  }

  /// The three secondary actions, each present only when it does something —
  /// a null callback drops the tile rather than parking a dead button.
  List<ActionRowItem> get _actions => [
    if (onAddMark != null)
      ActionRowItem(
        icon: Icons.bookmark_add_outlined,
        label: 'Mark',
        onTap: onAddMark,
      ),
    if (onTestAlarm != null)
      ActionRowItem(
        icon: Icons.notifications_active_outlined,
        label: 'Test alarm',
        onTap: onTestAlarm,
      ),
    if (onExport != null)
      ActionRowItem(
        icon: Icons.ios_share_rounded,
        label: 'Export',
        onTap: onExport,
      ),
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
    final sAgo = snapshot.lastPacketSAgo;
    if (sAgo == null) {
      return frozen ? 'No recent readings.' : 'Reading age unknown.';
    }
    final age = formatDuration(sAgo);
    return frozen ? 'No readings for $age.' : 'Readings are $age old.';
  }

  Widget _unpaired(BuildContext context) => EmptyState(
    icon: Icons.link_off_rounded,
    title: 'No base station yet',
    message: 'This bridge hasn’t met your Smoke X yet.',
    action: onPair == null
        ? null
        : FilledButton.tonalIcon(
            onPressed: onPair,
            icon: const Icon(Icons.add_link_rounded, size: 18),
            label: const Text('Pair the base station'),
          ),
  );

  Widget _noProbes(BuildContext context) => const EmptyState(
    icon: Icons.sensors_rounded,
    title: 'No probes plugged in',
    message: 'Plug a probe into the base station and it will appear here.',
  );

  // ── headers ─────────────────────────────────────────────────────────

  Widget _bridgeHeader(BuildContext context) {
    final t = context.tokens;
    return SmokeCard(
      key: const ValueKey('bridge-header'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Instrument mode is never named after a cook — there is no
                // cook. It is always "Live readings".
                Text(
                  'Live readings',
                  style: SmokeType.displayS.copyWith(color: t.textHi),
                ),
                const SizedBox(height: 2),
                Text(
                  'Nothing is being cooked yet — the bridge is logging anyway',
                  style: SmokeType.bodySm.copyWith(color: t.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: SmokeTokens.s3),
          FilledButton.tonalIcon(
            onPressed: onSetupCook,
            icon: const Icon(Icons.bolt_rounded, size: 18),
            label: const Text('Set up a cook'),
          ),
        ],
      ),
    );
  }

  Widget _cookHeader(BuildContext context) {
    final t = context.tokens;
    return SmokeCard(
      key: const ValueKey('cook-header'),
      accent: StatusPalette.pit,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan!.title,
                  style: SmokeType.displayS.copyWith(color: t.textHi),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      formatElapsed(snapshot.elapsedS),
                      style: SmokeType.monoBig.copyWith(
                        color: StatusPalette.pit,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onStop,
            style: OutlinedButton.styleFrom(foregroundColor: t.textHi),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }

  // ── bodies ──────────────────────────────────────────────────────────

  Widget _instrumentBody(BuildContext context) {
    final t = context.tokens;
    return Column(
      key: const ValueKey('instrument'),
      children: [
        SmokeCard(
          padding: const EdgeInsets.symmetric(vertical: SmokeTokens.s1),
          child: Column(
            children: [
              for (var i = 0; i < snapshot.probes.length; i++) ...[
                if (i > 0) Divider(height: 1, color: t.hairline),
                ProbeStripRow(
                  view: snapshot.probes[i],
                  celsius: celsius,
                  onTap: () => onProbeTap?.call(snapshot.probes[i].probe),
                ),
              ],
            ],
          ),
        ),
      ],
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
            plan: plan,
            freshness: freshness,
            celsius: celsius,
            onTap: () => onProbeTap?.call(pit.probe),
          ),
        if (pit != null && food != null) const SizedBox(height: SmokeTokens.s3),
        if (food != null)
          ProbeHeroCard(
            view: food,
            plan: plan,
            freshness: freshness,
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

  Widget _compactGrid(List<ProbeView> probes) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < probes.length; i++) ...[
          if (i > 0) const SizedBox(width: SmokeTokens.s3),
          Expanded(
            child: ProbeCompactCard(
              view: probes[i],
              freshness: freshness,
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
}
