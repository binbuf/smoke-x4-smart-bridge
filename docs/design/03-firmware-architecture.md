# 03 — Firmware Architecture

ESP-IDF v5.4, C, targeting `esp32s3`. Structure follows the reference's component split (which is
sound) but pushes further: every piece of logic that can be tested on a host is in a component with
no ESP-IDF dependency.

## 3.1 Component map

```
firmware/
├── main/
│   ├── main.c                 app_main: boot sequence, wiring, nothing else
│   ├── tasks.h                single table of every task's stack/priority/core
│   └── CMakeLists.txt
├── components/
│   ├── smoke_x/               ── protocol (host-testable, no IDF)
│   │   ├── smoke_x_parser.c   MIT © G-Two, extended
│   │   ├── smoke_x_types.h
│   │   └── smoke_x_ctrl.c     pairing state machine, NVS, event publish  (IDF)
│   ├── cook_store/            ── history (host-testable core, no IDF)
│   │   ├── record.c           encode/decode/CRC of sample + header records
│   │   ├── session.c          session lifecycle, retention policy
│   │   └── store_vfs.c        LittleFS binding                            (IDF)
│   ├── app_lora/              SX1262 wrapper over the vendored ra01s driver
│   ├── app_net/               Wi-Fi AP/STA state machine, mDNS, DNS hijack
│   ├── app_ble/               NimBLE GATT server (Bridge Control Service)
│   ├── app_api/               esp_http_server: REST, WebSocket, static, OTA
│   ├── app_ui/                SSD1306 driver, page renderer, button gestures
│   ├── app_alarm/             ── rule engine (host-testable, no IDF)
│   │   └── rules.c
│   ├── app_power/             battery ADC, SoC curve, saver profile
│   ├── app_time/              clock source arbitration (phone / SNTP / none)
│   ├── app_config/            NVS-backed typed config with change notifications
│   └── bridge_event/          the event bus: base, IDs, payload structs
├── vendor/
│   └── esp-idf-sx126x/        submodule, pinned  (provides `ra01s`)
├── test/                      host unit tests — plain CMake, no ESP-IDF
├── partitions.csv
├── sdkconfig.defaults
├── sdkconfig.defaults.heltec-v3
└── Makefile                   convenience wrapper (sources export.sh, per-board sdkconfig)
```

`smoke_x` (parser), `cook_store` (record + session), and `app_alarm` (rules) build and test on the
host with `gcc`. That is roughly 60 % of the interesting logic and it runs in CI on every push
without hardware or an emulator — the pattern the reference already established with
`test/test_smoke_x_parser.c`.

## 3.2 Event bus

One `esp_event` base, `BRIDGE_EVENT`, on the default loop.

```c
ESP_EVENT_DECLARE_BASE(BRIDGE_EVENT);

typedef enum {
    BRIDGE_EVT_SAMPLE,          /* bridge_sample_t   — a decoded state message   */
    BRIDGE_EVT_PAIRING,         /* bridge_pairing_t  — paired / unpaired / synced */
    BRIDGE_EVT_BASE_LOST,       /* uint32_t seconds_since_last_packet             */
    BRIDGE_EVT_BASE_FOUND,      /* — */
    BRIDGE_EVT_NET,             /* bridge_net_t      — mode / ip / rssi changed   */
    BRIDGE_EVT_SESSION,         /* bridge_session_t  — started / ended / renamed  */
    BRIDGE_EVT_ALARM,           /* bridge_alarm_t    — raised / cleared / acked   */
    BRIDGE_EVT_BUTTON,          /* bridge_gesture_t  — tap / double / hold / …    */
    BRIDGE_EVT_STORAGE,         /* bridge_storage_t  — usage, low-space, purged   */
    BRIDGE_EVT_POWER,           /* bridge_power_t    — mV, SoC, charging, saver   */
    BRIDGE_EVT_TIME,            /* bridge_time_t     — clock source acquired      */
    BRIDGE_EVT_OTA,             /* bridge_ota_t      — progress / result          */
} bridge_event_id_t;
```

