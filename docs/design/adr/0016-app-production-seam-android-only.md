# 0016 — App production seam and Android-only targets

## Status

Accepted

## Context

T05 must turn the approved prototype tree into a production Flutter app without
redesigning the approved screens. Later tasks need stable seams: one controller
for app control, one repository for persistence, and a SQLite open path that T40
can migrate. The prototype also shipped Windows and web targets purely for
review, which conflicts with the Android-only MVP, and its entrypoint created the
prototype controller directly.

## Decision

Keep the approved prototype UI under `app/lib/features/`, `widgets/` and `theme/`.
Move the controller to `app/lib/app/bridge_controller.dart` and make it the single
`BridgeController extends ChangeNotifier`. Production startup is
`lib/main.dart` → `lib/app/bootstrap.dart`, which opens `AppDatabase` (sqflite),
builds a `BridgeRepository` (`app/lib/data/repository.dart`), initialises the
controller, and mounts `SmokeBridgeApp`. Keep prototype fixtures, the scenario
lab and formatters in `app/lib/prototype/` as review/test support until T06
replaces the screen-facing state with immutable view states. Remove the tracked
Windows and web targets; Android is the only app target.

The production entrypoint (`main.dart`, `app/bootstrap.dart`,
`app/smoke_bridge_app.dart`, `app/bridge_controller.dart`) must not import
`prototype/` code.

## Consequences

T06 can introduce view states behind the same `BridgeController` and screens
without touching startup. T07 can pass a `BridgeRepository`/BLE fake through
bootstrap, and T40 can add schema and migrations inside `AppDatabase` without
rewiring the entrypoint. The controller still carries prototype-shaped fields
and default values until T06; fixtures remain in the widget import graph through
the History/Live screens until then, so T06 must remove them before release.
`flutter analyze` and `flutter test` are part of the root workflow via
`make app-check`; CI (T08) must call it.
