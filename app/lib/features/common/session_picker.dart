/// A compact session selector shared by the Graph and History tabs.
library;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/domain.dart';

class SessionPicker extends StatelessWidget {
  const SessionPicker({
    super.key,
    required this.sessions,
    required this.selected,
    required this.onChanged,
  });

  final List<SessionInfo> sessions;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    // A stale selection (the session set was replaced) must not crash the
    // dropdown; fall back to the newest session.
    final value = sessions.any((s) => s.id == selected)
        ? selected
        : sessions.first.id;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SmokeSpace.md,
        vertical: SmokeSpace.xs,
      ),
      decoration: BoxDecoration(
        color: SmokePalette.card,
        borderRadius: BorderRadius.circular(SmokeRadius.control),
        border: Border.all(color: SmokePalette.hairline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: value,
          icon: const Icon(Icons.expand_more, color: SmokePalette.textMuted),
          dropdownColor: SmokePalette.cardRaised,
          style: const TextStyle(
            color: SmokePalette.textHi,
            fontSize: 14,
            fontFamily: 'Inter',
          ),
          items: [
            for (final s in sessions)
              DropdownMenuItem(
                value: s.id,
                child: Text(_label(s), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) {
              onChanged(v);
            }
          },
        ),
      ),
    );
  }
}

String _label(SessionInfo s) {
  final name = s.name.isEmpty ? 'Session #${s.id}' : s.name;
  final state = s.closed ? 'closed' : 'recording';
  return '$name · $state';
}
