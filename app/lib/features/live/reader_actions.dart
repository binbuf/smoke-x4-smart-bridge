/// The reader's action row (design 16 §16.5, §16.6).
///
/// §16.6 names it exactly: **Mark · Set a target / Edit cook · Export · Test
/// alarm**, and says it must be *real* — which the old one was not. Three
/// floating tiles rendered whichever callbacks happened to be non-null, so the
/// row silently changed arity between screens, and "Set up a cook" lived
/// somewhere else entirely: a button inside the header card, competing with the
/// screen title for the eye.
///
/// This is one strip, hairline-divided, and the arity is fixed by the caller
/// rather than by whichever handlers were wired. That matters because of the
/// other half of the rule (§16.7): **no control is dead — absent, or disabled
/// with its reason on screen.** A cell with no handler is not dropped, it is
/// dimmed, and [ReaderAction.reason] is printed under the strip. A row that
/// changes width when the bridge drops is a row you cannot build muscle memory
/// against.
///
/// It reflows to two columns rather than clipping when the labels get wide —
/// which at 200 % text scale they always do.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

@immutable
class ReaderAction {
  const ReaderAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.reason = '',
  });

  final IconData icon;

  /// A verb that names the outcome (§16.4 rule 7) — "Mark", "Set a target".
  final String label;

  /// Null renders the cell disabled, not absent.
  final VoidCallback? onTap;

  /// Why it is disabled, in the user's terms. Printed under the strip, because
  /// a greyed control with no explanation is a dead control with extra steps.
  final String reason;

  bool get enabled => onTap != null;
}

class ReaderActionRow extends StatelessWidget {
  const ReaderActionRow({super.key, required this.actions});

  final List<ReaderAction> actions;

  /// The narrowest a cell may get before the strip folds to two columns. Scaled
  /// by the reader's text setting, so the fold happens when the *words* stop
  /// fitting rather than at a width someone measured once on a Pixel.
  static const double _minCell = 78;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }
    final t = context.tokens;
    final scale = MediaQuery.textScalerOf(context).scale(11) / 11;
    final reasons = [
      for (final a in actions)
        if (!a.enabled && a.reason.isNotEmpty) a.reason,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final perRow =
                c.maxWidth / actions.length >= _minCell * scale ||
                    actions.length <= 2
                ? actions.length
                : 2;
            final rows = <List<ReaderAction>>[];
            for (var i = 0; i < actions.length; i += perRow) {
              rows.add(
                actions.sublist(i, (i + perRow).clamp(0, actions.length)),
              );
            }
            return DecoratedBox(
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(SmokeTokens.radiusCard),
                border: Border.all(color: t.hairline),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var r = 0; r < rows.length; r++) ...[
                    if (r > 0) Divider(height: 1, color: t.hairline),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < rows[r].length; i++) ...[
                            if (i > 0)
                              VerticalDivider(width: 1, color: t.hairline),
                            Expanded(child: _Cell(action: rows[r][i])),
                          ],
                          // Pad a short final row so three actions over two
                          // columns do not stretch the last one to double
                          // width and read as the primary one.
                          for (var i = rows[r].length; i < perRow; i++) ...[
                            VerticalDivider(width: 1, color: t.hairline),
                            const Expanded(child: SizedBox()),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        for (final reason in reasons) ...[
          const SizedBox(height: SmokeTokens.s2),
          Text(reason, style: SmokeType.bodySm.copyWith(color: t.textMuted)),
        ],
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.action});

  final ReaderAction action;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = action.enabled;
    return Semantics(
      button: true,
      enabled: enabled,
      label: enabled
          ? action.label
          : '${action.label}, unavailable. ${action.reason}',
      excludeSemantics: true,
      child: InkWell(
        onTap: action.onTap,
        child: Opacity(
          // Dimmed and present. The reason travels under the strip.
          opacity: enabled ? 1 : 0.4,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SmokeTokens.s2,
              vertical: SmokeTokens.s3,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  action.icon,
                  // Chrome in the accent, the way every other secondary
                  // control in the app is drawn.
                  color: enabled ? StatusPalette.pit : t.chromeDim,
                  size: 22,
                ),
                const SizedBox(height: SmokeTokens.s2),
                Text(
                  action.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SmokeType.labelSm.copyWith(
                    color: enabled ? t.textBody : t.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
