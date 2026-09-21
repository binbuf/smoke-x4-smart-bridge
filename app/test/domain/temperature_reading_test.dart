/// N0.6 — the generated model actually serialises, so codegen is wired for
/// real rather than merely configured.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/models/temperature_reading.dart';

void main() {
  test('freezed + json_serializable round-trip', () {
    final reading = TemperatureReading(
      probeId: 'p1',
      tempF10: 2034,
      recordedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    );

    final restored = TemperatureReading.fromJson(reading.toJson());

    expect(restored, reading);
    expect(restored.tempF10, 2034);
    expect(restored.probeId, 'p1');
  });
}
