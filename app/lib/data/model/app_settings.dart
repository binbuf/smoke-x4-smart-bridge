/// N2.25 — app preferences.
///
/// These are app-tier only; the device is authoritative about recording and its
/// own alarms (I2). [preferManualAlarm] changes which notification wins, never
/// whether the device rule fires.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/domain.dart';

part 'app_settings.freezed.dart';

/// App theme axis (`system` follows the OS).
enum AppThemeMode { system, light, dark }

/// Contrast profile — orthogonal to the theme axis.
enum DisplayProfile { standard, daylight }

/// Layout density.
enum Density { compact, comfortable }

/// The OTA release channel.
enum OtaChannel { stable, beta }

/// A user-defined food: identity, target and its own expected timeline.
class CustomFood {
  const CustomFood({
    required this.id,
    required this.name,
    required this.category,
    required this.hazard,
    required this.targetF10,
    this.pitBandMinF10,
    this.pitBandMaxF10,
    this.timeline,
  });

  final String id;
  final String name;
  final String category;
  final HazardClass hazard;
  final int targetF10;
  final int? pitBandMinF10;
  final int? pitBandMaxF10;

  /// The custom expected timeline; null means the cut has none.
  final CookTimeline? timeline;
}

/// The whole settings tree, as one value.
@freezed
abstract class AppSettings with _$AppSettings {
  const factory AppSettings({
    /// Display only; data stays canonical tenths-°F.
    @Default(TempUnit.fahrenheit) TempUnit units,
    @Default(AppThemeMode.system) AppThemeMode themeMode,
    @Default(DisplayProfile.standard) DisplayProfile displayProfile,
    @Default(Density.compact) Density density,
    @Default(false) bool reducedMotion,

    /// The user's own alarm wins over device rules.
    @Default(false) bool preferManualAlarm,

    /// 22:00–06:00 silences warning/info, never critical.
    @Default(true) bool quietHours,

    /// Background alarm monitoring.
    @Default(true) bool monitoring,

    /// Keep BLE warm while on Wi-Fi for fast failover.
    @Default(true) bool holdBle,

    /// The Timeline tab sends wrap/spritz reminders.
    @Default(true) bool autoWrapReminder,

    @Default(OtaChannel.stable) OtaChannel otaChannel,

    /// Allow an OTA while a session is recording (the 409 override).
    @Default(false) bool forceOta,

    /// User-defined foods, persisted with the preset library.
    @Default(<CustomFood>[]) List<CustomFood> customCatalog,
  }) = _AppSettings;

  static const AppSettings defaults = AppSettings();
}
