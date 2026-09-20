/// The confirm surface for anything that costs the user something
/// (design 13 §13.5.6).
///
/// Lifted out of `features/bridge/bridge_tab.dart`, where it was private, for
/// one reason: it was the best confirmation pattern in the app and the *only*
/// screen using it was the one whose actions were least likely to lose
/// anything. Restarting the bridge made you read a two-column ledger; ending a
/// fourteen-hour cook took one unlabelled tap.
///
/// The pattern, and why it beats "Are you sure?": a generic confirm asks the
/// user to supply the consequence from memory. This one **states it**, split
/// into what survives and what does not, so the decision is made on facts
/// rather than on nerve. The confirm button is a plain destructive
/// `FilledButton`, never the ember [PrimaryAction] — the one ember button on a
/// screen is a *forward* action, not an erase (rail R1).
///
/// The cancel label is a parameter with no default on purpose. "Cancel" names
/// the dialog mechanic; the escape hatch should name the outcome the same way
/// the confirm does ("Keep it running" against "Restart").
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

/// Opens the sheet and resolves true only if the user confirmed.
Future<bool> showCostSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
  String? keeps,
  String? loses,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CostSheet(
      title: title,
      body: body,
      keeps: keeps,
      loses: loses,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
  return ok ?? false;
}

class CostSheet extends StatelessWidget {
  const CostSheet({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    this.keeps,
    this.loses,
    super.key,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final String? keeps;
  final String? loses;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SafeArea(
      top: false,
      child: Container(
        // On a tablet or an unfolded Fold a full-bleed sheet puts the two
        // buttons a hand-span apart; the ledger is prose and reads at prose
        // width wherever it is shown.
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.symmetric(horizontal: SmokeTokens.s2),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(SmokeTokens.radiusCard),
          ),
          border: Border.all(color: t.hairline),
        ),
        padding: const EdgeInsets.all(SmokeTokens.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: SmokeType.displayS.copyWith(color: t.textHi)),
            const SizedBox(height: SmokeTokens.s2),
            Text(body, style: SmokeType.body.copyWith(color: t.textBody)),
            if (keeps != null) ...[
              const SizedBox(height: SmokeTokens.s3),
              _CostLine(
                icon: Icons.check_circle_outline_rounded,
                lead: 'Keeps',
                text: keeps!,
                // **Not `positive`.** Green means transport health and nothing
                // else (16 §16.5). This sheet fronts ten destructive actions —
                // end a cook, adopt a bridge, merge, delete, clear data,
                // restart, power off, factory reset — and not one of them is a
                // link coming back. A green "Keeps" on all ten is how green
                // stops meaning anything on the one chip where it must.
                // `pit` is the app's own accent, and the meaning is carried by
                // the tick and the word, which both stay.
                tint: StatusPalette.pit,
              ),
            ],
            if (loses != null) ...[
              const SizedBox(height: SmokeTokens.s2),
              _CostLine(
                icon: Icons.remove_circle_outline_rounded,
                lead: 'Loses',
                text: loses!,
                tint: StatusPalette.critical,
              ),
            ],
            const SizedBox(height: SmokeTokens.s5),
            FilledButton(
              key: const Key('cost-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: StatusPalette.critical,
                foregroundColor: t.textHi,
                minimumSize: const Size(64, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    SmokeTokens.radiusControl,
                  ),
                ),
              ),
              child: Text(confirmLabel, style: SmokeType.title),
            ),
            const SizedBox(height: SmokeTokens.s2),
            TextButton(
              key: const Key('cost-cancel'),
              // Focus starts here, not on the red button: a keyboard or
              // trackpad user on a tablet must not be one Enter away from an
              // erase they were only reading about.
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                cancelLabel,
                style: SmokeType.title.copyWith(color: t.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CostLine extends StatelessWidget {
  const _CostLine({
    required this.icon,
    required this.lead,
    required this.text,
    required this.tint,
  });

  final IconData icon;
  final String lead;
  final String text;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: tint),
        const SizedBox(width: SmokeTokens.s2),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: SmokeType.bodySm.copyWith(color: t.textBody),
              children: [
                TextSpan(
                  text: '$lead ',
                  style: SmokeType.bodySm.copyWith(
                    color: t.textHi,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
