import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../domain/models.dart';

/// Production formatter layer.
///
/// Everything here is a pure function so it can be unit-tested on the host and
/// reused by screens, the chart and the debug screenshot generator. Numbers and
/// dates use the process-wide `Intl.defaultLocale`, which the app sets from the
/// device locale once in [bootstrap] and again on a locale change. Callers that
/// already know the locale may pass it explicitly.
///
/// Temperature conversion lives here too: every screen, chart, confirmation and
/// the OLED go through [toDisplayTemperature] / [displayTemp]. Stored samples
/// stay in °F.

bool _dateSymbolsReady = false;

/// Loads CLDR date symbols once. The underlying intl call initialises its maps
/// synchronously before returning an already-completed future.
void _ensureDateSymbols() {
  if (_dateSymbolsReady) return;
  initializeDateFormatting();
  _dateSymbolsReady = true;
}

String _localeOrCurrent(String? locale) => locale ?? Intl.getCurrentLocale();

/// Locale-aware grouping for counts and storage (`128,430` in `en_US`).
String commaInt(int value, {String? locale}) {
  try {
    return NumberFormat.decimalPattern(_localeOrCurrent(locale)).format(value);
  } catch (_) {
    // A malformed locale from the platform must not blank a count.
    final text = value.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
      buffer.write(text[i]);
    }
    return value < 0 ? '-$buffer' : buffer.toString();
  }
}

String percent(int value) => '$value%';

// ---------------------------------------------------------------------------
// Temperature: one conversion path.
// ---------------------------------------------------------------------------

/// Converts a canonical °F value to the presentation unit.
double toDisplayTemperature(double fahrenheit, Units units) =>
    units == Units.fahrenheit ? fahrenheit : (fahrenheit - 32) * 5 / 9;

/// Converts a temperature *difference*; the affine offset does not apply.
double toDisplayTemperatureDelta(double fahrenheitDelta, Units units) =>
    units == Units.fahrenheit ? fahrenheitDelta : fahrenheitDelta * 5 / 9;

/// `165.2` in the selected unit, one decimal, or `—` when unknown.
String temperatureValue(double? fahrenheit, Units units) {
  if (fahrenheit == null) return '—';
  return toDisplayTemperature(fahrenheit, units).toStringAsFixed(1);
}

/// `165.2°F` (no space, 13 §13.6) or `165.2°C`.
String temperatureText(double? fahrenheit, Units units) {
  if (fahrenheit == null) return '—';
  return '${temperatureValue(fahrenheit, units)}${unitLabel(units)}';
}

String temperatureDeltaText(double? fahrenheitDelta, Units units) {
  if (fahrenheitDelta == null) return '';
  final value = toDisplayTemperatureDelta(fahrenheitDelta, units);
  final sign = value > 0 ? '+' : (value < 0 ? '-' : '±');
  return '$sign${value.abs().toStringAsFixed(1)}${unitLabel(units)}';
}

String unitLabel(Units units) => units == Units.fahrenheit ? '°F' : '°C';

/// Backwards-compatible wrapper. Prefer [temperatureText] for new code.
String displayTemp(double? fahrenheit, Units units, {bool withUnit = true}) {
  if (fahrenheit == null) return '—';
  return withUnit
      ? temperatureText(fahrenheit, units)
      : temperatureValue(fahrenheit, units);
}

/// Backwards-compatible signed delta used by older widgets.
String deltaLabel(double? fahrenheit, Units units) =>
    temperatureDeltaText(fahrenheit, units);

// ---------------------------------------------------------------------------
// Dates and times.
// ---------------------------------------------------------------------------

String shortDate(DateTime time, {String? locale}) {
  _ensureDateSymbols();
  return DateFormat.MMMd(_localeOrCurrent(locale)).format(time);
}

String shortDateWithYear(DateTime time, {String? locale}) {
  _ensureDateSymbols();
  return DateFormat.yMMMd(_localeOrCurrent(locale)).format(time);
}

/// Upper-case month abbreviation for compact cook tiles (`OCT` in `en_US`).
String monthShort(DateTime time, {bool upper = false, String? locale}) {
  _ensureDateSymbols();
  final value = DateFormat.MMM(_localeOrCurrent(locale)).format(time);
  return upper ? value.toUpperCase() : value;
}

/// Compact date span used by History & storage and its delete sheets.
///
/// Same-year spans name the year once (`Sep 1 – Oct 24, 2026`); a span across
/// years keeps both. Same-day spans keep the date once.
String dateRangeLabel(DateTime start, DateTime end, {String? locale}) {
  if (start.year == end.year &&
      start.month == end.month &&
      start.day == end.day) {
    return shortDateWithYear(start, locale: locale);
  }
  if (start.year == end.year) {
    return '${shortDate(start, locale: locale)} – ${shortDateWithYear(end, locale: locale)}';
  }
  return '${shortDateWithYear(start, locale: locale)} – ${shortDateWithYear(end, locale: locale)}';
}

