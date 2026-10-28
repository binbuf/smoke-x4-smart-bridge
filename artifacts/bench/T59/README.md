# T59 bench evidence — Billows observation

**Status:** pass, 2026-10-28. Real Billows + real Smoke X4 + Pixel 11 Pro Fold,
receive-only observation. No cook.

Report: [`docs/progress/T59.md`](../../../docs/progress/T59.md).
Decision: [`docs/billows-decision.md`](../../../docs/billows-decision.md)
(Option C, observation only).

## Run conditions

| Field | Value |
|---|---|
| Phone | Pixel 11 Pro Fold, Android 17 / API 37, wireless ADB |
| App | release APK SHA-256 `3310BCE483C18D13CEE605BE90FE14FC6B2D5BC94938CAA4B6CF333A0D364F22` (0.1.0) |
| Board | Heltec WiFi LoRa 32 V3, COM5 |
| Firmware | T57 image, SHA-256 `B0E14FF55C81CFFF4B6E1F8CB7778A051897815F8C8CC12FE858A58E370C39B1` (603,472 B) |
| X4 | `LMXC[\`, operating channel 918,500,000 Hz |
| Billows | real unit on channel 4, air probe at room temperature, fan unobstructed |
| Capture | `serial-t59.log` (console), `app-live.log` (Flutter debug of the target/attached fields during the run) |

## Evidence matrix

| Check | Result | Evidence |
|---|---|---|
| Detached at start | Live has no Billows card and no loss notice. | `01-live-detached.*` |
| Attach at 225 °F | Card appears: `Set temp 225.0°F`, `Last detected 53s ago`, `Set on the Smoke X4.` No Connected/Read-only label. | `03-billows-225.*`, serial frame `p4 max=225`, `attached=1` |
| 250 °F | `Set temp 250.0°F`. | `04-billows-250.*`, serial frame `p4 max=250`, `attached=1` |
| 275 °F | `Set temp 275.0°F`. | `06-billows-275.*`, serial frame `p4 max=275`, `attached=1` |
| °C flip | App shows `Set temp 135.0°C` for the 275 °F target; Bridge logs `config applied: units 0`. | `09-settings-celsius.png`, `10-billows-275-celsius.*` |
| Back to °F | App shows `275.0°F` again; `config applied: units 1`. | `11-billows-275-fahrenheit-restored.png` |
| Detach | Card gone; one `Billows not detected` notice with `View connection log`; Settings shows `Lost this session`, `Last detected 3 min ago`, `—` target and the focused log. | `12-live-detached-after.*`, `13-billows-settings-lost.*`, serial `attached=0` |
| Offline last-known | Settings shows `Last observed state`, `Set temp (last known) 275.0°F`, `Last detected 1 min ago`; filtered log present. | `16-billows-offline-last-known.*` |
| Settings online | `Status Detected`, `Set temp 275.0°F`, `Set on Smoke X4 (channel 4)`, focused log; no mode/target editor or fan claim. | `22-billows-settings-online.*` |
| Re-pair ACK | Bridge logs `unpair_smoke_x: pairing cleared, scanning 915/920`, then **`pair ACK sent on 918500000 Hz`**. This is the only TX line in the whole capture. State frames resume immediately. | `serial-t59.log`; `Select-String 'ACK|sent on'` returns exactly one line |
| Stock receiver | Still updating after the re-pair (operator-confirmed). | operator report, this sitting |
| OLED | Billows page showed `DETECTED`, `SET 275°F` (and `135°C` in the unit flip), `Set on the Smoke X4`; no fan-running/duty claim. | operator report, this sitting |

## Notes / deviations

- The target notification occasionally lagged the base change by up to roughly
  two minutes while the BLE link churned (`central disconnected reason 0x213`,
  reconnect and `advertising start failed (6)`); a relaunch/read showed the
  correct target. The displayed target did follow every setpoint, but this is a
  live-refresh follow-up for T43/T46a, not a T59 failure.
- The first 250 °F screenshot still showed 225 °F until the next read/relaunch;
  the later frames and the controller log show `2500`, and the card was
  re-captured at `250.0°F`. Recorded rather than hidden.
- The Billows was detached and reattached once: first for the detach/lost
  evidence, then reattached at 275 °F for the offline last-known check and the
  re-pair ACK.
- Units were flipped on the phone Settings (which also drives the OLED), then
  restored to °F.
- No cook and no setpoint change during a cook.
- A temporary `print()` in `_onLinkLive` produced `app-live.log` (target/attached
  fields) and was removed before the final release build. The UI code in the
  screenshots is identical to the final APK; only the diagnostic line differed.
- Release-notes wording is fixed in `docs/billows-decision.md` ("Billows observed
  only; set the target on the Smoke X4"); the release-notes file itself is T66.