**Rules for handlers**, enforced by review and by a debug-build assertion that measures handler
duration:

1. Handlers run serially on the event-loop task. **Nothing may block for more than ~5 ms.**
2. Anything touching flash (`cook_store`) or the network (WebSocket fan-out) copies the payload to
   its own queue and returns immediately.
3. Event payloads are small, POD, and copied by `esp_event` — no pointers into caller stacks.
   `bridge_sample_t` is 20 bytes; that is fine to pass by value.

At one packet per 30 s there is no throughput concern. The discipline exists so that a slow flash
garbage-collection pass or an OTA write can never stall the decoder.

### Producer/consumer matrix

| Event                      | Producer                | Consumers                                                               |
| -------------------------- | ----------------------- | ----------------------------------------------------------------------- |
| `SAMPLE`                   | `smoke_x_ctrl`          | `cook_store`, `app_alarm`, `app_api` (WS), `app_ble` (notify), `app_ui` |
| `PAIRING`                  | `smoke_x_ctrl`          | `app_ui`, `app_api`, `app_ble`, `cook_store` (ends session on unpair)   |
| `BASE_LOST` / `BASE_FOUND` | `smoke_x_ctrl` watchdog | `app_alarm`, `app_ui`, `app_api`, `app_ble`                             |
| `NET`                      | `app_net`               | `app_ui`, `app_ble`, `app_api`                                          |
| `SESSION`                  | `cook_store`            | `app_ui`, `app_api`, `app_ble`                                          |
| `ALARM`                    | `app_alarm`             | `app_ui` (banner), `app_power` (LED), `app_api`, `app_ble`              |
| `BUTTON`                   | `app_ui`                | `app_net` (mode toggle), `cook_store` (start/stop, mark), `app_api`     |
| `POWER`                    | `app_power`             | `app_ui`, `app_alarm`, `app_net` (saver profile)                        |

## 3.3 Tasks

Single source of truth in `main/tasks.h` so the RAM budget in [01 §1.4](01-hardware.md) is auditable.

| Task          | Stack    | Prio | Core | Role                                                                                                         |
| ------------- | -------- | ---- | ---- | ------------------------------------------------------------------------------------------------------------ |
| `lora_rx`     | 4096     | 6    | 1    | Poll the SX1262, hand payloads to `smoke_x_ctrl`. Pinned to core 1, away from the Wi-Fi/BLE stacks on core 0 |
| `smoke_x`     | 3072     | 5    | 0    | Decode, run the pairing state machine, publish `SAMPLE`                                                      |
| `cook_store`  | 4096     | 4    | 0    | Drain its queue → append to LittleFS, manage sessions and retention                                          |
| `app_ui`      | 4096     | 3    | 0    | 4 Hz button sampling, 1 Hz OLED render (paused when the display sleeps)                                      |
| `app_alarm`   | 3072     | 4    | 0    | Evaluate rules on each sample and on a 10 s tick                                                             |
| `app_net`     | 3072     | 4    | 0    | Wi-Fi state machine, STA retry backoff, mDNS lifecycle                                                       |
| `app_power`   | 2560     | 2    | 0    | Battery ADC every 30 s, SoC filter, saver-profile transitions                                                |
| `ws_push`     | 3072     | 4    | 0    | Serialize and fan out frames to WebSocket clients                                                            |
| _NimBLE host_ | (NimBLE) | 5    | 0    | Created by the stack                                                                                         |
| _httpd_       | (IDF)    | 5    | 0    | Created by `esp_http_server`                                                                                 |
| _event loop_  | 4096     | 5    | 0    | `esp_event` default loop                                                                                     |

`lora_rx` is pinned to **core 1** and everything else to core 0. The vendored driver polls with
`vTaskDelay(1)` inside a semaphore (see [01 §1.5](01-hardware.md)); keeping it off the core that
runs Wi-Fi and BLE avoids scheduling interference on the only truly latency-sensitive path.

## 3.4 Boot sequence