String dateTimeLabel(
  DateTime time, {
  bool use24Hour = false,
  String? locale,
}) =>
    '${shortDateWithYear(time, locale: locale)} at '
    '${clockLabel(time, use24Hour: use24Hour, locale: locale)}';

/// Absolute first–last reading span with times, used in deletion confirmations.
/// Unlike [historyWindowLabel] this is not tied to a [HistoryRange].
String absoluteRangeLabel(
  DateTime start,
  DateTime end, {
  bool use24Hour = false,
  String? locale,
}) {
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  final startClock = clockLabel(start, use24Hour: use24Hour, locale: locale);
  final endClock = clockLabel(end, use24Hour: use24Hour, locale: locale);
  if (sameDay) {
    return '${shortDate(start, locale: locale)}, $startClock – $endClock';
  }
  if (start.year == end.year) {
    return '${shortDate(start, locale: locale)}, $startClock – '
        '${shortDateWithYear(end, locale: locale)}, $endClock';
  }
  return '${dateTimeLabel(start, use24Hour: use24Hour, locale: locale)} – '
      '${dateTimeLabel(end, use24Hour: use24Hour, locale: locale)}';
}

/// Decimal storage size, matching the storage figures in 04 §4.9.
String storageSizeLabel(int bytes, {String? locale}) {
  if (bytes <= 0) return '0 B';
  final decimal = _decimalOneFormat(locale);
  if (bytes < 1000) return '${commaInt(bytes, locale: locale)} B';
  if (bytes < 1000000) return '${decimal.format(bytes / 1000)} KB';
  return '${decimal.format(bytes / 1000000)} MB';
}

NumberFormat _decimalOneFormat(String? locale) {
  try {
    return NumberFormat('0.0', _localeOrCurrent(locale));
  } catch (_) {
    return NumberFormat('0.0', 'en_US');
  }
}

/// Time of day in the device locale. The 12/24-hour *choice* comes from the
/// platform setting; the AM/PM markers, if any, come from CLDR. Nothing here
/// hard-codes `AM` or `PM`.
String clockLabel(DateTime time, {bool use24Hour = false, String? locale}) {
  _ensureDateSymbols();
  final effective = _localeOrCurrent(locale);
  final pattern = use24Hour ? 'Hm' : 'h:mm a';
  try {
    return DateFormat(pattern, effective).format(time);
  } catch (_) {
    return DateFormat(pattern, 'en_US').format(time);
  }
}

String chartTime(
  DateTime time,
  Duration span, {
  bool use24Hour = false,
  String? locale,
}) {
  if (span.inHours <= 24) {
    if (time.hour == 0 && time.minute == 0) {
      return shortDate(time, locale: locale);
    }
    return clockLabel(time, use24Hour: use24Hour, locale: locale);
  }
  return '${shortDate(time, locale: locale)} '
      '${clockLabel(time, use24Hour: use24Hour, locale: locale)}';
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
  String? locale,
}) {
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  if (sameDay) {
    return '${shortDate(start, locale: locale)}, '
        '${clockLabel(start, use24Hour: use24Hour, locale: locale)} – '
        '${clockLabel(end, use24Hour: use24Hour, locale: locale)}';
  }
  return '${shortDate(start, locale: locale)}, '
      '${clockLabel(start, use24Hour: use24Hour, locale: locale)} – '
      '${shortDate(end, locale: locale)}, '
      '${clockLabel(end, use24Hour: use24Hour, locale: locale)}';
}

String timeRangeLabel(
  DateTime start,
  DateTime end, {
  bool use24Hour = false,
  String? locale,
}) {
  return '${clockLabel(start, use24Hour: use24Hour, locale: locale)} – '
      '${clockLabel(end, use24Hour: use24Hour, locale: locale)}';
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

String dayLabel(DateTime day, {DateTime? relativeTo, String? locale}) {
  final today = relativeTo ?? DateTime.now();
  final normalized = DateTime(day.year, day.month, day.day);
  final todayOnly = DateTime(today.year, today.month, today.day);
  if (normalized == todayOnly) return 'Today';
  if (normalized == todayOnly.subtract(const Duration(days: 1))) {
    return 'Yesterday';
  }
  return shortDateWithYear(day, locale: locale);
}

String relativeMinutes(int minutes) {
  if (minutes < 1) return 'just now';
  if (minutes == 1) return '1m ago';
  if (minutes < 60) return '${minutes}m ago';
  final hours = minutes ~/ 60;
  if (hours == 1) return '1h ago';
  return '${hours}h ago';
}

String gapDurationLabel(Duration duration) {
  final minutes = duration.inMinutes.abs();
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
}
