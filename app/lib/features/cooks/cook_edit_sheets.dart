/// Moving a cook's start, and splitting it (newapp §D.3, §C.4).
///
/// **The backdate sheet is the differentiator.** No competitor lets you truly
/// start a cook after the fact and re-anchor it; FireBoard comes closest by
/// auto-creating a date-named session and letting you edit its start and end
/// afterwards, and a whole community project exists because Garmin *won't* let
/// a user move a lap boundary in an uploaded activity. People want this badly
/// enough to build workarounds, so it should not be buried in a date picker.
///
/// Hence the shape: a **short list of times the recording can vouch for** —
/// when a probe was plugged in, when something first went above ambient, a mark
/// you placed — with a manual picker underneath for the case none of them is
/// right. Answering "when did the meat go on" from the data beats asking
/// someone to remember it at hour fourteen.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/entities/entities.dart';
import '../../domain/plan/plan.dart';
import '../../ui/ui.dart';
import '../cook/mark_sheet.dart';

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
    child: _BackdateSheet(cook: cook, anchors: anchors),
  ),
);

class _BackdateSheet extends StatelessWidget {
  const _BackdateSheet({required this.cook, required this.anchors});

  final CookAnnotation cook;
  final List<CookAnchor> anchors;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // An anchor at or after the end is not an offer — a cook cannot start
    // after it finished, and showing a row that throws on tap is a dead
    // control with extra steps.
    final offers = anchors
        .where((a) => cook.endUnixMs == null || a.unixMs < cook.endUnixMs!)
        .toList();
    return _sheetShell(
      context,
      title: 'When did this cook start?',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SmokeTokens.s4),
          child: Text(
            'It is currently ${formatSessionDate(cook.startUnixMs)}. '
            'The readings do not move — only the name and the targets follow '
            'the new start.',
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          ),
        ),
        const SizedBox(height: SmokeTokens.s3),
        if (offers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(SmokeTokens.s4),
            child: Text(
              'Nothing in the recording points at a start time — the bridge '
              'had no clock, or there is nothing cached from before this cook.',
              style: SmokeType.bodySm.copyWith(color: t.textMuted),
            ),
          )
        else
          for (final a in offers)
            ListTile(
              key: Key('anchor-${a.kind.name}-${a.unixMs}'),
              leading: Icon(_iconFor(a.kind), color: t.textBody),
              title: Text(
                a.label,
                style: SmokeType.title.copyWith(color: t.textHi),
              ),
              subtitle: Text(
                formatSessionDate(a.unixMs),
                style: SmokeType.bodySm.copyWith(color: t.textMuted),
              ),
              onTap: () => Navigator.of(context).pop(a.unixMs),
            ),
        const Divider(height: 1),
        ListTile(
          key: const Key('anchor-manual'),
          leading: Icon(Icons.edit_calendar_outlined, color: t.textBody),
          title: Text(
            'Pick a time myself',
            style: SmokeType.title.copyWith(color: t.textHi),
          ),
          onTap: () async {
            final picked = await _pickDateTime(context, cook.startUnixMs);
            if (picked != null && context.mounted) {
              Navigator.of(context).pop(picked);
            }
          },
        ),
      ],
    );
  }

  IconData _iconFor(AnchorKind k) => switch (k) {
    AnchorKind.probeInserted => Icons.sensors_rounded,
    AnchorKind.crossedAmbient => Icons.thermostat_rounded,
    AnchorKind.mark => Icons.flag_outlined,
    AnchorKind.recordingStart => Icons.fiber_manual_record_outlined,
  };
}

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
    child: _SplitSheet(cook: cook, marks: marks),
  ),
);

class _SplitSheet extends StatelessWidget {
  const _SplitSheet({required this.cook, required this.marks});

  final CookAnnotation cook;
  final List<Mark> marks;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Marks are session-relative; the cook's start is the anchor the detail
    // screen already resolved, so offsets are taken from it.
    final offers = <({int at, String label})>[
      for (final m in marks)
        (
          at: cook.startUnixMs + m.t * 1000,
          label: m.text.isEmpty ? markLabel(m.kind) : m.text,
        ),
    ].where((o) => cook.covers(o.at) && o.at > cook.startUnixMs).toList();

    return _sheetShell(
      context,
      title: 'Split this cook',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SmokeTokens.s4),
          child: Text(
            'Everything before the split keeps this cook’s name; everything '
            'after becomes a second one with the same targets. No readings '
            'move.',
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          ),
        ),
        const SizedBox(height: SmokeTokens.s3),
        for (final o in offers)
          ListTile(
            key: Key('split-at-${o.at}'),
            leading: Icon(Icons.flag_outlined, color: t.textBody),
            title: Text(
              o.label,
              style: SmokeType.title.copyWith(color: t.textHi),
            ),
            subtitle: Text(
              formatSessionDate(o.at),
              style: SmokeType.bodySm.copyWith(color: t.textMuted),
            ),
            onTap: () => Navigator.of(context).pop(o.at),
          ),
        if (offers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SmokeTokens.s4),
            child: Text(
              'No marks inside this cook to split at — pick a time instead.',
              style: SmokeType.bodySm.copyWith(color: t.textMuted),
            ),
          ),
        const Divider(height: 1),
        ListTile(
          key: const Key('split-manual'),
          leading: Icon(Icons.edit_calendar_outlined, color: t.textBody),
          title: Text(
            'Pick a time myself',
            style: SmokeType.title.copyWith(color: t.textHi),
          ),
          onTap: () async {
            final picked = await _pickDateTime(context, cook.startUnixMs);
            if (picked != null && context.mounted) {
              Navigator.of(context).pop(picked);
            }
          },
        ),
      ],
    );
  }
}

Widget _sheetShell(
  BuildContext context, {
  required String title,
  required List<Widget> children,
}) {
  final t = context.tokens;
  return Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    decoration: BoxDecoration(
      color: t.surface,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(SmokeTokens.radiusCard),
      ),
      border: Border.all(color: t.hairline),
    ),
    child: SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(SmokeTokens.s4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: SmokeType.displayS.copyWith(color: t.textHi),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: children),
          ),
        ],
      ),
    ),
  );
}

/// A date then a time, both seeded from the cook's current start.
Future<int?> _pickDateTime(BuildContext context, int seedUnixMs) async {
  final seed = DateTime.fromMillisecondsSinceEpoch(seedUnixMs);
  final date = await showDatePicker(
    context: context,
    initialDate: seed,
    // A cook can be backdated a long way — the bridge may have been recording
    // for weeks — and scheduled forward, so both directions are open.
    firstDate: seed.subtract(const Duration(days: 400)),
    lastDate: seed.add(const Duration(days: 30)),
  );
  if (date == null || !context.mounted) {
    return null;
  }
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(seed),
  );
  if (time == null) {
    return null;
  }
  return DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  ).millisecondsSinceEpoch;
}
