# Smoke X4 Smart Bridge Roadmap

A battery-powered ESP32 bridge records ThermoWorks Smoke X4 probe readings to a
rolling flash log, shows them on an OLED, and serves live values plus the full
history to an Android app over BLE. The plan below takes the project from an
empty production tree to a release-tested bridge and app, then closes one
optional post-MVP RF survey question.

Phases run in order. Each task is sized for one unattended coding session and
names the design sections, verification tier and board requirement it needs.
Bench tasks (tier B/P/C) require the physical bridge, phone or cook named in the
task.

## Phase 1 — Contract & Harness

Protocol contract, host tests, firmware and app skeletons, the approved-UI
baseline, the BLE fake, CI and the bench identity/power answers. No product
feature lands here, but every later task has a place to land.

- [x] T01 — Workspace scaffold and ignore rules → [tasks/01-workspace-scaffold.md](tasks/01-workspace-scaffold.md)
- [x] T02 — Protocol contract and codegen → [tasks/02-protocol-contract-codegen.md](tasks/02-protocol-contract-codegen.md)
- [x] T03 — Host test harness and fixtures → [tasks/03-host-test-harness.md](tasks/03-host-test-harness.md)
- [x] T04 — Firmware skeleton and partition table → [tasks/04-firmware-skeleton.md](tasks/04-firmware-skeleton.md)
- [x] T05 — App skeleton → [tasks/05-app-skeleton.md](tasks/05-app-skeleton.md)
- [x] T06 — UI baseline and view-model seam → [tasks/06-ui-baseline-view-model-seam.md](tasks/06-ui-baseline-view-model-seam.md)
- [x] T07 — BLE fake and app test seam → [tasks/07-ble-fake-app-test-seam.md](tasks/07-ble-fake-app-test-seam.md)
- [x] T08 — CI → [tasks/08-ci.md](tasks/08-ci.md)
- [x] T09 — Board identity, bench rig, and deep-sleep gate → [tasks/09-board-identity-bench-rig.md](tasks/09-board-identity-bench-rig.md) ⟵ accepted
- [x] T10 — Baseline capture → [tasks/10-baseline-capture.md](tasks/10-baseline-capture.md)
- [x] T11 — Deep-sleep and power decision record → [tasks/11-deep-sleep-power-decision.md](tasks/11-deep-sleep-power-decision.md)

**Exit gate:** contract files and generated C/Dart code compile; host tests run
in CI; the BLE fake works; the UI baseline/view-model seam is in place; board
identity is confirmed; the deep-sleep wake answer is recorded.

## Phase 2 — Firmware Core

A real Smoke X4 pairs, the stock receiver is unaffected, every valid packet
lands in the ring log, earlier records survive a power cut, and the
OLED/PRG/power path works. BLE may still be a skeleton.

- [x] T12 — sx_radio: vendor the SX1262 driver → [tasks/12-sx-radio-vendor-driver.md](tasks/12-sx-radio-vendor-driver.md)
- [x] T13 — sx_radio: RX loop and parameters → [tasks/13-sx-radio-rx-loop.md](tasks/13-sx-radio-rx-loop.md)
- [x] T14 — sx_protocol: port and extend the parser → [tasks/14-sx-protocol-parser.md](tasks/14-sx-protocol-parser.md)
- [x] T15 — bridge_config: typed NVS store → [tasks/15-bridge-config-nvs.md](tasks/15-bridge-config-nvs.md)
- [x] T16 — sx_radio: pairing state machine and TX guard → [tasks/16-sx-radio-pairing-fsm.md](tasks/16-sx-radio-pairing-fsm.md)
- [x] T17 — sample_log: record codec → [tasks/17-sample-log-record-codec.md](tasks/17-sample-log-record-codec.md)
- [x] T18 — sample_log: ring geometry → [tasks/18-sample-log-ring-geometry.md](tasks/18-sample-log-ring-geometry.md)
- [x] T19 — sample_log: flash adapter and boot recovery → [tasks/19-sample-log-flash-adapter.md](tasks/19-sample-log-flash-adapter.md)
- [x] T20 — bridge_state: clock and live snapshot → [tasks/20-bridge-state-clock-snapshot.md](tasks/20-bridge-state-clock-snapshot.md)
- [x] T21 — sample_pipe: parser → log → UI → [tasks/21-sample-pipe-parser-log-ui.md](tasks/21-sample-pipe-parser-log-ui.md)
- [x] T22 — ui: pages, renderer, and display sleep → [tasks/22-ui-pages-renderer.md](tasks/22-ui-pages-renderer.md)
- [x] T23 — ui: PRG gestures and deep sleep → [tasks/23-ui-prg-gestures-sleep.md](tasks/23-ui-prg-gestures-sleep.md)
- [x] T24 — board: battery ADC and power stats → [tasks/24-board-battery-adc.md](tasks/24-board-battery-adc.md)
- [ ] T25 — Bench prep: pair, stock receiver, power cut → [tasks/25-bench-pair-power-cut.md](tasks/25-bench-pair-power-cut.md)
- [ ] T26 — Bench prep: cadence and display → [tasks/26-bench-cadence-display.md](tasks/26-bench-cadence-display.md)