```
app_main()
 ├─ 1  nvs_flash_init()                     erase+retry on NO_FREE_PAGES / NEW_VERSION
 ├─ 2  bridge_boot_reason()                 read RTC-SRAM double-reset token  ── see §3.4.1
 ├─ 3  app_config_init()                    load typed config from NVS, apply defaults
 ├─ 4  esp_netif_init(); esp_event_loop_create_default()
 ├─ 5  app_power_init()                     ADC calibration, first battery read
 ├─ 6  app_ui_init()                        Vext LOW → OLED up → splash + FW version
 │                                          ┌──────────────────────────────────┐
 │                                          │  Smoke Bridge   v1.0.0           │
 │                                          │  hold PRG for AP mode      3…2…1 │
 │                                          └──────────────────────────────────┘
 ├─ 7  ── 3 s recovery window ──            PRG held → force AP  ── see §3.4.1
 ├─ 8  cook_store_init()                    mount /cooks, scan session index, resume active session
 ├─ 9  smoke_x_init()                       read pairing from NVS, LoRa init, tune or start scan
 ├─10  smoke_x_start()                      begin RX
 ├─11  app_time_init()                      restore last-known epoch from NVS (monotonic floor)
 ├─12  app_net_start()                      AP or STA per config/override; mDNS once we have an IP
 ├─13  app_api_start()                      httpd, REST + WS + OTA + captive-portal
 │                                          (mounts /www only if populated — D13)
 ├─14  app_ble_start()                      NimBLE, advertise with the status blob
 ├─15  app_alarm_start()
 └─16  esp_ota_mark_app_valid_cancel_rollback()   ── only after §3.7's health gate passes
```

Ordering rationale: **LoRa comes up before Wi-Fi and BLE.** Data capture is the product; if a later
subsystem fails to init, the bridge still records the cook. Every step after 8 is individually
failure-tolerant and logged; only NVS and the event loop are fatal.

### 3.4.1 Boot-mode selection — and why "hold PRG at reset" cannot work

