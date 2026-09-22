/// N15.13 — the persistent preferences repository.
///
/// Pure Dart (`package:test`), so it runs in both `flutter test` and
/// `dart test test/data`. It pins the *contract* the `shared_preferences`
/// adapter will satisfy: load once, serve synchronously, persist every change,
/// and never crash on a corrupt payload (I15).
library;

import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('the defaults round-trip unchanged', () {
    final decoded = decodeAppSettings(encodeAppSettings(AppSettings.defaults));
    expect(decoded, AppSettings.defaults);
  });

  test('every field and a custom food survive a round-trip', () {
    final settings = AppSettings.defaults.copyWith(
      units: TempUnit.celsius,
      themeMode: AppThemeMode.dark,
      displayProfile: DisplayProfile.daylight,
      density: Density.comfortable,
      reducedMotion: true,
      preferManualAlarm: true,
      quietHours: false,
      monitoring: false,
      holdBle: false,
      autoWrapReminder: false,
      otaChannel: OtaChannel.beta,
      forceOta: true,
      bridgeName: 'Patio Bridge',
      onboardStatus: OnboardStatus.fresh,
      customCatalog: [
        CustomFood(
          id: 'lamb_shoulder',
          name: 'Lamb shoulder',
          category: 'Custom',
          hazard: HazardClass.unstated,
          targetF10: 1450,
          pitBandMinF10: 2250,
          pitBandMaxF10: 2750,
          timeline: const CookTimeline(
            totalMin: MinuteRange(240, 300),
            spritzEveryMin: 45,
            restMin: 20,
          ),
          glyph: 'beef',
          thickness: CutThickness.thick,
          blurb: 'Low and slow',
        ),
      ],
    );

    final decoded = decodeAppSettings(encodeAppSettings(settings));
    expect(decoded, isNotNull);
    expect(decoded!.units, TempUnit.celsius);
    expect(decoded.themeMode, AppThemeMode.dark);
    expect(decoded.displayProfile, DisplayProfile.daylight);
    expect(decoded.density, Density.comfortable);
    expect(decoded.reducedMotion, isTrue);
    expect(decoded.preferManualAlarm, isTrue);
    expect(decoded.quietHours, isFalse);
    expect(decoded.monitoring, isFalse);
    expect(decoded.holdBle, isFalse);
    expect(decoded.autoWrapReminder, isFalse);
    expect(decoded.otaChannel, OtaChannel.beta);
    expect(decoded.forceOta, isTrue);
    expect(decoded.bridgeName, 'Patio Bridge');
    expect(decoded.onboardStatus, OnboardStatus.fresh);

    final food = decoded.customCatalog.single;
    expect(food.id, 'lamb_shoulder');
    expect(food.name, 'Lamb shoulder');
    expect(food.hazard, HazardClass.unstated);
    expect(food.targetF10, 1450);
    expect(food.pitBandMinF10, 2250);
    expect(food.glyph, 'beef');
    expect(food.thickness, CutThickness.thick);
    expect(food.blurb, 'Low and slow');
    expect(food.timeline!.totalMin.min, 240);
    expect(food.timeline!.totalMin.max, 300);
    expect(food.timeline!.spritzEveryMin, 45);
    expect(food.timeline!.restMin, 20);
  });

  test('a missing field falls back to its default (older payload)', () {
    final decoded = decodeAppSettings('{"bridge_name":"Half"}');
    expect(decoded, isNotNull);
    expect(decoded!.bridgeName, 'Half');
    expect(decoded.units, TempUnit.fahrenheit);
    expect(decoded.onboardStatus, OnboardStatus.paired);
    expect(decoded.customCatalog, isEmpty);
  });

  test('a corrupt payload decodes to null, never throws', () {
    expect(decodeAppSettings('{not json'), isNull);
    expect(decodeAppSettings('[1,2,3]'), isNull);
  });

  test('write persists through the store and load reads it back', () async {
    final store = InMemoryKeyValueStore();
    final repo = await JsonPrefsRepository.load(store);
    expect(repo.current, AppSettings.defaults);

    await repo.update(
      (s) => s.copyWith(
        bridgeName: 'Backyard',
        onboardStatus: OnboardStatus.skipped,
      ),
    );
    expect(store.read(JsonPrefsRepository.storageKey), completion(isNotNull));

    final reloaded = await JsonPrefsRepository.load(store);
    expect(reloaded.current.bridgeName, 'Backyard');
    expect(reloaded.current.onboardStatus, OnboardStatus.skipped);
  });

  test('a corrupt stored payload still boots on the defaults (I15)', () async {
    final store = InMemoryKeyValueStore();
    await store.write(JsonPrefsRepository.storageKey, '{broken');
    final repo = await JsonPrefsRepository.load(store);
    expect(repo.current, AppSettings.defaults);
  });

  test('watch replays the current value then every change', () async {
    final repo = await JsonPrefsRepository.load(InMemoryKeyValueStore());
    addTearDown(repo.dispose);

    final seen = <AppSettings>[];
    final sub = repo.watch().listen(seen.add);
    await Future<void>.delayed(Duration.zero);
    await repo.update((s) => s.copyWith(bridgeName: 'Smoke'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sub.cancel();

    expect(seen.first, AppSettings.defaults);
    expect(seen.last.bridgeName, 'Smoke');
  });
}
