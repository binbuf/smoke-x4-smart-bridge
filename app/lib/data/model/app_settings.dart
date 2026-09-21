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

/// Whether the first-run onboarding wizard still has to run (N14.12).
///
/// * [fresh] — no bridge is known yet; the wizard owns the screen (N14.12).
/// * [skipped] — the user skipped; the shell shows the "connect a bridge"
///   empty state so it is never a dead end (N14.13).
/// * [paired] — onboarding finished (or this build already has a bridge); the
///   shell launches straight to Live.
enum OnboardStatus { fresh, skipped, paired }

/// A user-defined food: identity, target and its own expected timeline.
///
/// N9.17 adds the identity fields the custom-food form collects ([glyph],
/// [thickness], [blurb]) so a custom cut renders in the picker exactly like a
/// catalog entry. They default to a safe placeholder so existing stored values
/// keep loading.
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
    this.glyph = 'unstated',
    this.thickness = CutThickness.medium,
    this.blurb = 'Custom food',
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

  /// Placeholder-avatar glyph name (`beef`, `veg` …).
  final String glyph;

  /// Drives carryover, exactly as it does for a catalog cut.
  final CutThickness thickness;

  /// One line under the name in the picker.
  final String blurb;
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

    /// The friendly bridge name the wizard collects (N14.9).
    @Default('Backyard Bridge') String bridgeName,

    /// First-run gating (N14.12/N14.13). `paired` on the mock build because
    /// every N2 scenario already carries a bridge; a factory-fresh install is
    /// `fresh` and the wizard walks it to a live shell.
    @Default(OnboardStatus.paired) OnboardStatus onboardStatus,

    /// User-defined foods, persisted with the preset library.
    @Default(<CustomFood>[]) List<CustomFood> customCatalog,
  }) = _AppSettings;

  static const AppSettings defaults = AppSettings();
}
