/// N5.6 — the instrument-mode card shown when no cook is active.
///
/// Watching without targets is a first-class state, not a degraded one: the
/// copy says so and the bridge still records. The card owns the screen's single
/// ember action **unless** the adopt banner is also on screen (I14), which is
/// why [primary] exists.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

class InstrumentModeCard extends StatelessWidget {
  const InstrumentModeCard({
    super.key,
    this.primary = true,
    this.onStartCook,
    this.onViewGraph,
  });

  /// Whether "Start a cook" is the ember primary. False when the adopt banner
  /// already owns it (I14).
  final bool primary;

  final VoidCallback? onStartCook;
  final VoidCallback? onViewGraph;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return SmokeCard(
      key: const ValueKey<String>('live-instrument'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              SmokeIcon(
                SmokeGlyph.thermometer,
                size: 17,
                color: tokens.textBody,
              ),
              const SizedBox(width: 8),
              Text(
                'Instrument mode',
                style: SmokeText.cardTitle.copyWith(color: tokens.textHi),
              ),
              const Spacer(),
              Text(
                'no targets',
                style: SmokeText.labelSm.copyWith(
                  fontSize: 10.5,
                  color: tokens.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Watching live temperatures without a cook. Nothing is lost — the '
            'bridge records everything either way. Add a cook whenever you want '
            'targets, timers and a timeline.',
            style: SmokeText.sub.copyWith(color: tokens.textBody),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: primary
                    ? PrimaryAction(
                        key: const ValueKey<String>('live-instrument-start'),
                        label: 'Start a cook',
                        icon: SmokeGlyph.plus,
                        onPressed: onStartCook,
                      )
                    : SmokeButton(
                        key: const ValueKey<String>('live-instrument-start'),
                        label: 'Start a cook',
                        icon: SmokeGlyph.plus,
                        onPressed: onStartCook,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SmokeButton(
                  key: const ValueKey<String>('live-instrument-graph'),
                  label: 'View graph',
                  icon: SmokeGlyph.chart,
                  variant: SmokeButtonVariant.ghost,
                  onPressed: onViewGraph,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
