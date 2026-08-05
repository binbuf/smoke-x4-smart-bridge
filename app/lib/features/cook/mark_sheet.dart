/// Placing a mark on the recording (newapp §C.1 — one of the dead controls).
///
/// The **Mark** button existed on the reader's action row and was wired to
/// nothing; the only code that had ever sent `ControlCommand.mark` was the
/// pre-shell `session_controls.dart`, which no route reached. Marks were
/// therefore readable — the chart drew them, History listed them, the stats
/// counted lid events from them — and not writable, which is a strange asymmetry
/// for the app that is supposed to control a one-button device.
///
/// This is that sheet, moved into the design system and reachable from the
/// reader. The label table is shared with the History timeline so a mark reads
/// the same wherever it appears.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../domain/entities/entities.dart';

/// The kinds a human places. `alarm` and `autoDetected` are the firmware's to
/// write (09 §9.2, §9.4) and are deliberately absent — offering them would let
/// a user forge an event the device is authoritative for.
const List<MarkKind> userMarkKinds = [
  MarkKind.note,
  MarkKind.wrapped,
  MarkKind.lidOpen,
  MarkKind.fuel,
  MarkKind.probeMoved,
  MarkKind.phaseChange,
];

/// Shared with the sessions detail timeline (A11.3), so a mark reads the same
/// wherever it appears.
String markLabel(MarkKind k) => switch (k) {
  MarkKind.note => 'Note',
  MarkKind.wrapped => 'Wrapped',
  MarkKind.lidOpen => 'Lid open',
  MarkKind.fuel => 'Added fuel',
  MarkKind.probeMoved => 'Moved a probe',
  MarkKind.alarm => 'Alarm',
  MarkKind.phaseChange => 'Phase change',
  MarkKind.autoDetected => 'Auto-detected',
};

IconData markIcon(MarkKind k) => switch (k) {
  MarkKind.note => Icons.sticky_note_2_outlined,
  MarkKind.wrapped => Icons.inventory_2_outlined,
  MarkKind.lidOpen => Icons.door_front_door_outlined,
  MarkKind.fuel => Icons.local_fire_department_outlined,
  MarkKind.probeMoved => Icons.swap_horiz_rounded,
  MarkKind.alarm => Icons.notifications_active_rounded,
  MarkKind.phaseChange => Icons.flag_outlined,
  MarkKind.autoDetected => Icons.auto_awesome_outlined,
};

/// Asks which kind of mark, and returns it. Null if dismissed.
Future<MarkKind?> showMarkSheet(BuildContext context) => showModalBottomSheet<
  MarkKind
>(
  context: context,
  backgroundColor: Colors.transparent,
  builder: (ctx) => Theme(
    data: SmokeTheme.dark,
    child: Builder(
      builder: (ctx) {
        final t = ctx.tokens;
        return Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(SmokeTokens.radiusCard),
            ),
            border: Border.all(color: t.hairline),
          ),
          child: SafeArea(
            child: Column(
              key: const Key('mark-sheet'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(SmokeTokens.s4),
                  child: Row(
                    children: [
                      Text(
                        'Mark this moment',
                        style: SmokeType.displayS.copyWith(color: t.textHi),
                      ),
                    ],
                  ),
                ),
                for (final k in userMarkKinds)
                  ListTile(
                    key: Key('mark-kind-${k.name}'),
                    leading: Icon(markIcon(k), color: t.textBody),
                    title: Text(
                      markLabel(k),
                      style: SmokeType.title.copyWith(color: t.textHi),
                    ),
                    onTap: () => Navigator.of(ctx).pop(k),
                  ),
                const SizedBox(height: SmokeTokens.s2),
              ],
            ),
          ),
        );
      },
    ),
  ),
);
