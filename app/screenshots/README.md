# UI reference screenshots

Generated from the real Flutter widget tree at 390 × 844 (3×), with both dark and
light themes. They are review artifacts, not golden tests that block the suite.

| Image | Screen |
|---|---|
| `live_dark.png`, `live_light.png` | Live, four numbered probes with sparklines, Billows monitor-only |
| `live_billows_control.png` | Billows control capability and target action |
| `live_offline_cache.png` | Offline with dimmed cached readings |
| `history_dark.png`, `history_light.png` | History, 24 h, gap and summary |
| `history_all_dark.png` | All history, estimated time |
| `history_days_dark.png` | History day groups and summary |
| `history_filter_dark.png` | History filtered to P1 and 1 h |
| `history_empty_dark.png` | No readings yet |
| `history_probe_empty_dark.png` | Selected probe has no data in range |
| `history_fullscreen_dark.png` | Full-screen History chart |
| `settings_dark.png`, `settings_light.png` | Settings root with inline units |
| `bridge_details_dark.png` | Bridge status, technical details, actions |
| `history_storage_dark.png` | Phone history vs bridge log |
| `appearance_dark.png` | System / light / dark appearance |
| `setup_dark.png` | First-run “Connect your bridge” |
| `passkey_dark.png` | OLED passkey instruction |
| `phone_history_dark.png` | Orphaned phone history after forget/reset |
| `billows_settings_control_dark.png` | Billows control mode and target |
| `oled_page_dark.png`, `oled_passkey_dark.png` | Device OLED pages/overlays |
| `confirm_factory_reset_dark.png` | Destructive confirmation sheet |
| `scenario_lab_dark.png` | Scenario lab |

Regenerate with:

```bash
cd app
flutter test --update-goldens tool/ui_screenshots_test.dart
```
