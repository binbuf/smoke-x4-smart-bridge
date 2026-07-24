/// A10.4 — the chart viewport (design 08 §8.7, §12.8).
///
/// §12.8 flags this as its own task for a concrete reason: **`fl_chart`
/// has no native zoom.** Pan and pinch are a custom transform over
/// `minX`/`maxX` that we own. Treating it as part of "render the chart" is
/// how that estimate blows up — so it is separated, and it is a plain
/// value type with no widget in it, which is why every edge below is
/// table-tested rather than gesture-tested.
///
/// The one behaviour worth naming: **live mode auto-scrolls until the
/// user pans, and then stops**, offering a "jump to now" pill. That is the
/// standard log-viewer behaviour and the one people expect; a chart that
/// yanks itself back to now while you are reading hour six is the single
/// most annoying thing a live chart can do.
library;

import 'dart:math';

/// The §8.7 window chips.
enum ChartWindow {
  m15(900, '15m'),
  h1(3600, '1h'),
  h6(21600, '6h'),
  h15(54000, '15h'),
  all(0, 'All');

  const ChartWindow(this.seconds, this.label);

  /// 0 = the whole session.
  final int seconds;
  final String label;
}

/// The smallest window a pinch may reach: below this, decimation has
/// nothing to do and the axis labels collide.
const int minViewportSpanS = 60;

class ChartViewport {
  const ChartViewport({
    required this.minX,
    required this.maxX,
    required this.sessionFromT,
    required this.sessionToT,
    this.window = ChartWindow.h15,
    this.following = true,
  });

  /// The visible range, in seconds-into-session.
  final int minX;
  final int maxX;

  /// The session's own bounds — no gesture may leave them.
  final int sessionFromT;
  final int sessionToT;

  /// The chip the user last chose. A pan does not clear it; it only
  /// stops the follow.
  final ChartWindow window;

  /// True while the viewport tracks new samples. Set false by any pan or
  /// zoom, restored by [jumpToNow] or a chip.
  final bool following;

  int get spanS => maxX - minX;

  /// True when the right edge is at the newest sample — the "jump to now"
  /// pill hides itself rather than offering a no-op.
  bool get atNow => maxX >= sessionToT;

  /// Initial viewport for a session: the chosen window, anchored at now.
  factory ChartViewport.forSession({
    required int fromT,
    required int toT,
    ChartWindow window = ChartWindow.h15,
  }) {
    final span = window == ChartWindow.all
        ? max(toT - fromT, minViewportSpanS)
        : window.seconds;
    final lo = max(fromT, toT - span);
    return ChartViewport(
      minX: lo,
      maxX: max(toT, lo + minViewportSpanS),
      sessionFromT: fromT,
      sessionToT: toT,
      window: window,
    );
  }

  ChartViewport _clamped(int lo, int hi, {bool? following, ChartWindow? win}) {
    final sessionSpan = max(sessionToT - sessionFromT, minViewportSpanS);
    var span = (hi - lo).clamp(minViewportSpanS, sessionSpan);
    var newLo = lo;
    if (newLo < sessionFromT) {
      newLo = sessionFromT;
    }
    if (newLo + span > sessionToT) {
      newLo = sessionToT - span;
    }
    if (newLo < sessionFromT) {
      // A session shorter than the minimum span: show all of it and
      // stop, rather than inventing time that does not exist.
      newLo = sessionFromT;
      span = max(sessionToT - sessionFromT, minViewportSpanS);
    }
    return ChartViewport(
      minX: newLo,
      maxX: newLo + span,
      sessionFromT: sessionFromT,
      sessionToT: sessionToT,
      window: win ?? window,
      following: following ?? this.following,
    );
  }

  /// Selecting a chip re-anchors at now and resumes following — choosing
  /// "1h" means "the last hour", which is only true if it follows.
  ChartViewport withWindow(ChartWindow w) {
    final span = w == ChartWindow.all
        ? max(sessionToT - sessionFromT, minViewportSpanS)
        : w.seconds;
    return _clamped(sessionToT - span, sessionToT, following: true, win: w);
  }

  /// Pinch. [scale] < 1 zooms in. [focalT] stays under the finger, which
  /// is the whole point — zooming about the centre while pinching the
  /// left edge feels broken.
  ChartViewport zoom(double scale, {int? focalT}) {
    final focus = (focalT ?? (minX + maxX) ~/ 2).clamp(minX, maxX);
    final ratio = spanS == 0 ? 0.5 : (focus - minX) / spanS;
    final newSpan =
        (spanS * scale).round().clamp(
              minViewportSpanS,
              max(sessionToT - sessionFromT, minViewportSpanS),
            )
            as int;
    final lo = focus - (newSpan * ratio).round();
    return _clamped(lo, lo + newSpan, following: false);
  }

  /// Drag. Positive [deltaS] moves the window forward in time.
  ChartViewport pan(int deltaS) =>
      _clamped(minX + deltaS, maxX + deltaS, following: false);

  /// Double-tap: back to the chosen window at now.
  ChartViewport reset() => withWindow(window);

  ChartViewport jumpToNow() => withWindow(window);

  /// Centre on a mark, without changing the zoom (A11.3 taps a mark).
  ChartViewport centreOn(int t) {
    final half = spanS ~/ 2;
    return _clamped(t - half, t - half + spanS, following: false);
  }

  /// A new sample arrived. Follows only if the user has not taken over.
  ChartViewport extendTo(int newToT) {
    if (newToT <= sessionToT) {
      return this;
    }
    final grown = ChartViewport(
      minX: minX,
      maxX: maxX,
      sessionFromT: sessionFromT,
      sessionToT: newToT,
      window: window,
      following: following,
    );
    if (!following) {
      return grown;
    }
    return grown._clamped(newToT - spanS, newToT, following: true);
  }
}
