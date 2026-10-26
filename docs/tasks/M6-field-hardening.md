# M6 — Field Hardening & Release

**Exit gate:** a 24-hour soak and a real overnight cook pass; the release
checklist is complete; a new user can follow the README from a blank phone and
board to live data; known limitations are written down.

**Design:** [10](../design/10-test-and-release.md)

---

### V6.1 24-hour soak

- **blocked-by:** V2.1, V3.1, V4.1, V5.1 · **verify:** B · **board:** yes
- **design:** [10 §10.4](../design/10-test-and-release.md)

Run the release image for 24 h with real samples (or a fixture transmitter), BLE
advertising, a phone connected for part of it, OLED asleep, and periodic sync.
Capture `heap_free`, `heap_min`, stack margins, packet counters, storage, and
reconnect counts. Apply the fixed criteria in 10 §10.4.

**Done when.** The trace and report are committed; failures become named tasks,
not silently lowered thresholds.

---

### V6.2 Power, deep sleep, and runtime

- **blocked-by:** F1.12, F1.13 · **verify:** B · **board:** yes
- **design:** [01 §1.4, §1.9](../design/01-hardware.md)

Measure:

- on + advertising + OLED asleep,
- on + connected + OLED awake,
- deep sleep,
- 24 h on the 3000 mAh pack (advertising, OLED asleep).

Confirm hold-PRG wake 20/20 with USB attached and detached. Record the fallback
if the strap issue appears.

**Done when.** The runtime and current table is committed; the 24 h target is
passed or the release note states the measured value honestly.

---

### V6.3 Field cook

- **blocked-by:** V3.1, V4.1 · **verify:** C · **board:** yes
- **design:** [10 §10.3 B5](../design/10-test-and-release.md)

One supervised cook and one overnight cook with the phone away for ≥ 6 h:

- stock receiver works throughout,
- the bridge records continuously,
- the phone reconnects and syncs the whole period,
- History shows the cook and any real gaps,
- no reboot/panic,
- delete/retention not accidentally triggered.

**Done when.** A short field report and screenshots are committed; any defect has
a named follow-up. Update the open-decisions table and roadmap the same way V2.2
does; a field cook that changes an assumption changes a task.

---

### V6.4 App release build

- **blocked-by:** A4.4, V6.1 · **verify:** H/P · **board:** no / phone
- **design:** [10 §10.5](../design/10-test-and-release.md)

Set the version, icon, package id, release signing (or a documented debug-only
bench build), and Android manifest. Remove debug-only UI. Run `flutter analyze`
and `flutter test`. Install a fresh APK and upgrade an existing install.

**Done when.** A release APK installs and completes the V0/V3 flows; the manifest
contains no unused network/notification/foreground-service permissions.

---

### V6.5 Firmware release build

- **blocked-by:** V6.1, V6.2 · **verify:** H/B · **board:** yes
- **design:** [10 §10.5](../design/10-test-and-release.md)

Set the firmware version, run the host suite and `idf.py build`, produce a
merged image, and document the USB flash command. Confirm factory reset, deep
sleep, and the TX invariant on the release image (sync ACK only; no Billows TX
path, `caps.billows_control = 0`).

**Done when.** The image and flash instructions are committed; a clean board
flashes and reaches advertising.

---

### V6.6 Documentation and handoff

- **blocked-by:** V6.3, V6.4, V6.5 · **verify:** H · **board:** no
- **design:** [10 §10.5, §10.7](../design/10-test-and-release.md)

Write/refresh:

- root `README.md`: what it is, hardware, build/flash, install, pair, first run,
  limitations, attribution.
- `docs/hardware-verified.md`: dated bench results.
- `docs/billows-decision.md`: observation-only decision and evidence.
- release notes per 10 §10.7.
- a one-page "new user" path: power, fit antenna, pair, live, history.

**Done when.** A person who has never seen the repo can follow the README from a
blank phone/board to live data without external prose.

---

### V6.7 Final acceptance audit

- **blocked-by:** V6.3, V6.4, V6.5, V6.6 · **verify:** H/B/P/C · **board:** yes
- **design:** [10 §10.6](../design/10-test-and-release.md)

Walk the acceptance matrix row by row. For each:

- mark pass/fail by observation,
- link the evidence,
- if fail, create a named follow-up or explicitly descope with the owner.

Confirm the release notes match the capability bits (`billows_control`,
`history`, `battery`, `power_off`, `factory_reset`). `billows_control` is 0 and
the Billows copy says "Set the target on the Smoke X4." Confirm
`docs/billows-decision.md` records the observation-only decision and owner
acceptance; without it, release is blocked, not merely worded differently.

**Done when.** Every row is pass, fail, or explicitly descoped; nothing is blank.