**GPIO0 is the ESP32-S3 boot strapping pin.** Holding PRG through a reset pulls it LOW, which puts
the ROM into _download boot_ — our firmware never runs. The obvious design ("hold the button while
powering on to force AP mode") is therefore not implementable on this board.

Two mechanisms replace it:

**Primary — the post-boot recovery window (step 7).** After the OLED comes up, the splash screen
shows a 3-second countdown and the prompt `hold PRG for AP mode`. Holding PRG through the countdown
forces AP mode for this boot only (config is untouched, so a normal reboot returns to STA). This is
_more_ discoverable than the reset-hold idiom because the screen tells you it's happening.

**Backup — double-reset detection.** A token in RTC SRAM (which survives a reset but not a power
cycle) plus a persisted timestamp: on boot, if the token is present and less than 10 s old, treat it
as a double-reset → force AP mode. Otherwise write the token, wait 10 s, clear it. This works even
if the OLED is dead or unpopulated, and matches an idiom ESP users already know.

A third path exists for the truly stuck: `POST /api/v1/config/wifi` from a machine on the current
network, and a 10 s PRG hold performs a factory reset ([07](07-display-and-controls.md)).

## 3.5 Partition table

8 MB, OTA-capable from day one (D8). Repartitioning after ship means a full erase and history loss.

```csv
# Name,     Type, SubType,  Offset,   Size,      Flags
nvs,        data, nvs,      0x9000,   0x6000,          #   24 KB  config + pairing
otadata,    data, ota,      0xF000,   0x2000,          #    8 KB  OTA slot selector
phy_init,   data, phy,      0x11000,  0x1000,          #    4 KB
coredump,   data, coredump, 0x12000,  0xE000,          #   56 KB  panic dumps (fills the align gap)
ota_0,      app,  ota_0,    0x20000,  0x280000,        # 2560 KB  app slot A
ota_1,      app,  ota_1,    0x2A0000, 0x280000,        # 2560 KB  app slot B
www,        data, littlefs, 0x520000, 0x80000,         #  512 KB  fallback web UI — RESERVED, empty in MVP
cooks,      data, littlefs, 0x5A0000, 0x260000,        # 2432 KB  cook history
```

`0x5A0000 + 0x260000 = 0x800000` — exactly 8 MB, nothing stranded. App partitions are 64 KB
aligned as ESP-IDF requires; the 56 KB that alignment would otherwise waste becomes the coredump
partition.

**`www` ships declared but unformatted** (D13). Whether the device serves its own browser UI is a
post-MVP decision, but the partition is claimed now for the same reason as the second OTA slot:
handing 512 KB back to `cooks` later is free, while carving it out later means repartitioning and
erasing every stored cook. `app_api` mounts `www` only if it formats cleanly and contains an
`index.html.gz`; otherwise unmatched `GET`s return a small built-in page pointing at the app, and
the captive-portal probes still answer from flash-resident string constants.

Compared with the reference (`nvs 24K / phy 4K / factory 2M / spiffs 1M`, leaving ~5 MB unused),
this trades a second app slot for OTA safety and turns the idle space into history.

**Capacity:** 2,432 KB ÷ 16 B/sample ≈ 155,600 samples ≈ **1,297 h ≈ 54 days** of continuous 30 s
logging, before LittleFS overhead (~10 %) and per-session headers. See
[04](04-storage-and-history.md).

**LittleFS over SPIFFS** for both data partitions: roughly 30× faster on the benchmarks the
`joltwallet/esp_littlefs` project publishes, proper power-loss resilience, and real dynamic wear
levelling. SPIFFS also degrades badly as it fills, which is exactly the regime a history partition
lives in. Pulled in via the component manager (`joltwallet/littlefs`).

## 3.6 Configuration and NVS

`app_config` owns all persistent settings behind a typed API with change notifications, so no other
component opens NVS directly (the reference scatters `nvs_open` across four files).

| Namespace | Keys                                                                                                                                                                | Notes                                                                                           |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `sx_pair` | `device_id`, `frequency`, `num_probes`                                                                                                                              | Blob, format-compatible with the reference so an upgrade keeps its pairing                      |
| `net`     | `mode`, `sta_ssid`, `sta_psk`, `sta_auth`, `sta_user`, `ap_ssid`, `ap_psk`, `hostname`                                                                              | AP PSK is generated at first boot, not hard-coded                                               |
| `device`  | `units`, `display_timeout_s`, `led_enabled`, `buzzer_enabled`, `battery_saver`, `vbat_cal_num/den`, `api_token`, `retention_max_sessions`, `retention_min_free_pct` |                                                                                                 |
| `probes`  | `p{1..4}_name`, `p{1..4}_role`, `p{1..4}_target`                                                                                                                    | `role` ∈ {`pit`, `food`, `ambient`, `unused`} — the Smoke X does not distinguish; the user does |
| `session` | `next_id`, `active_id`                                                                                                                                              | `active_id` lets a session resume across an unexpected reboot                                   |
| `time`    | `last_epoch_ms`, `tz_offset_min`, `source`                                                                                                                          | Persisted ~every 10 min; acts as a monotonic floor after a reboot                               |
| `alarms`  | rule enable/threshold set                                                                                                                                           | See [09](09-alarms-and-insights.md)                                                             |

Every writable key is exposed through `GET|POST /api/v1/config/*` and, for the network subset, the
BLE control characteristic. A single `config_version` key drives forward migrations.

## 3.7 Reliability

**Watchdogs.** Task WDT enabled and subscribed by every application task (5 s). Interrupt WDT at
defaults. A task that blocks on flash for longer than its budget panics loudly rather than hanging
the bridge silently mid-cook.

**Panic handling.** `CONFIG_ESP_SYSTEM_PANIC_PRINT_REBOOT` plus the coredump partition. On the next
boot the firmware notices a stored coredump, logs a one-line summary, raises a `SYSTEM_FAULT`
alarm-info event so the app can surface "the bridge restarted unexpectedly", and offers the dump at
`GET /api/v1/debug/coredump`. Crucially: **an active session survives a panic** — `session.active_id`
is in NVS and `cook_store` reopens and appends to the existing file (§4.5).

**OTA rollback.** `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE=y`. A freshly flashed image is _pending
verify_; step 16 only calls `esp_ota_mark_app_valid_cancel_rollback()` after a health gate passes:

- LittleFS mounted, both partitions
- Wi-Fi reached its configured state (AP started, or STA got an IP)
- httpd is listening
- 120 s of uptime with no panic

Fail any of these and the next reset rolls back to the previous slot. A bricked bridge halfway
through a brisket is the failure mode this exists to prevent.

**Brownout.** Enable the brownout detector at a threshold above the point where flash writes get
unreliable. `cook_store` treats a brownout the same as any power loss: the last record may be torn,
and the per-record CRC catches it on the next read (§4.5).

## 3.8 Build system

Keep the reference's `Makefile` wrapper — it sources `export.sh`, selects a Python, and applies the
right `SDKCONFIG_DEFAULTS` per board. One board matters now (`heltec-v3`, which also covers V4), so
the matrix is simpler.

```bash
make setup                 # submodules + idf component manager   (+ web assets, if D13 says yes)
make build                 # firmware image
make flash                 # auto-detect port
make flash-monitor
make menuconfig
make test-host             # host unit tests, no hardware, no ESP-IDF
make sim                   # run tools/sim against the Flutter app
```

`sdkconfig.defaults` deltas from the reference worth calling out:

```ini
CONFIG_IDF_TARGET="esp32s3"
CONFIG_ESPTOOLPY_FLASHSIZE_8MB=y
CONFIG_PARTITION_TABLE_CUSTOM=y

# BLE: NimBLE, not Bluedroid (D6) — ~100 KB of SRAM
CONFIG_BT_ENABLED=y
CONFIG_BT_NIMBLE_ENABLED=y
CONFIG_BT_NIMBLE_MAX_CONNECTIONS=2

# Wi-Fi + BLE share the 2.4 GHz radio
CONFIG_ESP_COEX_SW_COEXIST_ENABLE=y

# WebSocket support in esp_http_server
CONFIG_HTTPD_WS_SUPPORT=y
CONFIG_HTTPD_MAX_REQ_HDR_LEN=1024

# OTA safety
CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE=y
CONFIG_ESP_TASK_WDT_INIT=y

# Power
CONFIG_PM_ENABLE=y
CONFIG_FREERTOS_USE_TICKLESS_IDLE=y

# Trim Wi-Fi buffers — we move kilobytes, not megabits (see 01 §1.4)
CONFIG_ESP_WIFI_STATIC_RX_BUFFER_NUM=6
CONFIG_ESP_WIFI_DYNAMIC_RX_BUFFER_NUM=16
CONFIG_ESP_WIFI_TX_BUFFER_TYPE=1
CONFIG_ESP_WIFI_DYNAMIC_TX_BUFFER_NUM=16
```

MQTT and its TLS transport config are gone (D2), which removes a chunk of `mbedtls` from the image —
though OTA over HTTPS keeps most of it.

## 3.9 What a sample's journey looks like

End to end, the hot path, to make the layering concrete:

```
SX1262 IRQ/poll
   └─ lora_rx: LoRaReceive() → char[121] + rssi/snr
        └─ smoke_x_ctrl: count commas → 26 → parse_state(msg, 4, &st)
             ├─ device_id != paired_id ?  → drop, bump counter, return
             ├─ build bridge_sample_t { t_rel, temp[4], flags, rssi, snr }
             └─ esp_event_post(BRIDGE_EVENT, BRIDGE_EVT_SAMPLE, &s, 20, 0)
                  ├─ cook_store handler → xQueueSend (non-blocking) → task appends 16 B, fsync/4
                  ├─ app_alarm handler  → evaluate rules → maybe post BRIDGE_EVT_ALARM
                  ├─ app_api handler    → xQueueSend → ws_push serializes ~180 B JSON → clients
                  ├─ app_ble handler    → ble_gatts_notify on live_state (14 B packed)
                  └─ app_ui handler     → update live ring, mark display dirty
```

One decoded packet touches flash once, produces one ~180 byte WebSocket frame and one 14 byte BLE
notification, and never allocates.
</content>
