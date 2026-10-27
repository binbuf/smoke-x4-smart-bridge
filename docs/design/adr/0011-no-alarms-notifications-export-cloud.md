# 0011 — No alarms, notifications, export or cloud in the MVP

## Status

Accepted

## Context

The requested product records and displays probe history. Alarms, phone
notifications, export/share and accounts each add an independent feature surface,
and the Smoke X4 already owns its alarm behaviour.

## Decision

The MVP has no alarm engine, buzzer/LED alarm patterns, phone notifications,
foreground service, quiet hours, CSV/JSON export, share sheets, accounts or cloud
sync. The bridge is a recorder; the Smoke X4's own alarm remains the alarm. Live
health and storage remain visible on the OLED and in the app.

## Consequences

Tasks must not add these surfaces. If a future request needs one, it requires a
new decision record and its own design/task set. History remains an on-phone and
on-bridge archive, not an export or notification platform.
