/// A19.6 — EmptyState, LoadingState, ProblemState, CapabilityNotice
/// (design 14 §14.7, 16 §16.5, §16.7).
///
/// The four surfaces that say *"there is nothing here — yet, or ever, or not
/// on this transport"*. They are the most-reused things in the app: eleven call
/// sites across five features, which means they are also the app's *voice*, and
/// a generic centred icon-over-two-lines is that voice sounding like every
/// other Flutter app.
///
/// ## The rules they enforce
///
/// **Glyph, title, one sentence, exactly one action** (§16.4 rule 6). A
/// dead-end screen with no next step is the thing this app is built not to do
/// (rail R2, 13 §13.2), and a *list* of choices in an empty state is a triage
/// job handed to a tired person.
///
/// **A wait has words.** §16.2: *"a spinner with no words is worse than an
/// error with words."* [LoadingState] exists because the app had no worded
/// wait at all — bare `CircularProgressIndicator`s that tell a user nothing
/// about whether to keep waiting.
///
/// **`terminal` is not a failure of the one-action rule, it is the honest form
/// of it** (§14.7.1). A phone with no Bluetooth cannot be told "use Wi-Fi
/// instead": a factory-fresh bridge hosts an AP whose name and 10-character
/// password are readable only on its own OLED, so there is no address to type
/// and no credential to type it with. The honest render is the instruction and
/// **no button** — a button that leads nowhere is worse than an admitted dead
/// end.
///
/// ## The §H.2 pass
///
/// The glyph was a bare 48 dp icon floating on the background, which is the
/// default every framework ships with. It is now a **medallion**: a 76 dp
/// rounded square on `cardSubtle` with a hairline, and — for a problem — the
/// status treatment §14.6.1 actually prescribes, a 14 % fill and a 35 % border
/// carrying the hue so the icon does not have to carry it alone. That single
/// change is what turns these from "an icon and some text" into a component
/// that looks like it was drawn for this app.
///
/// Rhythm is on the 4 dp scale and stated once here rather than guessed per
/// call site: medallion · s5 · title · s2 · body · s6 · action · s3 ·
/// secondary. Prose is `textBody`, not `textMuted` — `textMuted` is the label
/// ink, and an empty state's sentence is the only thing on screen.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

/// Widest an empty state's column may get. Prose, not a readout: past ~45
/// characters a centred sentence stops being one thing the eye takes in.
const double _stateMaxWidth = 360;

/// A neutral empty state: no cook yet, no history yet, nothing found.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.secondary,
  });

  final IconData icon;
  final String title;
  final String message;

  /// The one action. Null only for a genuinely terminal empty state.
  final Widget? action;

  /// A single quieter escape hatch. Never a second primary — two filled
  /// buttons is a screen that has not decided what the user should do next.
  final Widget? secondary;

  @override
  Widget build(BuildContext context) => _Frame(
    icon: icon,
    title: title,
    message: message,
    tone: _Tone.neutral,
    action: action,
    secondary: secondary,
  );
}

/// A wait that says what it is waiting for.
///
/// The indicator is deliberately small and beneath the words rather than a
/// 48 dp spinner above them: the words are the information, and a big spinner
/// with a caption reads as *loading*, while a caption with a thin progress
/// line reads as *this specific thing is happening*.
class LoadingState extends StatelessWidget {
  const LoadingState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.hourglass_empty_rounded,
    this.action,
  });

  /// What is happening, in the present tense. "Looking for your bridge…"
  final String title;

  /// Why it might take a moment, or what will happen if it does not work.
  /// One sentence, and optional — a wait that needs a paragraph is a wait
  /// that should have been an error.
  final String? message;

  final IconData icon;

  /// The escape hatch. A wait longer than a moment must be interruptible, so
  /// callers that can cancel or fall back put it here.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      container: true,
      liveRegion: true,
      label: message == null ? title : '$title. $message',
      child: _Frame(
        icon: icon,
        title: title,
        message: message ?? '',
        tone: _Tone.neutral,
        // Under the words, full width of the column, 2 dp: a progress *rule*,
        // not a spinning disc. Indeterminate, because the app genuinely does
        // not know how long a radio takes and a fake percentage is a lie.
        beneath: ClipRRect(
          borderRadius: BorderRadius.circular(SmokeTokens.radiusPill),
          child: LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: t.cardSubtle,
            color: StatusPalette.pit,
          ),
        ),
        action: action,
      ),
    );
  }
}

