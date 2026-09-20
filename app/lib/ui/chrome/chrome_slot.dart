/// The reveal every piece of shell chrome shares (newapp §H.2).
///
/// Four things ride above every tab — the status bar, the alarm, a failed
/// refresh, and whatever situation the reconciler names — and before this they
/// were four full-bleed strips that appeared by *jumping the layout down*. Three
/// of them stacked read as an accident rather than as a decision, and each one
/// arriving shoved the temperatures the user was reading.
///
/// [ChromeSlot] is the fix, and it is one widget so the rhythm cannot drift:
///
///  * **always mounted, zero height when silent.** A healthy screen shows no
///    chrome about health at all, but the slot is still in the tree, so the
///    notice animates in rather than teleporting;
///  * **it grows downward under a clip**, so a banner slides out from beneath
///    the bezel instead of expanding from its own middle;
///  * **it cross-fades**, so replacing one notice with a louder one is a
///    substitution rather than a flicker of nothing in between;
///  * **the whole thing collapses to an instant swap under reduced motion**,
///    because every duration it uses comes from [SmokeMotion.of] and there is
///    not a `Duration` literal in this layer to defeat it.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

class ChromeSlot extends StatelessWidget {
  const ChromeSlot({super.key, this.child, this.padding = EdgeInsets.zero});

  /// Null → the slot is silent and takes no height.
  final Widget? child;

  /// Applied **inside** the slot, so it collapses with the content. Padding
  /// outside a collapsing banner is a stripe of dead space on a healthy
  /// screen, which is the tell that the chrome was bolted on.
  final EdgeInsetsGeometry padding;

  /// The notice, padded and capped. Capped because a notice stretched across
  /// an unfolded Fold is a strip the eye has to traverse rather than a thing
  /// it takes in — [SmokeWindow.noticeMax], and aligned to the start so it
  /// sits under the bezel's chip rather than floating in the middle of a
  /// window with nothing above it.
  Widget _content(Widget c) => Padding(
    padding: padding,
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: SmokeWindow.noticeMax),
        child: c,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final motion = SmokeMotion.of(context);
    final c = child;

    // Reduced motion: hand back the notice itself, with no animator between.
    // `AnimatedSize` at `Duration.zero` does not merely finish instantly — it
    // re-dirties its own layout inside `performLayout` and throws, so the
    // "just set the duration to zero" reading of the motion tokens is a
    // crash on exactly the accessibility path it was meant to serve.
    if (motion.standard == Duration.zero) {
      return c == null
          ? const SizedBox(width: double.infinity)
          : _content(c);
    }

    return ClipRect(
      child: AnimatedSize(
        duration: motion.standard,
        curve: motion.curve,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: motion.standard,
          switchInCurve: motion.curve,
          switchOutCurve: motion.curve,
          // Layout, not stack: an outgoing notice must not hold the height of
          // the incoming one, or the collapse stutters.
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          // Explicit keys: `AnimatedSwitcher` compares runtimeType *and* key,
          // and two notices of the same type would otherwise swap in place
          // with no transition at all.
          //
          // Deliberately `ValueKey<bool>` rather than a string: the goldens
          // describe every `ValueKey<String>` they meet, and a slot's internal
          // plumbing appearing on every screen's snapshot is noise that makes
          // the real diffs harder to read.
          child: c == null
              ? const SizedBox(key: ValueKey(false), width: double.infinity)
              : KeyedSubtree(key: const ValueKey(true), child: _content(c)),
        ),
      ),
    );
  }
}
