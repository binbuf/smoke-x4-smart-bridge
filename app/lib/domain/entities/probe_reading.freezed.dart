// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'probe_reading.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ProbeReading {

 ProbeJack get jack;/// False for an unplugged or unused jack. Never rendered as `0°`.
 bool get attached;/// The current reading; [TempValue.absent] when detached.
 TempValue get temp;/// How current the reading is. Gates every derived value below via
/// [Freshness.showsDerived].
 Freshness get freshness;/// °F per hour, or null when unknown/stale.
 double? get trendFPerHr; bool get stalled;/// Tenths °F over the session, or null when the probe has no history.
 int? get peakF10; int? get lowF10; int? get avgF10;/// The ETA range or a named refusal; null when none was requested.
 EtaResult? get eta;/// Recent readings for the sparkline, tenths °F.
 List<int> get spark;
/// Create a copy of ProbeReading
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProbeReadingCopyWith<ProbeReading> get copyWith => _$ProbeReadingCopyWithImpl<ProbeReading>(this as ProbeReading, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProbeReading&&(identical(other.jack, jack) || other.jack == jack)&&(identical(other.attached, attached) || other.attached == attached)&&(identical(other.temp, temp) || other.temp == temp)&&(identical(other.freshness, freshness) || other.freshness == freshness)&&(identical(other.trendFPerHr, trendFPerHr) || other.trendFPerHr == trendFPerHr)&&(identical(other.stalled, stalled) || other.stalled == stalled)&&(identical(other.peakF10, peakF10) || other.peakF10 == peakF10)&&(identical(other.lowF10, lowF10) || other.lowF10 == lowF10)&&(identical(other.avgF10, avgF10) || other.avgF10 == avgF10)&&(identical(other.eta, eta) || other.eta == eta)&&const DeepCollectionEquality().equals(other.spark, spark));
}


@override
int get hashCode => Object.hash(runtimeType,jack,attached,temp,freshness,trendFPerHr,stalled,peakF10,lowF10,avgF10,eta,const DeepCollectionEquality().hash(spark));

@override
String toString() {
  return 'ProbeReading(jack: $jack, attached: $attached, temp: $temp, freshness: $freshness, trendFPerHr: $trendFPerHr, stalled: $stalled, peakF10: $peakF10, lowF10: $lowF10, avgF10: $avgF10, eta: $eta, spark: $spark)';
}


}