/// Something is wrong and the user can do something about it — or, when
/// [terminal], provably cannot, and is told so instead of being handed a
/// button that leads nowhere.
class ProblemState extends StatelessWidget {
  const ProblemState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.error_outline_rounded,
    this.action,
    this.secondary,
    this.terminal = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Widget? secondary;

  /// The instruction *is* the whole body, and there is no button (§14.7.1).
  /// Asserted rather than politely ignored: passing an action here is a
  /// contradiction, and a silent one would ship.
  final bool terminal;

  @override
  Widget build(BuildContext context) {
    assert(
      !terminal || (action == null && secondary == null),
      'A terminal ProblemState is terminal *because* there is nothing to '
      'press. Drop the action or drop `terminal: true`.',
    );
    return _Frame(
      icon: icon,
      title: title,
      message: message,
      tone: _Tone.problem,
      action: terminal ? null : action,
      secondary: terminal ? null : secondary,
    );
  }
}

/// "This needs a Wi-Fi connection to the bridge." — what a section renders in
/// place of controls it cannot honour on the current transport.
///
/// Sized and shaped like an [InsightBanner] on purpose: a capability notice is
/// an advisory about *this section*, not a page-level error, and it must not
/// look like one.
class CapabilityNotice extends StatelessWidget {
  const CapabilityNotice({
    super.key,
    required this.message,
    this.icon = Icons.lock_outline_rounded,
    this.action,
    this.role = StatusRole.info,
  });

  final String message;
  final IconData icon;
  final Widget? action;

  /// Which status hue carries the notice.
  ///
  /// The hue rides the **icon and the border only** — the words stay
  /// `textBody` at every role (§14.6.5, §16.5). That is the whole reason a
  /// failed save should reach for this rather than a bare `Text` in
  /// `StatusPalette.critical`: red on the surface measures 3.19:1, and a
  /// sentence a tired person cannot read is not an error message.
  final StatusRole role;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      container: true,
      label: message,
      child: Container(
        padding: const EdgeInsets.all(SmokeTokens.s4),
        decoration: BoxDecoration(
          color: StatusPalette.fill(role),
          borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
          border: Border.all(color: StatusPalette.border(role)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: StatusPalette.hue(role)),
            const SizedBox(width: SmokeTokens.s3),
            Expanded(
              child: Text(
                message,
                style: SmokeType.bodySm.copyWith(color: t.textBody),
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: SmokeTokens.s2),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

enum _Tone { neutral, problem }

class _Frame extends StatelessWidget {
  const _Frame({
    required this.icon,
    required this.title,
    required this.message,
    required this.tone,
    this.action,
    this.secondary,
    this.beneath,
  });

  final IconData icon;
  final String title;
  final String message;
  final _Tone tone;
  final Widget? action;
  final Widget? secondary;

  /// Sits between the sentence and the action. The loading rule lives here.
  final Widget? beneath;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final problem = tone == _Tone.problem;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _stateMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(SmokeTokens.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(child: _Medallion(icon: icon, problem: problem)),
              const SizedBox(height: SmokeTokens.s5),
              Text(
                title,
                textAlign: TextAlign.center,
                style: SmokeType.displayS.copyWith(color: t.textHi),
              ),
              if (message.isNotEmpty) ...[
                const SizedBox(height: SmokeTokens.s2),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  // Prose ink, not label ink. This sentence is the only thing
                  // on the screen; muting it to `textMuted` was the component
                  // apologising for being there.
                  style: SmokeType.body.copyWith(color: t.textBody),
                ),
              ],
              if (beneath != null) ...[
                const SizedBox(height: SmokeTokens.s5),
                beneath!,
              ],
              if (action != null) ...[
                const SizedBox(height: SmokeTokens.s6),
                action!,
              ],
              if (secondary != null) ...[
                const SizedBox(height: SmokeTokens.s3),
                Align(child: secondary!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The framed glyph. A bare icon on a background is the default every
/// framework ships; a medallion is a decision, and for a problem it is also
/// the only §14.6.1-legal way for the hue to appear at this size — 14 % fill,
/// 35 % border, and the word directly under it.
class _Medallion extends StatelessWidget {
  const _Medallion({required this.icon, required this.problem});

  final IconData icon;
  final bool problem;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: problem
            ? StatusPalette.fill(StatusRole.critical)
            : t.cardSubtle,
        borderRadius: BorderRadius.circular(SmokeTokens.radiusCard),
        border: Border.all(
          color: problem
              ? StatusPalette.border(StatusRole.critical)
              : t.hairlineStrong,
        ),
      ),
      child: Icon(
        icon,
        size: 32,
        color: problem ? StatusPalette.critical : t.textMuted,
      ),
    );
  }
}
