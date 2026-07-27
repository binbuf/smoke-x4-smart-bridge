/// A10.3 / A10.5 — the chart (design 08 §8.7).
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
///    pretending everything was fine.
///  * **Detached probes contribute no spots.** By construction — A10.1
///    never emits one — but the type here cannot express a zero either.
///  * **The capability notice, not an error.** A transport whose
///    `fullHistory` is false shows its 2-hour preview and says
///    _"connected over Bluetooth — full history needs Wi-Fi"_. A3.1 built
///    that flag for this exact moment, three milestones ago.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/palette.dart';
import '../../core/format.dart';
import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';
import 'chart_viewport.dart';

class CookChart extends StatelessWidget {
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

  Probe? _cfg(int n) => probes.where((p) => p.n == n).firstOrNull;

  /// A raw °F axis value as the label the user's unit calls it.
  static String axisTemp(double f, {required bool celsius}) =>
      '${(celsius ? f10ToC10((f * 10).round()) / 10 : f).round()}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    // Read eagerly: the axis label builders run during layout, and the
    // collision test below measures a label at the scale it will paint at.
    final textScaler = MediaQuery.textScalerOf(context);

    if (model.isEmpty) {
      return _EmptyChart(fullHistory: fullHistory);
    }

    final lo = (model.minF ?? 0) - 10;
    final hi = (model.maxF ?? 100) + 10;

    final bars = <LineChartBarData>[];
    for (final s in model.series) {
      if (s.isEmpty) {
        continue;
      }
      final style = ProbePalette.styleFor(
        s.probe,
        brightness,
        role: _cfg(s.probe)?.role ?? ProbeRole.unused,
      );
      // The envelope goes in first so it sits behind the mean line.
      if (s.envelope.isNotEmpty) {
        bars.add(
          LineChartBarData(
            spots: [
              for (final e in s.envelope) FlSpot(e.t.toDouble(), e.max),
              for (final e in s.envelope.reversed)
                FlSpot(e.t.toDouble(), e.min),
            ],
            color: style.color.withValues(alpha: 0.18),
            barWidth: 0,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: style.color.withValues(alpha: 0.18),
            ),
          ),
        );
      }
      for (final run in s.runs) {
        bars.add(
          LineChartBarData(
            spots: [for (final p in run.points) FlSpot(p.t.toDouble(), p.f)],
            color: style.color,
            barWidth: style.strokeWidth,
            dashArray: style.dashArray,
            isStrokeCapRound: true,
            isStrokeJoinRound: true,
            dotData: const FlDotData(show: false),
          ),
        );
      }
    }

    // Overlays — §8.7's list, and no more.
    final targetLines = <HorizontalLine>[
      for (final p in probes)
        if (p.targetF10 != null &&
            model.series.any((s) => s.probe == p.n && !s.isEmpty))
          HorizontalLine(
            y: p.targetF10! / 10.0,
            color: ProbePalette.styleFor(
              p.n,
              brightness,
              role: p.role,
            ).color.withValues(alpha: 0.55),
            strokeWidth: 1,
            dashArray: const [4, 4],
          ),
    ];
    final markLines = <VerticalLine>[
      for (final m in marks)
        if (m.t >= viewport.minX && m.t <= viewport.maxX)
          VerticalLine(
            x: m.t.toDouble(),
            color: ProbePalette.axisInk(brightness).withValues(alpha: 0.7),
            strokeWidth: 1,
            dashArray: const [2, 3],
          ),
      if (crosshairT != null)
        VerticalLine(
          x: crosshairT!.toDouble(),
          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
          strokeWidth: 1,
        ),
    ];

    // A shaded band for the pit's alarm min/max.
    final pit = probes.where((p) => p.role == ProbeRole.pit).firstOrNull;
    final band = <HorizontalRangeAnnotation>[
      if (pit?.alarmMinF10 != null && pit?.alarmMaxF10 != null)
        HorizontalRangeAnnotation(
          y1: pit!.alarmMinF10! / 10.0,
          y2: pit.alarmMaxF10! / 10.0,
          color: ProbePalette.styleFor(
            pit.n,
            brightness,
            role: ProbeRole.pit,
          ).color.withValues(alpha: 0.08),
        ),
    ];

    final chart = LineChart(
      LineChartData(
        minX: viewport.minX.toDouble(),
        maxX: viewport.maxX.toDouble(),
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
              FlLine(color: ProbePalette.grid(brightness), strokeWidth: 1),
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
                final style = theme.textTheme.labelSmall?.copyWith(
                  color: ProbePalette.axisInk(brightness),
                );
                String fmt(double x) => axisTemp(x, celsius: celsius);
                if (!showAxisLabel(
                  v,
                  meta,
                  measure: (x) => measureAxisLabel(fmt(x), style, textScaler),
                )) {
                  return const SizedBox.shrink();
                }
                return Text(fmt(v), style: style);
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: _axisInterval(viewport.spanS),
              getTitlesWidget: (v, meta) {
                final style = theme.textTheme.labelSmall?.copyWith(
                  color: ProbePalette.axisInk(brightness),
                );
                String fmt(double x) =>
                    formatAxisTime(x.round(), startedUnixMs);
                if (!showAxisLabel(
                  v,
                  meta,
                  measure: (x) => measureAxisLabel(fmt(x), style, textScaler),
                )) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(fmt(v), style: style),
                );
              },
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!fullHistory)
          const _CapabilityNotice(key: Key('chart-capability-notice')),
        Expanded(
          child: _ChartGestures(
            viewport: viewport,
            onViewport: onViewport,
            onCrosshair: onCrosshair,
            child: chart,
          ),
        ),
      ],
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

