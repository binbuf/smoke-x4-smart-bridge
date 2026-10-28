import 'package:flutter/widgets.dart';

/// One motion policy for the app.
///
/// The UI contract allows 150–220 ms ease-out transitions and requires reduced
/// motion to be respected. Screens use [AppMotion.duration] instead of a raw
/// constant so a system "remove animations" setting collapses the transition
/// to a single frame without changing any state.
class AppMotion {
  const AppMotion._();

  /// The approved in-app transition length.
  static const standard = Duration(milliseconds: 180);

  /// The transition length for [context], or [Duration.zero] when the platform
  /// asks for reduced motion.
  static Duration duration(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
      ? Duration.zero
      : standard;
}
