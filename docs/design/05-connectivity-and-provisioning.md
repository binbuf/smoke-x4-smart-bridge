# 05 — Connectivity and Provisioning

Covers the two Wi-Fi modes, how the mode gets chosen, the BLE control service, the handoff
choreography between them, and the Android-specific traps that will otherwise eat a week.

## 5.1 The two modes

|                       | **Hosted** (`AP`)                                                | **Joined** (`STA`)                             |
| --------------------- | ---------------------------------------------------------------- | ---------------------------------------------- |
| The bridge            | runs its own Wi-Fi network                                       | joins your existing network                    |
| Reach it at           | `http://192.168.4.1`                                             | `http://smokebridge.local` or its DHCP address |
| Phone must            | leave your home network to join the bridge's                     | stay on your home network                      |
| Range                 | ~30 m to the bridge                                              | anywhere on your LAN                           |
| Internet on the phone | none while joined (see §5.7)                                     | normal                                         |
| Bridge power draw     | **high** — an AP cannot sleep (~145 mA)                          | modem sleep (~70 mA)                           |
| Good for              | tailgating, a remote smoker, no Wi-Fi in range, first-time setup | home use, the default once set up              |

Both modes serve the identical HTTP + WebSocket API ([06](06-device-api.md)) and advertise the same
mDNS service. Nothing above the transport layer knows or cares which is active.

## 5.2 How the mode gets chosen

Five paths, in precedence order:

| #   | Path                                                                          | When                                                    |
| --- | ----------------------------------------------------------------------------- | ------------------------------------------------------- |
| 1   | **Post-boot recovery window** — hold PRG for 3 s while the splash counts down | Forces `AP` for this boot only; stored config untouched |
| 2   | **Double reset** — press reset twice within 10 s                              | Same effect. Works with a dead OLED                     |
| 3   | **BLE** — `wifi_config` write                                                 | The normal path, from the app                           |
| 4   | **HTTP** — `POST /api/v1/config/wifi`                                         | From a browser or a script already on the network       |
| 5   | **Button** — 2 s hold on the Network page                                     | Toggles AP ↔ STA on the device itself                   |

Otherwise the stored `net/mode` applies.

> **Why not "hold the button while powering on"?** GPIO0 is the ESP32-S3 boot strapping pin. Held
> LOW through a reset it puts the ROM into download mode and our firmware never runs. Paths 1 and 2
> exist specifically to replace that idiom. See [03 §3.4.1](03-firmware-architecture.md).

## 5.3 Hosted (AP) mode

**SSID** `SmokeBridge-XXXX`, where `XXXX` is the last two bytes of the Wi-Fi MAC in hex — stable
per device, distinguishable when two are in range.

**PSK**: **generated on first boot** from the hardware RNG — 10 characters from an unambiguous
alphabet (no `0/O`, `1/l/I`). Stored in NVS, regenerated only on factory reset. It is shown on the
OLED Network page, returned in the BLE `result` frame after a mode change, and readable at
`GET /api/v1/config/wifi` from within the AP.

This replaces the reference's hard-coded `Smoke X Receiver` / `The extra B is for BYOBB`. A fixed,
publicly documented password on a device that broadcasts an open API is not a good default, however
charming the passphrase.

**Network**: `192.168.4.1/24`, DHCP pool `.2–.20`, `max_connection = 4`, channel auto-selected at
startup by a quick scan for the least congested of 1/6/11.

**QR join code.** The OLED can render a Wi-Fi join QR: the payload
`WIFI:T:WPA;S:SmokeBridge-A4F2;P:Gk7mR2xQpT;;` is ~44 characters, which fits a **version 3 QR (29×29
modules) at ECC level L**. At 2 px/module that is 58×58 px — inside the 64 px display height. Point
a phone camera at the bridge and you are on its network, no typing. Tracked as a stretch item in
[11](11-roadmap-and-risks.md) since it needs a QR encoder (~3 KB of code) in firmware.

**Captive-portal shim** — see §5.7, this is what makes Android behave.

## 5.4 Joined (STA) mode

- Hostname / DHCP name: `smokebridge`, so `smokebridge.local` resolves via mDNS
- WPA2/WPA3-PSK and WPA2-Enterprise (EAP-TTLS/MSCHAPv2) both supported — the reference already has
  working enterprise code worth carrying over
