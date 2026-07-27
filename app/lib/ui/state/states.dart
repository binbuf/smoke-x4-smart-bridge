/// A19.6 — EmptyState, ProblemState, CapabilityNotice (design 14 §14.7).
///
/// The three "there is nothing here yet" surfaces, and the rule they enforce:
/// **glyph + title + one sentence + exactly one action, never actionless.** A
/// dead-end screen with no next step is the thing this app is built not to do
/// (rail R2, 13 §13.2). A degraded section renders a [CapabilityNotice] instead
/// of leaving inert controls on screen pretending to work.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

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

/// Something is wrong and the user can do something about it.
class ProblemState extends StatelessWidget {
  const ProblemState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.error_outline_rounded,
    this.action,
    this.secondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) => _Frame(
    icon: icon,
    title: title,
    message: message,
    tone: _Tone.problem,
    action: action,
    secondary: secondary,
  );
}

/// "This needs a Wi-Fi connection to the bridge." — what a section renders in
/// place of controls it cannot honour on the current transport.
class CapabilityNotice extends StatelessWidget {
  const CapabilityNotice({
    super.key,
    required this.message,
    this.icon = Icons.lock_outline_rounded,
    this.action,
  });

  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(SmokeTokens.s4),
      decoration: BoxDecoration(
        color: StatusPalette.fill(StatusRole.info),
        borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
        border: Border.all(color: StatusPalette.border(StatusRole.info)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: StatusPalette.info),
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
  });

  final IconData icon;
  final String title;
  final String message;
  final _Tone tone;
  final Widget? action;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final accent = tone == _Tone.problem ? StatusPalette.critical : t.textMuted;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(SmokeTokens.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: accent),
              const SizedBox(height: SmokeTokens.s4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: SmokeType.displayS.copyWith(color: t.textHi),
              ),
              const SizedBox(height: SmokeTokens.s2),
              Text(
                message,
                textAlign: TextAlign.center,
                style: SmokeType.body.copyWith(color: t.textMuted),
              ),
              if (action != null) ...[
                const SizedBox(height: SmokeTokens.s5),
                action!,
              ],
              if (secondary != null) ...[
                const SizedBox(height: SmokeTokens.s2),
                secondary!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
