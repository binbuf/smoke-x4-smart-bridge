/// N5 — the Live screen's pure projections.
///
/// Formatting and naming only: no Flutter, no repository. Kept out of the
/// widgets so `fmtStopwatch`, `probeName` and the temp split can be unit-tested
/// against the prototype's exact strings.
library;

import '../../data/content/catalog.dart';
import '../../data/model/cook_state.dart';
import '../../domain/domain.dart';

/// `HH:MM:SS`, clamped at zero. The prototype's `fmtStopwatch`.
String fmtStopwatch(int ms) {
  final t = ms <= 0 ? 0 : (ms / 1000).round();
  final h = t ~/ 3600;
  final m = (t % 3600) ~/ 60;
  final s = t % 60;
  return '${_two(h)}:${_two(m)}:${_two(s)}';
}

/// `4h 12m` / `38m` / `12s`. The prototype's `fmtDuration`.
String fmtDuration(int ms) {
  final t = ms <= 0 ? 0 : (ms / 1000).round();
  final h = t ~/ 3600;
  final m = (t % 3600) ~/ 60;
  final s = t % 60;
  if (h > 0) {
    return '${h}h ${m}m';
  }
  if (m > 0) {
    return '${m}m';
  }
  return '${s}s';
}

/// A 12-hour clock label (`9:41 AM`). The prototype's `fmtClock`.
String fmtClock(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = _two(time.minute);
  return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
}

/// `<1 min` / `38 min` / `1h 5m`, or null when there is no estimate. This is
/// only ever called behind the I4 gate ([Freshness.showsDerived]).
String? fmtEta(int? minutes) {
  if (minutes == null) {
    return null;
  }
  if (minutes < 1) {
    return '<1 min';
  }
  if (minutes < 60) {
    return '$minutes min';
  }
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// The unit suffix (`° F` / `° C`).
String unitLabel(TempUnit unit) => unit.suffix;

/// A temperature split into the compact tile's parts. Absent is `—`, never `0`
/// (I3).
({String num, String dec, String unit}) tempParts(int? f10, TempUnit unit) {
  final value = f10 == null ? null : TempValue.ofF10(f10).toDisplay(unit);
  if (value == null) {
    return (num: '—', dec: '', unit: '');
  }
  final s = value.toStringAsFixed(1);
  final dot = s.indexOf('.');
  return (num: s.substring(0, dot), dec: s.substring(dot), unit: unit.suffix);
}

/// A screen-reader phrase for a temperature (N16.3).
///
/// The visual readout stays compact (`164.2° F`); a screen reader gets the
/// words. Absent is **"No reading"**, never "zero" (I3/I14).
String spokenTemp(int? f10, TempUnit unit) {
  if (f10 == null) {
    return 'No reading';
  }
  final value = TempValue.ofF10(f10).toDisplay(unit);
  final scale = unit == TempUnit.fahrenheit ? 'Fahrenheit' : 'Celsius';
  return '${value!.toStringAsFixed(1)} degrees $scale';
}

/// A whole-degree temperature, or `—` (I3). Used by the summary strip.
String fmtTemp0(int? f10, TempUnit unit) {
  final value = f10 == null ? null : TempValue.ofF10(f10).toDisplay(unit);
  if (value == null) {
    return '—';
  }
  return value.round().toString();
}

/// Whether a probe is a live, attached reading (not unplugged, not unused).
bool isLiveProbe(ProbeState probe) =>
    probe.attached && probe.role != ProbeRole.unused;

/// The tile name: grate, catalog name when a cook item is assigned, else
/// `Probe N`. The prototype's `probeName`.
String probeName(ProbeState probe, CookState cook, CatalogTable catalog) {
  if (probe.role == ProbeRole.pit) {
    return 'Grate · jack ${probe.jack.n}';
  }
  if (probe.role == ProbeRole.unused) {
    return 'Jack ${probe.jack.n} · unused';
  }
  for (final item in cook.items) {
    if (item.jack == probe.jack) {
      final entry = catalog.byId(item.presetId);
      if (entry != null) {
        return entry.name;
      }
    }
  }
  return 'Probe ${probe.jack.n}';
}

String _two(int n) => n.toString().padLeft(2, '0');
