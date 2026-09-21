/// N3.30 — `CostSheet` and `showCostSheet`.
///
/// **State the cost before a destructive action, split into keeps / loses
/// (I8).** The sheet names both consequences and both buttons; neither button
/// is "OK". [destructive] paints the confirm action in the critical hue, and
/// the confirm is the only ember-or-danger action on the surface.
library;

import 'package:flutter/material.dart';

import 'buttons.dart';
import 'icons.dart';
import 'text.dart';
import 'tokens.dart';

/// The destructive-confirm body.
class CostSheet extends StatelessWidget {
  const CostSheet({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    this.keeps = const <String>[],
    this.loses = const <String>[],
    this.destructive = true,
    this.busy = false,
    this.onConfirm,
    this.onCancel,
  });

  final String title;
  final String message;

  /// What survives the action.
  final List<String> keeps;

  /// What the action destroys.
  final List<String> loses;

  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final bool busy;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(tokens.density.cardPadding),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radii.card),
        border: Border.all(color: tokens.hairlineStrong),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            style: SmokeText.cardTitle.copyWith(
              fontSize: 19,
              color: tokens.textHi,
            ),
          ),
          const SizedBox(height: 8),
          CostSheetBody(message: message, keeps: keeps, loses: loses),
          const SizedBox(height: 20),
          PrimaryAction(
            label: confirmLabel,
            onPressed: onConfirm,
            busy: busy,
            icon: destructive ? SmokeGlyph.alertTriangle : null,
          ),
          const SizedBox(height: 8),
          SmokeButton(
            label: cancelLabel,
            onPressed: onCancel,
            variant: SmokeButtonVariant.ghost,
          ),
        ],
      ),
    );
  }
}

/// The content half of a [CostSheet]: the message plus the keeps/loses split.
///
/// Split out so the generic `confirm` overlay (N13.22) can render the same
/// cost language under the shell's modal chrome (title + Confirm/Cancel row).
class CostSheetBody extends StatelessWidget {
  const CostSheetBody({
    super.key,
    required this.message,
    this.keeps = const <String>[],
    this.loses = const <String>[],
  });

  final String message;

  /// What survives the action.
  final List<String> keeps;

  /// What the action destroys.
  final List<String> loses;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(message, style: SmokeText.sub.copyWith(color: tokens.textBody)),
        if (keeps.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          _Group(
            label: 'Keeps',
            glyph: SmokeGlyph.check,
            hue: tokens.positive,
            items: keeps,
          ),
        ],
        if (loses.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _Group(
            label: 'Loses',
            glyph: SmokeGlyph.alertTriangle,
            hue: tokens.critical,
            items: loses,
          ),
        ],
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.label,
    required this.glyph,
    required this.hue,
    required this.items,
  });

  final String label;
  final SmokeGlyph glyph;
  final Color hue;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            SmokeIcon(glyph, size: 15, color: hue),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: SmokeText.labelSm.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: hue,
              ),
            ),
          ],
        ),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              item,
              style: SmokeText.labelSm.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: tokens.textBody,
              ),
            ),
          ),
      ],
    );
  }
}

/// Presents a [CostSheet] as a modal; resolves to true on confirm.
Future<bool?> showCostSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  List<String> keeps = const <String>[],
  List<String> loses = const <String>[],
  bool destructive = true,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: CostSheet(
          title: title,
          message: message,
          keeps: keeps,
          loses: loses,
          destructive: destructive,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          onCancel: () => Navigator.of(sheetContext).pop(false),
          onConfirm: () => Navigator.of(sheetContext).pop(true),
        ),
      ),
    ),
  );
}
