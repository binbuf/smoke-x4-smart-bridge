# ROADMAP — slim MVP to high quality

The product is now a **slim, BLE-only bridge**: receive the Smoke X4 over LoRa,
record it to flash, draw it on the OLED, and serve it over Bluetooth. The app is
three destinations — **Live**, **Graph**, **History** — plus a connection sheet
and a cook clock. Feature bloat was cut because quality on the kept features was
poor; this roadmap is the work to make the kept features excellent.

This file replaces the aspiration in the older design docs and task plans as the
*active* plan. Those documents describe the full Wi-Fi/HTTP/MQTT/OTA/alarm
product and are now history (see **Phase 0**).

## State at the time of writing (verified)

| | |
|---|---|
| Firmware | BLE-only slim build. `ctest --test-dir firmware/test/build-local` → **21/21 pass**. Never flashed to a board (`docs/firmware-slim.md:72-76`). |
| App | `flutter analyze` clean · `flutter test` → **45/45 pass**. |
| Docs | `README.md`, `docs/new-app.md`, `docs/RELEASE.md`, `docs/FIELD-REPORT.md`, `docs/tasks/M4`, `docs/tasks/M8` and `docs/design/*` describe a far larger product that does not exist here. |

Task ids are `S<phase>.<n>` (S = slim). Each task states **why**, the **evidence**
(file:line), the **action**, and **done when**. `board: yes` needs hardware.

---

## Phase 0 — Truth in the repo

**Why first:** the documentation actively misleads. Every other task below is
easier to judge and to ship once the repo describes the thing that exists. This
phase is cheap and blocks nothing downstream, but it blocks good decisions.

### S0.1 Rewrite the root `README.md` for the slim build

- **why:** `README.md` advertises Wi-Fi AP/STA provisioning, the `esp-web-tools`
  browser installer, `scripts/deploy.sh bridge --image`, MQTT / Home Assistant,
  OTA updates, "alarms that wake you", guided cooks, CSV export, a 15 h pan/zoom
  chart, and a pairing-ack handshake. The slim build has none of these.
