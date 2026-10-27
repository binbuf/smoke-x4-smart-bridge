import '../domain/models.dart';

/// Production formatter layer.
///
/// Everything here is a pure function so it can be unit-tested on the host and
/// reused by screens, the chart and the debug screenshot generator. Dates and
/// times take `use24Hour` from the widget layer; full locale plumbing lands with
/// T53, which owns units/time/theme end-to-end.

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
  if (span.inHours <= 24) {
    if (time.hour == 0 && time.minute == 0) return shortDate(time);
    return clockLabel(time, use24Hour: use24Hour);
  }
  return '${shortDate(time)} ${clockLabel(time, use24Hour: use24Hour)}';
}

String historyRangeLabel(HistoryRange range) {
  switch (range) {
    case HistoryRange.oneHour:
      return 'Last hour';
    case HistoryRange.sixHours:
      return 'Last 6 hours';
    case HistoryRange.twentyFourHours:
      return 'Last 24 hours';
    case HistoryRange.twoDays:
      return 'Last 2 days';
    case HistoryRange.custom:
      return 'Custom';
  }
}

String historyChipLabel(HistoryRange range) {
  switch (range) {
    case HistoryRange.oneHour:
      return '1 hour';
    case HistoryRange.sixHours:
      return '6 hours';
    case HistoryRange.twentyFourHours:
      return '24 hours';
    case HistoryRange.twoDays:
      return '2 days';
    case HistoryRange.custom:
      return 'Custom';
  }
}

String historyRangeKey(HistoryRange range) {
  switch (range) {
    case HistoryRange.oneHour:
      return '1h';
    case HistoryRange.sixHours:
      return '6h';
    case HistoryRange.twentyFourHours:
      return '24h';
    case HistoryRange.twoDays:
      return '2d';
    case HistoryRange.custom:
      return 'custom';
  }
}

String historyWindowLabel(
  HistoryRange range,
  DateTime start,
  DateTime end, {
  bool use24Hour = false,
}) {
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  if (sameDay) {
    return '${shortDate(start)}, ${clockLabel(start, use24Hour: use24Hour)} – ${clockLabel(end, use24Hour: use24Hour)}';
  }
  return '${shortDate(start)}, ${clockLabel(start, use24Hour: use24Hour)} – ${shortDate(end)}, ${clockLabel(end, use24Hour: use24Hour)}';
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

String durationLong(Duration duration) {
  final value = duration.abs();
  if (value.inMinutes < 1) {
    return '${value.inSeconds} ${value.inSeconds == 1 ? 'second' : 'seconds'}';
  }
  if (value.inHours < 1) {
    return '${value.inMinutes} ${value.inMinutes == 1 ? 'minute' : 'minutes'}';
  }
  if (value.inDays >= 1) {
    final days = value.inDays;
    final hours = value.inHours % 24;
    final dayLabel = '$days ${days == 1 ? 'day' : 'days'}';
    if (hours == 0) return dayLabel;
    return '$dayLabel, $hours ${hours == 1 ? 'hour' : 'hours'}';
  }
  final hours = value.inHours;
  final minutes = value.inMinutes % 60;
  final hourLabel = '$hours ${hours == 1 ? 'hour' : 'hours'}';
  if (minutes == 0) return hourLabel;
  return '$hourLabel, $minutes ${minutes == 1 ? 'minute' : 'minutes'}';
}

String dayLabel(DateTime day, {DateTime? relativeTo}) {
  final today = relativeTo ?? DateTime.now();
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
