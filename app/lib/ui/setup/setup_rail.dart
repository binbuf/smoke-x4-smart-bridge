/// A23.2 — SetupRail (design 14 §14.7.4, and the hop model in 13 §13.2).
///
/// The three-circle progress rail for `/setup`. It exists to keep ~34 setup
/// states legible as **three hops** — phone↔bridge (BLE), bridge↔Smoke X (LoRa),
/// bridge↔network (Wi-Fi) — no matter how many failure branches sit under each.
///
/// Two design facts drive the whole widget:
///
/// * **hop 0 is preflight, not a step.** It precedes hop 1 and has no active
///   circle. All `of` circles render dimmed at 45 %, and the rail carries the
///   eyebrow *Before we start* instead of a lit ring (§14.7.4). Inventing a
///   fourth circle would tell the user they had failed a step they never
///   reached.
/// * **a failure is a bad hop, not a fourth hop.** [errorTint] recolours the
///   **active** circle to `StatusPalette.critical` — the ring and its glow, not
///   the digit inside, which is ink in every state (§14.6.5). At hop 0, where
///   there is no circle to recolour, it recolours the eyebrow instead
///   (§14.7.4): that is the *one* place a status hue is allowed to carry a word
///   here, because at preflight there is no ring to put it on. That is the
///   whole reason the error states stay countable as three.
///
/// A **skipped** hop (a bridge already bonded to a base skips hop 2) renders as
/// done with a *dash*, never a tick it did not earn.
///
/// ## The connector carries the progress (17 §17.5)
///
/// The rail used to draw one flat `chromeDim` line behind three circles, so the
/// only thing that said *how far in you are* was which circle happened to be
/// lit. §17.5 lifts the austerity where there is no live state to lie about —
/// setup has no session and no readings — so the connector is now **filled with
/// ember up to the hop you have reached** and neutral beyond it. It is a
/// progress bar, and it reads as one from across the room.
///
/// It is not the *only* thing saying so: the hops behind carry a tick, the
/// current one carries its numeral in a lit ring, and the ones ahead are dim
/// with a plain numeral. Remove the colour and the rail still reads (§17.5's
/// colour-blind clause). And the digit stays ink in every state — that is
/// §14.6.5 and a sibling test pins it.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

/// How one circle is drawn. Derived from `hop`/`skipped`, never passed in.
enum _Circle { done, doneSkipped, active, activeError, inactive }

class SetupRail extends StatelessWidget {
  const SetupRail({
    super.key,
    required this.hop,
    required this.of,
    required this.errorTint,
    required this.skipped,
  }) : assert(hop >= 0 && hop <= of, 'hop must be in 0..of');

  /// 0 = preflight, 1..[of] = a real hop.
  final int hop;

  /// How many circles. A parameter only so the rail is testable and a hop can
  /// be skipped — three ship.
  final int of;

  /// Recolour the active circle (or, at hop 0, the eyebrow) to `critical`.
  final bool errorTint;

  /// 1-based hop indices that were skipped with a stated consequence. They
  /// render done-with-a-dash.
  final Set<int> skipped;

  static const double _size = 30;
  static const double _stroke = 2;

