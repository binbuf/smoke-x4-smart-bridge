/// N4.1/N4.11 — the phone chrome and the scroll host.
///
/// [ShellPhoneFrame] is the persistent frame every destination lives inside:
/// the simulated system status bar, the app area, the overlay host and the
/// toast host, stacked in that order. It is deliberately *not* a fake bezel —
/// on a real phone the device is the bezel — but it does draw the prototype's
/// status bar (clock, radio, battery) so the reference frame and the device
/// render the same chrome.
///
/// [ShellScrollHost] is the destination scroll surface. It resets to the top
/// when its [resetToken] changes (N4.11), which is the prototype's
/// `$('#view').scrollTop = 0` in `go()`.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

/// The simulated system status bar (`.statusbar`).
class ShellStatusBar extends StatelessWidget {
  const ShellStatusBar({super.key, required this.now});

  /// The instant the status bar renders. No ticker is owned here: a repeating
  /// clock would make `pumpAndSettle` unusable for every golden.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final label = '$hour:${now.minute.toString().padLeft(2, '0')}';

    return SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: <Widget>[
            Text(
              label,
              key: const ValueKey<String>('shell-clock'),
              style: SmokeText.label.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.textHi,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            SmokeIcon(SmokeGlyph.signal, size: 15, color: tokens.textHi),
            const SizedBox(width: 6),
            SmokeIcon(SmokeGlyph.wifi, size: 15, color: tokens.textHi),
            const SizedBox(width: 6),
            const _Battery(),
          ],
        ),
      ),
    );
  }
}

class _Battery extends StatelessWidget {
  const _Battery();

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 22,
          height: 11,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            border: Border.all(color: tokens.textHi, width: 1.4),
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: 0.71,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.textHi,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        Container(
          width: 2,
          height: 5,
          decoration: BoxDecoration(
            color: tokens.textHi,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(2),
              bottomRight: Radius.circular(2),
            ),
          ),
        ),
      ],
    );
  }
}

/// The persistent phone chrome.
class ShellPhoneFrame extends StatelessWidget {
  const ShellPhoneFrame({
    super.key,
    required this.now,
    required this.child,
    this.overlay,
    this.toast,
  });

  final DateTime now;

  /// The app area: app bar, scroll host and bottom nav.
  final Widget child;

  /// Mounted above the app area (and above the fullscreen graph).
  final Widget? overlay;

  /// Mounted above everything.
  final Widget? toast;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Material(
      color: tokens.bg,
      child: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              ShellStatusBar(now: now),
              Expanded(child: child),
            ],
          ),
          if (overlay != null) Positioned.fill(child: overlay!),
          if (toast != null) Positioned.fill(child: toast!),
        ],
      ),
    );
  }
}

/// The destination scroll surface, reset on [resetToken] change (N4.11).
class ShellScrollHost extends StatefulWidget {
  const ShellScrollHost({
    super.key,
    required this.resetToken,
    required this.child,
  });

  final Object resetToken;
  final Widget child;

  @override
  State<ShellScrollHost> createState() => _ShellScrollHostState();
}

class _ShellScrollHostState extends State<ShellScrollHost> {
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(ShellScrollHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken && _controller.hasClients) {
      _controller.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Scrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        key: const ValueKey<String>('shell-scroll'),
        controller: _controller,
        padding: EdgeInsets.fromLTRB(
          tokens.density.pageGutter,
          4,
          tokens.density.pageGutter,
          104,
        ),
        child: widget.child,
      ),
    );
  }
}