- PMF capable and required, matching the reference

**Connection supervision**, improved over the reference:

```
STA configured
   ├─ connect attempt, 30 s budget
   ├─ success → mDNS up, notify BLE net_status, done
   └─ timeout / auth failure
        └─ start AP (so the device is never unreachable)
             └─ background retry of STA at 1, 2, 5, 10, 10, 10… min
                  └─ on success: switch back to STA **only if**
                       • no station is associated to the AP, and
                       • no HTTP/WebSocket client has been active for 60 s
```

The reference falls back to AP and then gives up forever, which means a router reboot during a cook
strands the bridge until someone walks out to it. The backoff-retry self-heals. The guard condition
matters: if the user has already given up and joined the bridge's AP from their phone, silently
jumping back to STA would yank the network out from under them.

**Reconfiguration is deferred, not immediate.** A `POST` that changes Wi-Fi settings answers first,
waits ~500 ms for the response to flush, and only then tears down the interface — otherwise the
reply dies with the network it was sent over. The reference discovered this the hard way; keep it.

## 5.5 mDNS

Registered in both modes as soon as an interface has an address.

|                 |                                                                                               |
| --------------- | --------------------------------------------------------------------------------------------- |
| Hostname        | `smokebridge.local`                                                                           |
| Primary service | `_smokebridge._tcp`, port 80                                                                  |
| Also advertised | `_http._tcp`, port 80 — so browsers and generic tools find it                                 |
| TXT records     | `id=A4F2` `model=heltec-v3` `fw=1.0.0` `api=v1` `probes=4` `paired=1` `session=27` `mode=sta` |

The TXT records let the app render a useful picker ("Smoke Bridge · 4 probes · cooking") **before**
opening a connection. Discovery is never the only path — the app also caches the last known address
and always offers manual IP entry (§5.7).

## 5.6 BLE — the Bridge Control Service

Decision D1: a **custom GATT service** rather than Espressif's `wifi_provisioning` manager. The
manager only carries STA credentials and then shuts itself down; we need AP/STA switching, pairing
control, clock setting, and — the reason this choice pays for itself — **live telemetry with no
Wi-Fi at all**, plus a control channel that still works when a Wi-Fi provision has just failed.

Stack: **NimBLE** (D6, ~100 KB less RAM than Bluedroid).

### Advertising

|               |                                                                                                |
| ------------- | ---------------------------------------------------------------------------------------------- |
| Local name    | `SmokeBridge-A4F2`                                                                             |
| Adv payload   | Flags + the 128-bit service UUID (that alone is 16 of the 31 legacy bytes)                     |
| Scan response | Manufacturer-specific status blob — `ver, flags, pit_temp(i16), soc(u8), session_minutes(u16)` |
| Interval      | 500 ms idle, 250 ms for 60 s after a button press (`identify`) or a fresh boot                 |

The scan-response blob lets the app's device list show _"Smoke Bridge · pit 243 °F · 4 h 12 m"_
without connecting — a genuinely nice touch when you have two bridges.

### UUIDs

Base `7f9aXXXX-4c5b-4b0f-9a3d-1c2e3f405162`.

| `XXXX` | Characteristic             | Props        | Security                      |
| ------ | -------------------------- | ------------ | ----------------------------- |
| `0000` | **Bridge Control Service** | —            | —                             |
| `0001` | `device_info`              | Read         | open                          |
| `0002` | `net_status`               | Read, Notify | encrypted                     |
| `0003` | `wifi_scan_ctrl`           | Write        | encrypted                     |
| `0004` | `wifi_scan_result`         | Notify       | encrypted                     |
| `0005` | `wifi_config`              | Write        | **encrypted + authenticated** |
| `0006` | `device_control`           | Write        | **encrypted + authenticated** |
| `0007` | `live_state`               | Read, Notify | encrypted                     |
| `0008` | `history_preview`          | Read         | encrypted                     |
| `0009` | `result`                   | Notify       | encrypted                     |

### Security

**LE Secure Connections with passkey entry.** The bridge generates a 6-digit passkey and **displays
it on the OLED**; the user types it into the app. This gives real MITM protection — the display is
the whole reason we can do better than Just Works here, and it costs nothing.

