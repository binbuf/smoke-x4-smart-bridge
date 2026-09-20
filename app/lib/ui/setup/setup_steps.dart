/// `SetupSteps` — "here is what happens next", in order (design 17 §17.3 C).
///
/// WHY a component and not three `Text`s: §17.3 C asks setup to *"say what will
/// happen next, in three short steps, before it happens — the pairing passkey
/// especially"*, and the reason it matters is specific. When the app hands
/// bonding to the platform, the platform puts up its own dialog whose hint
/// reads **"Usually 0000 or 1234"**. That is flatly wrong for this bridge: the
/// six digits are generated on the device and shown only on its OLED
/// (13 §13.2.1), and there is no API to change what that dialog says. So the
/// last thing a user reads before being asked for a code is a wrong guess at
/// it. The correction has to land *before* the dialog, and it has to be
/// impossible to skim past.
///
/// Hence [SetupStep.caution]: a step may be drawn as **chrome** — a `warning`
/// fill, a `warning` border, a `warning` icon — with its words at `textHi`,
/// which is exactly 16 §16.5's shape for a status hue (*"fill + border + icon +
/// word, never words alone"*). A reader who cannot see amber still gets the
/// glyph and the sentence; a reader skimming still gets the block of colour.
///
/// The steps carry no numbers-as-status and no colour that means anything else:
/// a neutral step is a numeral in a `cardSubtle` disc, and that is all.
/// Strings come from the caller — `ui/` owns no user-facing copy (14 §14.11).
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

/// One line of "what happens next".
@immutable
class SetupStep {
  const SetupStep(this.text, {this.caution = false});

  final String text;

  /// Draw this step as caution chrome rather than a numbered neutral row.
  /// Reserved for a step that corrects something the user is about to be told
  /// wrong by someone else — see the library doc.
  final bool caution;
}

class SetupSteps extends StatelessWidget {
  const SetupSteps({super.key, required this.steps});

  final List<SetupStep> steps;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < steps.length; i++) ...[
        if (i > 0) const SizedBox(height: SmokeTokens.s3),
        _StepRow(
          // The ordinal counts the *steps*, so a caution inserted between two
          // of them does not renumber the ones after it.
          ordinal: steps.take(i).where((s) => !s.caution).length + 1,
          step: steps[i],
        ),
      ],
    ],
  );
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.ordinal, required this.step});

  final int ordinal;
  final SetupStep step;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final caution = step.caution;

    final marker = caution
        ? const Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: StatusPalette.warning,
          )
        // Ember-filled, not a grey disc. 17 §17.5: onboarding has no session
        // and no reading, so a saturated identity fill here cannot misstate
        // anything — and the numeral inside carries the meaning on its own, so
        // the colour is never the sole signal.
        : Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: StatusPalette.pit,
              shape: BoxShape.circle,
              boxShadow: [?t.glowTight(StatusPalette.pit)],
            ),
            child: Text(
              '$ordinal',
              style: SmokeType.labelSm.copyWith(
                color: StatusPalette.onPit,
                letterSpacing: 0,
                height: 1,
              ),
            ),
          );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        marker,
        const SizedBox(width: SmokeTokens.s3),
        Expanded(
          child: Text(
            step.text,
            // Banner text is `textHi`, never the hue (§14.6.5) — the amber is
            // carried by the icon and the border.
            style: SmokeType.bodySm.copyWith(
              color: caution ? t.textHi : t.textBody,
              fontWeight: caution ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );

    if (!caution) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SmokeTokens.s1),
        child: row,
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SmokeTokens.s3,
        vertical: SmokeTokens.s3,
      ),
      decoration: BoxDecoration(
        color: StatusPalette.fill(StatusRole.warning),
        borderRadius: BorderRadius.circular(SmokeTokens.radiusChip),
        border: Border.all(color: StatusPalette.border(StatusRole.warning)),
      ),
      child: row,
    );
  }
}