**Exit gate:** a real X4 pairs; the stock receiver keeps updating; samples
survive a power cut; the OLED and PRG work; the host suite is green.

## Phase 3 — BLE + App Slice (V0)

A factory-fresh phone scans the bridge, pairs with the OLED code, sees four live
temperatures, and shows the last 15 minutes in the full History shell. Reconnect,
offline-cache and power-cycle states work. This is the first deployable
end-to-end build.

- [ ] T27 — ble_service: GATT server and info → [tasks/27-ble-gatt-info.md](tasks/27-ble-gatt-info.md)
- [ ] T28 — ble_service: live notify → [tasks/28-ble-live-notify.md](tasks/28-ble-live-notify.md)
- [ ] T29 — ble_service: control, result, and the clock → [tasks/29-ble-control-result-clock.md](tasks/29-ble-control-result-clock.md)
- [ ] T30 — ble_service: security, passkey, and advertising → [tasks/30-ble-security-passkey.md](tasks/30-ble-security-passkey.md)
- [ ] T31 — ble_service: sync status and recent records → [tasks/31-ble-sync-recent-records.md](tasks/31-ble-sync-recent-records.md)
- [ ] T32 — app: BLE client and scan → [tasks/32-app-ble-client-scan.md](tasks/32-app-ble-client-scan.md)
- [ ] T33 — app: setup and passkey flow → [tasks/33-app-setup-passkey-flow.md](tasks/33-app-setup-passkey-flow.md)
- [ ] T34 — app: Live screen → [tasks/34-app-live-screen.md](tasks/34-app-live-screen.md)
- [ ] T35 — app: link procedures and time sync → [tasks/35-app-link-procedures-time-sync.md](tasks/35-app-link-procedures-time-sync.md)
- [ ] T36 — app: recent History (V0) → [tasks/36-app-recent-history-v0.md](tasks/36-app-recent-history-v0.md)
- [ ] T37 — Bench: V0 end-to-end → [tasks/37-bench-v0-end-to-end.md](tasks/37-bench-v0-end-to-end.md)
- [ ] T38 — Field observation: first normal cook on V0 → [tasks/38-field-observation-first-cook.md](tasks/38-field-observation-first-cook.md)

**Exit gate (V0):** a fresh phone scans, pairs with the OLED code, sees four live
temperatures, and shows the last 15 minutes in the full History shell; reconnect
and offline-cache states work; no prototype chrome appears on product screens.

## Phase 4 — History

The app syncs the full ring, resumes after disconnect, survives relaunch, draws
gaps honestly, and never deletes data without an explicit user action. History,
Summary, Cooks and the Cook view match the approved UI contract.

- [ ] T39 — ble_service: full sync cursor, gap, and generation → [tasks/39-ble-full-sync-cursor.md](tasks/39-ble-full-sync-cursor.md)
- [ ] T40 — app: local database and DAO → [tasks/40-app-local-database.md](tasks/40-app-local-database.md)
- [ ] T41 — app: repository and two-phase sync → [tasks/41-app-repository-two-phase-sync.md](tasks/41-app-repository-two-phase-sync.md)
- [ ] T42 — app: full History chart, Summary and Cooks → [tasks/42-app-history-chart-summary-cooks.md](tasks/42-app-history-chart-summary-cooks.md)
- [ ] T43 — app: connection health and stale states → [tasks/43-app-connection-health.md](tasks/43-app-connection-health.md)
- [ ] T44 — app: data use and explicit deletion → [tasks/44-app-data-use-deletion.md](tasks/44-app-data-use-deletion.md)
- [ ] T45 — app: History/data empty and error states → [tasks/45-app-history-empty-error-states.md](tasks/45-app-history-empty-error-states.md)
- [ ] T46 — Bench: full history and resume → [tasks/46-bench-full-history-resume.md](tasks/46-bench-full-history-resume.md)

**Exit gate:** the full ring syncs and resumes; relaunch keeps the archive;
gaps and estimated times are honest; Summary/Cooks work; deletion is explicit;
the History UI matches the approved contract.

## Phase 5 — Settings & Actions

Every setting the device cannot expose with one button is editable from the
phone, and forget/factory-reset/power-off work on the real bridge. Destructive
actions explain their cost before sending. Accessibility, copy and layout gates
pass.

