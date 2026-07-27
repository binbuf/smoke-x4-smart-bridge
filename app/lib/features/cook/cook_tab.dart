/// Branch 0 — the Cook tab (design 13 §13.3.1, §13.5.2).
///
/// Promoted out of `AppShell._cookTab` when the router became a
/// `StatefulShellRoute`: the branch builder constructs this, and it reads the
/// one live session from [ShellScope] rather than being handed it.
///
/// **The plan is no longer a widget field.** It used to be `CookPlan? _plan` on
/// the shell's State, which meant a guided cook existed only for as long as
/// that State did — an OS kill at hour nine of an eighteen-hour brisket
/// silently dropped the user back to instrument mode with the targets, gauges
/// and cook name gone, and nothing on screen to say it had happened. It now
/// lives on [ShellSession], which persists it. This widget only asks.
///
/// **Ending a cook is confirmed.** `Stop` used to be `setState(() => _plan =
/// null)`: one unlabelled tap, no confirm, no undo — in an app that makes you
/// read a two-column ledger before *restarting the bridge*. It is now
/// `End cook` behind the same [showCostSheet], with the honest ledger — the
/// bridge never stopped recording, so what you lose is the targets and the
/// name, and that is exactly what the sheet says.
///
/// **Adaptive.** Compact stacks readouts over the chart, as before. From
/// medium up it is a supporting-pane layout: readouts in a capped column on
/// the left, chart filling the rest — because on this product extra width
/// should buy a bigger chart, never a stretched temperature (§13.3, tokens
/// `SmokeWindow.readableMax`).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/connection.dart';
import '../../design/design.dart';
import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';
import '../../ui/ui.dart';
import '../chart/chart_viewport.dart';
import '../chart/cook_chart.dart';
import '../dashboard/dashboard_snapshot.dart';
import '../shell/shell_scope.dart';
import '../shell/shell_session.dart';
import 'cook_setup_sheet.dart';
import 'cook_view.dart';

class CookTab extends StatefulWidget {
  const CookTab({super.key});

  @override
  State<CookTab> createState() => _CookTabState();
}

class _CookTabState extends State<CookTab> {
  ChartViewport? _viewport;

  /// Initialise, then keep extending, the chart viewport as samples arrive.
  ChartViewport? _viewportFor(DashboardSnapshot? s, [ChartViewport? current]) {
    if (s == null) {
      return current;
    }
    final toT = s.samples.isEmpty ? 60 : s.samples.last.t;
    if (current == null) {
      return ChartViewport.forSession(
        fromT: s.samples.isEmpty ? 0 : s.samples.first.t,
        toT: toT,
      );
    }
    return current.extendTo(toT);
  }

  Future<void> _setupCook(ShellSession session) async {
    final plan = await showCookSetupSheet(context, celsius: session.celsius);
    if (plan != null) {
      plan.startedUnixMs = DateTime.now().millisecondsSinceEpoch;
      await session.setPlan(plan);
    }
  }

