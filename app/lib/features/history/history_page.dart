/// N12.1–N12.4 — the History destination.
///
/// Past cooks as annotations over the continuous recording: the educational
/// notice, the This week / Earlier groups and the cook cards. It owns no
/// business state: the list comes from [historyGroupsProvider] and every
/// mutation goes through the repository seam.
///
/// Invariants encoded here:
/// * **I10** — the annotation-over-recording notice stays on screen.
/// * **I14** — exactly one ember primary action ("Start a new cook").
/// * **I6** — an empty history has one way forward.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/model/history_entry.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import '../live/live_format.dart';
import '../shell/phone_frame.dart';
import '../shell/shell.dart';
import '../shell/shell_screen.dart';
import 'history_format.dart';
import 'history_model.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final groups = ref.watch(historyGroupsProvider);
    final unit = ref.watch(historyUnitProvider);
    final scope = ShellScope.maybeOf(context);

    if (!history.hasValue) {
      return const LoadingState(
        title: 'Reading the cache',
        copy: 'Waiting for the first history read.',
        actionLabel: 'Retry',
        onAction: _noop,
      );
    }

    return ShellScrollHost(
      resetToken: ShellScreen.history,
      child: Column(
        key: const ValueKey<String>('history-page'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (groups.isNotEmpty)
            PrimaryAction(
              key: const ValueKey<String>('history-start'),
              label: 'Start a new cook',
              icon: SmokeGlyph.plus,
              onPressed: () => scope?.openOverlay(DevOverlay.setup),
            ),
          const SizedBox(height: 12),
          // N12.2 — the annotation-over-recording promise, always on screen.
          const CapabilityNotice(
            key: ValueKey<String>('history-notice'),
            message:
                'Every cook is an annotation over one continuous recording. '
                'The bridge records even when this app is closed — you never '
                'lose the gap.',
          ),
          const SizedBox(height: 8),
          if (groups.isEmpty)
            EmptyState(
              key: const ValueKey<String>('history-empty'),
              icon: SmokeGlyph.history,
              title: 'No cooks yet',
              copy:
                  'Your past cooks appear here as annotations over the '
                  'bridge’s recording. Start one and it will show up.',
              actionLabel: 'Start a cook',
              onAction: () => scope?.openOverlay(DevOverlay.setup),
            )
          else
            for (final group in groups) ...<Widget>[
              SectionLabel(
                label: group.group.label,
                trailing: Text(
                  '${group.entries.length}',
                  key: ValueKey<String>(
                    'history-group-count-${group.group.name}',
                  ),
                  style: SmokeText.labelSm.copyWith(
                    color: SmokeTokens.of(context).textMuted,
                  ),
                ),
              ),
              Column(
                key: ValueKey<String>('history-group-${group.group.name}'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final entry in group.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CookCard(entry: entry, unit: unit),
                    ),
                ],
              ),
            ],
        ],
      ),
    );
  }
}

/// N12.4 — one cook card.
class _CookCard extends StatelessWidget {
  const _CookCard({required this.entry, required this.unit});

  final HistoryEntry entry;
  final TempUnit unit;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final scope = ShellScope.maybeOf(context);
    return SmokeCard(
      key: ValueKey<String>('history-card-${entry.id}'),
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      onTap: () => scope?.openCookDetail(entry.id),
      child: Row(
        children: <Widget>[
          FoodAvatar(FoodGlyph.parse(entry.glyph)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        entry.name,
                        key: ValueKey<String>('history-card-name-${entry.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SmokeText.bodyStrong.copyWith(
                          fontSize: 14,
                          color: tokens.textHi,
                        ),
                      ),
                    ),
                    if (entry.favourite) ...<Widget>[
                      const SizedBox(width: 5),
                      SmokeIcon(
                        SmokeGlyph.star,
                        size: 13,
                        color: tokens.warning,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  cookCardFacts(entry).join(' · '),
                  key: ValueKey<String>('history-card-sub-${entry.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SmokeText.labelSm.copyWith(
                    fontSize: 11.5,
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '${fmtTemp0(entry.peakF10, unit)}${unit.suffix}',
                key: ValueKey<String>('history-card-peak-${entry.id}'),
                style: SmokeText.monoValue.copyWith(color: tokens.textHi),
              ),
              Text(
                'PEAK',
                style: SmokeText.labelSm.copyWith(
                  fontSize: 9.5,
                  letterSpacing: 0.5,
                  color: tokens.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(width: 2),
          SmokeIcon(SmokeGlyph.chevronRight, color: tokens.textMuted),
        ],
      ),
    );
  }
}

void _noop() {}
