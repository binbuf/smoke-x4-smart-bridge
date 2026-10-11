/// The pure-Dart domain barrel.
///
/// Everything under `lib/domain/` imports nothing from Flutter or `dart:ui`, so
/// the whole of it is host-testable without a binding (`dart test`).
library;

export 'entities/freshness.dart';
export 'entities/gap.dart';
export 'entities/probe.dart';
export 'entities/sample.dart';
export 'entities/session.dart';
export 'units/temp_value.dart';