  _Circle _stateFor(int i) {
    if (hop == 0) {
      return _Circle.inactive;
    }
    if (skipped.contains(i)) {
      return _Circle.doneSkipped;
    }
    if (i < hop) {
      return _Circle.done;
    }
    if (i == hop) {
      return errorTint ? _Circle.activeError : _Circle.active;
    }
    return _Circle.inactive;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // How much of the connector is behind the user, 0..1. Hop 0 (preflight) is
    // *before* step one, so nothing is filled; the last hop fills it all.
    final progress = hop <= 0 || of <= 1
        ? 0.0
        : ((hop - 1) / (of - 1)).clamp(0.0, 1.0);

    final circles = SizedBox(
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The connector, from the centre of the first circle to the centre of
          // the last. `chromeDim` is the sanctioned gap-connector ink; the
          // travelled part of it is ember, which is what makes the rail a
          // progress bar rather than three dots (§17.5).
          Positioned(
            left: _size / 2,
            right: _size / 2,
            top: (_size - _stroke) / 2,
            child: SizedBox(
              height: _stroke,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: t.chromeDim),
                  FractionallySizedBox(
                    key: const Key('setup-rail-progress'),
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: errorTint
                            ? StatusPalette.critical
                            : StatusPalette.pit,
                        boxShadow: [
                          ?t.glowTight(
                            errorTint
                                ? StatusPalette.critical
                                : StatusPalette.pit,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 1; i <= of; i++)
                _RailCircle(
                  key: Key('setup-rail-circle-$i'),
                  index: i,
                  state: _stateFor(i),
                ),
            ],
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hop == 0) ...[
          Text(
            'Before we start'.toUpperCase(),
            key: const Key('setup-rail-eyebrow'),
            textAlign: TextAlign.center,
            style: SmokeType.label.copyWith(
              color: errorTint ? StatusPalette.critical : t.textMuted,
            ),
          ),
          const SizedBox(height: SmokeTokens.s2),
          // The circles are dimmed at preflight; the eyebrow above carries the
          // signal, so it stays at full strength.
          Opacity(opacity: 0.45, child: circles),
        ] else
          circles,
      ],
    );
  }
}

class _RailCircle extends StatelessWidget {
  const _RailCircle({super.key, required this.index, required this.state});

  final int index;
  final _Circle state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    late final Color fill;
    late final Color border;
    late final Widget content;
    var shadow = const <BoxShadow>[];

    TextStyle numStyle(Color c) =>
        SmokeType.label.copyWith(color: c, letterSpacing: 0, height: 1);

    switch (state) {
      case _Circle.done:
        fill = StatusPalette.pit;
        border = StatusPalette.pit;
        content = const Icon(
          Icons.check_rounded,
          size: 16,
          color: StatusPalette.onPit,
        );
      case _Circle.doneSkipped:
        fill = StatusPalette.pit;
        border = StatusPalette.pit;
        // Done with a dash, not a tick — a skipped hop earned no checkmark.
        content = const Icon(
          Icons.remove_rounded,
          size: 16,
          color: StatusPalette.onPit,
        );
      // The two lit states put the hue on the **ring and the glow**, and the
      // digit stays ink. §14.7.4 specifies the circle — *"a 2 dp `pit` ring
      // with `glow(pit)`"*, *"`errorTint` recolours the active circle"* — and
      // says nothing about the number, while §14.6.5 and this widget's own
      // sibling do: *"the title is never tinted — the status hue rides the
      // icon and the border, never the words"* (`setup_scaffold.dart`). A
      // tinted digit was the one half of this component following the opposite
      // rule to the other half; it also stated a failure in hue alone, with no
      // icon anywhere in the circle to survive a colour-blind reader. The
      // failure's *word* is on the scaffold above, in the title.
      // The lit fill is §17.5's licence spent where it is cheapest: an ember
      // wash inside the ring, so the current step reads as *warm* rather than
      // as an empty circle. The digit on top of it stays ink.
      case _Circle.active:
        fill = StatusPalette.fill(StatusRole.pit);
        border = StatusPalette.pit;
        shadow = [?t.glow(StatusPalette.pit)];
        content = Text('$index', style: numStyle(t.textHi));
      case _Circle.activeError:
        fill = StatusPalette.fill(StatusRole.critical);
        border = StatusPalette.critical;
        shadow = [?t.glow(StatusPalette.critical)];
        content = Text('$index', style: numStyle(t.textHi));
      case _Circle.inactive:
        fill = t.cardSubtle;
        border = t.hairlineStrong;
        content = Text('$index', style: numStyle(t.textMuted));
    }

    return Container(
      width: SetupRail._size,
      height: SetupRail._size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: SetupRail._stroke),
        boxShadow: shadow,
      ),
      child: content,
    );
  }
}
