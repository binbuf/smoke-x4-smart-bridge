# 0008 — Approved prototype is the production UI contract

## Status

Accepted

## Context

The prototype in `app/` is complete: `flutter analyze` is clean, the widget suite
is green and the dark/light screenshots are generated from the real widget tree.
Rebuilding the approved screens during production wiring would create a second
design and risk visual regressions.

## Decision

Production keeps the prototype's screens, widgets, theme, copy and interaction
states. The work replaces fixture/direct-controller state with immutable view
models and real business logic. Prototype-only chrome and simulation controls are
lab-only, gated by `kDebugMode` or `ENABLE_EXPERIMENTAL_LAB`.

## Consequences

UI tasks cite `13-ui-implementation-contract.md` and must not redesign a screen
without updating the design first. Widget tests, the state matrix and screenshot
goldens guard the contract. Release builds must not expose the lab, fixtures or
fake OS prompts.
