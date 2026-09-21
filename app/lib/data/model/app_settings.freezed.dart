// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AppSettings {

/// Display only; data stays canonical tenths-°F.
 TempUnit get units; AppThemeMode get themeMode; DisplayProfile get displayProfile; Density get density; bool get reducedMotion;/// The user's own alarm wins over device rules.
 bool get preferManualAlarm;/// 22:00–06:00 silences warning/info, never critical.
 bool get quietHours;/// Background alarm monitoring.
 bool get monitoring;/// Keep BLE warm while on Wi-Fi for fast failover.
 bool get holdBle;/// The Timeline tab sends wrap/spritz reminders.
 bool get autoWrapReminder; OtaChannel get otaChannel;/// Allow an OTA while a session is recording (the 409 override).
 bool get forceOta;/// User-defined foods, persisted with the preset library.
 List<CustomFood> get customCatalog;
/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppSettingsCopyWith<AppSettings> get copyWith => _$AppSettingsCopyWithImpl<AppSettings>(this as AppSettings, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppSettings&&(identical(other.units, units) || other.units == units)&&(identical(other.themeMode, themeMode) || other.themeMode == themeMode)&&(identical(other.displayProfile, displayProfile) || other.displayProfile == displayProfile)&&(identical(other.density, density) || other.density == density)&&(identical(other.reducedMotion, reducedMotion) || other.reducedMotion == reducedMotion)&&(identical(other.preferManualAlarm, preferManualAlarm) || other.preferManualAlarm == preferManualAlarm)&&(identical(other.quietHours, quietHours) || other.quietHours == quietHours)&&(identical(other.monitoring, monitoring) || other.monitoring == monitoring)&&(identical(other.holdBle, holdBle) || other.holdBle == holdBle)&&(identical(other.autoWrapReminder, autoWrapReminder) || other.autoWrapReminder == autoWrapReminder)&&(identical(other.otaChannel, otaChannel) || other.otaChannel == otaChannel)&&(identical(other.forceOta, forceOta) || other.forceOta == forceOta)&&const DeepCollectionEquality().equals(other.customCatalog, customCatalog));
}


@override
int get hashCode => Object.hash(runtimeType,units,themeMode,displayProfile,density,reducedMotion,preferManualAlarm,quietHours,monitoring,holdBle,autoWrapReminder,otaChannel,forceOta,const DeepCollectionEquality().hash(customCatalog));

@override
String toString() {
  return 'AppSettings(units: $units, themeMode: $themeMode, displayProfile: $displayProfile, density: $density, reducedMotion: $reducedMotion, preferManualAlarm: $preferManualAlarm, quietHours: $quietHours, monitoring: $monitoring, holdBle: $holdBle, autoWrapReminder: $autoWrapReminder, otaChannel: $otaChannel, forceOta: $forceOta, customCatalog: $customCatalog)';
}


}

/// @nodoc
abstract mixin class $AppSettingsCopyWith<$Res>  {
  factory $AppSettingsCopyWith(AppSettings value, $Res Function(AppSettings) _then) = _$AppSettingsCopyWithImpl;
@useResult
$Res call({
 TempUnit units, AppThemeMode themeMode, DisplayProfile displayProfile, Density density, bool reducedMotion, bool preferManualAlarm, bool quietHours, bool monitoring, bool holdBle, bool autoWrapReminder, OtaChannel otaChannel, bool forceOta, List<CustomFood> customCatalog
});




}
/// @nodoc
class _$AppSettingsCopyWithImpl<$Res>
    implements $AppSettingsCopyWith<$Res> {
  _$AppSettingsCopyWithImpl(this._self, this._then);

  final AppSettings _self;
  final $Res Function(AppSettings) _then;

/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? units = null,Object? themeMode = null,Object? displayProfile = null,Object? density = null,Object? reducedMotion = null,Object? preferManualAlarm = null,Object? quietHours = null,Object? monitoring = null,Object? holdBle = null,Object? autoWrapReminder = null,Object? otaChannel = null,Object? forceOta = null,Object? customCatalog = null,}) {
  return _then(_self.copyWith(
units: null == units ? _self.units : units // ignore: cast_nullable_to_non_nullable
as TempUnit,themeMode: null == themeMode ? _self.themeMode : themeMode // ignore: cast_nullable_to_non_nullable
as AppThemeMode,displayProfile: null == displayProfile ? _self.displayProfile : displayProfile // ignore: cast_nullable_to_non_nullable
as DisplayProfile,density: null == density ? _self.density : density // ignore: cast_nullable_to_non_nullable
as Density,reducedMotion: null == reducedMotion ? _self.reducedMotion : reducedMotion // ignore: cast_nullable_to_non_nullable
as bool,preferManualAlarm: null == preferManualAlarm ? _self.preferManualAlarm : preferManualAlarm // ignore: cast_nullable_to_non_nullable
as bool,quietHours: null == quietHours ? _self.quietHours : quietHours // ignore: cast_nullable_to_non_nullable
as bool,monitoring: null == monitoring ? _self.monitoring : monitoring // ignore: cast_nullable_to_non_nullable
as bool,holdBle: null == holdBle ? _self.holdBle : holdBle // ignore: cast_nullable_to_non_nullable
as bool,autoWrapReminder: null == autoWrapReminder ? _self.autoWrapReminder : autoWrapReminder // ignore: cast_nullable_to_non_nullable
as bool,otaChannel: null == otaChannel ? _self.otaChannel : otaChannel // ignore: cast_nullable_to_non_nullable
as OtaChannel,forceOta: null == forceOta ? _self.forceOta : forceOta // ignore: cast_nullable_to_non_nullable
as bool,customCatalog: null == customCatalog ? _self.customCatalog : customCatalog // ignore: cast_nullable_to_non_nullable
as List<CustomFood>,
  ));
}

}


