/// N15.13 — the real preferences repository.
///
/// The app needs settings **synchronously** from the very first frame
/// (`AppSettings.defaults` drives theming before the platform channel answers),
/// so this repository loads once at boot and then serves [current] from memory,
/// writing every change back through a [KeyValueStore].
///
/// The store is an interface so the persistence layer stays pure Dart and in
/// the `dart test test/data` gate: tests use [InMemoryKeyValueStore], while the
/// app build backs it with `shared_preferences` (a three-method adapter).
///
/// **No Wi-Fi secret is ever stored here** (N10.7). The only persisted
/// bridge-adjacent values are the friendly [AppSettings.bridgeName] and the
/// onboarding status.
library;

import 'dart:async';
import 'dart:convert';

import '../../domain/domain.dart';
import '../model/app_settings.dart';
import 'prefs_repository.dart';

/// The minimal persistence surface [JsonPrefsRepository] needs. A
/// `shared_preferences` adapter implements exactly this.
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// An in-memory store for tests, the UX lab and the pre-persistence build.
class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}

/// The persistent [PrefsRepository]. Construct with [load] so the first
/// synchronous [current] read already reflects what was on disk.
class JsonPrefsRepository implements PrefsRepository {
  JsonPrefsRepository._(this._store, this._settings);

  /// The storage slot. Versioned so a future migration can detect the old shape.
  static const String storageKey = 'app_settings_v1';

  final KeyValueStore _store;
  AppSettings _settings;
  final StreamController<AppSettings> _controller =
      StreamController<AppSettings>.broadcast();

  /// Read the persisted settings once; fall back to [initial] (or the defaults)
  /// when nothing valid is stored. Never throws — a corrupt payload is ignored
  /// rather than crashing boot (I15).
  static Future<JsonPrefsRepository> load(
    KeyValueStore store, {
    AppSettings? initial,
  }) async {
    AppSettings settings = initial ?? AppSettings.defaults;
    try {
      final raw = await store.read(storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = decodeAppSettings(raw);
        if (decoded != null) {
          settings = decoded;
        }
      }
    } on Object {
      // Keep the fallback; a bad prefs blob must not brick the app.
    }
    return JsonPrefsRepository._(store, settings);
  }

  @override
  AppSettings get current => _settings;

  @override
  Stream<AppSettings> watch() async* {
    yield _settings;
    yield* _controller.stream;
  }

  @override
  Future<void> write(AppSettings settings) async {
    _settings = settings;
    _emit();
    try {
      await _store.write(storageKey, encodeAppSettings(settings));
    } on Object {
      // A write failure is not fatal: the in-memory value still drives the UI.
    }
  }

  @override
  Future<void> update(AppSettings Function(AppSettings) transform) =>
      write(transform(_settings));

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(_settings);
    }
  }

  @override
  Future<void> dispose() => _controller.close();
}

// ── serialisation ─────────────────────────────────────────────────────────

/// Encode [settings] to the versioned JSON this repository persists.
String encodeAppSettings(AppSettings s) => jsonEncode({
  'units': s.units.name,
  'theme_mode': s.themeMode.name,
  'display_profile': s.displayProfile.name,
  'density': s.density.name,
  'reduced_motion': s.reducedMotion,
  'prefer_manual_alarm': s.preferManualAlarm,
  'quiet_hours': s.quietHours,
  'monitoring': s.monitoring,
  'hold_ble': s.holdBle,
  'auto_wrap_reminder': s.autoWrapReminder,
  'ota_channel': s.otaChannel.name,
  'force_ota': s.forceOta,
  'bridge_name': s.bridgeName,
  'onboard_status': s.onboardStatus.name,
  'custom_catalog': [for (final f in s.customCatalog) _encodeCustomFood(f)],
});

/// Decode a payload written by [encodeAppSettings], or null when it is not a
/// usable object. Missing fields fall back to their defaults, so an older
/// payload keeps loading (forward/backward compatible).
AppSettings? decodeAppSettings(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) {
    return null;
  }
  final j = decoded.cast<String, Object?>();
  final foods = j['custom_catalog'];
  return AppSettings(
    units: _enum(TempUnit.values, j['units'], TempUnit.fahrenheit),
    themeMode: _enum(AppThemeMode.values, j['theme_mode'], AppThemeMode.system),
    displayProfile: _enum(
      DisplayProfile.values,
      j['display_profile'],
      DisplayProfile.standard,
    ),
    density: _enum(Density.values, j['density'], Density.compact),
    reducedMotion: j['reduced_motion'] as bool? ?? false,
    preferManualAlarm: j['prefer_manual_alarm'] as bool? ?? false,
    quietHours: j['quiet_hours'] as bool? ?? true,
    monitoring: j['monitoring'] as bool? ?? true,
    holdBle: j['hold_ble'] as bool? ?? true,
    autoWrapReminder: j['auto_wrap_reminder'] as bool? ?? true,
    otaChannel: _enum(OtaChannel.values, j['ota_channel'], OtaChannel.stable),
    forceOta: j['force_ota'] as bool? ?? false,
    bridgeName: j['bridge_name'] as String? ?? 'Backyard Bridge',
    onboardStatus: _enum(
      OnboardStatus.values,
      j['onboard_status'],
      OnboardStatus.paired,
    ),
    customCatalog: [
      for (final f in foods is List ? foods : const []) ?_decodeCustomFood(f),
    ],
  );
}

Map<String, Object?> _encodeCustomFood(CustomFood f) => {
  'id': f.id,
  'name': f.name,
  'category': f.category,
  'hazard': f.hazard.name,
  'target_f10': f.targetF10,
  if (f.pitBandMinF10 != null) 'pit_min_f10': f.pitBandMinF10,
  if (f.pitBandMaxF10 != null) 'pit_max_f10': f.pitBandMaxF10,
  if (f.timeline != null) 'timeline': f.timeline!.toJson(),
  'glyph': f.glyph,
  'thickness': f.thickness.name,
  'blurb': f.blurb,
};

CustomFood? _decodeCustomFood(Object? value) {
  if (value is! Map) {
    return null;
  }
  final j = value.cast<String, Object?>();
  final id = j['id'];
  if (id is! String || id.isEmpty) {
    return null;
  }
  final timeline = j['timeline'];
  return CustomFood(
    id: id,
    name: j['name'] as String? ?? 'Custom food',
    category: j['category'] as String? ?? 'Custom',
    hazard: _enum(HazardClass.values, j['hazard'], HazardClass.unstated),
    targetF10: (j['target_f10'] as num?)?.toInt() ?? 1600,
    pitBandMinF10: (j['pit_min_f10'] as num?)?.toInt(),
    pitBandMaxF10: (j['pit_max_f10'] as num?)?.toInt(),
    timeline: timeline is Map
        ? CookTimeline.fromJson(timeline.cast<String, Object?>())
        : null,
    glyph: j['glyph'] as String? ?? 'unstated',
    thickness: _enum(CutThickness.values, j['thickness'], CutThickness.medium),
    blurb: j['blurb'] as String? ?? 'Custom food',
  );
}

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is String) {
    for (final value in values) {
      if (value.name == name) {
        return value;
      }
    }
  }
  return fallback;
}
