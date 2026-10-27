# 0005 — LE Secure Connections with passkey and bonding

## Status

Accepted

## Context

The bridge shows a six-digit code on its OLED and the phone needs a pairing flow
that works without a shared secret or an app-specific provisioning step. Just
Works would not prove physical possession of the device.

## Decision

Use BLE LE Secure Connections with a passkey displayed on the OLED and OS-level
bonding. The app never displays the real code. Cap the bridge at four bonds with
one active connection; forget removes the current peer's bond only.

## Consequences

Pairing and reconnect depend on the phone OS bond store, so stale-bond and
bond-full recovery states are required. `info` is readable without a bond; live
data and protected procedures require one. A wrong code fails and never falls
back to Just Works.
