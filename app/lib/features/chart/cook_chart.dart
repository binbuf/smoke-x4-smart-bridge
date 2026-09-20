/// A10.3 / A10.5 — the chart (design 08 §8.7), enriched per 17 §17.3 D.
///
/// `fl_chart`'s `LineChart`, with **all the work already done before it
/// ever sees the data** — A10.1 built the runs, the gaps and the
/// envelope; A10.2 chose and validated the colours; A10.4 owns the
/// viewport. This file is the thin part: turn a [ChartSeriesModel] into
/// bars and overlays, and put a finger on it.
///
/// Three things here are load-bearing rather than cosmetic:
///
///  * **Runs become separate `LineChartBarData` segments.** A 30-minute
///    dropout must look like a 30-minute dropout, not like a straight line
///    pretending everything was fine. The area fill added below is drawn
///    **per run** for the same reason: a filled slab bridging a dropout would
///    undo the split it sits under.
///  * **Detached probes contribute no spots.** By construction — A10.1
///    never emits one — but the type here cannot express a zero either.
///  * **The capability notice, not an error.** A transport whose
///    `fullHistory` is false shows its 2-hour preview and says
///    _"connected over Bluetooth — full history needs Wi-Fi"_. A3.1 built
///    that flag for this exact moment, three milestones ago.
///
/// ## What §17.3 D added, and what it is answering
///
/// The teardown in 17 §17.1 is blunt about this file: *"Ours draws lines on a
/// grid."* Four things came back from `FireBoard-1` and `TemProBBQ-3`:
///
///  1. **an area fill under each series**, at [SeriesFill.area] and through
///     [ProbePalette.tint] and nothing else — §17.2's second sanctioned
///     extension of the series channel;
///  2. **a legend**, under the chart. `SeriesLegend` had existed, documented
///     and tested, with zero call sites since A19; this is where it is spent;
///  3. **target lines labelled with their value, on the line.** A target line
///     you cannot read the value of is decoration;
///  4. **a channel-dot selector**, above the chart, to isolate one series.
///
/// ## And the migration that came with them
///
/// This was the last file in the app not on the design system: ten
/// `Theme.of(context)` reach-arounds, its own warm-grey chart ink, raw
/// `ChoiceChip`/`ActionChip`, and `BorderRadius.circular(10)` — a radius the
/// token set does not contain. It is the single biggest reason the chart read
/// as a different app from every screen around it. `Theme.of` now appears
/// nowhere in this file; ink comes from `context.tokens`, type from
/// [SmokeType], geometry from `SmokeTokens.radius*`, motion from [SmokeMotion]
/// — which is also how the chart finally honours reduced motion and the
/// daylight profile, neither of which used to reach it.
///
/// **No status hue enters a series.** There is not one `StatusPalette`
/// reference in this file and every stroke, band, fill and mark resolves
/// through [ProbePalette]. That is a property, not an accident; `chart_test`
/// asserts it so a future edit has to argue with a red test.
///
/// ## Where the discipline relaxes, and why that is not a loophole
///
/// §17.5 makes the colour rule proportional: it exists to stop colour *lying
/// about how the cook is going*, and that failure **needs live state to fail
/// about**. Two surfaces here have none, and both are bold on purpose:
///
///  * [_EmptyChart] — no series, no reading, no claim. It gets a filled ember
///    medallion and a sentence instead of the grey line it used to be.
///  * [_ChannelDots] — a control that says *which probe*, which is identity
///    rather than state, and §17.2 already sanctions a badge filled with a
///    probe's own hue for exactly that reason.
///
/// Everything with data behind it — every stroke, fill, band and target rule —
/// stays under strict §16.5, because that is where the rule earns its keep.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';
import '../../ui/ui.dart';
import 'chart_viewport.dart';

/// Below this the plot has stopped being a plot, and chrome that squeezes it
/// under the floor is chrome that cost more than it bought.
///
/// The chart is handed anything from 120 dp (a half-open Fold's chart pane,
/// `live_tab.dart`) to a full supporting pane, and the height it gets is a
/// caller's decision this widget cannot see. So the legend and the selector are
/// **budgeted rather than assumed**: measured against the space actually
/// available, dropped from the bottom of the priority list up when it runs out.
const double _plotFloorDp = 132;

/// One channel dot's tap target. Material's 48 is more than this row can
/// afford out of a 240 dp chart; 44 is the floor the rest of the app uses
/// (`series_legend.dart`) and the one iOS asks for.
const double _dotRowDp = 44;

class CookChart extends StatefulWidget {
  const CookChart({
    required this.model,
    required this.viewport,
    this.probes = const [],
    this.marks = const [],
    this.startedUnixMs,
    this.crosshairT,
    this.onCrosshair,
    this.onViewport,
    this.fullHistory = true,
    this.celsius = false,
    super.key,
  });

  final ChartSeriesModel model;
  final ChartViewport viewport;

  /// Configuration, for the target lines, the alarm band, and the roles
  /// that decide stroke weight.
  final List<Probe> probes;
  final List<Mark> marks;

  /// Null when the bridge had no clock: the axis then reads elapsed time,
  /// which is honest, instead of dates in 1970.
  final int? startedUnixMs;