/// @nodoc
abstract mixin class $ProbeReadingCopyWith<$Res>  {
  factory $ProbeReadingCopyWith(ProbeReading value, $Res Function(ProbeReading) _then) = _$ProbeReadingCopyWithImpl;
@useResult
$Res call({
 ProbeJack jack, bool attached, TempValue temp, Freshness freshness, double? trendFPerHr, bool stalled, int? peakF10, int? lowF10, int? avgF10, EtaResult? eta, List<int> spark
});




}
/// @nodoc
class _$ProbeReadingCopyWithImpl<$Res>
    implements $ProbeReadingCopyWith<$Res> {
  _$ProbeReadingCopyWithImpl(this._self, this._then);

  final ProbeReading _self;
  final $Res Function(ProbeReading) _then;

/// Create a copy of ProbeReading
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? jack = null,Object? attached = null,Object? temp = null,Object? freshness = null,Object? trendFPerHr = freezed,Object? stalled = null,Object? peakF10 = freezed,Object? lowF10 = freezed,Object? avgF10 = freezed,Object? eta = freezed,Object? spark = null,}) {
  return _then(_self.copyWith(
jack: null == jack ? _self.jack : jack // ignore: cast_nullable_to_non_nullable
as ProbeJack,attached: null == attached ? _self.attached : attached // ignore: cast_nullable_to_non_nullable
as bool,temp: null == temp ? _self.temp : temp // ignore: cast_nullable_to_non_nullable
as TempValue,freshness: null == freshness ? _self.freshness : freshness // ignore: cast_nullable_to_non_nullable
as Freshness,trendFPerHr: freezed == trendFPerHr ? _self.trendFPerHr : trendFPerHr // ignore: cast_nullable_to_non_nullable
as double?,stalled: null == stalled ? _self.stalled : stalled // ignore: cast_nullable_to_non_nullable
as bool,peakF10: freezed == peakF10 ? _self.peakF10 : peakF10 // ignore: cast_nullable_to_non_nullable
as int?,lowF10: freezed == lowF10 ? _self.lowF10 : lowF10 // ignore: cast_nullable_to_non_nullable
as int?,avgF10: freezed == avgF10 ? _self.avgF10 : avgF10 // ignore: cast_nullable_to_non_nullable
as int?,eta: freezed == eta ? _self.eta : eta // ignore: cast_nullable_to_non_nullable
as EtaResult?,spark: null == spark ? _self.spark : spark // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}

}


/// Adds pattern-matching-related methods to [ProbeReading].
extension ProbeReadingPatterns on ProbeReading {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProbeReading value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProbeReading() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProbeReading value)  $default,){
final _that = this;
switch (_that) {
case _ProbeReading():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProbeReading value)?  $default,){
final _that = this;
switch (_that) {
case _ProbeReading() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProbeJack jack,  bool attached,  TempValue temp,  Freshness freshness,  double? trendFPerHr,  bool stalled,  int? peakF10,  int? lowF10,  int? avgF10,  EtaResult? eta,  List<int> spark)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProbeReading() when $default != null:
return $default(_that.jack,_that.attached,_that.temp,_that.freshness,_that.trendFPerHr,_that.stalled,_that.peakF10,_that.lowF10,_that.avgF10,_that.eta,_that.spark);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProbeJack jack,  bool attached,  TempValue temp,  Freshness freshness,  double? trendFPerHr,  bool stalled,  int? peakF10,  int? lowF10,  int? avgF10,  EtaResult? eta,  List<int> spark)  $default,) {final _that = this;
switch (_that) {
case _ProbeReading():
return $default(_that.jack,_that.attached,_that.temp,_that.freshness,_that.trendFPerHr,_that.stalled,_that.peakF10,_that.lowF10,_that.avgF10,_that.eta,_that.spark);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProbeJack jack,  bool attached,  TempValue temp,  Freshness freshness,  double? trendFPerHr,  bool stalled,  int? peakF10,  int? lowF10,  int? avgF10,  EtaResult? eta,  List<int> spark)?  $default,) {final _that = this;
switch (_that) {
case _ProbeReading() when $default != null:
return $default(_that.jack,_that.attached,_that.temp,_that.freshness,_that.trendFPerHr,_that.stalled,_that.peakF10,_that.lowF10,_that.avgF10,_that.eta,_that.spark);case _:
  return null;

}
}

}

/// @nodoc


class _ProbeReading implements ProbeReading {
  const _ProbeReading({required this.jack, this.attached = false, this.temp = const TempValue.absent(), this.freshness = Freshness.unknown, this.trendFPerHr, this.stalled = false, this.peakF10, this.lowF10, this.avgF10, this.eta, final  List<int> spark = const <int>[]}): _spark = spark;
  

@override final  ProbeJack jack;
/// False for an unplugged or unused jack. Never rendered as `0°`.
@override@JsonKey() final  bool attached;
/// The current reading; [TempValue.absent] when detached.
@override@JsonKey() final  TempValue temp;
/// How current the reading is. Gates every derived value below via
/// [Freshness.showsDerived].
@override@JsonKey() final  Freshness freshness;
/// °F per hour, or null when unknown/stale.
@override final  double? trendFPerHr;
@override@JsonKey() final  bool stalled;
/// Tenths °F over the session, or null when the probe has no history.
@override final  int? peakF10;
@override final  int? lowF10;
@override final  int? avgF10;
/// The ETA range or a named refusal; null when none was requested.
@override final  EtaResult? eta;
/// Recent readings for the sparkline, tenths °F.
 final  List<int> _spark;
/// Recent readings for the sparkline, tenths °F.
@override@JsonKey() List<int> get spark {
  if (_spark is EqualUnmodifiableListView) return _spark;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_spark);
}


