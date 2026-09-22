/// N15.13 — the `shared_preferences` adapter for [KeyValueStore].
///
/// This is the only place the prefs layer touches a platform plugin; the
/// repository above it is pure Dart and in the `dart test test/data` gate.
/// `bootstrap.dart` opens it once and overrides `prefsProvider` with a
/// [JsonPrefsRepository] already loaded from it, so the first synchronous
/// `current` read already reflects what was on disk.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'real_prefs_repository.dart';

/// A [KeyValueStore] over the platform key-value store.
///
/// `SharedPreferences.setMockInitialValues({})` backs this in widget tests;
/// no test needs a real device.
class SharedPrefsKeyValueStore implements KeyValueStore {
  SharedPrefsKeyValueStore.fromPreferences(this._prefs);

  /// Open the platform store. Loads once; the returned store is synchronous
  /// only in the sense that callers await per call (never on the first frame).
  static Future<SharedPrefsKeyValueStore> open() async =>
      SharedPrefsKeyValueStore.fromPreferences(
        await SharedPreferences.getInstance(),
      );

  final SharedPreferences _prefs;

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _prefs.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }
}
