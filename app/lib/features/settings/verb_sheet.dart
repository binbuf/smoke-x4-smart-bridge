/// N13.13/N13.20 — the verb-progress sheet.
///
/// One shared sheet for restart / forget / factory / OTA. It names every step
/// as it completes and applies the scenario mutation **on the last step**, then
/// reports what the bridge actually did by reading the resulting snapshot back
/// (I7 — verify by behaviour, not by a return value).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repository/bridge_repository.dart';
import '../../design/design.dart';
import 'settings_format.dart';

/// The body behind `?overlay=verb&kind=<id>` (N13.20).
class VerbSheetBody extends ConsumerStatefulWidget {
  const VerbSheetBody({super.key, required this.onDone, this.kind});

  final VoidCallback onDone;

  /// The `kind` prop; null renders a passive sheet (no run, no mutation).
  final String? kind;

  @override
  ConsumerState<VerbSheetBody> createState() => _VerbSheetBodyState();
}

class _VerbSheetBodyState extends ConsumerState<VerbSheetBody> {
  Timer? _timer;
  int _step = 0;
  bool _done = false;
  bool _started = false;

  DeviceVerb? get _verb => verbFromId(widget.kind);

  VerbSpec? get _spec {
    final verb = _verb;
    return verb == null ? null : verbSpec(verb);
  }

  /// N16.4 — the step pace is a motion token, so reduced motion zeroes it.
  Duration get _stepDelay => SmokeMotion.of(context).valueEffective;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && _spec != null) {
      _started = true;
      _timer = Timer(_stepDelay, _advance);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _advance() {
    final spec = _spec;
    if (spec == null || _done) {
      return;
    }
    setState(() => _step += 1);
    if (_step >= spec.steps.length) {
      unawaited(_apply(spec));
    } else {
      _timer = Timer(_stepDelay, _advance);
    }
  }

  Future<void> _apply(VerbSpec spec) async {
    final verb = spec.verb;
    final force =
        verb == DeviceVerb.ota && ref.read(prefsProvider).current.forceOta;
    await ref.read(bridgeRepositoryProvider).performVerb(verb, force: force);
    if (!mounted) {
      return;
    }
    setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    if (spec == null) {
      final tokens = SmokeTokens.of(context);
      return Text(
        'A device action starts this sheet.',
        key: const ValueKey<String>('verb-passive'),
        style: SmokeText.sub.copyWith(color: tokens.textBody),
      );
    }
    // Watch so the read-back line updates the moment the mutation lands (I7).
    final notice = ref.watch(snapshotProvider).value?.notice;
    final tokens = SmokeTokens.of(context);
    final steps = spec.steps;
    final readback = notice ?? spec.sub;

    return Column(
      key: const ValueKey<String>('verb-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Center(
          child: SmokeIcon(
            _done ? SmokeGlyph.check : SmokeGlyph.refresh,
            size: 30,
            color: _done ? tokens.positive : tokens.textBody,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _done ? 'Done' : spec.title,
                key: const ValueKey<String>('verb-title'),
                textAlign: TextAlign.center,
                style: SmokeText.cardTitle.copyWith(
                  fontSize: 18,
                  color: tokens.textHi,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _done ? 'All steps finished' : spec.sub,
                textAlign: TextAlign.center,
                style: SmokeText.sub.copyWith(color: tokens.textBody),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SmokeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < steps.length; i++)
                _VerbStep(
                  key: ValueKey<String>('verb-step-$i'),
                  label: steps[i],
                  done: _done || i < _step,
                  active: !_done && i == _step,
                ),
            ],
          ),
        ),
        if (_done) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            readback,
            key: const ValueKey<String>('verb-readback'),
            textAlign: TextAlign.center,
            style: SmokeText.labelSm.copyWith(
              fontSize: 12,
              color: tokens.textBody,
            ),
          ),
          const SizedBox(height: 12),
          PrimaryAction(
            key: const ValueKey<String>('verb-close'),
            label: 'Close',
            icon: SmokeGlyph.check,
            onPressed: widget.onDone,
          ),
        ] else ...<Widget>[
          const SizedBox(height: 14),
          Text(
            'Keep the app open…',
            key: const ValueKey<String>('verb-keep-open'),
            textAlign: TextAlign.center,
            style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
          ),
        ],
      ],
    );
  }
}

class _VerbStep extends StatelessWidget {
  const _VerbStep({
    super.key,
    required this.label,
    required this.done,
    required this.active,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final hue = done
        ? tokens.positive
        : active
        ? tokens.textHi
        : tokens.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 20,
            child: done
                ? SmokeIcon(SmokeGlyph.check, size: 14, color: tokens.positive)
                : Text(
                    active ? '●' : '',
                    style: SmokeText.label.copyWith(color: tokens.textHi),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: SmokeText.label.copyWith(fontSize: 12.5, color: hue),
            ),
          ),
        ],
      ),
    );
  }
}
