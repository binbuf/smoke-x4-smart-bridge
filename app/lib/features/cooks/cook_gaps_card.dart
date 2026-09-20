/// The two kinds of hole in a recording, told apart (newapp §E.5, 16 §16.6).
///
/// Both look identical on a chart — a stretch of missing line — and they mean
/// opposite things to the person looking at it:
///
///  * **buffer rollover** is data *nobody has any more*. The bridge's ring
///    wrapped past what this phone had fetched. Waiting will not bring it back,
///    and an app that lets someone wait for it has lied by omission;
///  * **connectivity** is data *arriving on the next sync*. The bridge still
///    holds it; the phone was simply not there to collect it.
///
/// So they are rendered as two different things, three ways over, because one
/// of those ways is always the one a given reader notices first:
///
///  1. **texture** — a hatched band against a dotted one, the same two marks
///     the chart draws, in `chromeDim` (the token whose docstring names gap
///     connectors) so neither can be mistaken for a series;
///  2. **status chrome** — `warning` against `info`, each with an icon *and* a
///     word, never colour alone;
///  3. **words** — "Lost for good" against "Waiting on the bridge", and a
///     sentence underneath that names the consequence rather than the cause.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/analysis/analysis.dart';
import '../../ui/ui.dart';

class CookGapsCard extends StatelessWidget {
  const CookGapsCard({required this.gaps, this.startedUnixMs, super.key});

  final List<RecordedGap> gaps;

  /// Wall clock at `t = 0`, so a hole can be named by the time of day it
  /// happened. Null when the bridge had no clock — the holes are then named by
  /// elapsed time, never by an epoch date.
  final int? startedUnixMs;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final lost = gaps.where((g) => g.reason.isPermanent).toList();
    final waiting = gaps.where((g) => !g.reason.isPermanent).toList();
    if (lost.isEmpty && waiting.isEmpty) {
      return const SizedBox.shrink();
    }
    return SmokeCard(
      key: const Key('cook-gaps'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'GAPS IN RECORDING',
            style: SmokeType.label.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: SmokeTokens.s3),
          if (lost.isNotEmpty)
            _GapBlock(
              key: const Key('gap-lost'),
              gaps: lost,
              role: StatusRole.warning,
              icon: Icons.warning_amber_rounded,
              // Not "Buffer rolled over": that names the mechanism. This names
              // what it costs the person reading it.
              headline: 'Lost for good',
              explanation: GapReason.bufferRollover.explanation,
              hatched: true,
              startedUnixMs: startedUnixMs,
            ),
          if (lost.isNotEmpty && waiting.isNotEmpty)
            const SizedBox(height: SmokeTokens.s2),
          if (waiting.isNotEmpty)
            _GapBlock(
              key: const Key('gap-waiting'),
              gaps: waiting,
              role: StatusRole.info,
              icon: Icons.cloud_sync_outlined,
              headline: 'Waiting on the bridge',
              explanation: GapReason.connectivity.explanation,
              hatched: false,
              startedUnixMs: startedUnixMs,
            ),
        ],
      ),
    );
  }
}

class _GapBlock extends StatelessWidget {
  const _GapBlock({
    required this.gaps,
    required this.role,
    required this.icon,
    required this.headline,
    required this.explanation,
    required this.hatched,
    required this.startedUnixMs,
    super.key,
  });

  final List<RecordedGap> gaps;
  final StatusRole role;
  final IconData icon;
  final String headline;
  final String explanation;
  final bool hatched;
  final int? startedUnixMs;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final total = gaps.fold(0, (a, g) => a + g.durationS);
    return Container(
      padding: const EdgeInsets.all(SmokeTokens.s3),
      decoration: BoxDecoration(
        color: StatusPalette.fill(role),
        borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
        border: Border.all(color: StatusPalette.border(role)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: StatusPalette.hue(role)),
              const SizedBox(width: SmokeTokens.s2),
              Expanded(
                child: Text(
                  headline,
                  style: SmokeType.title.copyWith(color: t.textHi),
                ),
              ),
              const SizedBox(width: SmokeTokens.s2),
              Flexible(
                child: Text(
                  '${gaps.length == 1 ? '1 gap' : '${gaps.length} gaps'} · '
                  '${formatDuration(total)}',
                  textAlign: TextAlign.end,
                  style: SmokeType.bodySm.copyWith(color: t.textBody),
                ),
              ),
            ],
          ),
          const SizedBox(height: SmokeTokens.s2),
          for (final g in gaps)
            Padding(
              key: Key('gap-row-${g.fromT}'),
              padding: const EdgeInsets.only(bottom: SmokeTokens.s1),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    height: 12,
                    child: CustomPaint(
                      key: Key(hatched ? 'gap-mark-hatched' : 'gap-mark-dots'),
                      painter: _GapSwatch(hatched: hatched, ink: t.chromeDim),
                    ),
                  ),
                  const SizedBox(width: SmokeTokens.s2),
                  Expanded(
                    child: Text(
                      '${_at(g.fromT)} → ${_at(g.toT)} · '
                      '${formatDuration(g.durationS)}',
                      style: SmokeType.bodySm.copyWith(color: t.textBody),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: SmokeTokens.s1),
          Text(
            explanation,
            style: SmokeType.bodySm.copyWith(color: t.textBody),
          ),
        ],
      ),
    );
  }

  /// Clock time when the bridge knew it, elapsed time when it did not. Never
  /// an epoch date dressed up as a wall clock.
  String _at(int t) {
    final start = startedUnixMs;
    if (start == null) {
      return formatElapsed(t);
    }
    final d = DateTime.fromMillisecondsSinceEpoch(start + t * 1000);
    return '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
}

/// The two marks: hatch for gone, dots for coming.
///
/// Drawn in `chromeDim` — the token that exists for exactly this ("non-text
/// only: gap connectors") — so a hole can never read as a probe's series.
class _GapSwatch extends CustomPainter {
  const _GapSwatch({required this.hatched, required this.ink});

  final bool hatched;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    if (hatched) {
      // 45° fill: a band of data that was there and is not.
      for (var x = -size.height; x < size.width; x += 5) {
        canvas.drawLine(
          Offset(x, size.height),
          Offset(x + size.height, 0),
          paint,
        );
      }
      return;
    }
    // A dotted through-line: the series is expected to resume here.
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += 5) {
      canvas.drawLine(Offset(x, y), Offset(x + 2, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GapSwatch old) =>
      old.hatched != hatched || old.ink != ink;
}