  /// §13.5.6's cost sheet, applied to the one action that could lose fourteen
  /// hours of setup. The `keeps` line is the load-bearing half: users end a
  /// cook expecting recording to stop, and it does not.
  Future<void> _endCook(ShellSession session) async {
    final ok = await showCostSheet(
      context,
      title: 'End this cook?',
      body:
          'The readings keep going either way — the bridge records whether or '
          'not a cook is set up. This puts the app back to live readings.',
      keeps: 'Every reading, and this cook in your history.',
      loses: 'Your targets, the doneness gauges and the cook’s name.',
      confirmLabel: 'End cook',
      cancelLabel: 'Keep cooking',
    );
    if (ok) {
      await session.setPlan(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ShellScope.maybeOf(context);
    if (session == null) {
      // Mounted outside a shell (a bare test, a stale deep link). There is no
      // session to render, and inventing one would dial a radio from a widget.
      return const EmptyState(
        icon: Icons.local_fire_department_outlined,
        title: 'No live session',
        message: 'Open the app from its home screen to see live readings.',
      );
    }

    final snapshot = session.snapshot;
    _viewport = _viewportFor(snapshot, _viewport);

    if (snapshot == null) {
      return SafeArea(
        bottom: false,
        child: switch (session.launch) {
          LaunchOffline() => _pullable(
            session,
            const EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Can’t reach your bridge',
              message:
                  'Saved cooks are still here. Pull down to try again — the '
                  'app also reconnects on its own when the bridge is back.',
            ),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      );
    }

    final window = context.window;
    final probeConfig = [
      for (final p in snapshot.probes)
        Probe(n: p.probe, name: p.name, role: p.role, targetF10: p.targetF10),
    ];
    final viewport = _viewport;
    final showChart = snapshot.samples.isNotEmpty && viewport != null;

    final readouts = CookView(
      snapshot: snapshot,
      plan: session.plan,
      freshness: session.freshness,
      celsius: session.celsius,
      paired: snapshot.paired,
      // The shell owns the transport chip and the alarm bar for every tab
      // now, so this one must not draw its own — two chips that move when you
      // change tabs was the polish tell (§13.5.7).
      showChrome: false,
      onSetupCook: () => unawaited(_setupCook(session)),
      onStop: session.plan == null ? null : () => unawaited(_endCook(session)),
      onAck: (alarm) => unawaited(session.ackAlarm(alarm.id)),
      onRefresh: session.refresh,
    );

    // A **builder**, not a widget, and the `SizedBox` lands *inside* the card.
    //
    // [SmokeCard] wraps its child in a `mainAxisSize: min` Column, which hands
    // that child unbounded height — so `SizedBox(height: h, child: SmokeCard(…))`
    // silently un-bounds the chart again, and `CookChart`'s own `Expanded`
    // then throws "RenderFlex children have non-zero flex but incoming height
    // constraints are unbounded" and paints nothing. Found on the device: the
    // Cook body came up blank. Every caller must therefore hand the chart a
    // height that reaches it.
    Widget chartCard(double height) => SmokeCard(
      child: SizedBox(
        height: height,
        child: CookChart(
          model: buildChartSeries(
            snapshot.samples,
            fromT: viewport!.minX,
            toT: viewport.maxX,
          ),
          viewport: viewport,
          probes: probeConfig,
          marks: snapshot.marks,
          startedUnixMs: snapshot.startedUnixMs,
          celsius: session.celsius,
          onViewport: (v) => setState(() => _viewport = v),
          fullHistory: snapshot.fullHistory,
        ),
      ),
    );

    return SafeArea(
      bottom: false,
      child: window.usesSupportingPane
          ? _wide(window, readouts, chartCard, hasChart: showChart)
          : _tall(window, readouts, chartCard, hasChart: showChart),
    );
  }

  /// The vertical space [SmokeCard] spends on its own padding, which a caller
  /// sizing the chart inside one has to subtract.
  static const double _cardPadding = SmokeTokens.s4 * 2;

  /// Compact, and the closed Fold: readouts scroll, the chart is pinned under
  /// them at a height proportional to the window rather than a fixed 240 px.
  Widget _tall(
    SmokeWindow window,
    Widget readouts,
    Widget Function(double height) chartCard, {
    required bool hasChart,
  }) {
    // Tabletop posture — the device standing half-open on a counter, which is
    // this product's best physical posture. The chart takes the upper screen
    // and the readouts the lower one, so it becomes a purpose-built pit
    // monitor with no stand.
    if (window.isTabletop && hasChart) {
      final split = window.hinge?.top ?? window.height / 2;
      // The card sits inside `split`, so the chart gets what is left after the
      // outer padding and the card's own.
      final inner = (split - SmokeTokens.s4 * 2 - _cardPadding).clamp(
        120.0,
        double.infinity,
      );
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(SmokeTokens.s4),
            child: chartCard(inner),
          ),
          SizedBox(height: window.hingeGap),
          Expanded(child: readouts),
        ],
      );
    }
    // 28%, not a third: the readouts above are the primary content, and on a
    // phone the chart has to leave room for the header plus a couple of probe
    // rows or the list clips mid-row with nothing to say it scrolls. The old
    // fixed 240 was about right on a 900 dp-tall phone; this tracks the window
    // instead of assuming one.
    final chartHeight = (window.height * 0.28).clamp(200.0, 300.0);
    return Column(
      children: [
        Expanded(child: readouts),
        if (hasChart)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SmokeTokens.s4,
              0,
              SmokeTokens.s4,
              SmokeTokens.s4,
            ),
            child: chartCard(chartHeight - _cardPadding),
          ),
      ],
    );
  }

  /// Medium and expanded: a supporting pane. The readout column is capped at
  /// [SmokeWindow.readableMax] — a 90 dp temperature stretched across 900 dp
  /// reads as a broken layout, not a big number — and every remaining dp goes
  /// to the chart, which can genuinely use it.
  Widget _wide(
    SmokeWindow window,
    Widget readouts,
    Widget Function(double height) chartCard, {
    required bool hasChart,
  }) {
    if (!hasChart) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: SmokeWindow.readableMax),
          child: readouts,
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The readouts take a **share**, capped — not the cap itself.
        //
        // First cut handed them `readableMax` (480 dp) outright, which on the
        // Fold's ~870 dp inner display left the chart *narrower than the
        // readouts*: the exact inversion of this layout's premise, and it
        // looked it — a squeezed time axis and a capability notice wrapped
        // over five lines. Flex, not a measured width: a `LayoutBuilder` here
        // would read `maxWidth: infinity`, because a `Row` hands unbounded
        // main-axis constraints to its non-flex children, and the clamp would
        // quietly land back on the cap.
        Flexible(
          flex: 38,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: SmokeWindow.readableMax,
              ),
              child: readouts,
            ),
          ),
        ),
        SizedBox(width: window.hingeIsVertical ? window.hingeGap : 0),
        Expanded(
          flex: 62,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              0,
              SmokeTokens.s4,
              SmokeTokens.s4,
              SmokeTokens.s4,
            ),
            // The chart fills the pane here — which is the whole point of the
            // supporting-pane layout — so its height comes from the measured
            // space rather than a fraction of the window.
            child: LayoutBuilder(
              builder: (context, constraints) => chartCard(
                (constraints.maxHeight - _cardPadding).clamp(
                  120.0,
                  double.infinity,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Makes a screen-sized, non-scrolling branch pullable. An empty state is
  /// exactly where "try the bridge again, now" matters most, and a widget that
  /// does not scroll cannot be pulled.
  Widget _pullable(ShellSession session, Widget child) => RefreshIndicator(
    onRefresh: session.refresh,
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    ),
  );
}