/// Create a copy of ProbeReading
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProbeReadingCopyWith<_ProbeReading> get copyWith => __$ProbeReadingCopyWithImpl<_ProbeReading>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProbeReading&&(identical(other.jack, jack) || other.jack == jack)&&(identical(other.attached, attached) || other.attached == attached)&&(identical(other.temp, temp) || other.temp == temp)&&(identical(other.freshness, freshness) || other.freshness == freshness)&&(identical(other.trendFPerHr, trendFPerHr) || other.trendFPerHr == trendFPerHr)&&(identical(other.stalled, stalled) || other.stalled == stalled)&&(identical(other.peakF10, peakF10) || other.peakF10 == peakF10)&&(identical(other.lowF10, lowF10) || other.lowF10 == lowF10)&&(identical(other.avgF10, avgF10) || other.avgF10 == avgF10)&&(identical(other.eta, eta) || other.eta == eta)&&const DeepCollectionEquality().equals(other._spark, _spark));
}


@override
int get hashCode => Object.hash(runtimeType,jack,attached,temp,freshness,trendFPerHr,stalled,peakF10,lowF10,avgF10,eta,const DeepCollectionEquality().hash(_spark));

@override
String toString() {
  return 'ProbeReading(jack: $jack, attached: $attached, temp: $temp, freshness: $freshness, trendFPerHr: $trendFPerHr, stalled: $stalled, peakF10: $peakF10, lowF10: $lowF10, avgF10: $avgF10, eta: $eta, spark: $spark)';
}


}

/// @nodoc
abstract mixin class _$ProbeReadingCopyWith<$Res> implements $ProbeReadingCopyWith<$Res> {
  factory _$ProbeReadingCopyWith(_ProbeReading value, $Res Function(_ProbeReading) _then) = __$ProbeReadingCopyWithImpl;
@override @useResult
$Res call({
 ProbeJack jack, bool attached, TempValue temp, Freshness freshness, double? trendFPerHr, bool stalled, int? peakF10, int? lowF10, int? avgF10, EtaResult? eta, List<int> spark
});




}
/// @nodoc
class __$ProbeReadingCopyWithImpl<$Res>
    implements _$ProbeReadingCopyWith<$Res> {
  __$ProbeReadingCopyWithImpl(this._self, this._then);

  final _ProbeReading _self;
  final $Res Function(_ProbeReading) _then;

/// Create a copy of ProbeReading
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? jack = null,Object? attached = null,Object? temp = null,Object? freshness = null,Object? trendFPerHr = freezed,Object? stalled = null,Object? peakF10 = freezed,Object? lowF10 = freezed,Object? avgF10 = freezed,Object? eta = freezed,Object? spark = null,}) {
  return _then(_ProbeReading(
jack: null == jack ? _self.jack : jack // ignore: cast_nullable_to_non_nullable
as ProbeJack,attached: null == attached ? _self.attached : attached // ignore: cast_nullable_to_non_nullable
as bool,temp: null == temp ? _self.temp : temp // ignore: cast_nullable_to_non_nullable
as TempValue,freshness: null == freshness ? _self.freshness : freshness // ignore: cast_nullable_to_non_nullable
as Freshness,trendFPerHr: freezed == trendFPerHr ? _self.trendFPerHr : trendFPerHr // ignore: cast_nullable_to_non_nullable
as double?,stalled: null == stalled ? _self.stalled : stalled // ignore: cast_nullable_to_non_nullable
as bool,peakF10: freezed == peakF10 ? _self.peakF10 : peakF10 // ignore: cast_nullable_to_non_nullable
as int?,lowF10: freezed == lowF10 ? _self.lowF10 : lowF10 // ignore: cast_nullable_to_non_nullable
as int?,avgF10: freezed == avgF10 ? _self.avgF10 : avgF10 // ignore: cast_nullable_to_non_nullable
as int?,eta: freezed == eta ? _self.eta : eta // ignore: cast_nullable_to_non_nullable
as EtaResult?,spark: null == spark ? _self._spark : spark // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}


}

// dart format on
