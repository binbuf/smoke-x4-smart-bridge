# The app (`app/`)

The companion app is the Flutter package at [`app/`](../app/) (package
`smoke_bridge`). It is **BLE-only** and deliberately small: live temperatures, a
graph, and history, plus a connection sheet and a cook clock. There is no Wi-Fi,
MQTT, OTA, alarms, notifications, marks, probe roles/targets, or settings tree —
see [`app/pubspec.yaml`](../app/pubspec.yaml) for the one-paragraph statement of
scope.

This page is the entry point for the app. [`current-app.md`](current-app.md),
[`newapp.md`](newapp.md), and the `newui/` prototype are **history**: they
describe the design language and an earlier, larger app and are kept for
reference only.

## Where things live

```
app/lib/
  app/        bootstrap, root widget, router, the one BridgeController
  design/     tokens, typography, primitives — presentation only, stateless
  domain/     pure Dart entities and engines — zero Flutter imports
  data/
    ble/      GATT contract + the BLE transport (BridgeTransport)
    repo/     BridgeRepository and SyncEngine
    local/    drift database (the persistent sample cache) and prefs
    dto/      records.g.dart, generated from protocol/records.yaml
  features/   the three destinations and their pieces:
                live/     live_screen, probe_card
                graph/    graph_screen, temp_chart
                history/  history_screen, session_detail_screen
                common/   connection (chip + sheet), session_picker
                cook/     cook_clock_card
  platform/   Android seams (system settings)
app/test/
  app/ data/ domain/ features/   unit, controller and widget tests
  support/                        FakePeripheral — the board-free BLE fake
```

The layering rule: `domain/` imports no Flutter and is host-testable with
`package:test`. `design/` is presentation-only. `data/` owns transports and the
cache. `features/` composes them.

## Commands

From the repo root:

| Command | Does |
|---|---|
| `make app.run` | `flutter run` on a device/emulator |
| `make app.test` | analyze + format check + `flutter test` |
| `make app.gen` | `dart run build_runner build` (after a model/provider change) |

From `app/` directly:

```
flutter analyze
flutter test
dart test test/domain test/data
flutter build apk --release
```

The **real bridge is the only repository**. There is no mock switch and no
`BRIDGE_HOST`: the app talks to the bridge over BLE, and board-free development
and tests drive [`test/support/fake_peripheral.dart`](../app/test/support/fake_peripheral.dart),
which speaks the same generated codecs as the firmware.

## Testing and release

- The suite is `flutter analyze && flutter test` (`make app.test`); the pure-Dart
  `domain/` and `data/` tests also run under `dart test`.
- There is **no golden suite and no separate invariant/verification suite** in
  the slim app. Adding an end-to-end BLE harness and filling the widget-test gaps
  is [S3.5 in the roadmap](../ROADMAP.md).
- The release considerations for the slim app are in [`RELEASE.md`](RELEASE.md).