/// Splitting a cook, and merging it with a neighbour (newapp §C.4).
///
/// Both are arithmetic on two time bounds. Neither moves a sample, and both
/// sheets say so, because "split" and "merge" sound like operations on data
/// and the whole reframe rests on them not being.
///
/// The backdate sheet used to live here and now has a file of its own
/// (`cook_backdate_sheet.dart`) — it earned one.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/entities/entities.dart';
import '../../domain/plan/plan.dart';
import '../../ui/ui.dart';
import '../cook/mark_sheet.dart';
import 'cook_sheet_shell.dart';

/// Asks where to split. Returns the chosen instant, or null.
Future<int?> showSplitSheet(
  BuildContext context, {
  required CookAnnotation cook,
  required List<Mark> marks,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => Theme(
    data: SmokeTheme.dark,
    child: SplitSheet(cook: cook, marks: marks),
  ),
);

class SplitSheet extends StatelessWidget {
  const SplitSheet({required this.cook, required this.marks, super.key});

  final CookAnnotation cook;
  final List<Mark> marks;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Marks are session-relative; the cook's start is the anchor the detail
    // screen already resolved, so offsets are taken from it.
    final offers =
        <({int at, String label, String kind})>[
              for (final m in marks)
                (
                  at: cook.startUnixMs + m.t * 1000,
                  label: m.text.isEmpty ? markLabel(m.kind) : m.text,
                  kind: markLabel(m.kind),
                ),
            ]
            .where((o) => cook.covers(o.at) && o.at > cook.startUnixMs)
            .toList();

    return cookSheetShell(
      context,
      key: const Key('split-sheet'),
      title: 'Split this cook',
      children: [
        Text(
          'Everything before the split keeps this cook’s name; everything '
          'after becomes a second one with the same targets. No reading '
          'moves.',
          style: SmokeType.bodySm.copyWith(color: t.textBody),
        ),
        const SizedBox(height: SmokeTokens.s5),
        if (offers.isEmpty)
          const CapabilityNotice(
            key: Key('split-no-marks'),
            icon: Icons.flag_outlined,
            message:
                'Nothing is marked inside this cook, so there is no obvious '
                'place to cut it. Pick a time instead.',
          )
        else ...[
          Text(
            'MARKS IN THIS COOK',
            style: SmokeType.label.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: SmokeTokens.s2),
          SmokeCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < offers.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: SmokeTokens.s4,
                      endIndent: SmokeTokens.s4,
                      color: t.hairlineStrong,
                    ),
                  CookSheetRow(
                    key: Key('split-at-${offers[i].at}'),
                    icon: Icons.flag_outlined,
                    title: offers[i].label,
                    subtitle: offers[i].kind,
                    trailing: _clock(offers[i].at),
                    onTap: () => Navigator.of(context).pop(offers[i].at),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: SmokeTokens.s3),
        SmokeCard(
          padding: EdgeInsets.zero,
          child: CookSheetRow(
            key: const Key('split-manual'),
            icon: Icons.edit_calendar_outlined,
            title: 'Pick a time myself',
            subtitle: 'A date and a time inside this cook.',
            onTap: () async {
              final picked = await pickCookDateTime(context, cook.startUnixMs);
              if (picked != null && context.mounted) {
                Navigator.of(context).pop(picked);
              }
            },
          ),
        ),
      ],
    );
  }
}

/// Asks which neighbour to merge with. Returns the chosen cook, or null.
Future<CookAnnotation?> showMergeSheet(
  BuildContext context, {
  required CookAnnotation cook,
  required List<CookAnnotation> neighbours,
}) => showModalBottomSheet<CookAnnotation>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => Theme(
    data: SmokeTheme.dark,
    child: MergeSheet(cook: cook, neighbours: neighbours),
  ),
);

class MergeSheet extends StatelessWidget {
  const MergeSheet({
    required this.cook,
    required this.neighbours,
    super.key,
  });

  final CookAnnotation cook;

  /// The cook immediately before and after this one — the only two a merge can
  /// sensibly offer. The whole list would be a picker nobody reads.
  final List<CookAnnotation> neighbours;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return cookSheetShell(
      context,
      key: const Key('merge-sheet'),
      title: 'Merge with a neighbour',
      children: [
        Text(
          'The two become one cook spanning both, keeping the earlier one’s '
          'name and targets. Any gap between them still shows as a gap.',
          style: SmokeType.bodySm.copyWith(color: t.textBody),
        ),
        const SizedBox(height: SmokeTokens.s5),
        if (neighbours.isEmpty)
          const CapabilityNotice(
            key: Key('merge-no-neighbours'),
            icon: Icons.merge_rounded,
            message: 'Nothing is recorded next to this cook to merge with.',
          )
        else
          SmokeCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < neighbours.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: SmokeTokens.s4,
                      endIndent: SmokeTokens.s4,
                      color: t.hairlineStrong,
                    ),
                  CookSheetRow(
                    key: Key('cook-merge-${neighbours[i].id}'),
                    icon: neighbours[i].startUnixMs < cook.startUnixMs
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    title: neighbours[i].displayName(),
                    subtitle: neighbours[i].startUnixMs < cook.startUnixMs
                        ? 'the cook before this one'
                        : 'the cook after this one',
                    trailing: _clock(neighbours[i].startUnixMs),
                    onTap: () => Navigator.of(context).pop(neighbours[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

String _clock(int unixMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixMs);
  final sameDay = DateTime.now().difference(d).inHours.abs() < 24;
  return sameDay
      ? '${d.hour.toString().padLeft(2, '0')}:'
            '${d.minute.toString().padLeft(2, '0')}'
      : formatSessionDate(unixMs);
}
