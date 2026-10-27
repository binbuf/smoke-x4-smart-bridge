# 0002 — One continuous rolling log, no cook sessions

## Status

Accepted

## Context

The requirement is to collect whenever the bridge is on and the Smoke X4 is
sending, then graph whatever was collected. A cook/session lifecycle is not part
of the requested product and creates sync-completeness and state-recovery bugs.

## Decision

The bridge records one continuous sequence-numbered log. There is no user-created
cook session, name, mark, phase, preset, cook clock, ETA or stall/lid model.
Detected Cooks in the app are a read-only view derived from recorded timestamps.

## Consequences

Gaps must be explicit and honest rather than hidden inside a session. The app can
offer range filters, detected cooks and summaries without owning a session
lifecycle. Tasks must not add a session model; detected history remains read-only.
