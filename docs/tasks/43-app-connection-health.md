# T43 — app: connection health and stale states

## Goal
Make the app's connection state honest: separate the BLE link from Smoke X4 telemetry, detect stale data with a 110 s watchdog, reconnect within a bounded budget, and never present cached readings as live. This is what lets the app recover from walking out of range, app kills, and bridge power cycles without a manual restart.

## Context (read first)
- Design: [06 §6.3, §6.8](../design/06-app.md), [13 §13.5 — UI lifecycle flows](../design/13-ui-implementation-contract.md#135-ui-lifecycle-flows)
- Verification: **H/P** (host/CI plus phone) · Board required: **no / phone**
- Depends on T35.
- The state inventory is [13 §13.4 — Live](../design/13-ui-implementation-contract.md#live); copy is [12 §12.2 — Live](../design/12-copy-and-label-review.md#live).

## Scope
- [ ] Implement the 110 s notification watchdog and the `live` read that follows it.
- [ ] Keep BLE-vs-X4 state separate: a connected bridge with a quiet X4 is not offline.
- [ ] Implement stale vs offline states and the transitions between them.
- [ ] Implement bounded reconnect with backoff 1, 2, 4, 8, 15, 30 s and a maximum of six attempts.
- [ ] Implement the `Can’t reach the Bridge` actionable state with Retry and the forget escape.
- [ ] Implement app pause/resume behavior: no foreground service, no background scanning; on resume run a health check and forward sync.
- [ ] Implement pull-to-refresh: read `live` and run a forward sync.
- [ ] Map every platform exception to a named state; no raw exception text reaches the UI.
- [ ] Keep last-known values dimmed and labelled when offline with cache.
- [ ] Show no current probe values and one next action when offline without cache.

## Out of scope
- Sync cursor, backfill, resume, and repository persistence — owned by T41.
- Settings shell, Bridge details, and `Sync now`/`Reconnect` placement — owned by T50/T51.
- History, Summary, Cooks, and their empty/error states — owned by T42/T45.
- History deletion and storage — owned by T44.
- Firmware connection/state reporting and BLE transport — owned by T27/T28; app link procedures and time sync — owned by T35.
- Billows status surfaces — M5 (T56–T60).
- Alarms, phone notifications, foreground service, and background scanning — outside MVP; no task owns them.
- Server/cloud sync and export/share — outside MVP; no task owns them.

## Design notes
- Lifecycle states are fixed by [06 §6.3](../design/06-app.md): `UNINITIALIZED`, `SETUP`, `SCANNING`, `CONNECTING`, `PAIRING`, `SECURING`, `SYNCING`, `LIVE`, `STALE`, `RECONNECTING`, `FAILED`, `BLOCKED`.
- A live notification is fresh for 90 s. 90 s–10 min is delayed/stale; after 10 min the X4 link is lost. `Aging`, `Stale`, and `Frozen` remain internal; the UI speaks in time, not taxonomy.
- No notification for 110 s → read `live`. A successful read with a fresh `age_s` returns to `LIVE`; a successful read with a quiet X4 stays `STALE`; a failed read moves to `RECONNECTING`. Any GATT disconnect moves to `RECONNECTING` even if the last sample was recent.
- Use the app's own receipt time as well as `live.age_s`, so a bad bridge clock cannot fake freshness.
- Product copy: `Updated 62s ago`, `No readings for 4 min`, `Showing saved readings`, `Bridge disconnected · last connected 2h ago`, `Bridge disconnected · nothing saved yet`, `Reconnecting… attempt 2 of 6`, `Can’t reach the Bridge`. One status surface, not four repeated no-reading lines.
- Offline with cache: keep the chart and tiles, dim values, hide signal, and label the saved state. Offline without cache: no fake probe values, no fake zeros.
- A user pull-to-refresh or app resume cuts the reconnect wait short.
- Never spin forever silently; after six failed attempts show `Can’t reach the Bridge` with a Retry action and the forget escape.
- Bounded retry must recover when the bridge returns; no manual app restart should be required.
- Do not request battery-optimization exemptions and do not add a foreground service.

## Done when
- [ ] Walking out of range, killing the app, and power-cycling the bridge each produce the intended state.
- [ ] Each case recovers without a manual app restart.
- [ ] No cached value is presented as live.
- [ ] The no-cache state has no fake probe readings.
- [ ] Widget tests cover fresh, stale, reconnecting, failed, offline-with-cache, and offline-without-cache states; `flutter test` passes.
- [ ] `flutter analyze` passes.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