/// Adds pattern-matching-related methods to [AppSettings].
extension AppSettingsPatterns on AppSettings {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AppSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AppSettings value)  $default,){
final _that = this;
switch (_that) {
case _AppSettings():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AppSettings value)?  $default,){
final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TempUnit units,  AppThemeMode themeMode,  DisplayProfile displayProfile,  Density density,  bool reducedMotion,  bool preferManualAlarm,  bool quietHours,  bool monitoring,  bool holdBle,  bool autoWrapReminder,  OtaChannel otaChannel,  bool forceOta,  List<CustomFood> customCatalog)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that.units,_that.themeMode,_that.displayProfile,_that.density,_that.reducedMotion,_that.preferManualAlarm,_that.quietHours,_that.monitoring,_that.holdBle,_that.autoWrapReminder,_that.otaChannel,_that.forceOta,_that.customCatalog);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TempUnit units,  AppThemeMode themeMode,  DisplayProfile displayProfile,  Density density,  bool reducedMotion,  bool preferManualAlarm,  bool quietHours,  bool monitoring,  bool holdBle,  bool autoWrapReminder,  OtaChannel otaChannel,  bool forceOta,  List<CustomFood> customCatalog)  $default,) {final _that = this;
switch (_that) {
case _AppSettings():
return $default(_that.units,_that.themeMode,_that.displayProfile,_that.density,_that.reducedMotion,_that.preferManualAlarm,_that.quietHours,_that.monitoring,_that.holdBle,_that.autoWrapReminder,_that.otaChannel,_that.forceOta,_that.customCatalog);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TempUnit units,  AppThemeMode themeMode,  DisplayProfile displayProfile,  Density density,  bool reducedMotion,  bool preferManualAlarm,  bool quietHours,  bool monitoring,  bool holdBle,  bool autoWrapReminder,  OtaChannel otaChannel,  bool forceOta,  List<CustomFood> customCatalog)?  $default,) {final _that = this;
switch (_that) {
case _AppSettings() when $default != null:
return $default(_that.units,_that.themeMode,_that.displayProfile,_that.density,_that.reducedMotion,_that.preferManualAlarm,_that.quietHours,_that.monitoring,_that.holdBle,_that.autoWrapReminder,_that.otaChannel,_that.forceOta,_that.customCatalog);case _:
  return null;

}
}

}

/// @nodoc


class _AppSettings implements AppSettings {
  const _AppSettings({this.units = TempUnit.fahrenheit, this.themeMode = AppThemeMode.system, this.displayProfile = DisplayProfile.standard, this.density = Density.compact, this.reducedMotion = false, this.preferManualAlarm = false, this.quietHours = true, this.monitoring = true, this.holdBle = true, this.autoWrapReminder = true, this.otaChannel = OtaChannel.stable, this.forceOta = false, final  List<CustomFood> customCatalog = const <CustomFood>[]}): _customCatalog = customCatalog;
  

/// Display only; data stays canonical tenths-°F.
@override@JsonKey() final  TempUnit units;
@override@JsonKey() final  AppThemeMode themeMode;
@override@JsonKey() final  DisplayProfile displayProfile;
@override@JsonKey() final  Density density;
@override@JsonKey() final  bool reducedMotion;
/// The user's own alarm wins over device rules.
@override@JsonKey() final  bool preferManualAlarm;
/// 22:00–06:00 silences warning/info, never critical.
@override@JsonKey() final  bool quietHours;
/// Background alarm monitoring.
@override@JsonKey() final  bool monitoring;
/// Keep BLE warm while on Wi-Fi for fast failover.
@override@JsonKey() final  bool holdBle;
/// The Timeline tab sends wrap/spritz reminders.
@override@JsonKey() final  bool autoWrapReminder;
@override@JsonKey() final  OtaChannel otaChannel;
/// Allow an OTA while a session is recording (the 409 override).
@override@JsonKey() final  bool forceOta;
/// User-defined foods, persisted with the preset library.
 final  List<CustomFood> _customCatalog;
/// User-defined foods, persisted with the preset library.
@override@JsonKey() List<CustomFood> get customCatalog {
  if (_customCatalog is EqualUnmodifiableListView) return _customCatalog;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_customCatalog);
}


