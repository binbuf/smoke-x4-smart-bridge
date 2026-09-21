/// N5.12/N5.13 (and the N5.3 adopt confirm) — the Live overlay bodies.
///
/// These are the real contents behind `?overlay=mark`, `?overlay=editStart` and
/// `?overlay=adopt`. Each takes the host's `onDone` so it can apply an action
/// and close without importing the shell. All of them are repository-backed and
/// mutate only the snapshot.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import 'live_format.dart';
import 'live_page.dart';

/// One row in the mark sheet's kind grid.
const List<({MarkKind kind, SmokeGlyph glyph, String label})> kMarkKinds = [
  (kind: MarkKind.note, glyph: SmokeGlyph.bookmark, label: 'Note'),
  (kind: MarkKind.wrapped, glyph: SmokeGlyph.wrap, label: 'Wrapped'),
  (kind: MarkKind.spritz, glyph: SmokeGlyph.droplet, label: 'Spritzed'),
  (kind: MarkKind.turn, glyph: SmokeGlyph.rotate, label: 'Turned'),
  (kind: MarkKind.lidOpen, glyph: SmokeGlyph.package, label: 'Lid open'),
  (kind: MarkKind.fuel, glyph: SmokeGlyph.flame, label: 'Added fuel'),
  (
    kind: MarkKind.probeMoved,
    glyph: SmokeGlyph.thermometer,
    label: 'Probe moved',
  ),
  (
    kind: MarkKind.phaseChange,
    glyph: SmokeGlyph.activity,
    label: 'Phase change',
  ),
];

/// N5.13 — the mark sheet: eight kinds plus an optional note.
class MarkSheetBody extends ConsumerStatefulWidget {
  const MarkSheetBody({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<MarkSheetBody> createState() => _MarkSheetBodyState();
}

class _MarkSheetBodyState extends ConsumerState<MarkSheetBody> {
  MarkKind _kind = MarkKind.note;
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(bridgeRepositoryProvider);
    await repo.mark(kind: _kind, text: _note.text.trim());
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Log what just happened. Marks appear on the graph and the timeline.',
          style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final entry in kMarkKinds)
              _KindButton(
                key: ValueKey<String>('mark-kind-${entry.kind.name}'),
                glyph: entry.glyph,
                label: entry.label,
                selected: entry.kind == _kind,
                onTap: () => setState(() => _kind = entry.kind),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Add a note (optional)',
          style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey<String>('mark-note'),
          controller: _note,
          minLines: 2,
          maxLines: 3,
          style: SmokeText.body.copyWith(color: tokens.textHi),
          decoration: InputDecoration(
            hintText: 'Wrapped the brisket in butcher paper…',
            hintStyle: SmokeText.body.copyWith(color: tokens.textMuted),
            filled: true,
            fillColor: tokens.well,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(tokens.radii.control),
              borderSide: BorderSide(color: tokens.hairlineStrong),
            ),
          ),
        ),
        const SizedBox(height: 16),
        PrimaryAction(
          key: const ValueKey<String>('mark-save'),
          label: 'Save mark',
          icon: SmokeGlyph.check,
          onPressed: _save,
        ),
      ],
    );
  }
}