class _CapabilityNotice extends StatelessWidget {
  const _CapabilityNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.bluetooth, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Connected over Bluetooth — full history needs Wi-Fi. '
              'Showing the last 2 hours.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart({required this.fullHistory});
  final bool fullHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!fullHistory)
          const _CapabilityNotice(key: Key('chart-capability-notice')),
        Expanded(
          child: Center(
            child: Text(
              'No readings yet',
              key: const Key('chart-empty'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The window chips (§8.7's 15 m / 1 h / 6 h / 15 h / All) plus the
/// "jump to now" pill, which appears only once the user has panned away —
/// offering it while it is already at now is a no-op with a button on it.
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
      // Five chips plus a pill do not fit a 320 dp phone, and a chip row
      // that overflows is one you cannot reach the end of. Scroll it.
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final w in ChartWindow.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    key: Key('chart-chip-${w.name}'),
                    label: Text(w.label),
                    selected: viewport.window == w,
                    onSelected: (_) => onViewport(viewport.withWindow(w)),
                  ),
                ),
            ],
          ),
        ),
      ),
      if (!viewport.atNow || !viewport.following)
        ActionChip(
          key: const Key('chart-jump-to-now'),
          avatar: const Icon(Icons.fast_forward, size: 18),
          label: const Text('Now'),
          onPressed: () => onViewport(viewport.jumpToNow()),
        ),
    ],
  );
}

/// The crosshair readout (A10.5): every probe's value at an instant, read
/// from the **nearest actual sample** with its distance stated. It never
/// interpolates across a gap — an invented reading in the middle of a
/// 30-minute dropout is worse than no reading.
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
    final theme = Theme.of(context);
    return Container(
      key: const Key('chart-crosshair-readout'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatAxisTime(atT, startedUnixMs),
            style: theme.textTheme.labelLarge,
          ),
          for (final r in readings)
            Row(
              children: [
                Container(
                  width: 12,
                  height: 3,
                  margin: const EdgeInsets.only(right: 8),
                  color: ProbePalette.styleFor(
                    r.probe,
                    theme.brightness,
                    role:
                        probes.where((p) => p.n == r.probe).firstOrNull?.role ??
                        ProbeRole.unused,
                  ).color,
                ),
                Text(
                  '${_name(r.probe)}  '
                  '${formatTempPrecise(r.f == null ? null : (r.f! * 10).round(), celsius: celsius)}'
                  '${r.f != null && r.deltaS > 30 ? ' (${r.deltaS}s away)' : ''}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _name(int n) {
    final p = probes.where((x) => x.n == n).firstOrNull;
    return (p?.name ?? '').isEmpty ? 'Probe $n' : p!.name;
  }
}
