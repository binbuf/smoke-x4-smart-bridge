/// The `/cooks` "+" (16 §16.6, newapp §C.3, §D.3).
///
/// "+" has to do something that used to be impossible: **create a cook now,
/// over readings that already exist.** The bridge has been recording the whole
/// time; a cook is a name and a pair of bounds laid over that recording, and
/// nothing about starting one requires knowing a target yet.
///
/// So the sheet leads with the one-tap path and keeps the guided setup as the
/// second option, rather than making every cook begin with a form. The sentence
/// at the top is doing real work — it is where the model gets taught, once, at
/// the only moment somebody is actually thinking about it.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../ui/ui.dart';
import 'cook_sheet_shell.dart';

/// Which way the user chose to start.
enum CookCreateChoice {
  /// A cook starting now, no targets. They can be added later, and the start
  /// can be moved back to where the recording says it belongs.
  now,

  /// The guided setup sheet: preset, roles, targets, then start.
  withTargets,
}

Future<CookCreateChoice?> showCreateCookSheet(BuildContext context) =>
    showModalBottomSheet<CookCreateChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Theme(
        data: SmokeTheme.dark,
        child: const CreateCookSheet(),
      ),
    );

class CreateCookSheet extends StatelessWidget {
  const CreateCookSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return cookSheetShell(
      context,
      key: const Key('create-cook-sheet'),
      title: 'Start a cook',
      children: [
        Text(
          'Your bridge is already recording. A cook just names a stretch of '
          'it — you can move its start and set targets whenever you like.',
          style: SmokeType.bodySm.copyWith(color: t.textBody),
        ),
        const SizedBox(height: SmokeTokens.s5),
        PrimaryAction(
          key: const Key('create-cook-now'),
          label: 'Start one now',
          icon: Icons.play_arrow_rounded,
          onPressed: () => Navigator.of(context).pop(CookCreateChoice.now),
        ),
        const SizedBox(height: SmokeTokens.s3),
        SmokeCard(
          padding: EdgeInsets.zero,
          child: CookSheetRow(
            key: const Key('create-cook-targets'),
            icon: Icons.adjust_rounded,
            title: 'Choose targets first',
            subtitle:
                'Pick a preset or set your own numbers, then start the cook.',
            onTap: () =>
                Navigator.of(context).pop(CookCreateChoice.withTargets),
          ),
        ),
      ],
    );
  }
}