Bonds persist in NVS, up to 3 phones. "Forget all phones" is available in settings, on a 10 s PRG
factory reset, and via `device_control`.

`device_info` is readable unencrypted so the app can identify a bridge before bonding. Everything
else requires encryption; the two write characteristics that can change network config or wipe the
device additionally require authentication.

### Payloads

Packed little-endian structs with a leading version byte — same philosophy as the storage records,
and no CBOR/protobuf parser in the firmware.

**`live_state` (notify, 16 B)** — deliberately ≤ 20 B so it fits the default 23-byte ATT MTU. Live
telemetry works even if MTU negotiation fails.

```
u8  ver          = 1
u8  flags        b0 paired · b1 session_active · b2 billows · b3 alarm_active · b4 clock_valid
i16 temp[4]      tenths °F; INT16_MIN = detached
u8  soc_pct      battery state of charge
i8  rssi_lora    dBm of the last state message
u32 session_t    seconds into the active session
```

Notified on every decoded packet (~30 s), plus immediately on any alarm transition.

**`net_status` (read/notify, variable ≤ 64 B)**

```
u8  ver, u8 mode (0 off · 1 AP · 2 STA), u8 state (0 idle · 1 connecting · 2 up · 3 failed)
i8  wifi_rssi, u8 ip[4], u8 ssid_len, u8 host_len, char ssid[], char host[]
```

**`wifi_scan_result` (notify, one AP per notification)**

```
u8 ver, u8 index, u8 total, i8 rssi, u8 auth, u8 channel, u8 ssid_len, char ssid[]
```

**`wifi_config` (write)**

```
u8 ver, u8 mode, u8 auth, u8 ssid_len, u8 psk_len, u8 user_len, char ssid[], psk[], user[]
```

**`device_control` (write)** — `u8 ver, u8 op, …op-specific`

| op  | Action                                               |
| --- | ---------------------------------------------------- |
| 1   | `pair` — enter sync/scan mode                        |
| 2   | `unpair`                                             |
| 3   | `set_time` — `u64 unix_ms, i16 tz_offset_min`        |
| 4   | `session_start`                                      |
| 5   | `session_stop`                                       |
| 6   | `mark` — `u8 kind, u8 len, char text[]`              |
| 7   | `reboot`                                             |
| 8   | `factory_reset`                                      |
| 9   | `set_units` — `u8 (0 °C, 1 °F)` (display preference) |
| 10  | `identify` — flash the LED and screen for 5 s        |
| 11  | `ack_alarm` — `u8 alarm_id`                          |

**`result` (notify)** — `u8 ver, u8 op_echo, u8 status, u8 len, char detail[]`. Status: `0` ok,
`1` invalid, `2` busy, `3` failed, `4` unauthorized. `detail` carries the AP PSK after a mode
change, or an error string.

**`history_preview` (read, 244 B)** — pit-probe temperature at 1-minute buckets for the last 2 h:
`u8 ver, u8 probe_index, u8 count, u8 bucket_min, i16 values[count]`. Enough to draw a real
sparkline over BLE alone. Full history over BLE is deferred to v1.1 ([11](11-roadmap-and-risks.md));
v1.0 says so in the UI rather than showing a stub.

### MTU

Request 247 on connect. `live_state` is designed to work at the 23-byte default; everything else
degrades gracefully by chunking, with the chunk boundary derived from the negotiated MTU.

### Coexistence

Wi-Fi and BLE share the 2.4 GHz radio; `CONFIG_ESP_COEX_SW_COEXIST_ENABLE=y`. Expect BLE
notification jitter under Wi-Fi load and ~20–30 % lower AP throughput while advertising. At one
16-byte notification per 30 s and a few KB of HTTP, neither matters. The SX1262 is sub-GHz and
independent — but confirm empirically ([01 §1.8](01-hardware.md)).

## 5.7 The handoff

The choreography the app performs. **The escape hatch is the point**: BLE stays connected across
the whole Wi-Fi transition, so a wrong password or an unreachable AP is recoverable without walking
to the device.

