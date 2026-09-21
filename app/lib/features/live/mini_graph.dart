/// N5.9 — the mini graph card.
///
/// A small multi-series preview of the attached probes' recent readings, tap to
/// open the full Graph destination. The label is `<unit> · last Nm`, matching
/// the prototype's `miniChart`. The real chart is N7; this is the glance.
library;

import 'package:flutter/material.dart';

import '../../data/model/cook_state.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import 'live_format.dart';

class LiveMiniGraphCard extends StatelessWidget {
  const LiveMiniGraphCard({
    super.key,
    required this.probes,
    required this.cook,
    required this.unit,
    required this.now,
    this.onTap,
  });

  final List<ProbeState> probes;
  final CookState cook;
  final TempUnit unit;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final series = <({Color color, List<double> values})>[
      for (final probe in probes)
        if (probe.attached && probe.spark.length > 1)
          (
            color: tokens.series(probe.jack.n),
            values: <double>[for (final value in probe.spark) value.toDouble()],
          ),
    ];

    final start = cook.startedAtMs;
    final elapsedMin = start == null
        ? 0
        : ((now.millisecondsSinceEpoch - start) / 60000).round();

    return SmokeCard(
      key: const ValueKey<String>('live-mini-graph'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              SmokeIcon(SmokeGlyph.chart, size: 17, color: tokens.textBody),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Live graph',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SmokeText.cardTitle.copyWith(color: tokens.textHi),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${unitLabel(unit)} · last ${elapsedMin}m',
                  key: const ValueKey<String>('live-mini-graph-label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: SmokeText.labelSm.copyWith(
                    fontSize: 10.5,
                    color: tokens.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SmokeIcon(
                SmokeGlyph.chevronRight,
                size: 16,
                color: tokens.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            child: series.isEmpty
                ? Center(
                    child: Text(
                      'No attached probes yet',
                      style: SmokeText.labelSm.copyWith(
                        color: tokens.textMuted,
                      ),
                    ),
                  )
                : CustomPaint(
                    size: Size.infinite,
                    painter: _MiniGraphPainter(series: series),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MiniGraphPainter extends CustomPainter {
  _MiniGraphPainter({required this.series});

  final List<({Color color, List<double> values})> series;

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in series) {
      final values = line.values;
      var lo = values.first;
      var hi = values.first;
      for (final value in values) {
        lo = value < lo ? value : lo;
        hi = value > hi ? value : hi;
      }
      final span = (hi - lo) == 0 ? 1.0 : hi - lo;
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = (i / (values.length - 1)) * size.width;
        final y =
            size.height - 4 - ((values[i] - lo) / span) * (size.height - 8);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line.color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniGraphPainter old) => old.series != series;
}
