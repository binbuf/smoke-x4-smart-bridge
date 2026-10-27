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
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
