/// Moving a cook's start (newapp §D.3.1, 16 §16.6) — the differentiator.
///
/// No competitor lets you truly start a cook after the fact and re-anchor it.
/// FireBoard comes closest: it auto-creates a date-named session and lets you
/// edit its start and end afterwards. A whole community project exists because
/// Garmin *won't* let a user move a lap boundary in an uploaded activity —
/// people want this badly enough to build workarounds.
///
/// **So it is not a date picker.** A date picker asks the user to remember,
/// at hour fourteen, when the meat went on. The recording already knows: a
/// probe went from unplugged to reading, something climbed past room
/// temperature, somebody placed a mark. `CookRepository.anchorsFor` finds those
/// moments; this sheet's whole job is to make each one **legible as evidence**
/// and to state, on the row itself, what choosing it would do:
///
///  * the plain-words label — "Probe 2 plugged in", never "sample[413] null→2110";
///  * the clock time it happened;
///  * **how far that moves the start** — "2h 14m earlier". This is the line
///    that makes the feature land, because it is where someone discovers the
///    cook really did begin two hours before they opened the app;
///  * one sentence saying why the recording thinks this is a start.
///
/// Tapping a row commits. There is no confirm step, because the row *is* the
/// preview, nothing is destroyed, and the screen behind offers an undo.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/plan/plan.dart';
import '../../ui/ui.dart';
import 'cook_sheet_shell.dart';

/// Asks for a new start time. Returns null if dismissed.
Future<int?> showBackdateSheet(
  BuildContext context, {
  required CookAnnotation cook,
  required List<CookAnchor> anchors,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => Theme(
    data: SmokeTheme.dark,
    child: BackdateSheet(cook: cook, anchors: anchors),
  ),
);

/// Stateless over plain values so the sheet renders in a test with no
/// repository and no database behind it.
class BackdateSheet extends StatelessWidget {
  const BackdateSheet({
    required this.cook,
    required this.anchors,
    super.key,
  });

  final CookAnnotation cook;
  final List<CookAnchor> anchors;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // An anchor at or after the end is not an offer: a cook cannot start after
    // it finished, and a row that throws on tap is a dead control with extra
    // steps.
    final offers = anchors
        .where((a) => cook.endUnixMs == null || a.unixMs < cook.endUnixMs!)
        .toList();

    return cookSheetShell(
      context,
      key: const Key('backdate-sheet'),
      title: 'When did this cook start?',
      children: [
        Text(
          'It starts at ${formatSessionDate(cook.startUnixMs)} right now. '
          'Moving it re-measures the cook. No reading moves — they were '
          'always there.',
          style: SmokeType.bodySm.copyWith(color: t.textBody),
        ),
        const SizedBox(height: SmokeTokens.s5),
        if (offers.isEmpty)
          const CapabilityNotice(
            key: Key('backdate-no-anchors'),
            icon: Icons.search_off_rounded,
            message:
                'Nothing in the recording points at a start time. Either the '
                'bridge had no clock when it recorded this, or this phone '
                'holds nothing from before the cook began.',
          )
        else ...[
          Text(
            'FROM THE RECORDING',
            style: SmokeType.label.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: SmokeTokens.s1),
          Text(
            'These are the moments something actually changed. Pick one and '
            'the cook starts there.',
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
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
                  _AnchorRow(
                    anchor: offers[i],
                    currentStartUnixMs: cook.startUnixMs,
                    onTap: () => Navigator.of(context).pop(offers[i].unixMs),
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
            key: const Key('anchor-manual'),
            icon: Icons.edit_calendar_outlined,
            title: 'Pick a time myself',
            subtitle: offers.isEmpty
                ? 'A date and a time, in your own hand.'
                : 'If none of these is the moment.',
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

class _AnchorRow extends StatelessWidget {
  const _AnchorRow({
    required this.anchor,
    required this.currentStartUnixMs,
    required this.onTap,
  });

  final CookAnchor anchor;
  final int currentStartUnixMs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final at = DateTime.fromMillisecondsSinceEpoch(anchor.unixMs);
    final clock =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    return CookSheetRow(
      key: Key('anchor-${anchor.kind.name}-${anchor.unixMs}'),
      icon: _iconFor(anchor.kind),
      leadingDot: anchor.probe >= 1 && anchor.probe <= 4
          ? ProbePalette.hue(anchor.probe)
          : null,
      title: anchor.label,
      trailing: clock,
      subtitle: '${shiftLabel(anchor.unixMs, currentStartUnixMs)} · '
          '${reasonFor(anchor.kind)}',
      onTap: onTap,
    );
  }

  IconData _iconFor(AnchorKind k) => switch (k) {
    AnchorKind.probeInserted => Icons.sensors_rounded,
    AnchorKind.crossedAmbient => Icons.thermostat_rounded,
    AnchorKind.mark => Icons.flag_outlined,
    AnchorKind.recordingStart => Icons.fiber_manual_record_outlined,
  };
}

/// "2h 14m earlier" — the line that makes backdating land, because it is where
/// someone sees the cook really did begin before they opened the app.
///
/// Public so the detail screen can say the same thing in past tense once the
/// move has happened, in the same words.
String shiftLabel(int toUnixMs, int fromUnixMs) {
  final deltaS = (toUnixMs - fromUnixMs) ~/ 1000;
  if (deltaS.abs() < 60) {
    return 'where it starts now';
  }
  return deltaS < 0
      ? '${formatDuration(-deltaS)} earlier'
      : '${formatDuration(deltaS)} later';
}

/// Why the recording is offering this moment. Plain words, one sentence.
String reasonFor(AnchorKind kind) => switch (kind) {
  AnchorKind.probeInserted =>
    'a probe went from unplugged to reading, which is usually the food going '
        'on',
  AnchorKind.crossedAmbient =>
    'a probe climbed past room temperature, so the food met the fire',
  AnchorKind.mark => 'a mark placed during the cook',
  AnchorKind.recordingStart => 'the oldest reading this phone holds',
};
