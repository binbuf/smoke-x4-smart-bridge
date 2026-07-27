/// The adaptive matrix (design 13 §13.3) — window class and foldable posture.
///
/// `SmokeWindow.from` is pure over a size and a display-feature list, which is
/// the whole reason it exists: the entire Fold matrix, including postures no
/// CI machine has hardware for, is exercisable here.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/breakpoints.dart';

DisplayFeature _fold({
  required Rect bounds,
  DisplayFeatureState state = DisplayFeatureState.postureHalfOpened,
}) =>
    DisplayFeature(bounds: bounds, type: DisplayFeatureType.fold, state: state);

void main() {
  group('window classes', () {
    test('the three Material thresholds, and what each one buys', () {
      final phone = SmokeWindow.from(size: const Size(400, 800));
      expect(phone.windowClass, SmokeWindowClass.compact);
      expect(phone.usesRail, isFalse);
      expect(phone.usesSplitPane, isFalse);

      // A Fold, opened.
      final medium = SmokeWindow.from(size: const Size(700, 900));
      expect(medium.windowClass, SmokeWindowClass.medium);
      expect(medium.usesRail, isTrue);
      expect(medium.usesSplitPane, isTrue);
      expect(medium.railExtended, isFalse, reason: 'labels would eat the win');

      final tablet = SmokeWindow.from(size: const Size(1280, 900));
      expect(tablet.windowClass, SmokeWindowClass.expanded);
      expect(tablet.railExtended, isTrue);
    });

    test('599 is compact and 600 is not — the boundary is exact', () {
      expect(
        SmokeWindow.from(size: const Size(599, 900)).windowClass,
        SmokeWindowClass.compact,
      );
      expect(
        SmokeWindow.from(size: const Size(600, 900)).windowClass,
        SmokeWindowClass.medium,
      );
    });
  });

  group('foldable posture', () {
    test('no display features is flat, and costs nothing', () {
      final w = SmokeWindow.from(size: const Size(400, 800));
      expect(w.posture, SmokePosture.flat);
      expect(w.hinge, isNull);
      expect(w.hingeGap, 0);
    });

    test('a horizontal seam half-open is tabletop — the counter posture', () {
      final w = SmokeWindow.from(
        size: const Size(840, 1000),
        displayFeatures: [_fold(bounds: const Rect.fromLTRB(0, 492, 840, 508))],
      );
      expect(w.posture, SmokePosture.tabletop);
      expect(w.isTabletop, isTrue);
      expect(w.hingeIsHorizontal, isTrue);
      expect(w.hingeGap, 16);
    });

    test('a vertical seam half-open is book, and panes meet at it', () {
      final w = SmokeWindow.from(
        size: const Size(840, 1000),
        displayFeatures: [
          _fold(bounds: const Rect.fromLTRB(416, 0, 424, 1000)),
        ],
      );
      expect(w.posture, SmokePosture.book);
      expect(w.hingeIsVertical, isTrue);
      // Not 0.38 of the width — the crease wins, so no content is bisected.
      expect(w.splitAt(840), 416);
    });

    test(
      'a fully-opened fold is flat: content may cross a continuous display',
      () {
        final w = SmokeWindow.from(
          size: const Size(840, 1000),
          displayFeatures: [
            _fold(
              bounds: const Rect.fromLTRB(416, 0, 424, 1000),
              state: DisplayFeatureState.postureFlat,
            ),
          ],
        );
        expect(w.posture, SmokePosture.flat);
        expect(w.hinge, isNull);
        // Falls back to the proportional split.
        expect(w.splitAt(840), closeTo(840 * 0.32, 0.001));
      },
    );

    test('a cutout is not a seam', () {
      final w = SmokeWindow.from(
        size: const Size(400, 800),
        displayFeatures: [
          const DisplayFeature(
            bounds: Rect.fromLTRB(180, 0, 220, 40),
            type: DisplayFeatureType.cutout,
            state: DisplayFeatureState.unknown,
          ),
        ],
      );
      expect(w.posture, SmokePosture.flat);
      expect(w.hinge, isNull);
    });
  });
}
