# UI reference screenshots

Generated from the real Flutter widget tree at 390 × 844 (3×), with both dark and
light themes. They are the approved production UI contract in
[`docs/design/13-ui-implementation-contract.md`](../../docs/design/13-ui-implementation-contract.md)
and CI job 5 compares against them on every pull request, so an intentional
visual change must be regenerated and reviewed with the code.

| Image | Screen |
|---|---|
| `live_dark.png`, `live_light.png` | Live: connection chain with separate BLE and Smoke X4 status, four probes with sparklines, Billows detected |
| `live_billows_detected.png` | Billows detected, set temp and last-detected age |
| `live_billows_lost.png` | Billows detected earlier but missing now |
| `live_offline_cache.png` | Offline with dimmed cached readings |
| `history_dark.png`, `history_light.png` | History: compact range/probe dropdowns, 24 h chart, gap, legend and chart controls |
| `history_custom_range_dark.png` | Custom date-and-time range sheet, starting with all saved history |
| `history_all_dark.png` | All saved history selected through Custom range, with estimated time |
| `history_cooks_dark.png` | Summary and detected cooks |
| `past_cook_dark.png` | Detected cook opened as a historical view |
| `history_filter_dark.png` | History filtered to P1 and 1 hour |
| `history_empty_dark.png` | No readings yet |
| `history_probe_empty_dark.png` | Selected probe has no data in range |
| `history_fullscreen_dark.png` | Dedicated full-screen chart in portrait |
| `settings_dark.png`, `settings_light.png` | Settings root: Bridge status with signal bars, History & storage, then Preferences |
| `bridge_details_dark.png` | Bridge status, Smoke X4 pairing, Bridge settings, technical details and actions |
| `history_storage_dark.png` | History on this phone vs History on the Bridge |
| `appearance_dark.png` | System / light / dark appearance |
| `setup_dark.png` | First-run “Connect your Bridge” |
| `passkey_dark.png` | Bridge screen pairing-code instruction |
| `device_log_dark.png` | History on this phone after forget/reset |
| `billows_settings_dark.png` | Billows status, set temp and connection log |
| `oled_page_dark.png`, `oled_passkey_dark.png` | Bridge screen pages and states |
| `confirm_factory_reset_dark.png` | Destructive confirmation sheet |

Regenerate with:

```bash
cd app
flutter test --update-goldens tool/ui_screenshots_test.dart
```

...though `make design-approve` from the repository root is the supported path:
it also rewrites `manifest.json` and refreshes `app/assets/thumbs` (the
Experimental lab contact sheet), so neither can lag behind an accepted visual
change.

Every image in this directory is one entry in
`app/lib/debug/scenario_catalog.dart`; the golden test and the lab both read that
list, so a screen cannot be added to one without the other.