class _KindButton extends StatelessWidget {
  const _KindButton({
    super.key,
    required this.glyph,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final SmokeGlyph glyph;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return SizedBox(
      width: 76,
      child: Material(
        color: selected ? tokens.tint(tokens.pit, 0.15) : tokens.cardSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radii.control),
          side: BorderSide(
            color: selected ? tokens.tint(tokens.pit, 0.4) : tokens.hairline,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.radii.control),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SmokeIcon(glyph, size: 22, color: tokens.textBody),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SmokeText.labelSm.copyWith(
                    fontSize: 10.5,
                    color: tokens.textHi,
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

/// N5.12 — quick start offsets. Moving the window never rewrites samples.
class EditStartBody extends ConsumerWidget {
  const EditStartBody({super.key, required this.onDone});

  final VoidCallback onDone;

  static const List<({String label, int minutes})> offsets = [
    (label: 'Just now', minutes: 0),
    (label: '30 min ago', minutes: 30),
    (label: '1 hour ago', minutes: 60),
    (label: '2 hours ago', minutes: 120),
    (label: '4 hours ago', minutes: 240),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final cook = ref.watch(snapshotProvider).value?.cook;
    final now = ref.watch(liveNowProvider);
    final repo = ref.watch(bridgeRepositoryProvider);
    final start = cook?.startedAtMs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'When did the cook actually start?',
          style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final offset in offsets)
              SmokeButton(
                key: ValueKey<String>('edit-start-${offset.minutes}'),
                label: offset.label,
                size: SmokeButtonSize.sm,
                onPressed: () async {
                  final target =
                      now.millisecondsSinceEpoch - offset.minutes * 60000;
                  await repo.setCookStart(target);
                  onDone();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        SmokeCard(
          inset: true,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Current start',
                style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: 2),
              Text(
                start == null
                    ? '—'
                    : fmtClock(DateTime.fromMillisecondsSinceEpoch(start)),
                key: const ValueKey<String>('edit-start-current'),
                style: SmokeText.bodyStrong.copyWith(color: tokens.textHi),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        CapabilityNotice(
          message:
              'Changing the start only moves the cook window. The recorded '
              'samples are never rewritten.',
        ),
      ],
    );
  }
}

/// N5.3 — the adopt confirmation summary.
class AdoptSessionBody extends ConsumerWidget {
  const AdoptSessionBody({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final pending = ref.watch(snapshotProvider).value?.pendingSession;
    final now = ref.watch(liveNowProvider);
    if (pending == null) {
      return Text(
        'No session is waiting to be adopted.',
        key: const ValueKey<String>('adopt-session-body'),
        style: SmokeText.body.copyWith(color: tokens.textBody),
      );
    }
    final elapsed = now.millisecondsSinceEpoch - pending.startedAtMs;
    return Column(
      key: const ValueKey<String>('adopt-session-body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text.rich(
          TextSpan(
            style: SmokeText.body.copyWith(color: tokens.textBody),
            children: <InlineSpan>[
              const TextSpan(text: 'The bridge recorded '),
              TextSpan(
                text: '${pending.samples} samples',
                style: SmokeText.bodyStrong.copyWith(color: tokens.textHi),
              ),
              const TextSpan(text: ' over '),
              TextSpan(
                text: fmtDuration(elapsed),
                style: SmokeText.bodyStrong.copyWith(color: tokens.textHi),
              ),
              TextSpan(
                text:
                    ' with ${pending.probeCount} probes attached. Adopting '
                    'keeps every one of them and starts the cook at ',
              ),
              TextSpan(
                text: fmtClock(
                  DateTime.fromMillisecondsSinceEpoch(pending.startedAtMs),
                ),
                style: SmokeText.bodyStrong.copyWith(color: tokens.textHi),
              ),
              const TextSpan(text: '.'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SmokeCard(
          inset: true,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _AdoptFact(label: 'Recording continues', value: 'Yes'),
              const SizedBox(height: 6),
              _AdoptFact(label: 'Existing samples', value: 'Kept'),
              const SizedBox(height: 6),
              _AdoptFact(
                label: 'Start time',
                value: fmtClock(
                  DateTime.fromMillisecondsSinceEpoch(pending.startedAtMs),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdoptFact extends StatelessWidget {
  const _AdoptFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
          ),
        ),
        Text(value, style: SmokeText.bodyStrong.copyWith(color: tokens.textHi)),
      ],
    );
  }
}

/// N5.3 — the adopt modal's action row.
class AdoptSessionActions extends ConsumerWidget {
  const AdoptSessionActions({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(snapshotProvider).value?.pendingSession;
    final repo = ref.watch(bridgeRepositoryProvider);
    return Row(
      children: <Widget>[
        Expanded(
          child: PrimaryAction(
            key: const ValueKey<String>('live-adopt-confirm'),
            label: 'Adopt',
            icon: SmokeGlyph.download,
            enabledReason: pending == null
                ? 'No session is waiting to be adopted.'
                : null,
            onPressed: pending == null
                ? null
                : () async {
                    await repo.adoptSession();
                    onDone();
                  },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SmokeButton(
            key: const ValueKey<String>('live-adopt-cancel'),
            label: 'Cancel',
            variant: SmokeButtonVariant.ghost,
            onPressed: onDone,
          ),
        ),
      ],
    );
  }
}