```
 App                                   Bridge (BLE)                    Bridge (Wi-Fi)
  │                                         │                                │
  │─ scan, connect, bond ──────────────────►│                                │
  │◄─ passkey shown on OLED ────────────────│   ┌───────────────────┐        │
  │─ user enters 6 digits ─────────────────►│   │  PAIR CODE        │        │
  │                                         │   │     418 302       │        │
  │─ read device_info ─────────────────────►│   └───────────────────┘        │
  │◄─ model, fw, id, caps ──────────────────│                                │
  │─ write device_control{set_time} ───────►│  clock valid → sessions dated  │
  │─ write wifi_scan_ctrl ─────────────────►│                                │
  │◄─ wifi_scan_result × N ─────────────────│                                │
  │                                         │                                │
  │   ── user picks: Hosted or Joined ──    │                                │
  │                                         │                                │
  │─ write wifi_config{mode,ssid,psk} ─────►│                                │
  │◄─ result{ok, ap_psk if hosted} ─────────│                                │
  │                                         │─ 500 ms flush, reconfigure ───►│
  │◄─ net_status{connecting} ───────────────│                                │
  │◄─ net_status{up, ip, host} ─────────────│                          AP or STA up
  │                                         │                                │
  │─ (STA) GET http://<ip>/api/v1/status ───┼───────────────────────────────►│
  │─ (AP)  join SSID, then GET 192.168.4.1 ─┼───────────────────────────────►│
  │◄─ 200 + status ─────────────────────────┼────────────────────────────────│
  │                                         │                                │
  │   transport := HTTP.  BLE held as fallback + out-of-Wi-Fi telemetry      │
  │                                         │                                │
  │   ✗ HTTP unreachable after 20 s:                                         │
  │─ write wifi_config{mode:AP} over BLE ──►│   ← recovery without touching  │
  │                                         │     the hardware               │
```

After a successful handoff the app keeps the BLE link by default (it costs the bridge ~1–3 mA and
gives instant fallback when you wander out of Wi-Fi range with the phone). A setting disables it
for users who care about the milliamps.

## 5.8 Android: the parts that will bite

Concrete, because each of these produces a "the app just doesn't work" bug report with no obvious
cause.

### 5.8.1 AP mode and Android's network validation

When the phone joins a Wi-Fi network, Android probes `http://connectivitycheck.gstatic.com/generate_204`.
Our AP has no internet, the probe fails, Android marks the network unvalidated — and **keeps the
default route on cellular**, so the app's requests to `192.168.4.1` go out the mobile interface and
vanish.

Two mitigations, both required:

**Firmware side — the captive-portal shim.** In AP mode the bridge runs a tiny UDP/53 responder
that answers every A query with `192.168.4.1`, and the HTTP server answers the probe URLs:

| Path                                                 | Response                 |
| ---------------------------------------------------- | ------------------------ |
| `/generate_204`, `/gen_204`                          | `204 No Content`         |
| `/hotspot-detect.html`, `/library/test/success.html` | Apple's success page     |
| `/ncsi.txt`                                          | `Microsoft NCSI`         |
| `/connecttest.txt`                                   | `Microsoft Connect Test` |

Answering `204` makes Android consider the network validated, which both routes traffic correctly
and suppresses the "sign in to Wi-Fi network" nag. A config flag switches to true captive-portal
behaviour (302 to a setup page) for users who prefer a browser flow.

**App side — bind the process to the network.** Even with the shim, be explicit:

```kotlin
val req = NetworkRequest.Builder()
    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
    .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    .build()
cm.requestNetwork(req, object : ConnectivityManager.NetworkCallback() {
    override fun onAvailable(n: Network) { cm.bindProcessToNetwork(n) }
})
```

This lives in a small platform channel (`platform/network_binder`), not a third-party package —
it is 60 lines and we need exact control over its lifecycle. Unbind when leaving AP mode, or the
app loses the internet everywhere else.

### 5.8.2 Joining the AP from the app

Android 10+ can join programmatically without sending the user to Settings:

- `WifiNetworkSpecifier` + `requestNetwork` — a **local-only, app-scoped** connection. Ideal: it
  binds automatically and does not disturb the user's saved networks. Shows a system dialog.
