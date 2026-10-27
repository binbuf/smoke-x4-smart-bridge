# 0007 — Billows is observation-only

## Status

Accepted

## Context

ThermoWorks documents that a Smoke X4 receiver cannot change set points or the
Billows; only the base can. The bridge sees the same one-way broadcast as the
receiver, so there is no receiver-side command path to emulate. Inventing one
would be unsupported and unsafe.

## Decision

The bridge and app observe Billows attachment and, only after the RF field is
validated, the target set on the Smoke X4. `caps.billows_control` is 0; the
`set_billows_target` op always returns `unsupported`; the only LoRa transmission
remains the pairing ACK. The full rationale is in `docs/billows-decision.md`.

## Consequences

Copy always says the target is set on the Smoke X4. There is no mode switch,
target editor, fan-speed claim or Billows TX path. An unknown target relation is
reported as `—`, never guessed. Post-MVP RF work is a receive-only survey and
requires a new decision before any control feature.
