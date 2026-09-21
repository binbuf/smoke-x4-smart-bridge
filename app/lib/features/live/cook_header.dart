/// N5.4/N5.5 — the cook identity header and the stopwatch.
///
/// The header states the I2 promise in words: "Recording on the bridge — safe
/// even if this phone drops". The stopwatch is **display-only**: pausing it
/// freezes the shown clock and never touches the device's recording (NOTES
/// §7.3). No ticker is owned here — a repeating clock would make
/// `pumpAndSettle` unusable — so the page supplies `now` from
/// `liveNowProvider`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/model/cook_state.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import 'live_format.dart';

/// Food avatar + name + the recording promise + the cook-settings button.
class CookHeaderCard extends StatelessWidget {
  const CookHeaderCard({
    super.key,
    required this.name,
    required this.glyph,
    required this.cook,
    required this.now,
    this.onSettings,
    this.onEditStart,
  });

  final String name;
  final FoodGlyph glyph;
  final CookState cook;
  final DateTime now;
  final VoidCallback? onSettings;
  final VoidCallback? onEditStart;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return SmokeCard(
      key: const ValueKey<String>('live-cook-header'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              FoodAvatar(glyph, register: FoodAvatarRegister.disciplined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      name,
                      key: const ValueKey<String>('live-cook-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SmokeText.cardTitle.copyWith(
                        fontSize: 17,
                        color: tokens.textHi,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        SmokeIcon(
                          SmokeGlyph.lock,
                          size: 12,
                          color: tokens.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Recording on the bridge — safe even if this '
                            'phone drops',
                            key: const ValueKey<String>('live-cook-line'),
                            style: SmokeText.labelSm.copyWith(
                              fontSize: 11.5,
                              color: tokens.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _IconAction(
                key: const ValueKey<String>('live-cook-settings'),
                glyph: SmokeGlyph.sliders,
                label: 'Cook settings',
                onTap: onSettings,
              ),
            ],
          ),
          const SizedBox(height: 14),
          StopwatchCard(cook: cook, now: now, onEditStart: onEditStart),
        ],
      ),
    );
  }
}

/// The `HH:MM:SS` clock with pause/resume and edit-start.
class StopwatchCard extends ConsumerStatefulWidget {
  const StopwatchCard({
    super.key,
    required this.cook,
    required this.now,
    this.onEditStart,
  });

  final CookState cook;
  final DateTime now;
  final VoidCallback? onEditStart;

  @override
  ConsumerState<StopwatchCard> createState() => _StopwatchCardState();
}

class _StopwatchCardState extends ConsumerState<StopwatchCard> {
  /// The elapsed ms captured at the moment of pausing. Pausing freezes the
  /// display at this value; resuming drops it so the clock catches up.
  int? _frozenMs;

  @override
  void didUpdateWidget(StopwatchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.cook.paused) {
      _frozenMs = null;
    }
    if (oldWidget.cook.startedAtMs != widget.cook.startedAtMs) {
      _frozenMs = null;
    }
  }

  int get _elapsedMs {
    final start = widget.cook.startedAtMs;
    if (start == null) {
      return 0;
    }
    if (widget.cook.paused && _frozenMs != null) {
      return _frozenMs!;
    }
    return widget.now.millisecondsSinceEpoch - start;
  }

  Future<void> _toggle() async {
    final repo = ref.read(bridgeRepositoryProvider);
    if (widget.cook.paused) {
      await repo.setCookPaused(false);
      return;
    }
    final start = widget.cook.startedAtMs;
    if (start != null) {
      setState(() {
        _frozenMs = widget.now.millisecondsSinceEpoch - start;
      });
    }
    await repo.setCookPaused(true);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final paused = widget.cook.paused;
    final hue = paused ? tokens.warning : tokens.hairline;

    return Container(
      key: const ValueKey<String>('live-stopwatch'),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: paused ? tokens.tint(tokens.warning, 0.08) : tokens.cardSubtle,
        borderRadius: BorderRadius.circular(tokens.radii.control),
        border: Border.all(color: hue),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Cook time',
                  style: SmokeText.labelSm.copyWith(
                    fontSize: 10.5,
                    letterSpacing: 0.8,
                    color: tokens.textMuted,
                  ),
                ),
                Text(
                  fmtStopwatch(_elapsedMs),
                  key: const ValueKey<String>('live-stopwatch-time'),
                  style: SmokeText.tempMd.copyWith(
                    fontSize: 26,
                    color: paused ? tokens.warning : tokens.textHi,
                  ),
                ),
                Text(
                  'Started ${_startedLabel()}${paused ? ' · paused' : ''}',
                  key: const ValueKey<String>('live-stopwatch-started'),
                  style: SmokeText.labelSm.copyWith(
                    fontSize: 12,
                    color: tokens.textBody,
                  ),
                ),
              ],
            ),
          ),
          _IconAction(
            key: const ValueKey<String>('live-stopwatch-toggle'),
            glyph: paused ? SmokeGlyph.play : SmokeGlyph.pause,
            label: paused ? 'Resume' : 'Pause',
            onTap: _toggle,
          ),
          const SizedBox(width: 6),
          _IconAction(
            key: const ValueKey<String>('live-stopwatch-edit-start'),
            glyph: SmokeGlyph.edit,
            label: 'Adjust start time',
            onTap: widget.onEditStart,
          ),
        ],
      ),
    );
  }

  String _startedLabel() {
    final start = widget.cook.startedAtMs;
    if (start == null) {
      return '—';
    }
    return fmtClock(DateTime.fromMillisecondsSinceEpoch(start));
  }
}

/// A round icon button used by the header and the stopwatch.
class _IconAction extends StatelessWidget {
  const _IconAction({
    super.key,
    required this.glyph,
    required this.label,
    this.onTap,
  });

  final SmokeGlyph glyph;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: tokens.cardRaised,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: tokens.hairlineStrong),
            ),
            child: SmokeIcon(glyph, size: 17, color: tokens.textHi),
          ),
        ),
      ),
    );
  }
}
