/// The controller's cache-first promise: history and graphs read from the
/// on-device cache with no bridge in range.
///
/// This is the regression for the bug that made every cold launch look empty
/// until the user reconnected — the cache was real, but nothing could read it
/// without a live repository.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/data/local/app_database.dart';
import 'package:smoke_bridge/data/local/app_prefs.dart';
import 'package:smoke_bridge/data/local/drift_sample_cache.dart';
import 'package:smoke_bridge/domain/domain.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftSampleCache cache;

  setUp(() {
    // No remembered bridge: bootstrap must not try to dial a radio.
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    cache = DriftSampleCache(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('a cold, unconnected launch paints history from the cache', () async {
    await cache.upsertSessions('A4F2', const [
      SessionInfo(
        id: 0x1A,
        name: 'Brisket',
        startedUnixMs: 1774051200000,
        endedUnixMs: null,
        samplePeriodS: 30,
        sampleCount: 2,
        numProbes: 4,
        closed: false,
        pinned: false,
      ),
    ]);
    await cache.upsertSamples('A4F2', 0x1A, const [
      Sample(t: 0, tempsF10: [2000, 1600, null, 900]),
      Sample(t: 30, tempsF10: [2010, 1601, null, 901]),
    ]);

    final controller = BridgeController(cache);
    await controller.bootstrap();

    expect(controller.link, BridgeLink.disconnected);
    expect(controller.sessions, hasLength(1));
    expect(controller.sessions.single.name, 'Brisket');

    final samples = await controller.samplesFor(0x1A);
    expect(samples, hasLength(2));
    expect(samples.last.t, 30);
    expect(samples.last.tempsF10[2], isNull, reason: 'detached stays null');

    controller.dispose();
  });

  test('with nothing cached the launch stays empty, not wrong', () async {
    final controller = BridgeController(cache);
    await controller.bootstrap();

    expect(controller.sessions, isEmpty);
    expect(await controller.samplesFor(1), isEmpty);

    controller.dispose();
  });

  test('a unit change is persisted for the next launch', () async {
    final controller = BridgeController(cache);
    await controller.bootstrap();
    expect(controller.unit, TempUnit.fahrenheit);

    controller.setUnit(TempUnit.celsius);
    // setUnit persists asynchronously; let the write land.
    await Future<void>.delayed(Duration.zero);

    expect(await AppPrefs().readUnit(), TempUnit.celsius);

    controller.dispose();
  });
}