/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AppSettingsCopyWith<_AppSettings> get copyWith => __$AppSettingsCopyWithImpl<_AppSettings>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AppSettings&&(identical(other.units, units) || other.units == units)&&(identical(other.themeMode, themeMode) || other.themeMode == themeMode)&&(identical(other.displayProfile, displayProfile) || other.displayProfile == displayProfile)&&(identical(other.density, density) || other.density == density)&&(identical(other.reducedMotion, reducedMotion) || other.reducedMotion == reducedMotion)&&(identical(other.preferManualAlarm, preferManualAlarm) || other.preferManualAlarm == preferManualAlarm)&&(identical(other.quietHours, quietHours) || other.quietHours == quietHours)&&(identical(other.monitoring, monitoring) || other.monitoring == monitoring)&&(identical(other.holdBle, holdBle) || other.holdBle == holdBle)&&(identical(other.autoWrapReminder, autoWrapReminder) || other.autoWrapReminder == autoWrapReminder)&&(identical(other.otaChannel, otaChannel) || other.otaChannel == otaChannel)&&(identical(other.forceOta, forceOta) || other.forceOta == forceOta)&&const DeepCollectionEquality().equals(other._customCatalog, _customCatalog));
}


@override
int get hashCode => Object.hash(runtimeType,units,themeMode,displayProfile,density,reducedMotion,preferManualAlarm,quietHours,monitoring,holdBle,autoWrapReminder,otaChannel,forceOta,const DeepCollectionEquality().hash(_customCatalog));

@override
String toString() {
  return 'AppSettings(units: $units, themeMode: $themeMode, displayProfile: $displayProfile, density: $density, reducedMotion: $reducedMotion, preferManualAlarm: $preferManualAlarm, quietHours: $quietHours, monitoring: $monitoring, holdBle: $holdBle, autoWrapReminder: $autoWrapReminder, otaChannel: $otaChannel, forceOta: $forceOta, customCatalog: $customCatalog)';
}


}

/// @nodoc
abstract mixin class _$AppSettingsCopyWith<$Res> implements $AppSettingsCopyWith<$Res> {
  factory _$AppSettingsCopyWith(_AppSettings value, $Res Function(_AppSettings) _then) = __$AppSettingsCopyWithImpl;
@override @useResult
$Res call({
 TempUnit units, AppThemeMode themeMode, DisplayProfile displayProfile, Density density, bool reducedMotion, bool preferManualAlarm, bool quietHours, bool monitoring, bool holdBle, bool autoWrapReminder, OtaChannel otaChannel, bool forceOta, List<CustomFood> customCatalog
});




}
/// @nodoc
class __$AppSettingsCopyWithImpl<$Res>
    implements _$AppSettingsCopyWith<$Res> {
  __$AppSettingsCopyWithImpl(this._self, this._then);

  final _AppSettings _self;
  final $Res Function(_AppSettings) _then;

/// Create a copy of AppSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? units = null,Object? themeMode = null,Object? displayProfile = null,Object? density = null,Object? reducedMotion = null,Object? preferManualAlarm = null,Object? quietHours = null,Object? monitoring = null,Object? holdBle = null,Object? autoWrapReminder = null,Object? otaChannel = null,Object? forceOta = null,Object? customCatalog = null,}) {
  return _then(_AppSettings(
units: null == units ? _self.units : units // ignore: cast_nullable_to_non_nullable
as TempUnit,themeMode: null == themeMode ? _self.themeMode : themeMode // ignore: cast_nullable_to_non_nullable
as AppThemeMode,displayProfile: null == displayProfile ? _self.displayProfile : displayProfile // ignore: cast_nullable_to_non_nullable
as DisplayProfile,density: null == density ? _self.density : density // ignore: cast_nullable_to_non_nullable
as Density,reducedMotion: null == reducedMotion ? _self.reducedMotion : reducedMotion // ignore: cast_nullable_to_non_nullable
as bool,preferManualAlarm: null == preferManualAlarm ? _self.preferManualAlarm : preferManualAlarm // ignore: cast_nullable_to_non_nullable
as bool,quietHours: null == quietHours ? _self.quietHours : quietHours // ignore: cast_nullable_to_non_nullable
as bool,monitoring: null == monitoring ? _self.monitoring : monitoring // ignore: cast_nullable_to_non_nullable
as bool,holdBle: null == holdBle ? _self.holdBle : holdBle // ignore: cast_nullable_to_non_nullable
as bool,autoWrapReminder: null == autoWrapReminder ? _self.autoWrapReminder : autoWrapReminder // ignore: cast_nullable_to_non_nullable
as bool,otaChannel: null == otaChannel ? _self.otaChannel : otaChannel // ignore: cast_nullable_to_non_nullable
as OtaChannel,forceOta: null == forceOta ? _self.forceOta : forceOta // ignore: cast_nullable_to_non_nullable
as bool,customCatalog: null == customCatalog ? _self._customCatalog : customCatalog // ignore: cast_nullable_to_non_nullable
as List<CustomFood>,
  ));
}


}

// dart format on
