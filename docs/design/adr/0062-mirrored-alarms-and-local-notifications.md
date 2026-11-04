# 0062 — Mirrored alarms and local notifications

## Status

Accepted

## Context

The Smoke X state packet already carries, for every supported probe, whether
its alarm is enabled and its high/low setpoints. The trailing field also carries
an alarm edge. The app previously discarded all of it. Users want the same
alarm information the hardware receiver shows, plus a phone alert when the app
is not on screen.

The physical link is one-way. The stock receiver is receive-only and cannot mute
the base; no receiver→base alarm-silence frame is documented. The Bridge only
ever transmits the pairing ACK.

## Decision

- The Bridge mirrors the Smoke X alarm fields per probe and latches an active
  alarm from the alarm edge or an out-of-band temperature.
- BLE protocol minor 1 adds `0009 alarm` (20 B, read/notify, encrypted) and
  control op 8 `ack_alarm`.
- The app shows alarm on/off, high/low thresholds, and active/acknowledged state
  on Live; it posts a local notification on a new unacknowledged alarm and shows
  an in-app dialog while foregrounded.
- Tapping the notification, the dialog action, or the Live card sends
  `ack_alarm`. This clears the Bridge/app unacknowledged latch only.
- The UI says plainly that the physical Smoke X must be muted on the base or its
  receiver. No experimental alarm-silence RF frame is invented.
- Fully terminated background delivery still depends on Android keeping the
  process alive; a foreground service is a separate decision and is not part of
  this change.

## Consequences

- Protocol minor 1 is backward-compatible for live/history/config/stats. A
  protocol-1.0 Bridge simply has no `alarm` characteristic; the app hides the
  card.
- `new_alarm` is treated as a bitfield: bit 0 is the alarm event. Values such as
  8 observed during Billows/menu activity must not raise an alarm.
- The OLED continues to show the Smoke X's own alarm state; the Bridge does not
  add a buzzer/LED alarm engine.
- An acknowledged alarm stays visible while the probe remains out of band, so
  the user can see the condition without repeated notifications.
