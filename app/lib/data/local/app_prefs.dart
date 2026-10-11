/// The app's tiny preference store.
///
/// Three things survive a process death because losing any is a visible
/// regression:
///
///  * **The last bridge's device id**, so a relaunch reconnects straight to a
///    known bridge instead of scanning and guessing at whichever one answers
///    first.
///  * **The chosen temperature unit**, so a °C user is not flipped back to °F
///    every launch.
///  * **The cook clock's start**, so a declared cook keeps running in the UI and
///    can be re-sent to the bridge (which forgets it across a reboot).
///
/// Deliberately a plain `shared_preferences` wrapper, not a settings tree.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/domain.dart';

class AppPrefs {
  static const _kUnit = 'temp_unit';
  static const _kLastBridge = 'last_bridge_device_id';

  /// The local start of the app-declared cook, so the clock can be re-sent to
  /// the bridge (which forgets it across a reboot) and keeps running in the UI
  /// across an app restart.
  static const _kCookStart = 'cook_started_unix_ms';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// The saved unit, defaulting to °F — the device's canonical scale.
  Future<TempUnit> readUnit() async {
    final raw = (await _prefs).getString(_kUnit);
    return raw == TempUnit.celsius.name
        ? TempUnit.celsius
        : TempUnit.fahrenheit;
  }

  Future<void> writeUnit(TempUnit unit) async {
    await (await _prefs).setString(_kUnit, unit.name);
  }

  /// The device id (Android MAC) of the bridge this phone last connected to.
  Future<String?> readLastBridgeId() async =>
      (await _prefs).getString(_kLastBridge);

  Future<void> writeLastBridgeId(String deviceId) async {
    await (await _prefs).setString(_kLastBridge, deviceId);
  }

  Future<void> clearLastBridgeId() async {
    await (await _prefs).remove(_kLastBridge);
  }

  /// The local cook start in ms since epoch, or null when no cook is declared.
  Future<int?> readCookStartedMs() async => (await _prefs).getInt(_kCookStart);

  Future<void> writeCookStartedMs(int unixMs) async {
    await (await _prefs).setInt(_kCookStart, unixMs);
  }

  Future<void> clearCookStartedMs() async {
    await (await _prefs).remove(_kCookStart);
  }
}