  final int? crosshairT;
  final ValueChanged<int?>? onCrosshair;
  final ValueChanged<ChartViewport>? onViewport;
  final bool fullHistory;

  /// Render the temperature axis and the crosshair in °C (13 §13.3.5).
  ///
  /// **Only the labels convert.** Storage, the series model, the viewport and
  /// every threshold stay in tenths of °F (04 §4.2), so a cook recorded in °F
  /// renders in °C with no migration and no second code path through the
  /// maths. The visible consequence is that gridlines fall on round °F rather
  /// than round °C values — `225°F` labels as `107°`. That is a real cosmetic
  /// cost, and it is the right trade against converting the plotted data,
  /// which would put two units into the analysis layer.
  final bool celsius;

  /// A raw °F axis value as the label the user's unit calls it.
  static String axisTemp(double f, {required bool celsius}) =>
      '${(celsius ? f10ToC10((f * 10).round()) / 10 : f).round()}';

  @override
  State<CookChart> createState() => _CookChartState();
}

/// Stateful for exactly one reason: the isolated channel (§17.3 D's fourth
/// item) is a **view** state, not a fact about the cook.
///
/// It is deliberately not lifted to the caller. Which series you are squinting
/// at right now does not survive leaving the screen, does not belong in a
/// session, and three call sites would each have to carry a field for it —
/// `live_tab`, `sessions_screen` and `probe_detail_route` — to gain nothing.
class _CookChartState extends State<CookChart> {
  /// The isolated jack, or null for "show everything". Never trusted directly:
  /// a probe can be unplugged while it is isolated, and a chart that then
  /// dimmed all four series would look broken rather than empty. [_focusIn]
  /// resolves it against what is actually drawable, every build.
  int? _focus;

  /// [_focus], but only if that channel still has something on screen.
  int? _focusIn(List<int> channels) => channels.contains(_focus) ? _focus : null;

  void _toggle(int probe) =>
      setState(() => _focus = _focus == probe ? null : probe);

  Probe? _cfg(int n) => widget.probes.where((p) => p.n == n).firstOrNull;

  String _name(int n) {
    final p = _cfg(n);
    return (p?.name ?? '').isEmpty ? 'Probe $n' : p!.name;
  }

  ProbeStyle _styleFor(int probe) => ProbePalette.styleFor(
    probe,
    Theme.brightnessOf(context),
    role: _cfg(probe)?.role ?? ProbeRole.unused,
  );

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final motion = SmokeMotion.of(context);
    // Read eagerly: the axis label builders run during layout, and the
    // collision test below measures a label at the scale it will paint at.
    final textScaler = MediaQuery.textScalerOf(context);

    if (widget.model.isEmpty) {
      return _EmptyChart(fullHistory: widget.fullHistory);
    }

    // The channels that actually drew something. A probe that contributed no
    // points to this window is not a series, so it is neither a legend entry
    // nor a dot — there is nothing for either to key.
    final channels = [
      for (final s in widget.model.series)
        if (!s.isEmpty) s.probe,
    ];
    final focus = _focusIn(channels);

    final lo = (widget.model.minF ?? 0) - 10;
    final hi = (widget.model.maxF ?? 100) + 10;

