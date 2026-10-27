# T05 — App skeleton

## Goal
Create the production Flutter app shell — Android-only, Material 3, with Live,
History, and Settings destinations — plus the controller, repository seam, and
database open path that later app tasks build on. It starts from the approved
prototype UI so the visual contract is preserved from day one.

## Context (read first)
- Design: [06 §6.2](../design/06-app.md),
  [13 §13.3](../design/13-ui-implementation-contract.md#133-production-ownership)
- Verification: **H** (host/CI) · Board required: **no**
- Depends on T01.
- Read [13 — UI/UX Implementation Contract](../design/13-ui-implementation-contract.md)
  before starting: the approved prototype is the production UI contract.

## Scope
- [ ] Create the production Flutter app: Android-only.
- [ ] Build a Material 3 shell with Live, History, and Settings destinations.
- [ ] Add a `BridgeController`.
- [ ] Add a repository seam.
- [ ] Add a DB open path.
- [ ] Start the screens from the approved prototype UI, not from placeholder
      tabs.
- [ ] Add `flutter analyze` to the project workflow.
- [ ] Add a first widget test.

## Out of scope
- View models and full UI-baseline promotion — owned by T06.
- BLE client interface, `FakeBleClient`, and `FakeBridge` — owned by T07.
- Real BLE scan/bond/live data and History sync — M2.
- Database schema, sync, and archive behaviour — M3.
- Settings behaviour and device actions — M4.
- iOS, web, desktop — outside MVP; no task owns them.
- A UI redesign or new prototype chrome — outside MVP; the contract is
  [13](../design/13-ui-implementation-contract.md).

## Design notes
- Android-only: do not scaffold iOS/web/desktop targets as deliverables.
- Material 3 is the shell's design system; keep the approved prototype's
  `features/`, `widgets/`, and `theme/` visual language.
- `BridgeController` is the app's control seam; the repository is the data
  seam; the DB open path must exist even though schema work lands in M3.
- Do not import anything from the `prototype/` fixture into the production
  entrypoint.
- No placeholder tabs: the Live tab must render the approved shell.
- No networking, OTA, cloud, accounts, or multi-bridge code — see the
  anti-tasks in [README](README.md).

## Done when
- [ ] `flutter analyze` passes.
- [ ] `flutter test` passes.
- [ ] The app launches to a Live tab that renders the approved shell.
- [ ] No `prototype/` fixture is imported by the production entrypoint.
- [ ] Hand-off below filled in.

## Hand-off

### Landed

- Production entrypoint `app/lib/main.dart` → `app/lib/app/bootstrap.dart`:
  `WidgetsFlutterBinding`, SQLite open, repository creation, controller
  initialisation, then `SmokeBridgeApp`.
- `app/lib/app/bridge_controller.dart` is the single
  `BridgeController extends ChangeNotifier`. The old
  `prototype/prototype_controller.dart` was moved here and every widget, test
  and tool import was retargeted.
- Repository seam `app/lib/data/repository.dart` (`BridgeRepository`,
  `SqliteBridgeRepository`, `EmptyBridgeRepository`, `BridgeSnapshot`).
- DB open path `app/lib/data/db/app_database.dart` using `sqflite`, with
  injectable factory/path and `openInMemory()` for host tests.
- `app/lib/app/smoke_bridge_app.dart` mounts the approved Material 3 shell
  unchanged: Live, History and Settings via `NavigationBar` + `IndexedStack`.
- Android-only: removed tracked `app/web/` and `app/windows/`, pruned
  `.metadata`, `analysis_options.yaml` and `app/README.md`.
- Workflow: root `Makefile` targets `app-analyze`, `app-test`, `app-check`;
  root README development checks updated.
- Tests: `app/test/app_skeleton_test.dart` (5 tests) plus the existing suite
  retargeted to the production entrypoint/controller.

### Deviations and boundaries

- T05 does not introduce immutable view states or remove fixture data from the
  screens; that remains T06. The controller keeps the prototype-shaped fields
  so the approved shell renders today.
- `BridgeRepository` exposes only a startup snapshot (`readingCount`,
  `lastReadingAt`); full archive queries and sync remain T41.
- `AppDatabase` has no schema yet (`schemaVersion = 1` is an empty DB); T40 owns
  tables, migrations and may bump the version.
- No BLE, permission, network, OTA, cloud or multi-bridge code was added.

### Checks run

```text
cd app && flutter analyze             -> No issues found
cd app && flutter test                -> 31 tests passed
cd app && flutter build apk --debug   -> Built app-debug.apk
make app-check                        -> analyze clean, 31 tests passed
```

The production entrypoint guard test fails if `lib/main.dart`,
`lib/app/bootstrap.dart`, `lib/app/smoke_bridge_app.dart` or
`lib/app/bridge_controller.dart` gains an import containing `prototype/`.

### Next task must know

- T06 owns replacing controller field reads with view states and removing the
  remaining `prototype/fixtures.dart` imports from the widget graph (Live
  sparklines, History fixture builder).
- T40 must add schema/migrations inside `AppDatabase`; repository queries can
  then replace the count/max stub.
- T07 can inject the BLE fake through bootstrap/controller without touching
  `main.dart`.
- CI (T08) should run `flutter pub get` then `make app-check`.
