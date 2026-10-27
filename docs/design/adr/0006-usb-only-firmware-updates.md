# 0006 — Firmware updates over USB only

## Status

Accepted

## Context

OTA would add a partition layout, update protocol, rollback/security design and a
large failure surface for a bench product whose enclosure is opened for service.
The MVP has no remote-update user.

## Decision

Firmware is updated over USB with `idf.py`/the documented flash command. The
partition table has no OTA slots and the image contains no OTA components. The app
has no firmware-update path.

## Consequences

The partition table stays simple and the full flash budget is available to the
sample log. Release instructions must include the USB flash command. A future OTA
feature requires a new decision record and a partition redesign.
