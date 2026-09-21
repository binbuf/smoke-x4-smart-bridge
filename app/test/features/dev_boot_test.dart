/// N2.32 — boot-time deep-link application.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/dev/dev_boot.dart';

void main() {
  late MockBridgeRepository repo;
  late MockPrefsRepository prefs;
  late ProviderContainer container;

  setUp(() {
    repo = MockBridgeRepository(nowMs: 1700000000000);
    prefs = MockPrefsRepository();
    container = ProviderContainer(
      overrides: [
        bridgeRepositoryProvider.overrideWithValue(repo),
        prefsProvider.overrideWithValue(prefs),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await repo.dispose();
    await prefs.dispose();
  });

  test(
    'applies scenario and units, and leaves screen/overlay for the shell',
    () async {
      final link = DevDeepLink.parse(
        '?scenario=offline&units=C&screen=timeline&overlay=probe&jack=3',
      );

      await applyDevDeepLink(container, link);

      expect(repo.activeScenarioKey, 'offline');
      expect(prefs.current.units, TempUnit.celsius);
      expect(link.screen, DevScreen.timeline);
      expect(link.overlay, DevOverlay.probe);
      expect(link.props, <String, String>{'jack': '3'});
    },
  );

  test('an empty link changes nothing', () async {
    await applyDevDeepLink(container, DevDeepLink.none);

    expect(repo.activeScenarioKey, 'running');
    expect(prefs.current.units, TempUnit.fahrenheit);
  });

  test('the initial deep link provider defaults to none', () {
    expect(container.read(initialDevDeepLinkProvider).isEmpty, isTrue);
  });
}
