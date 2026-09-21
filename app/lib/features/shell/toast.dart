/// N4.9 — transient toast messages.
///
/// The prototype's `toast(msg)` writes one line into `.toast` and clears it
/// after 2.2 s. The Flutter controller does the same, but reads its lifetime
/// from [SmokeMotion.pulse] so no `Duration` literal escapes `lib/design/` and
/// reduced motion never changes how long a message is readable.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/design.dart';

/// Owns the single visible toast message.
class ShellToastController extends ChangeNotifier {
  String? _message;
  Timer? _timer;

  /// The message currently shown, or null.
  String? get message => _message;

  /// Shows [message], replacing any current toast and restarting the timer.
  void show(String message) {
    _message = message;
    _timer?.cancel();
    _timer = Timer(const SmokeMotion().pulse, hide);
    notifyListeners();
  }

  /// Clears the toast immediately.
  void hide() {
    _timer?.cancel();
    _timer = null;
    if (_message == null) {
      return;
    }
    _message = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The toast host, pinned near the bottom of the phone frame.
class ShellToastHost extends StatelessWidget {
  const ShellToastHost({super.key, required this.controller});

  final ShellToastController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final motion = SmokeMotion.of(context);
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 132, left: 24, right: 24),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final message = controller.message;
              return AnimatedSwitcher(
                duration: motion.standardEffective,
                child: message == null
                    ? const SizedBox.shrink()
                    : Container(
                        key: const ValueKey<String>('shell-toast'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.cardRaised,
                          borderRadius: BorderRadius.circular(
                            tokens.radii.control,
                          ),
                          border: Border.all(color: tokens.hairlineStrong),
                        ),
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          style: SmokeText.label.copyWith(color: tokens.textHi),
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}
