/// N2.31 / N2.32 — the dev-panel control layer and deep links.
library;

import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('deep-link parsing', () {
    test('reads query parameters', () {
      final link = DevDeepLink.parse('index.html?screen=timeline&units=C');
      expect(link.screen, DevScreen.timeline);
      expect(link.units, TempUnit.celsius);
      expect(link.overlay, isNull);
      expect(link.isEmpty, isFalse);
    });

    test('reads a bare fragment', () {
      expect(DevDeepLink.parse('#screen=graph').screen, DevScreen.graph);
    });

    test('reads an overlay and keeps its props', () {
      final link = DevDeepLink.parse('#overlay=probe&jack=2');
      expect(link.overlay, DevOverlay.probe);
      expect(link.props, {'jack': '2'});
    });

    test('reads scenario + screen from an app URI', () {
      final link = DevDeepLink.parse(
        'smoke://app?scenario=offline&screen=live',
      );
      expect(link.scenario, 'offline');
      expect(link.screen, DevScreen.live);
    });

    test('drops unknown values instead of throwing', () {
      final link = DevDeepLink.parse('?screen=nope&units=X&overlay=nope');
      expect(link.screen, isNull);
      expect(link.units, isNull);
      expect(link.overlay, isNull);
      expect(link.isEmpty, isTrue);
    });

    test('an empty location is none', () {
      expect(DevDeepLink.parse('').isEmpty, isTrue);
      expect(DevDeepLink.parse('   ').isEmpty, isTrue);
    });
  });

  group('DevPanelController', () {
    test('lists every scenario and event', () async {
      final repo = MockBridgeRepository(nowMs: 1700000000000);
      addTearDown(repo.dispose);
      final prefs = MockPrefsRepository();
      addTearDown(prefs.dispose);
      final panel = DevPanelController(repository: repo, prefs: prefs);

      expect(panel.scenarios, hasLength(11));
      expect(panel.events, hasLength(12));
      expect(panel.activeScenarioKey, 'running');
    });

    test('applies scenario, units, screen and overlay', () async {
      final repo = MockBridgeRepository(nowMs: 1700000000000);
      addTearDown(repo.dispose);
      final prefs = MockPrefsRepository();
      addTearDown(prefs.dispose);

      DevScreen? seenScreen;
      DevOverlay? seenOverlay;
      Map<String, String>? seenProps;
      final panel = DevPanelController(
        repository: repo,
        prefs: prefs,
        onScreen: (s) => seenScreen = s,
        onOverlay: (o, p) {
          seenOverlay = o;
          seenProps = p;
        },
      );

      await panel.applyLocation(
        '?scenario=offline&units=C&screen=timeline&overlay=probe&jack=3',
      );

      expect(repo.activeScenarioKey, 'offline');
      expect(prefs.current.units, TempUnit.celsius);
      expect(seenScreen, DevScreen.timeline);
      expect(seenOverlay, DevOverlay.probe);
      expect(seenProps, {'jack': '3'});
    });

    test('fireEvent mutates the active snapshot', () async {
      final repo = MockBridgeRepository(
        nowMs: 1700000000000,
        initialScenario: 'idle',
      );
      addTearDown(repo.dispose);
      final prefs = MockPrefsRepository();
      addTearDown(prefs.dispose);
      final panel = DevPanelController(repository: repo, prefs: prefs);

      await panel.fireEvent('alarm-pit-crash');
      final s = await repo.snapshot().first;
      expect(s.alarms.single.ruleId, 'pit_crash');
    });

    test(
      'cycles theme in the prototype order and toggles the profile',
      () async {
        final repo = MockBridgeRepository(nowMs: 1700000000000);
        addTearDown(repo.dispose);
        final prefs = MockPrefsRepository();
        addTearDown(prefs.dispose);
        final panel = DevPanelController(repository: repo, prefs: prefs);

        expect(prefs.current.themeMode, AppThemeMode.system);
        await panel.cycleTheme();
        expect(prefs.current.themeMode, AppThemeMode.light);
        await panel.cycleTheme();
        expect(prefs.current.themeMode, AppThemeMode.dark);
        await panel.cycleTheme();
        expect(prefs.current.themeMode, AppThemeMode.system);

        expect(prefs.current.displayProfile, DisplayProfile.standard);
        await panel.toggleProfile();
        expect(prefs.current.displayProfile, DisplayProfile.daylight);
      },
    );

    test('openConnect asks the shell for the connect overlay', () {
      final repo = MockBridgeRepository(nowMs: 1700000000000);
      addTearDown(repo.dispose);
      final prefs = MockPrefsRepository();
      addTearDown(prefs.dispose);

      DevOverlay? seen;
      final panel = DevPanelController(
        repository: repo,
        prefs: prefs,
        onOverlay: (o, p) => seen = o,
      );
      panel.openConnect();
      expect(seen, DevOverlay.connect);
    });
  });
}
