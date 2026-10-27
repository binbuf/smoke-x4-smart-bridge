# 0041 — Live: null-capability Billows and an explicit no-cache state

**Status:** Accepted
**Date:** 2026-10-27

## Context

The T06 view-state seam exposed Live fields as required values. Two production
states therefore had no honest representation:

- A Bridge whose `info` read reports `caps.billows_observe = 0` never decodes
  Billows fields, so showing a card or a "Billows not detected" notice would
  invent a capability the device does not have.
- An offline phone with no saved readings still carried `content.probeTemps`
  and sparkline history. Rendering those produced last-session/fixture values
  that looked current.

Freshness also needs the phone's receipt time, not a Bridge-clock estimate.
T35 will supply it; the widget layer must stay independent of where the age
came from.

## Decision

- `LiveViewState.billows` is nullable. It is non-null only when
  `caps.billows_observe` is true **and** Billows is currently detected. The
  Billows-loss notice uses the same capability gate, so a never-detected or
  observe-incapable Bridge produces no Billows UI at all.
- `LiveViewState.showSavedReadings` distinguishes offline-with-cache from
  offline-without-cache. When false and offline, the controller nulls every
  probe value and sparkline, the status card reads
  `Bridge disconnected · nothing saved yet`, the second status row is hidden,
  and Live offers one `Retry` action.
- `BridgeController.smokeXAgeOverride` is the receipt-age seam. A null value
  keeps the prototype-derived baseline; T35 replaces the baseline with the
  phone's monotonic receipt time without changing the view-state shape.
- The Live widget test drives these states through
  `FakeBridgeSession.driveLiveState`, never by importing fixtures into
  production code.

## Consequences

- Later screens that need Billows metadata read the non-Live
  `BridgeDetailsViewState.billows`, which stays non-null. Only Live treats
  `null` as "do not render".
- Any new Live state must be expressible without reading controller fields in
  the widget; add a field to `LiveViewState` and drive it from the fake.
- T35 must set `smokeXAgeOverride` from receipt time and clear it on
  disconnect, otherwise a cached age can outlive the link.
- A phone with an intact cache keeps dimmed saved values; a phone without one
  must never fall back to `content.probeTemps`.
