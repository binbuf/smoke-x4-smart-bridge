/// The guided progression, drawn as **marks** (newapp §D.5, §H.2; design 16
/// §16.5).
///
/// The four phases — approaching → pull now → resting → ready — used to be a
/// single grey pill wearing a word, wedged into a row beside a two-line
/// sentence and a button. A pill says *where you are*; it does not say **how
/// far through** you are, which is the only thing a progression is for.
///
/// So it is a four-segment track: one segment per phase, filled in the probe's
/// own series hue up to and including the current one, `hairlineStrong` after
/// it. The current segment is the tall one — **the position is carried by a
/// shape, not by a colour**, which is what keeps this legible for a colour-blind
/// reader, on the OLED, and under the stale veil's desaturation.
///
/// There is no green anywhere in here and no status hue at all: reaching the
/// end of a cook is not a transport-health event (§16.5). A 4 dp rule is a
/// mark, so the series hue is allowed to carry it; the *word* beside it is
/// `textHi`, because a hue may never carry a word.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/plan/plan.dart';

class PhaseTrack extends StatelessWidget {
  const PhaseTrack({
    super.key,
    required this.state,
    required this.hue,
    this.dense = false,
  });

  final CookPhaseState state;

  /// The probe's series hue. A mark colour — it fills nothing wider than the
  /// 4 dp rule below.
  final Color hue;

  /// Drops the sentence, keeping the track and the word. Used where the card
  /// is already carrying an insight strip.
  final bool dense;

  /// Where in `CookPhase.values` the current phase sits.
  int get _index => CookPhase.values.indexOf(state.phase);

  /// `Pull now` on its own; `Resting · 12m left` while a rest is running.
  String get _word {
    final left = state.restRemainingS;
    if (state.phase == CookPhase.resting && left != null) {
      return '${state.phase.label} · ${formatDuration(left)} left';
    }
    return state.phase.label;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final motion = SmokeMotion.of(context);
    final index = _index;

    return Semantics(
      label:
          '${state.phase.label}, step ${index + 1} of ${CookPhase.values.length}'
          '${state.detail.isEmpty ? '' : '. ${state.detail}'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < CookPhase.values.length; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(
                  child: AnimatedContainer(
                    key: Key('phase-seg-$i'),
                    duration: motion.quick,
                    curve: motion.curve,
                    // The current phase is the TALL one. Height, not hue,
                    // says "you are here" — so it survives the stale veil's
                    // desaturation and a colour-blind reading alike.
                    height: i == index ? 7 : 4,
                    decoration: BoxDecoration(
                      color: i <= index ? hue : t.hairlineStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: SmokeTokens.s2),
          Text(
            _word,
            key: Key('phase-${state.phase.name}'),
            style: SmokeType.labelSm.copyWith(color: t.textHi),
          ),
          if (!dense && state.detail.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              // Rule 2 of the phase engine: a countdown from the cut's mass is
              // an estimate, and every place it appears has to say so.
              state.estimated ? '${state.detail} (estimate)' : state.detail,
              style: SmokeType.bodySm.copyWith(color: t.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