- **evidence:** `README.md:23-49, 68-139` vs `docs/firmware-slim.md:12-23` and
  `app/pubspec.yaml:1-6` ("No Wi-Fi/SoftAP, MQTT, OTA, alarms, notifications,
  marks, probe roles/targets, or settings tree").
- **action:** rewrite README around the real product: what it is, the hardware,
  the two-step flash (once a release path exists) and app install, the three
  screens, the BLE-only pairing story, and the honest limitations. Remove or
  relocate every claim about a dropped subsystem.
- **done when:** every link and command in `README.md` resolves, and no sentence
  describes a subsystem absent from `firmware/` and `app/lib/`.

### S0.2 Correct `new-app.md`, `RELEASE.md`, `FIELD-REPORT.md`, `CONTRIBUTING.md`

- **why:** these name files, screens, commands, an invariant suite (I2–I15), a
  golden set, and a test count that do not exist.
- **evidence:** `docs/new-app.md:14-25` lists `settings`, `onboarding`, `alarms`,
  `monitor`, `timeline`, `temps` directories in `app/lib/features/` that are
  absent; `docs/RELEASE.md:24-33` cites `app/test/verification/` and
  `app/test/golden/` (neither exists); `docs/FIELD-REPORT.md:34-40` cites a
  Device tab, Diagnostics, and a field report no screen provides;
  `docs/new-app.md:6` references `app/README.md` and `docs/RELEASE.md`
  references `app/CHANGELOG.md` — neither file exists.
- **action:** rewrite each to the slim reality, or move it under a clearly
  labelled "archive / full-bridge" heading. Fix the `app/lib/features/` tree,
  the test commands (`flutter analyze && flutter test`, `ctest`), and the gate
  list.
- **done when:** each of the four documents can be followed top to bottom without
  hitting a missing file, screen, or command.

### S0.3 Mark the full-bridge design and task docs as historical

- **why:** `docs/design/05,06,08,09,13,14,16,17` and `docs/tasks/M4,M8` are the
  spec for the removed product and will keep steering work if they read as
  current.
- **evidence:** `docs/tasks/M4-flutter-mvp.md:1-16` describes a Wi-Fi/HTTP
  dashboard MVP; `docs/tasks/M8-ux-rearchitecture.md:20-47` opens with four
  failures in code (`onboarding_route.dart`, `app_net_core.c`) that no longer
  exists on the slim build.
- **action:** add a one-line banner at the top of each ("Historic — describes the
  full Wi-Fi bridge, not the shipped slim build") or move them under
  `docs/archive/`. Point `docs/design/README.md` at this roadmap.
- **done when:** no current document presents the full-bridge behaviour as the
  plan, and `docs/design/README.md` directs readers here.

---

## Phase 1 — End-to-end experience blockers

**Why:** these are the items that make the app feel incomplete or untrustworthy
on first contact. They are the difference between "a demo" and "a product you
cook with".

### S1.1 Set the bridge's clock automatically on every connect

- **why:** the bridge stores sessions with no wall clock until an app writes one.
  Today that write is a manual button most users never find, so History and the
  Graph show `—` timestamps and unnamed sessions indefinitely.
- **evidence:** `setTime` is called only from `BridgeController.syncClock()`
  (`app/lib/app/bridge_controller.dart:508-523`), wired to one button on the Live
  footer (`app/lib/features/live/live_screen.dart:121-124`). Firmware writes
  `started_unix_ms = 0` until then (`protocol/records.yaml:234-238`), and the app
  maps 0 → `null` (`app/lib/data/ble/ble_transport.dart:353-355`).
- **action:** on every successful connect, send `repo.setTime(now, tzOffsetMin:)`
  as part of the connect sequence (before `_refreshSessions`), and keep the
  convention that the phone is the clock source. Re-send if the last set is older
  than a threshold. Surface success/failure through the existing `_report`
  channel; keep the manual button as an override.
- **done when:** a fresh connect with an unset bridge results in subsequent
  sessions carrying a real date, the History rows show a date with no user
  action, and a test asserts `setTime` is written exactly once per connect.

### S1.2 Show base-station pairing state, and drive it from the app

- **why:** the product's defining action — pairing the bridge to the Smoke X base
  (the single LoRa transmit) — has no app counterpart. The user cannot see
  whether the base is paired and cannot initiate pairing.
- **evidence:** firmware exposes `pair`/`unpair` (`app_ble_ctrl.c:175-180` →
  `smoke_x_ctrl_unpair`) but the app never calls them (no `PAIR` reference under
  `app/lib/`). `live_state.paired` is decoded
  (`app/lib/data/ble/bridge_transport.dart:112-117`) but used only to compute
  `Freshness.frozen` (`bridge_controller.dart:120-127`).
- **action:** surface paired/unpaired prominently (Live header or a pairing
  card), and offer a "Pair with base station" action that dispatches op `pair`
  and reflects the result. When unpaired, say what to do; when paired, show the
  last LoRa RSSI.
- **done when:** the app states paired/unpaired from `live_state`, a user can
  initiate pairing from the app, and a widget test covers both states.

### S1.3 Guided first-run pairing (passkey + base SYNC)

- **why:** bonding raises an OS passkey dialog while the six digits appear only
  on the bridge's OLED; the app never tells the user to read them, and first-run
  users must discover "Find my bridge" inside a sheet.
- **evidence:** the code documents this exact hazard but relies on a wizard that
  does not exist (`app/lib/data/ble/ble_gatt_fbp.dart:11-22` references "the
  onboarding wizard"); first-run shows only the disconnected Live state
  (`app/lib/features/live/live_screen.dart:50-63`).
- **action:** add a minimal first-run/setup surface that (1) explains the three
  hops — find, pair, optionally name — (2) during bonding, instructs the user to
  read the six digits on the bridge's OLED, and (3) explains the base-station
  SYNC gesture and the bridge OLED confirmation. Keep it to the slim scope; no
  Wi-Fi step.
- **done when:** a factory-fresh install reaches a live reading through named,
  instructed steps without the user needing external prose.

### S1.4 An honest state when reconnect gives up

- **why:** after three silent auto-reconnects the app reads "Offline" with no
  explanation and no offered action.
- **evidence:** `bridge_controller.dart:308-314` stops after `_reconnectAttempts
  < 3`; the chip only says "Offline" (`app/lib/features/common/connection.dart:29-33`).
- **action:** when retries are exhausted, set a distinct state/message ("Lost
  the bridge — tap to retry" or an error banner) and keep the manual retry
  prominent. Do not spin forever; do not fail silently.
- **done when:** retry exhaustion renders a distinct, actionable state, asserted
  by a controller test.

---

## Phase 2 — Business logic

### S2.1 Make sync terminate and stay bounded

- **why:** a closed session whose `sample_count` can never be reached is
  re-fetched on every 30 s tick indefinitely; and the tick walks the entire
  session list, so a long history becomes a burst of BLE round trips.
- **evidence:** completion requires `before >= session.sampleCount`
  (`app/lib/data/repo/sync_engine.dart:53-58`); the timer re-runs over every
  session (`bridge_controller.dart:243-246, 390-412`).
- **action:** treat a closed session as complete when `deviceMaxT <= cachedMax`
  (persist the fact, independent of `sample_count`), and only sync sessions that
  are open or genuinely incomplete. Consider syncing only the newest open session
  on the periodic tick and doing the full sweep on user-triggered sync.
- **done when:** a fully-synced history performs zero transport reads on the
  periodic tick, a session that cannot reach `sample_count` stops being retried,
  and tests cover both.

### S2.2 Close the cook model in the UI

- **why:** "Start cook" only drives the OLED clock (op 14); recorded sessions are
  opened and closed automatically by the firmware. A user who taps Start expects
  a new History entry and does not get one.
- **evidence:** `setCookClock` is a display op (`app/lib/data/ble/bridge_transport.dart:179-190`);
  sessions start at power-on + sync and end on all-detached / cap
  (`firmware/components/cook_store/include/cook_lifecycle.h:1-35`).
- **action:** explain the relationship in-place — the app's "cook clock" is a
  clock over the bridge's continuous recording, and History sessions are the
  recording. Either surface `session_start`/`session_stop` as an explicit
  boundary or make the copy unambiguous that no boundary is being drawn.
- **done when:** a user can tell, from the UI alone, why pressing Start does or
  does not create a History entry.

### S2.3 Make the temperature unit changeable everywhere

- **why:** the °F/°C control lives only on the Live app bar, so a user reading the
  Graph cannot switch units.
- **evidence:** `app/lib/features/live/live_screen.dart:130-147`; no unit control
  in `graph_screen.dart` or `history_screen.dart`.
- **action:** move the unit control to a shared app bar or a small settings
  surface reachable from every tab; keep the persisted preference.
- **done when:** the unit can be changed from Live, Graph, and History, and the
  choice persists.

### S2.4 Prefer the remembered bridge when several are in range

- **why:** with more than one bridge advertising, the app connects to whichever
  advertisement arrives first. Multi-bridge is out of scope, but "arbitrary" is a
  hazard, not a decision.
- **evidence:** `_scanForDeviceId` takes `.first` (`app/lib/data/ble/ble_gatt_fbp.dart:575-585`);
  `_candidate` only prefers the remembered id when it is a system device
  (`:553-562`).
- **action:** re-scan and prefer a device whose advertised name/id matches the
  remembered bridge; at minimum, show the connected bridge's `id`/name so the
  user can tell which one it is (the connection sheet already shows it,
  `connection.dart:214-223`).
- **done when:** a scan with a remembered bridge present selects it, and tests
  assert first-match is not the only path.

---

## Phase 3 — UI/UX and architecture

### S3.1 Extract one shared app bar

- **why:** the connection chip and sync `IconButton` (with its
  syncing/sync-error/disabled logic) are copy-pasted across every tab.
- **evidence:** near-identical `AppBar` blocks in
  `app/lib/features/live/live_screen.dart:26-34`,
  `app/lib/features/graph/graph_screen.dart:57-85`,
  `app/lib/features/history/history_screen.dart:27-54`.
- **action:** one `BridgeAppBar` widget owning the title, connection chip, sync
  control and (per S2.3) the unit control; each screen composes it.
- **done when:** the sync/chip logic exists once and all three screens use it.

### S3.2 Make the graph scale to real cooks

- **why:** the chart draws every sample with no decimation/envelope and only
  three bottom ticks, and has no pan/zoom. On multi-hour sessions it is the
  weakest screen.
- **evidence:** `app/lib/features/graph/temp_chart.dart:44-138` builds a spot per
  sample; `_bounds` (`:222-249`) applies no downsampling; no gesture handling.
- **action:** add LTTB decimation to a pixel budget (per docs: ~2 pts/pixel) plus
  a min/max envelope for wide ranges, and the standard viewport affordances
  (window chips, pan, pinch, jump-to-now). Keep the existing run-splitting at
  gaps — it is correct and load-bearing.
- **done when:** a 15 h session renders within one frame budget, gaps remain
  gaps, and the viewport is table-testable without a gesture.

### S3.3 Remove dead contract constants

- **why:** `BridgeChar` still declares the Wi-Fi and preview characteristics the
  slim firmware does not register, inviting use of a contract that will never
  answer.
- **evidence:** `app/lib/data/ble/ble_gatt.dart:24-31` (`netStatus`, `wifiScanCtrl`,
  `wifiScanResult`, `wifiConfig`, `historyPreview`) vs the registered set in
  `firmware/components/app_ble/include/app_ble_core.h:49-59`.
- **action:** keep only the characteristics the slim build serves
  (`device_info`, `device_control`, `live_state`, `result`, `history_ctrl`,
  `history_data`), or comment the rest as reserved and unused.
- **done when:** the client's declared characteristic set matches the firmware's
  registry exactly.

### S3.4 Purge stale references in doc comments

- **why:** comments point at files and systems that were deleted, which misleads
  every future review.
- **evidence:** references to `app/lib/app/palette.dart`, `onboarding_route.dart`,
  `dashboard_snapshot.dart`, `chart_series.dart`, `app/lib/truth/` across
  `app/lib/` (e.g. `data/ble/ble_transport.dart:1-15`,
  `data/ble/ble_gatt.dart:1-14`, `app/bridge_controller.dart:1-12`).
- **action:** rewrite comments to describe the slim architecture only; keep the
  "why" reasoning that still applies.
- **done when:** no comment in `app/lib/` names a module that does not exist.

### S3.5 Build a BLE end-to-end harness and close the coverage gaps

- **why:** the core flow (pair → connect → set clock → sync → graph) is only
  unit-tested piecemeal, and `tools/sim` speaks HTTP/WebSocket so it cannot drive
  a BLE-only app at all — there is no app-level E2E test.
- **evidence:** 45 app tests (`app/test/`); no golden or verification suite;
  `tools/sim/` is an HTTP server (`tools/sim/lib/src/server.dart`).
- **action:** add an end-to-end test driven through `FakePeripheral`
  (`app/test/support/fake_peripheral.dart`) covering connect → clock → session
  list → sync → samples → graph render, including the dropped-link reconnect
  path. Fill the widget-test gaps (connection-sheet states, session detail,
  error and empty states).
- **done when:** a single test drives the whole kept-feature path over the fake,
  and the untested screens/states above have coverage.

---

## Phase 4 — Firmware and hardware

### S4.1 Bench-sit the board

- **why:** everything on-glass is unverified. This is the top firmware risk and
  the only way to call the kept features "high quality".
- **evidence:** `docs/firmware-slim.md:72-76` — the image builds, 21/21 host
  suites pass, but it has **not been flashed**; OLED pages, the recovery
  gesture, BLE bonding, and LoRa RX cadence are owed a sitting.
- **action:** flash a real board and record: pages legible, hold-to-confirm
  recovery wipes and reboots, BLE bonds and streams history, LoRa RX cadence.
  Write results into `docs/hardware-verified.md`.
- **done when:** each owed row has a recorded, dated result; deviations become
  named follow-up tasks.
- **board:** yes

### S4.2 Fix the GATT write error path

- **why:** on a failed attribute flatten the handler passes an uninitialized
  buffer and a length one past the array. It currently happens to answer
  `invalid` because the length check fires first, but it is unintended and
  fragile.
- **evidence:** `firmware/components/app_ble/app_ble.c:203-206` —
  `app_ble_core_write(ch, &link, buf, sizeof buf + 1)` on the `!= 0` branch.
- **action:** answer `invalid` explicitly (no data), or pass a correct length;
  add a host test for the flatten-failure path.
- **done when:** the branch no longer reads past the buffer and is covered by a
  test.
- **board:** no

### S4.3 Prune the inert config surface

- **why:** the slim build still stores Wi-Fi, MQTT, alarm, and probe-role keys
  that nothing uses, which is dead surface area and a false suggestion of
  features.
- **evidence:** `firmware/components/app_config/include/app_config_store.h:51-108`
  (`net/*`, `mqtt/*`, `alarms/rules`, probe name/role/target, `api_token`,
  retention); flagged already in `docs/firmware-slim.md:85-86`.
- **action:** remove the keys with no live consumer (keeping any the OLED/retention
  path still reads), and update the host config test.
- **done when:** every remaining config key has a production reader, and the
  config host suite is green.
- **board:** no

### S4.4 OLED Bluetooth-page golden, and decide the update path

- **why:** the new Bluetooth page's content is only covered by the
  render-all-pages test, not a byte golden; and the update path is undecided.
- **evidence:** `docs/firmware-slim.md:80-84`.
- **action:** add a byte golden for the Bluetooth page; decide and record
  USB-only vs BLE OTA for MVP.
- **done when:** the page has a committed golden and the update-path decision is
  written down.
- **board:** no

---

## Suggested execution order (fastest path to "high quality")

| Sprint | Tasks | Outcome |
|---|---|---|
| 1 | S0.1–S0.3 | The repo describes the real product. |
| 2 | S1.1, S1.2, S1.3 | First contact feels complete: clock, pairing, and guidance. |
| 3 | S2.1, S3.1, S2.3 | Sync is trustworthy; the shell is DRY; units work everywhere. |
| 4 | S3.5, S3.2 | A real E2E test, then a graph that scales. |
| 5 | S4.1–S4.4 | Hardware-verified, pruned, and documented. |

S1.4, S2.2 and S2.4 can slot anywhere after S1.1; S3.3 and S3.4 are
drive-by cleanups that can ride with any app change.