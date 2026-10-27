# Smoke X4 Smart Bridge — Android app

Production Flutter app for the Smoke X4 bridge. It is **Android-only**; iOS,
web and desktop targets are intentionally absent.

The screens, widgets and theme come from the approved prototype and remain the
production UI contract. Read
[`docs/design/13-ui-implementation-contract.md`](../docs/design/13-ui-implementation-contract.md)
before changing a screen. Copy is governed by
[`docs/design/12-copy-and-label-review.md`](../docs/design/12-copy-and-label-review.md).

T05 establishes the production skeleton:

- `lib/main.dart` → `lib/app/bootstrap.dart` (DB open, repository, controller);
- `BridgeController` in `lib/app/bridge_controller.dart` is the control seam;
- `BridgeRepository` in `lib/data/repository.dart` is the data seam;
- `AppDatabase` in `lib/data/db/app_database.dart` is the SQLite open path
  (the schema and migrations land in T40);
- `SmokeBridgeApp` mounts the approved Live / History / Settings shell.

The screen-facing fields still come from the prototype controller shape; T06
moves them behind immutable view states and removes fixture data from the
production screens.

## Run it

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter run -d <android>   # target device/emulator
```

From the repository root, `make app-check` runs analyze and the widget suite.

## Review every scenario

In debug builds, open the app-bar menu and choose **Experimental lab**, or go to
**Settings → About** and long-press the app title. Release builds hide the entry
by default; opt in with `--dart-define=ENABLE_EXPERIMENTAL_LAB=true` when a
review build needs it. The lab is review-only and is not part of the release
entrypoint.

Reference screenshots live in [`screenshots/`](screenshots/). They are generated
from the production screens, seeded through the debug-only demo adapter:

```bash
flutter test --update-goldens tool/ui_screenshots_test.dart
```

The screenshot tool is outside `test/`, so it does not run as part of the normal
test suite.

## Structure

```text
lib/
├── main.dart                  production entrypoint
├── app/                       bootstrap, BridgeController, view state, formatters
├── domain/                    Flutter-free models and BridgeContent data seam
├── data/                      repository seam and SQLite open path
├── debug/                     fixtures, demo adapter and experimental lab (review/test)
├── theme/                     light/dark design tokens
├── widgets/                   shared cards, banner, chart
└── features/                  setup, shell, live, history, settings, device
```
