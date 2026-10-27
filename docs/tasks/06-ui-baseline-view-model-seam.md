# T06 — UI baseline and view-model seam

## Goal
Promote the approved prototype UI into the production tree and put immutable
view-state objects between widgets and data, so real business logic can replace
in-memory prototype state without rebuilding the approved screens.

## Context (read first)
- Design: [13 §13.2–13.4, §13.7](../design/13-ui-implementation-contract.md),
  [06 §6.2](../design/06-app.md)
- Verification: **H** (host/CI) · Board required: **no**
- Depends on T05.
- Read [13 — UI/UX Implementation Contract](../design/13-ui-implementation-contract.md):
  the approved prototype is the visual contract, not a starting suggestion.

## Scope
- [ ] Promote the prototype UI into the production tree.
- [ ] Keep `features/`, `widgets/`, and `theme/` as the visual contract.
- [ ] Introduce immutable `LiveViewState`, `HistoryViewState`, `SetupViewState`,
      `SettingsViewState`, and `BridgeDetailsViewState` objects.
- [ ] Replace direct `PrototypeController` reads in widgets with view state.
- [ ] Keep the scenario lab and fixture data behind a debug/test adapter,
      gated by `kDebugMode` or `ENABLE_EXPERIMENTAL_LAB`.
- [ ] Move reusable formatters to the production formatter layer.
- [ ] Make the screenshot generator run against the production screens.

## Out of scope
- BLE interface and fake — owned by T07.
- Real scan/live/sync data wiring — M2.
- History archive and chart data — M3.
- Settings actions and confirmations — M4.
- A UI redesign, new destination, second chart, probe names/roles, or new
  prototype chrome — outside MVP; the contract is
  [13](../design/13-ui-implementation-contract.md).
- Shipping the lab, fixture values, simulation buttons, or fake OS prompts in a
  release build — explicitly forbidden by the anti-tasks; T06 only gates them.

## Design notes
- The view states are **immutable**; widgets render from them and never read
  `PrototypeController` directly.
- `features/`, `widgets/`, and `theme/` define the approved visual contract and
  must not be redesigned while porting.
- The scenario lab is reachable only through a debug/test adapter, gated by
  `kDebugMode` or `ENABLE_EXPERIMENTAL_LAB`; it is not reachable from the
  release entrypoint.
- Reusable formatting logic moves to the production formatter layer rather than
  staying in prototype-only code.
- Screenshot generation targets the **production** screens so the approved
  baseline is validated against the real widget tree.
- Stable test keys and approved states come from
  [13](../design/13-ui-implementation-contract.md).

## Done when
- [ ] Production screens render from view models.
- [ ] The widget suite still covers the approved states.
- [ ] The lab is not reachable from the release entrypoint.
- [ ] `flutter analyze` passes.
- [ ] `flutter test` passes.
- [ ] Screenshot generation passes.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
