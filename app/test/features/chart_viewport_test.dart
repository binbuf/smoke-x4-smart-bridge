/// A10.4 — the viewport transform.
///
/// `fl_chart` has no native zoom (§12.8), so this arithmetic is ours and
/// every edge of it is a table row here rather than a gesture in a widget
/// test. The behaviour that matters most is the last group: **live mode
/// auto-scrolls until the user pans, and then stops.**
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/features/chart/chart_viewport.dart';

ChartViewport vp({
  int from = 0,
  int to = 54000,
  ChartWindow window = ChartWindow.h1,
}) => ChartViewport.forSession(fromT: from, toT: to, window: window);

void main() {
  group('windows', () {
    test('a chip anchors the window at now and resumes following', () {
      final v = vp().withWindow(ChartWindow.h6);
      expect(v.spanS, 21600);
      expect(v.maxX, 54000);
      expect(v.following, isTrue);
      expect(v.window, ChartWindow.h6);
    });

    test('All spans the whole session', () {
      final v = vp(from: 100, to: 40000).withWindow(ChartWindow.all);
      expect(v.minX, 100);
      expect(v.maxX, 40000);
    });

    test('a session shorter than the window shows all of it, not more', () {
      final v = vp(to: 600, window: ChartWindow.h15);
      expect(v.minX, 0);
      expect(v.maxX, 600);
      expect(v.spanS, 600);
    });

    test('a session shorter than the minimum span does not invent time', () {
      final v = vp(to: 10);
      expect(v.minX, 0);
      expect(v.spanS, greaterThanOrEqualTo(minViewportSpanS));
      expect(v.minX, greaterThanOrEqualTo(v.sessionFromT));
    });
  });

  group('zoom', () {
    test('the focal timestamp stays under the finger', () {
      final v = vp(window: ChartWindow.h6);
      const focal = 40000;
      final z = v.zoom(0.5, focalT: focal);
      final beforeFrac = (focal - v.minX) / v.spanS;
      final afterFrac = (focal - z.minX) / z.spanS;
      expect(afterFrac, closeTo(beforeFrac, 0.02));
      expect(z.spanS, closeTo(v.spanS / 2, 2));
    });

    test('zoom stops taking over the follow', () {
      expect(vp().zoom(0.5).following, isFalse);
    });

    test('zooming in clamps at the minimum span', () {
      var v = vp(window: ChartWindow.m15);
      for (var i = 0; i < 12; i++) {
        v = v.zoom(0.5);
      }
      expect(v.spanS, minViewportSpanS);
    });

    test('zooming out clamps at the session', () {
      var v = vp(window: ChartWindow.m15);
      for (var i = 0; i < 12; i++) {
        v = v.zoom(2);
      }
      expect(v.minX, 0);
      expect(v.maxX, 54000);
    });
  });

  group('pan', () {
    test('panning back moves the window and stops the follow', () {
      final v = vp(window: ChartWindow.h1).pan(-1800);
      expect(v.maxX, 54000 - 1800);
      expect(v.following, isFalse);
      expect(v.atNow, isFalse);
    });

    test('panning past the start clamps at the session start', () {
      final v = vp(window: ChartWindow.h1).pan(-999999);
      expect(v.minX, 0);
      expect(v.spanS, 3600);
    });

    test('panning past the end clamps at now', () {
      final v = vp(window: ChartWindow.h1).pan(999999);
      expect(v.maxX, 54000);
    });

    test('a chip while panned re-anchors and resumes', () {
      final v = vp(
        window: ChartWindow.h1,
      ).pan(-20000).withWindow(ChartWindow.h1);
      expect(v.atNow, isTrue);
      expect(v.following, isTrue);
    });

    test('double-tap resets to the chosen window at now', () {
      final v = vp(window: ChartWindow.h6).pan(-20000).zoom(0.3).reset();
      expect(v.spanS, 21600);
      expect(v.atNow, isTrue);
      expect(v.following, isTrue);
    });
  });

  group('live follow', () {
    test('a new sample scrolls the window while following', () {
      final v = vp(window: ChartWindow.h1).extendTo(54600);
      expect(v.maxX, 54600);
      expect(v.spanS, 3600);
      expect(v.following, isTrue);
    });

    test('after a pan, new samples do not yank the window', () {
      final panned = vp(window: ChartWindow.h1).pan(-10000);
      final after = panned.extendTo(54600);
      expect(after.minX, panned.minX);
      expect(after.maxX, panned.maxX);
      expect(after.sessionToT, 54600);
      // ... and the pill has something to do.
      expect(after.atNow, isFalse);
    });

    test('jump-to-now releases the suppression', () {
      final v = vp(window: ChartWindow.h1).pan(-10000).extendTo(54600);
      final back = v.jumpToNow();
      expect(back.atNow, isTrue);
      expect(back.following, isTrue);
    });

    test('an older sample cannot shrink the session', () {
      final v = vp().extendTo(10);
      expect(v.sessionToT, 54000);
    });
  });

  test('centreOn keeps the zoom and moves the window (A11.3 taps a mark)', () {
    final v = vp(window: ChartWindow.h1).centreOn(20000);
    expect(v.spanS, 3600);
    expect((v.minX + v.maxX) ~/ 2, closeTo(20000, 2));
    expect(v.following, isFalse);
  });
}
