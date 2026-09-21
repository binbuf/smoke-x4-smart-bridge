// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'temperature_reading.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TemperatureReading _$TemperatureReadingFromJson(Map<String, dynamic> json) =>
    _TemperatureReading(
      probeId: json['probeId'] as String,
      tempF10: (json['tempF10'] as num).toInt(),
      recordedAt: DateTime.parse(json['recordedAt'] as String),
    );

Map<String, dynamic> _$TemperatureReadingToJson(_TemperatureReading instance) =>
    <String, dynamic>{
      'probeId': instance.probeId,
      'tempF10': instance.tempF10,
      'recordedAt': instance.recordedAt.toIso8601String(),
    };
