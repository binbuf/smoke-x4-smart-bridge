/// Spacing tokens.
///
/// Colour already has a home ([ColorScheme] plus `StatusColors` and
/// `ProbeColors` in `app_theme.dart`); spacing did not, so the same gap was
/// written as a bare literal wherever it was needed. These names describe the
/// *job* of the space, not its size, so a designer can ask for "more room
/// between stacked cards" without naming a number.
///
/// Values are the shipping values. Tokenising must not move a pixel, so the
/// golden suite is the acceptance test: change a value here and the screenshots
/// that legitimately use it fail.
class Space {
  const Space._();

  /// Between a value and its label inside a metric.
  static const double labelGap = 2;

  /// Between an inline icon and the text it belongs to.
  static const double inlineGap = 6;

  /// Between a heading and the content it introduces.
  static const double headingGap = 8;

  /// Between stacked cards and notices in one column.
  static const double stackGap = 10;

  /// Gutter between grid cells, and between card rows.
  static const double gridGutter = 12;

  /// Between one section and the next.
  static const double sectionGap = 14;

  /// Before a heading that starts a new region of the screen.
  static const double blockGap = 18;
}
