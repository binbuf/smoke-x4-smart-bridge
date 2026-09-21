/// N2.25 / N2.29 — settings and the in-memory preferences repository.
library;

import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('defaults match the prototype settings block', () {
    const s = AppSettings.defaults;
    expect(s.units, TempUnit.fahrenheit);
    expect(s.themeMode, AppThemeMode.system);
    expect(s.displayProfile, DisplayProfile.standard);
    expect(s.density, Density.compact);
    expect(s.reducedMotion, isFalse);
    expect(s.preferManualAlarm, isFalse);
    expect(s.quietHours, isTrue);
    expect(s.monitoring, isTrue);
    expect(s.holdBle, isTrue);
    expect(s.autoWrapReminder, isTrue);
    expect(s.otaChannel, OtaChannel.stable);
    expect(s.forceOta, isFalse);
    expect(s.customCatalog, isEmpty);
  });

  test('the mock prefs repository reads, writes and watches', () async {
    final prefs = MockPrefsRepository();
    addTearDown(prefs.dispose);

    expect(prefs.current.units, TempUnit.fahrenheit);
    expect(await prefs.watch().first, same(prefs.current));

    final seen = <AppSettings>[];
    final sub = prefs.watch().listen(seen.add);
    await Future<void>.delayed(Duration.zero);
    await prefs.update(
      (s) => s.copyWith(units: TempUnit.celsius, density: Density.comfortable),
    );
    await Future<void>.delayed(Duration.zero);

    expect(prefs.current.units, TempUnit.celsius);
    expect(prefs.current.density, Density.comfortable);
    expect(seen, hasLength(2));
    expect(seen.last.units, TempUnit.celsius);
    await sub.cancel();
  });

  test('a custom food carries its own timeline', () {
    const food = CustomFood(
      id: 'custom_chili',
      name: 'Smoked Chili',
      category: 'Misc',
      hazard: HazardClass.unstated,
      targetF10: 1800,
      timeline: CookTimeline(totalMin: MinuteRange(120, 180), restMin: 10),
    );
    expect(food.timeline!.totalMin, const MinuteRange(120, 180));
    expect(food.targetF10, 1800);
  });
}
