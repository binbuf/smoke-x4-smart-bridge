# Smoke X4 Smart Bridge — UI Prototype

This is a **clickable UI/UX prototype**, not the production app. It contains no
BLE, database, permission, sync, network, or firmware code. Every state comes
from the in-memory scenario lab.

Android is the product target. The Windows and web targets exist only so the
prototype can be reviewed quickly; they are not part of the MVP release scope.

## Run it

```bash
cd app
flutter pub get
flutter run -d windows     # fastest review loop
flutter run -d chrome      # dev-only web preview, if enabled
flutter run -d <android>   # target device/emulator
```

`flutter analyze` and `flutter test` are clean.

Reference screenshots live in [`screenshots/`](screenshots/). They are generated
from the real widget tree with the screenshot tool:

```bash
flutter test --update-goldens tool/ui_screenshots_test.dart
```

The screenshot tool is outside `test/`, so it does not run as part of the normal
test suite.

## Review every scenario

In debug builds, open the app-bar menu and choose **Experimental lab**, or go to
**Settings → About** and long-press the app title. The Scenario Lab has 80+
reachable screens and states grouped by flow. Release builds hide the menu entry
by default; opt in with
`--dart-define=ENABLE_EXPERIMENTAL_LAB=true` when a review build needs it:

- Setup and permissions: primer, Bluetooth off, denied/blocked, unsupported,
  scanning, no results, results, protocol mismatch, passkey, pairing, wrong
  code, timeout, out-of-date pairing, phone list full, first sync, device log.
- Live and connection: live/aging/stale/frozen, detached and absent probes,
  no Smoke X4, storage unavailable, syncing, slow link, reconnecting, failed,
  offline with/without cache, sync failure, and every Billows variant.
- History: 1 h / 6 h / 24 h / 7 d / All, past cooks in a dedicated historical
  view, one probe, empty, no data in range, offline cache, estimated time, and
  missing-from-bridge.
- Settings: Bridge status first, then history & storage, preferences, units,
  appearance, Billows monitor/control/detection, deletion, re-pair, device log,
  About.
- Confirmations: forget, clear bridge log, delete 30/90/all, factory reset,
  power off, and the post-power-off wake screen.
- Device OLED: four pages, passkey, power-off countdown, storage failure,
  reset/clear progress, OFF, and boot.

The theme switch is in the lab header and in **Settings → Appearance**; it
covers both **dark and light** modes for every screen.

## What is simulated

- Permission/Bluetooth settings buttons show a snackbar; they do not open the OS.
- The OS passkey dialog is simulated in the lab. The real app never shows the
  code; it is only on the Bridge OLED.
- Save, sync, re-pair, delete, factory reset, and power off use local timers or
  state changes. No device is contacted.
- Charts use deterministic fixtures, including per-probe last-hour sparklines,
  a visible gap, four probe series, and an "all history" range.

## Structure

```text
lib/
├── main.dart                  prototype entrypoint
├── prototype/                 controller, fixtures, scenario lab
├── theme/                     light/dark design tokens
├── widgets/                   shared cards, banner, chart
└── features/                  setup, shell, live, history, settings, device
```

Screens consume UI state only. When the real `BridgeController` lands, it should
map domain state into the same view models; the widget layer should not need a
rewrite.
