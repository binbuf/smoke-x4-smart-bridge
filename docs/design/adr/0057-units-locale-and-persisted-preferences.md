# 0057 — Units, locale formatting and persisted local preferences

**Status:** accepted · 2026-10-27

## Context

T51 made units, Appearance and `Live change window` work in-process, but only
Appearance survived a relaunch. T53 had to make units, theme and the change
window persist, and to make the device locale and 12/24-hour setting govern
every date, time and count without introducing a second temperature conversion.
The History read model loads asynchronously, so a unit change could otherwise
show the previous unit until the next archive read.

## Decision

- `app/lib/app/formatters.dart` is the only conversion and formatting layer.
  `toDisplayTemperature`, `toDisplayTemperatureDelta`, `temperatureValue`,
  `temperatureText` and `temperatureDeltaText` own °F→°C. Charts, sparklines,
  live tiles, Billows, the Cook view, confirmations, counts, storage and the
  OLED view call these helpers or consume the controller's pre-formatted view
  state. Stored samples remain canonical °F.
- Numbers and dates use `intl` with `Intl.defaultLocale`, set from the device
  locale in `bootstrap` and kept in step by `SmokeBridgeApp`. The 12/24-hour
  choice comes from `PlatformDispatcher.alwaysUse24HourFormat`; widgets already
  read `MediaQuery.alwaysUse24HourFormatOf`. No production code hard-codes
  `AM`/`PM`.
- `BridgeController` keeps `localeName` and `use24Hour` so pre-formatted view
  states, including Bridge reading dates, format consistently. A platform
  change repaints the controller after the delivery frame.
- `HistoryViewLoader` treats units as presentation, not a data filter: it keeps
  the archive future and re-wraps the loaded `HistoryViewState` with
  `withUnits`, so an open History chart and Summary repaint in the next frame.
  An open `PastCookScreen` mirrors the source controller's units, locale and
  change window instead of freezing its initState snapshot.
- Local preferences use the existing `preference` table (`AppPreferences`):
  `appearance.theme_mode`, `preferences.temperature_units` and
  `preferences.live_change_window_minutes`. `prepareLaunch` restores all three
  before the first frame. Units are also persisted when the Bridge's config is
  adopted on connect, so the next offline launch agrees with the OLED.
- The OLED unit and timeout remain the Bridge `config` fields, written by the
  same `setUnits` / `setDisplayTimeout` whole-struct read-modify-write. A change
  made offline is queued and applied on the next healthy connect.

## Consequences

- Later screens must add temperature or date output through `formatters.dart`
  and the view-state seam, never with local `* 5 / 9` maths or literal clock
  suffixes.
- `HistoryViewLoader` no longer reloads when units change; presentation changes
  are cheap and immediate.
- Tests remain host-only; the real-phone relaunch and OLED walk stays with the
  bench task (T55/T46 follow-up).
