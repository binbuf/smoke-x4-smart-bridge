/// The shell's session, reachable from anything below it (design 13 §13.3.2).
///
/// Needed the moment the router became a `StatefulShellRoute`: the branch
/// builders construct the tab widgets, so the shell can no longer hand each one
/// its session through a constructor. The session is a [ChangeNotifier] and the
/// whole tree already rebuilds on it, so an [InheritedNotifier] is the exact
/// fit — a tab that reads it rebuilds when the snapshot moves, and one that
/// does not, does not.
///
/// [maybeOf] rather than a throwing `of`: several of these screens are also
/// mounted directly by tests and by the legacy flat routes, with no shell
/// above them. Those render their last-known/offline branch, which is a state
/// they all have to support anyway.
library;

import 'package:flutter/material.dart';

import 'shell_session.dart';

class ShellScope extends InheritedNotifier<ShellSession> {
  const ShellScope({
    required ShellSession session,
    required this.activeIndex,
    required super.child,
    super.key,
  }) : super(notifier: session);

  /// Which branch is on screen. All four stay mounted once visited, so
  /// "mounted" is not "visible" — and a screen that wakes a radio (the Bridge
  /// tab's signal poll) must not do it from behind three other tabs.
  final int activeIndex;

  ShellSession get session => notifier!;

  /// The ambient session, or null when this subtree is not under a shell.
  static ShellSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>()?.notifier;

  /// Whether the branch at [index] is the visible one. True with no shell
  /// above (a direct-mount test), where there is nothing to hide behind.
  static bool isActive(BuildContext context, int index) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>()?.activeIndex ==
          index ||
      context.getInheritedWidgetOfExactType<ShellScope>() == null;

  /// Read the session **without** subscribing to its changes — for callbacks
  /// and one-shot reads, where rebuilding on every snapshot would be waste.
  static ShellSession? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellScope>()?.notifier;

  @override
  bool updateShouldNotify(covariant ShellScope oldWidget) =>
      super.updateShouldNotify(oldWidget) ||
      oldWidget.activeIndex != activeIndex;
}
