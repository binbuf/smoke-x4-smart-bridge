# Smoke X4 Smart Bridge — UI Prototype

This is a **clickable UI/UX prototype**, not the production app. It contains no
BLE, database, permission, sync, network, or firmware code. Every state comes
from the in-memory experimental lab.

The prototype is the approved production UI contract. Production keeps the
screens, widgets, theme, copy and states and replaces the state source with real
business logic. Read
[`docs/design/13-ui-implementation-contract.md`](../docs/design/13-ui-implementation-contract.md)
before changing a screen. Copy is governed by
[`docs/design/12-copy-and-label-review.md`](../docs/design/12-copy-and-label-review.md).

UI baseline evidence: `flutter analyze` is clean, 26 widget tests pass, and the
dark/light screenshot set is generated from the real widget tree.

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
**Settings → About** and long-press the app title. The Experimental lab has 80+
reachable screens and states grouped by flow. Release builds hide the menu entry
by default; opt in with
`--dart-define=ENABLE_EXPERIMENTAL_LAB=true` when a review build needs it:

- Setup and permissions: primer, Bluetooth off, denied/blocked, unsupported,
  scanning, no results, results, protocol mismatch, pairing code, pairing, wrong
  code, timeout, out-of-date pairing, phone list full, first sync, history on
  this phone.
- Live and connection: live/aging/stale/frozen, detached and absent probes,
  no Smoke X4, not recording, syncing, slow connection, reconnecting, failed,
  offline with/without cache, sync failure, and every Billows variant.
- History: 1 hour / 6 hours / 24 hours / 2 days / Custom, Cooks in a dedicated
  historical view, one probe, empty, no data in range, offline cache, estimated
  time, and overwritten-before-sync.
- Settings: Bridge status first, then History & storage, preferences, units,
  appearance, Billows status, deletion, re-pair, history on this phone, About.
- Confirmations: forget, clear history on the Bridge, delete 30/90/all, factory
  reset, power off, and the post-power-off wake screen.
- Bridge screen: four pages, pairing code, power-off countdown, storage failure,
  reset/clear progress, OFF, and boot.

The theme switch is in the lab header and in **Settings → Appearance**; it
covers both **dark and light** modes for every screen.

## What is simulated

- Permission/Bluetooth settings buttons show a snackbar; they do not open the OS.
- The OS pairing prompt is simulated in the lab. The real app never shows the
  code; it is only on the Bridge screen.
- Save, sync, re-pair, delete, factory reset, and power off use local timers or
  state changes. No device is contacted.
- Charts use deterministic fixtures, including per-probe last-hour sparklines,
  a visible gap, four probe series, and an all-saved-history range.

## Structure

```text
lib/
├── main.dart                  prototype entrypoint
├── prototype/                 controller, fixtures, experimental lab
├── theme/                     light/dark design tokens
├── widgets/                   shared cards, banner, chart
└── features/                  setup, shell, live, history, settings, device
```

Screens consume UI state only. When the real `BridgeController` lands, it should
map domain state into the same view models; the widget layer should not need a
rewrite.
