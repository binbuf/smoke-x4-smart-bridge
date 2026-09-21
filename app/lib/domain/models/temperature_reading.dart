/// N0.6 — the codegen smoke test. N1 replaces this with the real domain
/// entities; its only job today is to prove that `build_runner` + `freezed` +
/// `json_serializable` are wired and reproducible from a clean checkout.
///
/// Pure Dart on purpose: `domain/` may not import Flutter (see
/// `test/domain/domain_purity_test.dart` and components_research_notes.md §6).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'temperature_reading.freezed.dart';
part 'temperature_reading.g.dart';

@freezed
abstract class TemperatureReading with _$TemperatureReading {
  const factory TemperatureReading({
    required String probeId,

    /// Tenths of a degree Fahrenheit — canonical storage (decision D7).
    required int tempF10,
    required DateTime recordedAt,
  }) = _TemperatureReading;

  factory TemperatureReading.fromJson(Map<String, dynamic> json) =>
      _$TemperatureReadingFromJson(json);
}