- [ ] T47 — ble_service: config read/write → [tasks/47-ble-config-read-write.md](tasks/47-ble-config-read-write.md)
- [ ] T48 — ble_service: control actions → [tasks/48-ble-control-actions.md](tasks/48-ble-control-actions.md)
- [ ] T49 — ble_service: destructive-action state and reconnect → [tasks/49-ble-destructive-state-reconnect.md](tasks/49-ble-destructive-state-reconnect.md)
- [ ] T50 — app: Settings shell → [tasks/50-app-settings-shell.md](tasks/50-app-settings-shell.md)
- [ ] T51 — app: bridge settings → [tasks/51-app-bridge-settings.md](tasks/51-app-bridge-settings.md)
- [ ] T52 — app: destructive actions → [tasks/52-app-destructive-actions.md](tasks/52-app-destructive-actions.md)
- [ ] T53 — app: units and time end-to-end → [tasks/53-app-units-time-end-to-end.md](tasks/53-app-units-time-end-to-end.md)
- [ ] T54 — app: UI state matrix, accessibility and copy gate → [tasks/54-app-ui-state-matrix-a11y-copy.md](tasks/54-app-ui-state-matrix-a11y-copy.md)
- [ ] T55 — Bench: all settings and actions → [tasks/55-bench-settings-actions.md](tasks/55-bench-settings-actions.md)

**Exit gate:** every app-controlled setting/action works on the real bridge;
factory reset returns the app to setup with saved history kept; Settings matches
the approved contract; UI/a11y/copy gate green.

## Phase 6 — Billows

Billows observation is verified with a real unit. The bridge shows
attached/not-attached and, only when the probe-4 target relation is confirmed,
the target set on the Smoke X4. `caps.billows_control = 0`; there is no setpoint
setter and no Billows TX path.

- [ ] T56 — Billows observation evidence (passive) → [tasks/56-billows-observation-evidence.md](tasks/56-billows-observation-evidence.md)
- [ ] T57 — Firmware: Billows observation → [tasks/57-firmware-billows-observation.md](tasks/57-firmware-billows-observation.md)
- [ ] T58 — App: Billows UI (observation only) → [tasks/58-app-billows-ui.md](tasks/58-app-billows-ui.md)
- [ ] T59 — Bench: Billows observation → [tasks/59-bench-billows-observation.md](tasks/59-bench-billows-observation.md)

**Exit gate:** observed state and target are verified with a real Billows; the
target shows only if validated, otherwise `—`; `billows_control = 0`; Option C
(observation only) is recorded in `docs/billows-decision.md`.

## Phase 7 — Field Hardening & Release

A 24-hour soak and a real overnight cook pass; the release checklist and UI/UX
acceptance are complete; a new user can follow the README from a blank phone and
board to live data; known limitations are written down.

- [ ] T61 — 24-hour soak → [tasks/61-24-hour-soak.md](tasks/61-24-hour-soak.md)
- [ ] T62 — Power, deep sleep, and runtime → [tasks/62-power-deep-sleep-runtime.md](tasks/62-power-deep-sleep-runtime.md)
- [ ] T63 — Field cook → [tasks/63-field-cook.md](tasks/63-field-cook.md)
- [ ] T64 — App release build → [tasks/64-app-release-build.md](tasks/64-app-release-build.md)
- [ ] T65 — Firmware release build → [tasks/65-firmware-release-build.md](tasks/65-firmware-release-build.md)
- [ ] T66 — Documentation and handoff → [tasks/66-documentation-handoff.md](tasks/66-documentation-handoff.md)
- [ ] T67 — Final acceptance audit → [tasks/67-final-acceptance-audit.md](tasks/67-final-acceptance-audit.md)

**Exit gate:** soak and overnight cook pass; UI parity/a11y/copy gate complete;
release APK and firmware image install/flash cleanly; README works from blank;
every acceptance row is pass, fail with a named follow-up, or explicitly
descoped.

## Phase 8 — Post-MVP

Optional work that must not run before T67 completes. It adds evidence only, not
a product control path.

- [ ] T68 — Post-MVP: passive RF survey for additional Billows data → [tasks/68-post-mvp-passive-rf-survey.md](tasks/68-post-mvp-passive-rf-survey.md)

**Exit gate:** a receive-only report records whether any additional displayable
Billows telemetry exists; if not, the question closes and observation stays
as-is.

<!-- symphony:status -->
**Pipeline status** — updated 2026-10-27T06:45:53Z · 24/67 done

- Completed: T01, T02, T03, T04, T05, T06, T07, T08, T09, T10, T11, T12, T13, T14, T15, T16, T17, T18, T19, T20, T21, T22, T23, T24
- Blocked: none
- Failed: none
- Remaining: T25, T26, T27, T28, T29, T30, T31, T32, T33, T34, T35, T36, T37, T38, T39, T40, T41, T42, T43, T44, T45, T46, T47, T48, T49, T50, T51, T52, T53, T54, T55, T56, T57, T58, T59, T61, T62, T63, T64, T65, T66, T67, T68
- Last finished: T24 — done · Battery ADC/divider sampling, Li-ion curve with SOC_UNKNOWN, power stats, and housekeeping publication landed; host tests and firmware build pass, with DMM/current measurements deferred to T62.
<!-- /symphony:status -->
