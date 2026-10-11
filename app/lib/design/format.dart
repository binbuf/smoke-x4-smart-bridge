/// Small, honest formatters shared by the screens.
///
/// Absent values are never fabricated: a unknown time formats to an em dash,
/// not to `0` or to an epoch date.
library;

/// `2h 31m`, `31m`, `45s`, or `—` for a null/negative duration.
String formatDuration(int? seconds) {
  if (seconds == null || seconds < 0) {
    return '—';
  }
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) {
    return '${h}h ${m}m';
  }
  if (m > 0) {
    return '${m}m';
  }
  return '${s}s';
}

/// `Sat 14 Mar, 06:12` in local time, or `—` when the bridge had no clock.
String formatClock(int? unixMs) {
  if (unixMs == null || unixMs <= 0) {
    return '—';
  }
  final d = DateTime.fromMillisecondsSinceEpoch(unixMs).toLocal();
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
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
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}, $hh:$mm';
}

/// A short relative age — `just now`, `12s ago`, `4m ago`, `1h 03m ago` — or
/// `—` when there is no timestamp. Relative age is the trust signal; an absolute
/// clock time makes the reader do the subtraction.
String formatAge(DateTime? at, {DateTime? now}) {
  if (at == null) {
    return '—';
  }
  final s = (now ?? DateTime.now()).difference(at).inSeconds;
  if (s < 5) {
    return 'just now';
  }
  if (s < 60) {
    return '${s}s ago';
  }
  final m = s ~/ 60;
  if (m < 60) {
    return '${m}m ago';
  }
  final h = m ~/ 60;
  return '${h}h ${(m % 60).toString().padLeft(2, '0')}m ago';
}

/// Seconds into a session as `h:mm:ss` / `m:ss`.
String formatElapsed(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}
