/// A7.5 — the store that makes the second launch fast.
///
/// The seam that was a no-op at every production call site since A7.1.
/// Two behaviours matter more than the getters: a BLE win must not blank
/// the cached address, and a corrupt preference must degrade to "no
/// cached lane" rather than take the launch with it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smoke_bridge/data/prefs/bridge_prefs.dart';

void main() {
  group('in memory (what the suite runs on)', () {
    test('records a connection and reads it back', () async {
      final p = InMemoryBridgePrefs();
      expect(p.lastBaseUrl, isNull);
      await p.recordConnection(
        'http://10.50.50.38',
        bridgeId: 'LMXC[\\',
        atMs: 5,
      );
      expect(p.lastBaseUrl, 'http://10.50.50.38');
      expect(p.lastBridgeId, 'LMXC[\\');
      expect(p.lastSeenUnixMs, 5);
    });

    test('forgetting a bridge clears the address but not the units', () async {
      final p = InMemoryBridgePrefs();
      await p.setDisplayUnits('C');
      await p.recordConnection('http://a');
      await p.forgetBridge();
      expect(p.lastBaseUrl, isNull);
      expect(p.displayUnits, 'C');
    });
  });

  group('shared_preferences backed', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('round-trips across a reload — the whole point of it', () async {
      final first = await SharedPrefsBridgePrefs.load();
      await first.recordConnection(
        'http://10.50.50.38',
        bridgeId: 'LMXC[\\',
        atMs: 1784786460027,
      );
      // A "relaunch": a fresh instance over the same store.
      final second = await SharedPrefsBridgePrefs.load();
      expect(second.lastBaseUrl, 'http://10.50.50.38');
      expect(second.lastBridgeId, 'LMXC[\\');
      expect(second.lastSeenUnixMs, 1784786460027);
    });

    test('an empty base URL is not recorded — that is the BLE lane', () async {
      final p = await SharedPrefsBridgePrefs.load();
      await p.recordConnection('http://10.50.50.38');
      // A6.5 hands back an empty address on a BLE win. Blanking the
      // cache here would break the next launch's fastest lane.
      await p.recordConnection('');
      expect(p.lastBaseUrl, 'http://10.50.50.38');
    });

    test('a stored value of the wrong type reads as absent', () async {
      SharedPreferences.setMockInitialValues({'bridge.base_url': 42});
      final p = await SharedPrefsBridgePrefs.load();
      // Losing the fast lane is a slower launch; throwing is a bug report.
      expect(p.lastBaseUrl, isNull);
      expect(p.lastBridgeId, isNull);
    });

    test('an empty stored address is absent, not an empty candidate', () async {
      SharedPreferences.setMockInitialValues({'bridge.base_url': ''});
      final p = await SharedPrefsBridgePrefs.load();
      expect(p.lastBaseUrl, isNull);
    });

    test('units default to nothing, and D14 decides elsewhere', () async {
      final p = await SharedPrefsBridgePrefs.load();
      expect(p.displayUnits, isNull);
      await p.setDisplayUnits('C');
      expect((await SharedPrefsBridgePrefs.load()).displayUnits, 'C');
    });

    test('forgetting a bridge really forgets it', () async {
      final p = await SharedPrefsBridgePrefs.load();
      await p.recordConnection('http://a', bridgeId: 'X');
      await p.forgetBridge();
      final reloaded = await SharedPrefsBridgePrefs.load();
      expect(reloaded.lastBaseUrl, isNull);
      expect(reloaded.lastBridgeId, isNull);
    });
  });
}
