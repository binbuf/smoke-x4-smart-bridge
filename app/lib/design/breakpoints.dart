/// Window classes and foldable posture — the adaptive layer (design 13 §13.3).
///
/// Nothing in this app was adaptive before this file: five `LayoutBuilder`s
/// existed and all five sized a widget against its own parent. On a 7.6"
/// unfolded Fold the shell rendered a stretched phone — a 240 px chart marooned
/// in the middle of a tablet.
///
/// The strategic point, and the reason the rules below are not the usual
/// "more columns at 600 dp": **this app is a monitor, not a task app.** It is
/// watched from across a room, propped on a counter, for fourteen hours. Extra
/// width must therefore buy *one screen that answers everything without
/// navigating*, not density. Two rules fall out of that and are enforced here:
///
///  * the **chart** is what grows (it is the artifact people read and share);
///  * the **probe readouts do not** — a 90 dp temperature stretched across
///    900 dp reads as a broken layout, not a big number, so callers cap their
///    content column at [readableMax] and give the remainder to the chart.
///
/// Postures come from `MediaQuery.displayFeatures`, which is real on a Fold and
/// simply empty everywhere else — so a phone, an emulator and the widget suite
/// all take the `flat` path with no branching at the call site.
library;

import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';

/// Material 3's three width classes. The names are theirs; the thresholds are
/// theirs; what each one *buys* in this app is decided in [SmokeWindow].
enum SmokeWindowClass {
  /// < 600 dp — a phone held normally, and the Fold closed.
  compact,

  /// 600–839 dp — the Fold opened, a small tablet, a large phone in landscape.
  medium,

  /// ≥ 840 dp — a tablet, a desktop window, the Fold opened in landscape.
  expanded,
}

/// How the device is physically folded right now.
enum SmokePosture {
  /// One flat display: every phone, every tablet, and a foldable fully open
  /// or fully closed.
  flat,

  /// Half-open with a **horizontal** hinge — the device is standing on a
  /// surface like a tiny laptop. The best posture this product has: chart
  /// above the fold, readouts below, no stand required.
  tabletop,

  /// Half-open with a **vertical** hinge — held like a book. Two side-by-side
  /// pages, so panes snap to the hinge rather than to a percentage.
  book,
}

/// The resolved adaptive facts for the current frame.
@immutable
class SmokeWindow {
  const SmokeWindow({
    required this.size,
    required this.windowClass,
    required this.posture,
    required this.hinge,
  });

  final Size size;
  final SmokeWindowClass windowClass;
  final SmokePosture posture;

  /// The separating display feature's bounds in **local** coordinates, or null
  /// when the window is not split by one. Non-null implies a non-flat posture.
  final Rect? hinge;

  double get width => size.width;
  double get height => size.height;

  bool get isCompact => windowClass == SmokeWindowClass.compact;
  bool get isExpanded => windowClass == SmokeWindowClass.expanded;
  bool get isLandscape => size.width > size.height;

  /// Half-open on a horizontal hinge — the counter-top posture.
  bool get isTabletop => posture == SmokePosture.tabletop;

  /// Half-open on a vertical hinge — held like a book.
  bool get isBook => posture == SmokePosture.book;

  /// Bottom [NavigationBar] on compact; [NavigationRail] from medium up.
  /// The destinations and their indices never change — only the chrome that
  /// carries them, which is what keeps the swap a layout change and not an
  /// IA change.
  bool get usesRail => !isCompact;

  /// Labels beside the rail icons rather than under them. Deliberately well
  /// above the medium threshold: an extended rail on a 600 dp window eats the
  /// width the content just gained.
  bool get railExtended => size.width >= 1240;

  /// List-detail (History, Bridge, Alerts) rather than push-a-route. This is
  /// what turns the History flow from a full-screen navigation into a
  /// selection change, which is most of why that flow was losing context.
  bool get usesSplitPane => !isCompact;

  /// The Cook tab's supporting-pane layout: readouts beside the chart instead
  /// of stacked above it.
  bool get usesSupportingPane => !isCompact;

  /// Widest a column of prose or a probe readout may get before it stops
  /// reading as one thing. Extra width goes to the chart, never here.
  static const double readableMax = 480;

  /// The fraction of the width the list takes in a list-detail split. Narrower
  /// on medium, where the detail needs every dp it can get.
  double get listPaneFraction =>
      windowClass == SmokeWindowClass.medium ? 0.38 : 0.32;

  /// A vertical hinge splits the window left/right; panes should meet *at* it.
  bool get hingeIsVertical {
    final h = hinge;
    return h != null && h.height >= h.width;
  }

  /// A horizontal hinge splits the window top/bottom.
  bool get hingeIsHorizontal {
    final h = hinge;
    return h != null && h.width > h.height;
  }

  /// How much to inset content so nothing lands in the crease. Zero without a
  /// hinge, so every non-foldable path pays nothing.
  double get hingeGap => hinge == null
      ? 0
      : (hingeIsVertical ? hinge!.width : hinge!.height).clamp(0.0, 64.0);

  /// Where to split a two-pane layout: the hinge's leading edge when one
  /// separates the window, otherwise [listPaneFraction] of the width.
  ///
  /// A brisket chart bisected by a crease is the single most obvious "this was
  /// never opened on the device" tell a foldable app can ship, and it costs one
  /// branch to avoid.
  double splitAt(double available) {
    final h = hinge;
    if (h != null && hingeIsVertical && h.left > 0 && h.right < size.width) {
      return h.left;
    }
    return available * listPaneFraction;
  }

  /// Read the adaptive facts for this frame. Cheap: one `MediaQuery` read and
  /// a walk over a list that is empty on every non-foldable device.
  factory SmokeWindow.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    return SmokeWindow.from(size: mq.size, displayFeatures: mq.displayFeatures);
  }

  /// The pure core, so the whole matrix is testable without a MediaQuery.
  factory SmokeWindow.from({
    required Size size,
    List<DisplayFeature> displayFeatures = const [],
  }) {
    final windowClass = size.width < 600
        ? SmokeWindowClass.compact
        : (size.width < 840
              ? SmokeWindowClass.medium
              : SmokeWindowClass.expanded);

    Rect? hinge;
    var posture = SmokePosture.flat;
    for (final f in displayFeatures) {
      final isSeam =
          f.type == DisplayFeatureType.fold ||
          f.type == DisplayFeatureType.hinge;
      if (!isSeam) {
        continue;
      }
      // A feature that does not actually separate the window (a fully-opened
      // Fold reports `postureFlat`) is not a layout constraint — the display
      // is continuous and content may cross it freely.
      if (f.state != DisplayFeatureState.postureHalfOpened) {
        continue;
      }
      hinge = f.bounds;
      posture = f.bounds.width > f.bounds.height
          ? SmokePosture.tabletop
          : SmokePosture.book;
      break;
    }

    return SmokeWindow(
      size: size,
      windowClass: windowClass,
      posture: posture,
      hinge: hinge,
    );
  }
}

/// `context.window` — the sanctioned way to reach the adaptive facts, matching
/// the `context.tokens` convention the design system already established.
extension SmokeWindowX on BuildContext {
  SmokeWindow get window => SmokeWindow.of(this);
}
