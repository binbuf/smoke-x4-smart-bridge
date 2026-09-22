/// N15.13 — the `shared_preferences` adapter.
///
/// Uses `flutter_test` (the plugin channel is mocked) so it lives outside the
/// pure-Dart `test/data` directory. It pins the persistence contract the app
/// boots on: settings written now are read back on the next launch, and a
/// first install starts `fresh`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smoke_bridge/data/model/app_settings.dart';
import 'package:smoke_bridge/data/repository/real_prefs_repository.dart';
import 'package:smoke_bridge/data/repository/shared_prefs_store.dart';
import 'package:smoke_bridge/domain/domain.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('round-trips a string through the platform store', () async {
    final store = await SharedPrefsKeyValueStore.open();
    expect(await store.read('missing'), isNull);
    await store.write('k', 'v');
    expect(await store.read('k'), 'v');
    await store.remove('k');
    expect(await store.read('k'), isNull);
  });

  test('the first install starts fresh and the choice persists', () async {
    final store = await SharedPrefsKeyValueStore.open();
    final repo = await JsonPrefsRepository.load(
      store,
      initial: AppSettings.defaults.copyWith(
        onboardStatus: OnboardStatus.fresh,
      ),
    );
    expect(repo.current.onboardStatus, OnboardStatus.fresh);

    await repo.update((s) => s.copyWith(onboardStatus: OnboardStatus.paired));

    // A second launch reads the same store without the first-install seed.
    final reloaded = await JsonPrefsRepository.load(store);
    expect(reloaded.current.onboardStatus, OnboardStatus.paired);
  });

  test('settings survive a reload with all fields intact', () async {
    final store = await SharedPrefsKeyValueStore.open();
    final repo = await JsonPrefsRepository.load(store);
    await repo.update(
      (s) => s.copyWith(
        units: TempUnit.celsius,
        bridgeName: 'Patio Bridge',
        density: Density.comfortable,
        monitoring: false,
      ),
    );

    final reloaded = await JsonPrefsRepository.load(store);
    expect(reloaded.current.units, TempUnit.celsius);
    expect(reloaded.current.bridgeName, 'Patio Bridge');
    expect(reloaded.current.density, Density.comfortable);
    expect(reloaded.current.monitoring, isFalse);
  });
}