- `WifiNetworkSuggestion` — a persistent suggestion; the user gets a notification to approve.

Use `WifiNetworkSpecifier` with the SSID and PSK we already know from the BLE `result` frame, so
joining the bridge's AP is one tap. Always keep the manual path ("here's the SSID and password")
because OEM behaviour varies.

### 5.8.3 Permissions by API level

| Permission                                                   | Needed for                                             | Levels                      |
| ------------------------------------------------------------ | ------------------------------------------------------ | --------------------------- |
| `INTERNET`, `ACCESS_NETWORK_STATE`                           | everything                                             | all                         |
| `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`                     | scan, join AP                                          | all                         |
| `CHANGE_WIFI_MULTICAST_STATE`                                | **mDNS** — without it discovery silently finds nothing | all                         |
| `ACCESS_FINE_LOCATION`                                       | Wi-Fi scan results                                     | ≤ 12                        |
| `NEARBY_WIFI_DEVICES` (`neverForLocation`)                   | Wi-Fi scan / local network                             | 13+                         |
| `BLUETOOTH_SCAN` (`neverForLocation`), `BLUETOOTH_CONNECT`   | BLE                                                    | 12+                         |
| `BLUETOOTH`, `BLUETOOTH_ADMIN`, `ACCESS_FINE_LOCATION`       | BLE                                                    | ≤ 11                        |
| `POST_NOTIFICATIONS`                                         | alarms                                                 | 13+                         |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_CONNECTED_DEVICE` | cook monitoring                                        | 14+ needs the typed variant |

Declaring `neverForLocation` on the BLE and Wi-Fi scan permissions avoids the location-permission
prompt on modern Android, which is a meaningful drop-off point in onboarding.

### 5.8.4 Cleartext HTTP

The bridge serves plain HTTP — a self-signed cert on a LAN device is worse than no cert (it trains
users to click through warnings, and certificate lifecycle on a device with no clock is miserable).
Scope the exemption rather than turning cleartext on globally:

```xml
<network-security-config>
  <domain-config cleartextTrafficPermitted="true">
    <domain includeSubdomains="true">smokebridge.local</domain>
    <domain>192.168.4.1</domain>
    <!-- private ranges, for STA-mode DHCP addresses -->
  </domain-config>
</network-security-config>
```

Because private-IP ranges cannot be expressed as domains, the STA case needs
`cleartextTrafficPermitted="true"` on a base config with certificate pinning left off. Document the
trade-off; revisit if the app ever talks to anything off-LAN.

### 5.8.5 mDNS reliability

Flutter's `multicast_dns` has a long-standing record of not discovering services on Android
([flutter#155499](https://github.com/flutter/flutter/issues/155499)). Use the **`nsd`** package,
which wraps Android's native `NsdManager`. Regardless:

**Discovery must never be the only path to the device.** The app always: (1) tries the last known
address first, (2) runs mDNS discovery, (3) offers manual IP entry, and (4) falls back to BLE. In
that order, in parallel where possible, first responder wins.

## 5.9 API security

Default: **no authentication**, matching the reference — the device is on a trusted LAN or its own
AP, and requiring a login to check on a brisket is hostile.

Optional: a bearer token, generated on the device, provisioned to the app over the (encrypted,
authenticated) BLE channel, and required on all `/api/v1/*` requests when
`device/api_token` is set. Off by default, one toggle in settings, worth having for users on a
shared or dormitory network. Documented in [06](06-device-api.md).

What we do **not** ship: the reference's unauthenticated `POST /cmd {"command":"startTx", "message":…}`,
which lets anyone on the network transmit arbitrary LoRa frames at 22 dBm. Ours is compile-time
gated off in release builds ([02 §2.5](02-smoke-x-protocol.md)).

## Sources

- [ESP-IDF Unified Provisioning](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/provisioning/provisioning.html) — the alternative we evaluated and rejected (D1)
- [`nsd` Flutter package](https://pub.dev/packages/nsd)
- [flutter/flutter#155499 — multicast_dns not discovering on Android](https://github.com/flutter/flutter/issues/155499)
- [Android `WifiNetworkSpecifier`](https://learn.microsoft.com/en-us/dotnet/api/android.net.wifi.wifinetworkspecifier)
  </content>
