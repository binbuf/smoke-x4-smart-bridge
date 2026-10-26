# UI reference screenshots

Generated from the real Flutter widget tree at 390 × 844 (3×), with both dark and
light themes. They are review artifacts, not golden tests that block the suite.

| Image | Screen |
|---|---|
| `live_dark.png`, `live_light.png` | Live: connection chain, four probes with sparklines, Billows detected |
| `live_billows_detected.png` | Billows detected, CH 4 set temp and status |
| `live_billows_lost.png` | Billows detected earlier but missing now |
| `live_offline_cache.png` | Offline with dimmed cached readings |
| `history_dark.png`, `history_light.png` | History: compact range/probe dropdowns, 24 h chart, gap, legend and chart controls |
| `history_custom_range_dark.png` | Custom date-and-time range sheet, starting with everything in memory |
| `history_all_dark.png` | Entire archive selected through Custom range, with estimated time |
| `history_cooks_dark.png` | Summary and detected past cooks |
| `past_cook_dark.png` | Detected past cook opened as a historical graph |
| `history_filter_dark.png` | History filtered to P1 and 1 h |
| `history_empty_dark.png` | No readings yet |
| `history_probe_empty_dark.png` | Selected probe has no data in range |
| `history_fullscreen_dark.png` | Dedicated full-screen chart in portrait |
| `settings_dark.png`, `settings_light.png` | Settings root: Bridge status with signal bars, merged logs, then Preferences |
| `bridge_details_dark.png` | Bridge status, Smoke X4 pairing, bridge settings, technical details and actions |
| `history_storage_dark.png` | Device log vs Bridge log |
| `appearance_dark.png` | System / light / dark appearance |
| `setup_dark.png` | First-run “Connect your Bridge” |
| `passkey_dark.png` | OLED passkey instruction |
| `device_log_dark.png` | Orphaned device log after forget/reset |
| `billows_settings_dark.png` | Billows read-only state, CH 4 set temp and connection log |
| `oled_page_dark.png`, `oled_passkey_dark.png` | Device OLED pages/overlays |
| `confirm_factory_reset_dark.png` | Destructive confirmation sheet |
| `scenario_lab_dark.png` | Scenario lab |

Regenerate with:

```bash
cd app
flutter test --update-goldens tool/ui_screenshots_test.dart
```