    final bars = <LineChartBarData>[];
    for (final s in widget.model.series) {
      if (s.isEmpty) {
        continue;
      }
      final style = _styleFor(s.probe);
      // A series that is not the isolated one recedes to a mark at
      // `ProbePalette.dim` and gives up its fill. The stroke stays — isolating
      // the pit to read it against nothing is a worse chart, not a better one
      // — but emphasis is carried by *ink and area* together, which is what
      // makes the isolated series legible at a glance.
      final receding = focus != null && focus != s.probe;
      final stroke = receding ? ProbePalette.dim(style.color) : style.color;

      // The envelope goes in first so it sits behind the mean line.
      if (s.envelope.isNotEmpty) {
        bars.add(
          LineChartBarData(
            spots: [
              for (final e in s.envelope) FlSpot(e.t.toDouble(), e.max),
              for (final e in s.envelope.reversed)
                FlSpot(e.t.toDouble(), e.min),
            ],
            color: receding
                ? Colors.transparent
                : ProbePalette.tint(style.color, SeriesFill.envelope),
            barWidth: 0,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: !receding,
              color: ProbePalette.tint(style.color, SeriesFill.envelope),
            ),
          ),
        );
      }
      for (final run in s.runs) {
        bars.add(
          LineChartBarData(
            spots: [for (final p in run.points) FlSpot(p.t.toDouble(), p.f)],
            color: stroke,
            barWidth: style.strokeWidth,
            dashArray: style.dashArray,
            isStrokeCapRound: true,
            isStrokeJoinRound: true,
            dotData: const FlDotData(show: false),
            // §17.2's sanctioned area fill (`FireBoard-1`), and the whole
            // reason it is sanctioned is that it is a *tint*: 16 %, through
            // `ProbePalette.tint` and nothing else.
            //
            // **One fill per series.** Where a window is wide enough to carry
            // an envelope, the envelope already is the fill; stacking an area
            // fill under it would composite two 16 % tints into 26 % over the
            // region they share, which is over §17.2's ceiling however each
            // one was declared. So the area fill yields to the band.
            //
            // It is attached to the **run**, not to the series, so it stops
            // dead at a gap boundary exactly as the stroke does.
            belowBarData: BarAreaData(
              show: !receding && s.envelope.isEmpty,
              color: ProbePalette.tint(style.color),
            ),
          ),
        );
      }
    }

    // Overlays — §8.7's list, plus §17.3 D's labels.
    final targetLines = <HorizontalLine>[
      for (final p in widget.probes)
        if (p.targetF10 != null && channels.contains(p.n))
          _targetLine(
            p,
            t,
            // Only the isolated channel keeps its label. Four labelled rules
            // stacked near the top of a 160 dp plot is not information, and
            // isolating a channel is a request to be told about *that one*.
            labelled: focus == null || focus == p.n,
            receding: focus != null && focus != p.n,
          ),
    ];
    final markLines = <VerticalLine>[
      for (final m in widget.marks)
        if (m.t >= widget.viewport.minX && m.t <= widget.viewport.maxX)
          VerticalLine(
            x: m.t.toDouble(),
            // `chromeDim` is the token reserved for non-text rules; a mark is
            // chrome saying *something happened here*, never data.
            color: ProbePalette.gapInk(t),
            strokeWidth: 1,
            dashArray: const [2, 3],
          ),
      if (widget.crosshairT != null)
        VerticalLine(
          x: widget.crosshairT!.toDouble(),
          // The one line that is allowed to be loud: it is under the finger.
          color: t.textHi,
          strokeWidth: 1,
        ),
    ];

    // A shaded band for the pit's alarm min/max.
    final pit = widget.probes
        .where((p) => p.role == ProbeRole.pit)
        .firstOrNull;
    final band = <HorizontalRangeAnnotation>[
      if (pit?.alarmMinF10 != null && pit?.alarmMaxF10 != null)
        HorizontalRangeAnnotation(
          y1: pit!.alarmMinF10! / 10.0,
          y2: pit.alarmMaxF10! / 10.0,
          color: ProbePalette.tint(
            ProbePalette.styleFor(
              pit.n,
              Theme.brightnessOf(context),
              role: ProbeRole.pit,
            ).color,
            SeriesFill.band,
          ),
        ),
    ];

    final axisStyle = SmokeType.labelSm.copyWith(color: ProbePalette.axisInk(t));

    final chart = LineChart(
      LineChartData(
        minX: widget.viewport.minX.toDouble(),
        maxX: widget.viewport.maxX.toDouble(),
        minY: lo,
        maxY: hi,
        clipData: const FlClipData.all(),
        lineBarsData: bars,
        rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: band),
        extraLinesData: ExtraLinesData(
          horizontalLines: targetLines,
          verticalLines: markLines,
        ),
        // Built-in touches are off: A10.4 owns the gestures, and two
        // things fighting over a drag is how a chart becomes unusable.
        lineTouchData: const LineTouchData(enabled: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: ProbePalette.grid(t), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) {
                String fmt(double x) =>
                    CookChart.axisTemp(x, celsius: widget.celsius);
                if (!showAxisLabel(
                  v,
                  meta,
                  measure: (x) => measureAxisLabel(fmt(x), axisStyle, textScaler),
                )) {
                  return const SizedBox.shrink();
                }
                return Text(fmt(v), style: axisStyle);
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: _axisInterval(widget.viewport.spanS),
              getTitlesWidget: (v, meta) {
                String fmt(double x) =>
                    formatAxisTime(x.round(), widget.startedUnixMs);
                if (!showAxisLabel(
                  v,
                  meta,
                  measure: (x) => measureAxisLabel(fmt(x), axisStyle, textScaler),
                )) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(fmt(v), style: axisStyle),
                );
              },
            ),
          ),
        ),
      ),
      // fl_chart tweens between two `LineChartData`s over a hard-coded 150 ms
      // by default. Isolating a channel repaints every bar, so that default was
      // an animation the "reduce motion" setting could not reach.
      duration: motion.quick,
      curve: motion.curve,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final budget = _ChromeBudget.measure(
          height: constraints.maxHeight,
          width: constraints.maxWidth,
          names: [for (final p in channels) _name(p)],
          fullHistory: widget.fullHistory,
          textScaler: textScaler,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.fullHistory) ...[
              const CapabilityNotice(
                key: Key('chart-capability-notice'),
                icon: Icons.bluetooth_rounded,
                message:
                    'Connected over Bluetooth — full history needs Wi-Fi. '
                    'Showing the last 2 hours.',
              ),
              const SizedBox(height: SmokeTokens.s2),
            ],
            if (budget.dots && channels.length >= 2) ...[
              _ChannelDots(
                styles: [for (final p in channels) _styleFor(p)],
                names: [for (final p in channels) _name(p)],
                focus: focus,
                onTap: _toggle,
              ),
              const SizedBox(height: SmokeTokens.s2),
            ],
            Expanded(
              child: _ChartGestures(
                viewport: widget.viewport,
                onViewport: widget.onViewport,
                onCrosshair: widget.onCrosshair,
                child: chart,
              ),
            ),
            if (budget.legend) ...[
              const SizedBox(height: SmokeTokens.s2),
              SeriesLegend(
                key: const Key('chart-legend'),
                // A **readout**, not a second control: the dots above already
                // isolate a channel, and two affordances for one action is how
                // a user learns that neither is quite the real one. The legend
                // answers "which line is which"; the dots answer "show me only
                // this one". `SeriesLegend` says as much itself — a null
                // `onTap` "leaves the legend a readout, and then it is not a
                // control, so it does not pretend to be one".
                entries: [
                  for (final p in channels)
                    SeriesLegendEntry(
                      name: _name(p),
                      style: _styleFor(p),
                      dimmed: focus != null && focus != p,
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  /// A target line, labelled with its value **on the line** (`TemProBBQ-3`).
  ///
  /// Two deliberate departures from that reference:
  ///
  ///  * **the label is ink, never the series hue.** TempPro prints `150°F` in
  ///    its line's blue; §16.5 says a series hue "never carries a word", and
  ///    §17.4 rejects MEATER's coloured readouts for exactly this — a hue that
  ///    carries a number is a hue making a claim. The dashed rule carries the
  ///    identity; the text carries the value, at `textBody`, where it is
  ///    legible in sunlight as well as at 3 a.m.
  ///  * **the probe's name leads it.** `250°` alone on a four-series chart
  ///    names nothing, and the alternative — colouring it to say whose it is —
  ///    is the thing above. `Pit 250°` is unambiguous in one channel.
  HorizontalLine _targetLine(
    Probe p,
    SmokeTokens t, {
    required bool labelled,
    required bool receding,
  }) {
    final hue = _styleFor(p.n).color;
    final series = receding ? ProbePalette.dim(hue) : hue;
    final text =
        '${_name(p.n)} ${formatSetpoint(p.targetF10, celsius: widget.celsius)}';
    return HorizontalLine(
      y: p.targetF10! / 10.0,
      // A target is a *reference*, not a reading: always exactly one step
      // quieter than the series it belongs to, so a rule and a probe can never
      // be read as two probes — including when that series is receding.
      color: ProbePalette.dim(series),
      strokeWidth: 1,
      dashArray: const [4, 4],
      label: HorizontalLineLabel(
        show: labelled,
        alignment: Alignment.topRight,
        padding: const EdgeInsets.only(right: SmokeTokens.s1, bottom: 2),
        style: SmokeType.labelSm.copyWith(color: t.textBody),
        labelResolver: (_) => text,
      ),
    );
  }
}

/// How much of the chart's height the chrome is allowed to take, decided
/// against the height it was actually given.
///
/// The rule is one sentence: **the plot never drops below [_plotFloorDp]**, and
/// what does not fit is dropped from the least load-bearing end. The legend
/// outranks the selector because a key that names the lines is worth more than
/// a control that hides some of them, and because the selector has a fallback
/// (do nothing) while the legend's fallback is guessing.
///
/// Everything here is measured rather than assumed — the legend's rows are
/// packed with the same [measureAxisLabel] the axis uses, at the scale it will
/// paint at — because the failure this guards against is a `RenderFlex
/// overflowed` at 200 % text on a 360 dp phone, which is a crash-shaped bug in
/// a screen whose whole job is to be readable at 3 a.m.
@immutable
class _ChromeBudget {
  const _ChromeBudget({required this.dots, required this.legend});

  final bool dots;
  final bool legend;

  static _ChromeBudget measure({
    required double height,
    required double width,
    required List<String> names,
    required bool fullHistory,
    required TextScaler textScaler,
  }) {
    if (!height.isFinite) {
      // Unbounded: the caller has already broken the `Expanded` below and will
      // hear about it from the framework. Nothing is gained by also hiding the
      // legend.
      return const _ChromeBudget(dots: true, legend: true);
    }
    final entry = SmokeType.bodySm;
    final rowH = _rowHeight(entry, textScaler);

    var room = height;
    if (!fullHistory) {
      // The capability notice is text in a padded slab; reserve three rows of
      // it. Over-reserving costs a legend on a short chart, under-reserving
      // costs an overflow — so this errs long on purpose.
      room -= SmokeTokens.s4 * 2 + rowH * 3 + SmokeTokens.s2;
    }

    final legendH =
        _legendHeight(width, names, entry, textScaler) + SmokeTokens.s2;
    final legend = room - legendH >= _plotFloorDp;
    if (legend) {
      room -= legendH;
    }
    final dots = room - (_dotRowDp + SmokeTokens.s2) >= _plotFloorDp;
    return _ChromeBudget(dots: dots, legend: legend);
  }

  static double _rowHeight(TextStyle s, TextScaler scaler) {
    final h = scaler.scale(s.fontSize ?? 14) * (s.height ?? 1.2);
    // A 12 dp glyph and a 20 dp stroke swatch share the row with the name.
    return h < 12 ? 12 : h;
  }

  /// The height `SeriesLegend`'s `Wrap` will occupy at [width], by packing it
  /// the way `Wrap` does. Rounds *up* — a row over-counted hides chrome, a row
  /// under-counted overflows the column.
  static double _legendHeight(
    double width,
    List<String> names,
    TextStyle style,
    TextScaler scaler,
  ) {
    if (names.isEmpty || !width.isFinite) {
      return 0;
    }
    // Glyph, gap, stroke swatch, gap — the fixed part of every entry.
    const marks = 12 + SmokeTokens.s1 + 20 + SmokeTokens.s2;
    final rowH = _rowHeight(style, scaler);
    var rows = 1;
    var x = 0.0;
    for (final n in names) {
      final w = marks + measureAxisLabel(n, style, scaler).width;
      if (x > 0 && x + SmokeTokens.s3 + w > width) {
        rows++;
        x = w;
      } else {
        x += (x > 0 ? SmokeTokens.s3 : 0) + w;
      }
    }
    return rows * rowH + (rows - 1) * SmokeTokens.s2;
  }
}

/// The channel-dot selector (`TemProBBQ-3`, 17 §17.3 D).
///
/// Tap a dot to isolate that series; tap it again to bring the rest back. The
/// second half is not optional — a filter with no visible way out is a screen
/// people get stuck on, and there is no other control here that restores them.
///
/// **Saturated, and a glyph rather than a plain dot.**
///
/// The fill is licensed: §17.2's first sanctioned extension of the series
/// channel is a badge filled with that probe's hue, because *"the hue **is** the
/// probe's identity and the numeral names the same thing the hue names — it is
/// a legend, not a claim"*. A channel dot is that badge with a glyph where the
/// numeral goes, and §17.5 restates the principle behind it: the discipline
/// exists to stop colour lying about **how the cook is going**, and a control
/// that says *which probe* makes no claim about temperature at all. So these do
/// not apologise — they are as bold as `TemProBBQ-3`'s.
///
/// What we do **not** copy from that reference is hue as the only channel.
/// TempPro's selector is four coloured circles and nothing else, which is the
/// one channel `series_palette.dart` measured and found wanting: P1 ember and
/// P4 blue sit 0.018 apart in luminance, so under a red-green deficiency, in
/// sunlight, or in a monochrome screenshot two of those four circles are the
/// same mark. The series' own [SeriesGlyph] is knocked out of the disc, so the
/// selector degrades the way the rest of the chart does (§14.10, §H.2).
///
/// The knockout is `bg` rather than a near-black constant so this file keeps
/// its zero references to `StatusPalette`. Measured against the four hues it
/// lands at 3.96:1 (green, the weakest), 5.06 (ember), 5.39 (blue) and 6.28
/// (violet) — all clear of the 3:1 graphics floor.
class _ChannelDots extends StatelessWidget {
  const _ChannelDots({
    required this.styles,
    required this.names,
    required this.focus,
    required this.onTap,
  });

  final List<ProbeStyle> styles;
  final List<String> names;
  final int? focus;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final motion = SmokeMotion.of(context);
    return SizedBox(
      height: _dotRowDp,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < styles.length; i++)
            _Dot(
              key: Key('chart-dot-${styles[i].probe}'),
              style: styles[i],
              name: names[i],
              selected: focus == styles[i].probe,
              receding: focus != null && focus != styles[i].probe,
              motion: motion,
              tokens: t,
              onTap: () => onTap(styles[i].probe),
            ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    super.key,
    required this.style,
    required this.name,
    required this.selected,
    required this.receding,
    required this.motion,
    required this.tokens,
    required this.onTap,
  });

  final ProbeStyle style;
  final String name;
  final bool selected;
  final bool receding;
  final SmokeMotionValues motion;
  final SmokeTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      // Glyph, stroke, then colour — the order these channels can be relied
      // on, and the same order the legend and the crosshair speak them in.
      label: style.describe(name),
      hint: selected ? 'Show every series' : 'Show only this series',
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: _dotRowDp / 2,
        child: SizedBox(
          width: _dotRowDp,
          height: _dotRowDp,
          child: Center(
            child: AnimatedContainer(
              duration: motion.quick,
              curve: motion.curve,
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                // Lit: the hue, filled. Receding: the same hue, hollow — a
                // channel that is switched off should look switched off, and
                // an empty ring says that without a second colour.
                color: receding ? null : style.color,
                shape: BoxShape.circle,
                border: Border.all(
                  // The "this one" ring is **ink**, not another hue: hue is
                  // already spent naming the probe, and a second meaning laid
                  // over it is how a mark starts making claims.
                  color: selected
                      ? tokens.textHi
                      : ProbePalette.dim(style.color),
                  width: selected ? 2 : 1,
                ),
              ),
              child: Center(
                child: SeriesGlyphMark(
                  style: style,
                  dimmed: receding,
                  color: receding ? null : tokens.bg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The first interval tick at or after [min] — fl_chart's own
/// `Utils.getBestInitialIntervalValue` against a baseline of 0, which is
/// what `LineChartData` uses when `baselineX`/`baselineY` are left unset.
/// Returns [min] itself when the bound *is* a tick, and also when the span
/// is too short to contain one.
double _firstTick(double min, double max, double interval) {
  final mod = (0.0 - min) % interval;
  if (mod == 0 || (max - min).abs() <= mod) {
    return min;
  }
  return min + mod;
}

/// The size [text] will paint at, so the collision test below measures the
/// label instead of assuming a width for it. Costs one layout per *bound*
/// label — two per axis per frame, and never for interior ticks.
Size measureAxisLabel(String text, TextStyle? style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout();
  return painter.size;
}

/// Whether an axis label should be drawn at all.
///
/// fl_chart emits a label at each axis *bound* on top of the interval ticks
/// and never checks that the two land in different places
/// (`AxisChartHelper.iterateThroughAxis`). A session whose bounds are ragged
/// — which is every real session — then draws the last tick and the end
/// bound as one smear. Measured on the bench cook: `5:30` and `5:32` 0.8 px
/// apart on the time axis, and `59` over `60` on the temperature axis.
///
/// The test is in **pixels**, not in fractions of the interval, because the
/// interval is only a proxy for distance and a bad one at the edges: when
/// fl_chart's auto-interval is wider than the whole visible range the two
/// bounds are the only labels there are, they sit a full axis apart, and a
/// fraction-of-interval rule throws one of them away for no reason.
///
/// Two labels clear each other exactly when their centres are half of each
/// label apart, so [measure] is called for the bound *and* for the tick it
/// is crowding — `4:29` next to `4p` needs less room than next to `11:30`,
/// and assuming one size for both would either drop labels that fit or keep
/// ones that do not. Interior ticks return before measuring anything.
///
/// A bound that *is* a tick is always kept, and so is one on a span too
/// short to hold any tick — suppressing collisions can never empty an axis.
bool showAxisLabel(
  double v,
  TitleMeta meta, {
  required Size Function(double value) measure,
}) {
  final interval = meta.appliedInterval;
  final span = meta.max - meta.min;
  if (interval <= 0 || span <= 0 || meta.parentAxisSize <= 0) {
    return true;
  }
  final eps = interval / 100000;
  final first = _firstTick(meta.min, meta.max, interval);

  final double gap;
  final double neighbour;
  if ((v - meta.min).abs() <= eps) {
    if ((first - meta.min).abs() <= eps) {
      return true;
    }
    gap = first - meta.min;
    neighbour = first;
  } else if ((v - meta.max).abs() <= eps) {
    final last = first + ((meta.max - first) / interval).floor() * interval;
    if ((last - meta.max).abs() <= eps) {
      return true;
    }
    gap = meta.max - last;
    neighbour = last;
  } else {
    return true;
  }

  final vertical =
      meta.axisSide == AxisSide.left || meta.axisSide == AxisSide.right;
  double extent(Size s) => vertical ? s.height : s.width;
  final needPx = (extent(measure(v)) + extent(measure(neighbour))) / 2 * 1.15;
  return gap * (meta.parentAxisSize / span) >= needPx;
}

/// Axis tick spacing that keeps labels from colliding at every window.
double _axisInterval(int spanS) {
  const steps = [60, 300, 900, 1800, 3600, 10800, 21600, 43200, 86400];
  for (final s in steps) {
    if (spanS / s <= 6) {
      return s.toDouble();
    }
  }
  return (spanS / 6).ceilToDouble();
}

/// Wall clock when the session has one, elapsed time when it does not.
/// Rendering `1970-01-01` because the bridge had no clock at boot is the
/// bug this function exists to make impossible.
String formatAxisTime(int t, int? startedUnixMs) {
  if (startedUnixMs == null) {
    final h = t ~/ 3600;
    final m = (t % 3600) ~/ 60;
    return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${m}m';
  }
  final d = DateTime.fromMillisecondsSinceEpoch(
    startedUnixMs + t * 1000,
  ).toLocal();
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'a' : 'p';
  return d.minute == 0
      ? '$h12$ampm'
      : '$h12:${d.minute.toString().padLeft(2, '0')}';
}

/// Pinch, drag, double-tap, and the crosshair — all of it delegating to
/// [ChartViewport], which is where the arithmetic is tested.
class _ChartGestures extends StatefulWidget {
  const _ChartGestures({
    required this.viewport,
    required this.child,
    this.onViewport,
    this.onCrosshair,
  });

  final ChartViewport viewport;
  final Widget child;
  final ValueChanged<ChartViewport>? onViewport;
  final ValueChanged<int?>? onCrosshair;

  @override
  State<_ChartGestures> createState() => _ChartGesturesState();
}

class _ChartGesturesState extends State<_ChartGestures> {
  double _startScale = 1;
  ChartViewport? _startViewport;
  double _width = 1;

  int _tAt(double dx) {
    final vp = widget.viewport;
    final frac = (dx / _width).clamp(0.0, 1.0);
    return vp.minX + (vp.spanS * frac).round();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _width = constraints.maxWidth <= 0 ? 1 : constraints.maxWidth;
      return GestureDetector(
        key: const Key('chart-gestures'),
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => widget.onViewport?.call(widget.viewport.reset()),
        onLongPressStart: (d) =>
            widget.onCrosshair?.call(_tAt(d.localPosition.dx)),
        onLongPressMoveUpdate: (d) =>
            widget.onCrosshair?.call(_tAt(d.localPosition.dx)),
        onLongPressEnd: (_) => widget.onCrosshair?.call(null),
        onScaleStart: (d) {
          _startScale = 1;
          _startViewport = widget.viewport;
        },
        onScaleUpdate: (d) {
          final start = _startViewport ?? widget.viewport;
          if ((d.scale - 1).abs() > 0.02) {
            final next = start.zoom(
              _startScale / d.scale,
              focalT: _tAt(d.localFocalPoint.dx),
            );
            widget.onViewport?.call(next);
          } else if (d.focalPointDelta.dx.abs() > 0) {
            final perPx = widget.viewport.spanS / _width;
            widget.onViewport?.call(
              widget.viewport.pan(-(d.focalPointDelta.dx * perPx).round()),
            );
          }
        },
        child: widget.child,
      );
    },
  );
}

/// Nothing to plot — and the one surface in this file where the discipline
/// deliberately relaxes (17 §17.5).
///
/// §17.5 makes the rule proportional: §16.5 exists to stop colour *lying about
/// how the cook is going*, and **that failure needs live state to fail about**.
/// Here there is none — no series, no reading, no claim — so *"the empty reader
/// may carry a warm illustrated empty state rather than a grey glyph"*. What
/// was here was exactly the grey glyph: one line of `textMuted` centred on
/// black, in a pane that is often the largest thing on the screen.
///
/// So it gets the app's fire. The medallion is a filled disc in the ember that
/// §14.6.4 pins as the brand accent — the same hue that already fills the
/// primary button, the AP transport chip, the cook header and the passkey well
/// — with the glyph knocked out of it in `bg`. It is drawn from
/// [ProbePalette.hue] rather than `StatusPalette.pit` for the one reason this
/// file cares about: **zero status references, still**, and §14.6.4 guarantees
/// the two are the same value, not two similar ones.
///
/// **What is deliberately not drawn here: a sample trace.** The obvious warm
/// illustration for an empty chart is a ghost line showing what a cook looks
/// like. In this app that is the single worst thing that could be put on this
/// surface — an invented plot on a chart whose entire contract is that it never
/// invents a reading. The warmth goes in the medallion and the words.
class _EmptyChart extends StatelessWidget {
  const _EmptyChart({required this.fullHistory});
  final bool fullHistory;

  /// Below this the illustration would crowd out its own caption, so the same
  /// state renders as one warm line instead. `live_tab` hands the chart 120 dp
  /// on a half-open Fold.
  ///
  /// Scaled by the text factor rather than fixed: at 200 % the medallion is
  /// unchanged but the title and the sentence are twice the height, so a pane
  /// that comfortably held the illustration at 1.0 cannot hold it at 2.0. The
  /// answer §14.10 gives is to reflow, not to clip.
  static const double _illustratedFloorDp = 200;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!fullHistory) ...[
          const CapabilityNotice(
            key: Key('chart-capability-notice'),
            icon: Icons.bluetooth_rounded,
            message:
                'Connected over Bluetooth — full history needs Wi-Fi. '
                'Showing the last 2 hours.',
          ),
          const SizedBox(height: SmokeTokens.s2),
        ],
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final floor =
                  _illustratedFloorDp *
                  SmokeTextScale.factorOf(context).clamp(1.0, 2.0);
              return Center(
                child: constraints.maxHeight >= floor
                    ? const _EmptyIllustrated()
                    : const _EmptyCompact(),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The ember medallion. A filled shape in a series-slot hue, which is only
/// legal because §14.6.4 makes slot 1 the brand accent and §17.5 removes the
/// live state that the fill rule protects.
class _EmberMedallion extends StatelessWidget {
  const _EmberMedallion({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ProbePalette.hue(1),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          Icons.outdoor_grill_rounded,
          // Knocked out, so the glyph is a hole in the ember rather than a
          // second colour laid on it. 5.06:1 against slot 1.
          color: t.bg,
          size: size * 0.5,
        ),
      ),
    );
  }
}

class _EmptyIllustrated extends StatelessWidget {
  const _EmptyIllustrated();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(SmokeTokens.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _EmberMedallion(size: 64),
          const SizedBox(height: SmokeTokens.s4),
          Text(
            'No readings yet',
            key: const Key('chart-empty'),
            textAlign: TextAlign.center,
            style: SmokeType.displayS.copyWith(color: t.textHi),
          ),
          const SizedBox(height: SmokeTokens.s2),
          Text(
            'The cook draws itself here as soon as a probe reports.',
            textAlign: TextAlign.center,
            // Prose ink. Muting the only sentence on screen is a component
            // apologising for being there (§14.7).
            style: SmokeType.bodySm.copyWith(color: t.textBody),
          ),
        ],
      ),
    );
  }
}

class _EmptyCompact extends StatelessWidget {
  const _EmptyCompact();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(SmokeTokens.s3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _EmberMedallion(size: 28),
          const SizedBox(width: SmokeTokens.s3),
          Flexible(
            child: Text(
              'No readings yet',
              key: const Key('chart-empty'),
              style: SmokeType.bodySm.copyWith(color: t.textBody),
            ),
          ),
        ],
      ),
    );
  }
}

