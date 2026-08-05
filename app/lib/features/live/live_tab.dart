/// Branch 1 — **the reader** (newapp §B.2, §C.1; design 13 §13.3.1, §13.5.2).
///
/// The landing screen, and the one the product sentence is about: *"first and
/// foremost a quick temperature reader for probes plus the synced history."*
/// It was `/cook` — named after the modal it used to be — and the rename to
/// `/live` is not cosmetic. This screen is **not** a cook. A cook is an
/// annotation you may attach to the recording that is happening anyway (§D.1),
/// and calling the live screen "Cook" is what made "End cook" read as "stop
/// recording" to every user who tried it.
///
/// **The dead controls are wired.** [CookView] has taken `onAddMark`,
/// `onTestAlarm`, `onExport` and `onProbeTap` since A22.7 and no caller passed
/// one, so the action row rendered empty and the probe rows kept a ripple and a
/// chevron that did nothing — a tappable-looking row that does not respond is
/// worse than a row that does not look tappable. All four now go somewhere:
/// Mark writes to the device, Export writes a CSV and hands it to the share
/// sheet, Test alarm posts on the real critical channel, and the chevron pushes
/// `/live/probe/:jack` inside this branch.
///
/// **The plan is not a widget field**, and never was after §13.3.1: it lives on
/// [ShellSession], which persists it, so an OS kill at hour nine of an
/// eighteen-hour brisket comes back to the same gauges. What is new is that it
/// is also an annotation row in drift — the prefs copy is a first-frame cache,
/// and `CookRepository` owns the history.
///
/// **Adaptive.** Compact stacks readouts over the chart. From medium up it is a
/// supporting-pane layout: readouts in a capped column, chart filling the rest,
/// because on this product extra width buys a bigger chart and never a
/// stretched temperature (§13.3, `SmokeWindow.readableMax`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/connection.dart';
import '../../app/router.dart';
import '../../data/transport/bridge_transport.dart' show ControlCommand;
import '../../design/design.dart';
import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';
import '../../ui/ui.dart';
import '../alarms/delivery_banner.dart';
import '../chart/chart_viewport.dart';
import '../chart/cook_chart.dart';
import '../cook/cook_setup_sheet.dart';
import '../cook/cook_view.dart';
import '../cook/mark_sheet.dart';
import '../cooks/cook_actions.dart';
import '../dashboard/dashboard_snapshot.dart';
import '../shell/shell_scope.dart';
import '../shell/shell_session.dart';

class LiveTab extends StatefulWidget {
  const LiveTab({super.key});

  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> {
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
    final snapshot = session.snapshot;
    final plan = await showCookSetupSheet(
      context,
      celsius: session.celsius,
      // Editing a running cook is now allowed (§D.4), and the sheet needs the
      // current one to open on it rather than on a blank form.
      initial: session.plan,
      probeNames: {
        for (final p in snapshot?.probes ?? const <ProbeView>[])
          p.probe: p.name,
      },
    );
    if (plan != null) {
      await session.startCook(plan);
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
      keeps:
          'Every reading, and this cook in your history — you can reopen it, '
          'rename it or move its start time later.',
      loses: 'The gauges and the guided progression on this screen.',
      confirmLabel: 'End cook',
      cancelLabel: 'Keep cooking',
    );
    if (ok) {
      await session.endCook();
    }
  }

  /// §C.1 — **Mark**. The button existed and wrote nothing; the only code that
  /// had ever sent `ControlCommand.mark` sat on an unrouted pre-shell screen.
  Future<void> _addMark(ShellSession session) async {
    final kind = await showMarkSheet(context);
    if (kind == null || !mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await session.control(
        ControlCommand.mark(kind: kind, text: markLabel(kind)),
      );
      messenger?.showSnackBar(
        SnackBar(content: Text('${markLabel(kind)} — marked on the recording')),
      );
    } on Object {
      // A mark that did not land must say so: a silent failure here means the
      // chart is missing an event the user believes is on it.
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Couldn’t reach the bridge — nothing was marked.'),
        ),
      );
    }
  }

  /// §D.5 — cached from the running annotation so the phase row does not
  /// await a database read on every frame.
  int? _pulledAtUnixMs;

  Future<void> _markPulled(ShellSession session) async {
    await session.markPulled();
    final cook = await session.runningCook();
    if (mounted) {
      setState(() => _pulledAtUnixMs = cook?.pulledAtUnixMs);
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
      // §C.1 — the four controls that used to render and do nothing.
      onAddMark: () => unawaited(_addMark(session)),
      onTestAlarm: () => unawaited(sendTestAlarm(context)),
      onExport: () => unawaited(exportRunningCook(context, session)),
      // The chevron was drawn unconditionally; now it goes somewhere. Pushed
      // **inside this branch**, so the nav bar stays and back means back.
      onProbeTap: (jack) => context.push(AppRoutes.probeDetail(jack)),
      // §D.5 — the guided progression. The pull time is a fact the user
      // supplies and the app never guesses at.
      nowUnixMs: DateTime.now().millisecondsSinceEpoch,
      pulledAtUnixMs: _pulledAtUnixMs,
      onPulled: session.plan == null
          ? null
          : () => unawaited(_markPulled(session)),
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
      child: Column(
        children: [
          // §B.2 — the `/alerts` verdict, folded. A permissions verdict is not a
          // place you live; it is a thing you need told *here*, where the
          // temperatures are, and only while it is true.
          const DeliveryBanner(),
          Expanded(
            child: window.usesSupportingPane
                ? _wide(window, readouts, chartCard, hasChart: showChart)
                : _tall(window, readouts, chartCard, hasChart: showChart),
          ),
        ],
      ),
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
