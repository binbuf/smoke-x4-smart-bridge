// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'temperature_reading.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TemperatureReading {

 String get probeId;/// Tenths of a degree Fahrenheit — canonical storage (decision D7).
 int get tempF10; DateTime get recordedAt;
/// Create a copy of TemperatureReading
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TemperatureReadingCopyWith<TemperatureReading> get copyWith => _$TemperatureReadingCopyWithImpl<TemperatureReading>(this as TemperatureReading, _$identity);

  /// Serializes this TemperatureReading to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TemperatureReading&&(identical(other.probeId, probeId) || other.probeId == probeId)&&(identical(other.tempF10, tempF10) || other.tempF10 == tempF10)&&(identical(other.recordedAt, recordedAt) || other.recordedAt == recordedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,probeId,tempF10,recordedAt);

@override
String toString() {
  return 'TemperatureReading(probeId: $probeId, tempF10: $tempF10, recordedAt: $recordedAt)';
}


}

/// @nodoc
abstract mixin class $TemperatureReadingCopyWith<$Res>  {
  factory $TemperatureReadingCopyWith(TemperatureReading value, $Res Function(TemperatureReading) _then) = _$TemperatureReadingCopyWithImpl;
@useResult
$Res call({
 String probeId, int tempF10, DateTime recordedAt
});




}
/// @nodoc
class _$TemperatureReadingCopyWithImpl<$Res>
    implements $TemperatureReadingCopyWith<$Res> {
  _$TemperatureReadingCopyWithImpl(this._self, this._then);

  final TemperatureReading _self;
  final $Res Function(TemperatureReading) _then;

/// Create a copy of TemperatureReading
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? probeId = null,Object? tempF10 = null,Object? recordedAt = null,}) {
  return _then(_self.copyWith(
probeId: null == probeId ? _self.probeId : probeId // ignore: cast_nullable_to_non_nullable
as String,tempF10: null == tempF10 ? _self.tempF10 : tempF10 // ignore: cast_nullable_to_non_nullable
as int,recordedAt: null == recordedAt ? _self.recordedAt : recordedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [TemperatureReading].
extension TemperatureReadingPatterns on TemperatureReading {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TemperatureReading value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TemperatureReading() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TemperatureReading value)  $default,){
final _that = this;
switch (_that) {
case _TemperatureReading():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TemperatureReading value)?  $default,){
final _that = this;
switch (_that) {
case _TemperatureReading() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String probeId,  int tempF10,  DateTime recordedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TemperatureReading() when $default != null:
return $default(_that.probeId,_that.tempF10,_that.recordedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String probeId,  int tempF10,  DateTime recordedAt)  $default,) {final _that = this;
switch (_that) {
case _TemperatureReading():
return $default(_that.probeId,_that.tempF10,_that.recordedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String probeId,  int tempF10,  DateTime recordedAt)?  $default,) {final _that = this;
switch (_that) {
case _TemperatureReading() when $default != null:
return $default(_that.probeId,_that.tempF10,_that.recordedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TemperatureReading implements TemperatureReading {
  const _TemperatureReading({required this.probeId, required this.tempF10, required this.recordedAt});
  factory _TemperatureReading.fromJson(Map<String, dynamic> json) => _$TemperatureReadingFromJson(json);

@override final  String probeId;
/// Tenths of a degree Fahrenheit — canonical storage (decision D7).
@override final  int tempF10;
@override final  DateTime recordedAt;

/// Create a copy of TemperatureReading
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TemperatureReadingCopyWith<_TemperatureReading> get copyWith => __$TemperatureReadingCopyWithImpl<_TemperatureReading>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TemperatureReadingToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TemperatureReading&&(identical(other.probeId, probeId) || other.probeId == probeId)&&(identical(other.tempF10, tempF10) || other.tempF10 == tempF10)&&(identical(other.recordedAt, recordedAt) || other.recordedAt == recordedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,probeId,tempF10,recordedAt);

@override
String toString() {
  return 'TemperatureReading(probeId: $probeId, tempF10: $tempF10, recordedAt: $recordedAt)';
}


}

/// @nodoc
abstract mixin class _$TemperatureReadingCopyWith<$Res> implements $TemperatureReadingCopyWith<$Res> {
  factory _$TemperatureReadingCopyWith(_TemperatureReading value, $Res Function(_TemperatureReading) _then) = __$TemperatureReadingCopyWithImpl;
@override @useResult
$Res call({
 String probeId, int tempF10, DateTime recordedAt
});




}
/// @nodoc
class __$TemperatureReadingCopyWithImpl<$Res>
    implements _$TemperatureReadingCopyWith<$Res> {
  __$TemperatureReadingCopyWithImpl(this._self, this._then);

  final _TemperatureReading _self;
  final $Res Function(_TemperatureReading) _then;

/// Create a copy of TemperatureReading
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? probeId = null,Object? tempF10 = null,Object? recordedAt = null,}) {
  return _then(_TemperatureReading(
probeId: null == probeId ? _self.probeId : probeId // ignore: cast_nullable_to_non_nullable
as String,tempF10: null == tempF10 ? _self.tempF10 : tempF10 // ignore: cast_nullable_to_non_nullable
as int,recordedAt: null == recordedAt ? _self.recordedAt : recordedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