/// The window chips (§8.7's 15 m / 1 h / 6 h / 15 h / All) plus the
/// "jump to now" pill, which appears only once the user has panned away —
/// offering it while it is already at now is a no-op with a button on it.
///
/// The chips are [SegmentedChips], whose own doc names *"chart windows"* as its
/// first use and which nothing in the chart had ever called: this row was a
/// scrolling strip of raw `ChoiceChip`s carrying Material's fill, Material's
/// radius and Material's type, sitting inside a card built from the token set.
class ChartControls extends StatelessWidget {
  const ChartControls({
    required this.viewport,
    required this.onViewport,
    super.key,
  });

  final ChartViewport viewport;
  final ValueChanged<ChartViewport> onViewport;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: SegmentedChips<ChartWindow>(
          options: [
            for (final w in ChartWindow.values) ChipOption(w, w.label),
          ],
          value: viewport.window,
          onChanged: (w) => onViewport(viewport.withWindow(w)),
        ),
      ),
      if (!viewport.atNow || !viewport.following) ...[
        const SizedBox(width: SmokeTokens.s2),
        _NowPill(onTap: () => onViewport(viewport.jumpToNow())),
      ],
    ],
  );
}

/// "Now" — the one control in the chart that is not a segment.
///
/// A pill rather than an `ActionChip` so it wears `radiusPill` and the token
/// surfaces. It says a word as well as showing an arrow, because a bare glyph
/// in a corner is a guess.
class _NowPill extends StatelessWidget {
  const _NowPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: 'Jump to now',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('chart-jump-to-now'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(SmokeTokens.radiusPill),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: SmokeTokens.s3),
          decoration: BoxDecoration(
            color: t.cardRaised,
            borderRadius: BorderRadius.circular(SmokeTokens.radiusPill),
            border: Border.all(color: t.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fast_forward_rounded, size: 16, color: t.textBody),
              const SizedBox(width: SmokeTokens.s1),
              Text(
                'Now',
                style: SmokeType.bodySm.copyWith(
                  color: t.textHi,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The crosshair readout (A10.5): every probe's value at an instant, read
/// from the **nearest actual sample** with its distance stated. It never
/// interpolates across a gap — an invented reading in the middle of a
/// 30-minute dropout is worse than no reading.
///
/// On `well`, in `mono`, because the token set says so in as many words:
/// `well` is *"the deepest inset — mono readouts only: passkey, AP password,
/// device id, **chart crosshair**"*, and `SmokeType.mono` names the same four.
/// It had been rendering on `surfaceContainerHighest` in `bodyMedium` at a
/// radius the design system does not contain. Tabular figures matter here more
/// than anywhere: dragging the crosshair changes every digit thirty times a
/// second, and proportional figures make the whole card twitch.
class CrosshairReadout extends StatelessWidget {
  const CrosshairReadout({
    required this.readings,
    required this.atT,
    this.startedUnixMs,
    this.probes = const [],
    this.celsius = false,
    super.key,
  });

  final List<CrosshairReading> readings;
  final int atT;
  final int? startedUnixMs;
  final List<Probe> probes;
  final bool celsius;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      key: const Key('chart-crosshair-readout'),
      padding: const EdgeInsets.symmetric(
        horizontal: SmokeTokens.s3,
        vertical: SmokeTokens.s2,
      ),
      decoration: BoxDecoration(
        color: t.well,
        borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
        border: Border.all(color: t.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatAxisTime(atT, startedUnixMs),
            style: SmokeType.labelSm.copyWith(color: t.textMuted),
          ),
          // Each reading is identified by a GLYPH, not by colour alone.
          //
          // The swatch here used to be a 12x3 bar of the series hue and
          // nothing else. Measured (`test/design/series_channels_test.dart`),
          // probe 1's ember and probe 4's blue sit **0.018 apart in
          // luminance** — under a red-green deficiency they are the same mark,
          // and no reordering of the palette fixes it. So the shape carries
          // the identity and the hue merely agrees with it; strip the colour
          // entirely and four distinct probes remain (§H.2).
          for (final r in readings)
            Semantics(
              // One node per reading, and it leads with the glyph exactly as
              // `describe` does — a screen reader gets the same channel a
              // colour-blind reader gets.
              label:
                  '${_styleFor(r.probe).describe(_name(r.probe))}, '
                  '${formatTempPrecise(r.f == null ? null : (r.f! * 10).round(), celsius: celsius)}'
                  '${r.f != null && r.deltaS > 30 ? ', ${r.deltaS} seconds away' : ''}',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(top: SmokeTokens.s1),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: SmokeTokens.s2),
                        child: SeriesGlyphMark(
                          style: _styleFor(r.probe),
                          // A reading the crosshair could not resolve is dimmed
                          // rather than dropped: a probe that vanishes from the
                          // readout reads as an app fault, not an empty jack.
                          dimmed: r.f == null,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _name(r.probe),
                          style: SmokeType.bodySm.copyWith(color: t.textBody),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: SmokeTokens.s2),
                      Text(
                        formatTempPrecise(
                          r.f == null ? null : (r.f! * 10).round(),
                          celsius: celsius,
                        ),
                        style: SmokeType.mono.copyWith(color: t.textHi),
                      ),
                      if (r.f != null && r.deltaS > 30) ...[
                        const SizedBox(width: SmokeTokens.s1),
                        Text(
                          '(${r.deltaS}s away)',
                          style: SmokeType.labelSm.copyWith(
                            color: t.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _name(int n) {
    final p = probes.where((x) => x.n == n).firstOrNull;
    return (p?.name ?? '').isEmpty ? 'Probe $n' : p!.name;
  }

  ProbeStyle _styleFor(int n) => ProbePalette.styleFor(
    n,
    Brightness.dark,
    role: probes.where((p) => p.n == n).firstOrNull?.role ?? ProbeRole.unused,
  );
}
