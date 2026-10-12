/// The cook start-time control.
///
/// The bridge records continuously whether or not anyone is cooking, so a
/// "cook" here is just a clock: start it now and the device's OLED shows how
/// long it has been running. There is nothing to end — clearing only blanks the
/// clock, it never stops a recording.
///
/// While a cook is running the card ticks once a second, so it reads the same
/// on the phone as on the bridge's screen rather than freezing at whatever
/// second it was last fetched.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../design/format.dart';
import '../../design/primitives.dart';
import '../../design/tokens.dart';

class CookClockCard extends StatefulWidget {
  const CookClockCard({super.key, required this.controller});

  final BridgeController controller;

  @override
  State<CookClockCard> createState() => _CookClockCardState();
}

class _CookClockCardState extends State<CookClockCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _retune();
  }

  @override
  void didUpdateWidget(CookClockCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _retune();
  }

  /// Starts or stops the one-second ticker with the running state. Called from
  /// the lifecycle only, never from `build` (it starts timers).
  void _retune() {
    if (widget.controller.cookRunning) {
      _ticker ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.controller.cookRunning;
    final elapsed = widget.controller.cookElapsedS ?? 0;

    return SmokeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cook clock',
            style: TextStyle(
              color: SmokePalette.textHi,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SmokeSpace.sm),
          Text(
            running ? formatElapsed(elapsed) : 'Not started',
            style: TextStyle(
              color: running ? SmokePalette.textHi : SmokePalette.textMuted,
              fontFamily: running ? 'JetBrainsMono' : null,
              fontSize: running ? 24 : 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: SmokeSpace.sm),
          // The honesty the card was missing: "Start" reads like a recording
          // boundary, but the bridge records continuously on its own. Say what
          // the clock is, and say that History is not split by it, so a user is
          // never surprised by a missing History entry.
          const Text(
            'This is a clock the bridge shows on its screen. Your bridge '
            'records continuously, whether or not it is running — History is '
            'that recording, not a new cook.',
            style: TextStyle(
              color: SmokePalette.textBody,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: SmokeSpace.md),
          Row(
            children: [
              FilledButton.icon(
                onPressed: widget.controller.connected
                    ? () => widget.controller.startCook()
                    : null,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(running ? 'Restart clock' : 'Start clock'),
              ),
              const SizedBox(width: SmokeSpace.sm),
              if (running)
                TextButton(
                  onPressed: widget.controller.connected
                      ? () => widget.controller.clearCook()
                      : null,
                  child: const Text('Clear'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
