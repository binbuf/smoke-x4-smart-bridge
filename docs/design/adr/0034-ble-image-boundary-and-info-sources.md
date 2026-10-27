# ADR 0034 — BLE image boundary and `info` identity sources

**Status:** accepted (T27, 2026-10-27)

## Context

ESP-IDF 6's `bt` component hard-requires `esp_wifi`, even for a NimBLE-only
build, and `ESP_WIFI_ENABLED` is a hidden symbol that defaults to `y` on the
ESP32-S3. A plain `set(COMPONENTS main espcoredump bt)` therefore compiled the
Wi-Fi stack, wpa_supplicant, lwIP and esp_netif into the image, contradicting
ADR 0001 and failing the post-link image guard.

T27 also had to choose where the open `info` fields come from. Design 05 names
the fields but not their sources; only `probes` could come from the existing
`bridge_config` pairing record.

## Decision

1. **`firmware/components/esp_wifi` is a project override.** It exposes the
   IDF esp_wifi headers the BLE controller needs and compiles one empty marker
   object. It does not call or link the Wi-Fi stack. Any future Wi-Fi call fails
   at link time, which is the intended boundary.
2. **The image guard checks actual linked objects, not just component names.**
   HTTP/TLS/MQTT/OTA components stay hard-forbidden. `build_components` may
   list `esp_wifi`, `lwip`, `esp_netif` and `esp_netif_stack` because they are
   inert build dependencies; `check_image.py` fails if the linker map contains
   an object from `libesp_wifi.a`, `liblwip.a`, `libesp_netif.a`,
   `libesp_netif_stack.a` or `libwpa_supplicant.a`. No Wi-Fi/lwIP/netif object
   is linked in the T27 image.
3. **`info` field sources:**
   - `device_id`: last two bytes of the bridge BLE MAC, uppercase hex (`A4F2`),
     matching the `SmokeX4-XXXX` local-name suffix T30 will advertise.
   - `probes`: the paired Smoke X4's persisted 2/4 count when `bridge_config`
     says paired and the count is valid; otherwise 4 (the UI supports four
     probe channels).
   - `bonds_free`: `4 - ble_store_util_count(PEER_SEC)`, clamped to 0–4.
   - `caps`: all MVP capabilities (`billows_observe`, `history`, `battery`,
     `display_config`, `power_off`, `factory_reset`, `config`); the encoder
     always clears `billows_control`.
   - `fw`: `0.1.0`, kept equal to `UI_VERSION`; `model`: `heltec3`;
     protocol major/minor come from the generated contract.
4. **`info` is served open as a Read Blob.** The access callback returns at most
   `MTU-1` bytes per response and lets NimBLE slice the next offset. Every other
   characteristic carries its 05 §5.1 security; the auto CCCD on each Notify
   slot inherits the same encryption level through
   `BLE_GATT_CHR_F_NOTIFY_INDICATE_ENC`.
5. **Advertising stays out of T27.** `ble_service_start()` initialises NimBLE
   and registers the service, but never calls `ble_gap_adv_start()`. T30 owns
   the advertising PDU, passkey/bond policy and disconnect restart.

## Consequences

- `firmware/sdkconfig.defaults` links `bt` and enables NimBLE; Wi-Fi/lwIP are
  not initialised and their objects are not in the image.
- The project override is narrower than IDF's component: any new code that
  needs a real Wi-Fi API will fail to link until this ADR is revisited. If lwIP
  is ever enabled, remove `firmware/compat/include/lwip/ip_addr.h` so the real
  lwIP headers win.
- T28/T29/T31/T47/T51 replace the placeholder read/write handlers but must keep
  the slot table and security levels in `ble_gatt_spec.c`.
- T30 changes the local name to `SmokeX4-XXXX` using the same MAC suffix as
  `info.device_id`.
