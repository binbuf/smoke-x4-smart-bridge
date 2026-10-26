import 'prototype_controller.dart';

String commaInt(int value) {
  final text = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return value < 0 ? '-$buffer' : buffer.toString();
}

String percent(int value) => '$value%';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String shortDate(DateTime time) => '${_months[time.month - 1]} ${time.day}';

String shortDateWithYear(DateTime time) => '${shortDate(time)}, ${time.year}';

String clockLabel(DateTime time, {bool use24Hour = false}) {
  if (use24Hour) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  final hour = time.hour == 0
      ? 12
      : (time.hour > 12 ? time.hour - 12 : time.hour);
  final minute = time.minute.toString().padLeft(2, '0');
  final suffix = time.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

String chartTime(DateTime time, Duration span, {bool use24Hour = false}) {
  if (span.inHours <= 24 && time.hour != 0) {
    return clockLabel(time, use24Hour: use24Hour);
  }
  return shortDate(time);
}

String historyRangeLabel(HistoryRange range) {
  switch (range) {
    case HistoryRange.oneHour:
      return '1 h';
    case HistoryRange.sixHours:
      return '6 h';
    case HistoryRange.twentyFourHours:
      return '24 h';
    case HistoryRange.twoDays:
      return '2 d';
    case HistoryRange.custom:
      return 'Custom';
  }
}

String historyChipLabel(HistoryRange range) {
  switch (range) {
    case HistoryRange.oneHour:
      return '1H';
    case HistoryRange.sixHours:
      return '6H';
    case HistoryRange.twentyFourHours:
      return '24H';
    case HistoryRange.twoDays:
      return '2D';
    case HistoryRange.custom:
      return 'CUSTOM';
  }
}

String historyWindowLabel(
  HistoryRange range,
  DateTime start,
  DateTime end, {
  bool use24Hour = false,
}) {
  switch (range) {
    case HistoryRange.oneHour:
    case HistoryRange.sixHours:
    case HistoryRange.twentyFourHours:
    case HistoryRange.twoDays:
    case HistoryRange.custom:
      final sameDay =
          start.year == end.year &&
          start.month == end.month &&
          start.day == end.day;
      if (sameDay) {
        return '${shortDate(start)} · ${clockLabel(start, use24Hour: use24Hour)} – ${clockLabel(end, use24Hour: use24Hour)}';
      }
      return '${shortDate(start)} ${clockLabel(start, use24Hour: use24Hour)} – ${shortDate(end)} ${clockLabel(end, use24Hour: use24Hour)}';
  }
}

String timeRangeLabel(DateTime start, DateTime end, {bool use24Hour = false}) {
  return '${clockLabel(start, use24Hour: use24Hour)} – ${clockLabel(end, use24Hour: use24Hour)}';
}

String durationShort(Duration duration) {
  final value = duration.abs();
  if (value.inMinutes < 1) return '${value.inSeconds}s';
  if (value.inHours < 1) return '${value.inMinutes}m';
  if (value.inDays >= 1) {
    final days = value.inDays;
    final hours = value.inHours % 24;
    return hours == 0 ? '${days}d' : '${days}d ${hours}h';
  }
  final hours = value.inHours;
  final minutes = value.inMinutes % 60;
  return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
}

String dayLabel(DateTime day, {DateTime? relativeTo}) {
  final today = relativeTo ?? DateTime(2026, 10, 25);
  final normalized = DateTime(day.year, day.month, day.day);
  final todayOnly = DateTime(today.year, today.month, today.day);
  if (normalized == todayOnly) return 'Today';
  if (normalized == todayOnly.subtract(const Duration(days: 1))) {
    return 'Yesterday';
  }
  return shortDateWithYear(day);
}

String relativeMinutes(int minutes) {
  if (minutes < 1) return 'just now';
  if (minutes == 1) return '1m ago';
  if (minutes < 60) return '${minutes}m ago';
  final hours = minutes ~/ 60;
  if (hours == 1) return '1h ago';
  return '${hours}h ago';
}

String unitLabel(Units units) => units == Units.fahrenheit ? '°F' : '°C';

String displayTemp(double? fahrenheit, Units units, {bool withUnit = true}) {
  if (fahrenheit == null) return '—';
  final value = units == Units.fahrenheit
      ? fahrenheit
      : (fahrenheit - 32) * 5 / 9;
  final text = value.toStringAsFixed(1);
  return withUnit ? '$text ${unitLabel(units)}' : text;
}

String deltaLabel(double? fahrenheit, Units units) {
  if (fahrenheit == null) return '';
  final value = units == Units.fahrenheit ? fahrenheit : fahrenheit * 5 / 9;
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(1)}°';
}

String gapDurationLabel(Duration duration) {
  final minutes = duration.inMinutes.abs();
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
}
