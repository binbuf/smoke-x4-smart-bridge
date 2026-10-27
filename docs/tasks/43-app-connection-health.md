# T43 — app: connection health, saved Bridge and launch auto-connect

## Goal
Make the app's connection state honest and continuous: separate the BLE link from Smoke X4 telemetry, detect stale data with a 110 s watchdog, reconnect within a bounded budget, never present cached readings as live, and stop asking a returning user to set up the same Bridge again. A saved Bridge is loaded on launch, scanned for by identity, and connected automatically; the setup flow is only for a first install, a forgotten Bridge, or an explicit re-pair.

## Context (read first)
- Design: [06 §6.3 later launches](../design/06-app.md), [06 §6.8](../design/06-app.md), [13 §13.5 — UI lifecycle flows](../design/13-ui-implementation-contract.md#135-ui-lifecycle-flows)
- Verification: **H/P** (host/CI plus phone) · Board required: **no / phone**
- Depends on T35, T40, and T41. T40 adds the `bridge` row and its saved-identity queries; T41 supplies the archive for last-known values and the durable cursor.
- The state inventory is [13 §13.4 — Live](../design/13-ui-implementation-contract.md#live); copy is [12 §12.2 — Live](../design/12-copy-and-label-review.md#live).
- **Post-T36 status:** the watchdog, stale/offline split, bounded backoff, Retry/Forget, resume and pull-to-refresh already landed in T35/T36 and are covered by `bridge_link_test.dart`. This task now owns the launch/relaunch path that is still missing; T37 ran before the archive exists and therefore still starts in Setup.

## Scope
Already landed (keep and regression-test; do not reimplement):

- [x] Implement the 110 s notification watchdog and the `live` read that follows it.
- [x] Keep BLE-vs-X4 state separate: a connected bridge with a quiet X4 is not offline.
- [x] Implement stale vs offline states and the transitions between them.
- [x] Implement bounded reconnect with backoff 1, 2, 4, 8, 15, 30 s and a maximum of six attempts.
- [x] Implement the `Can’t reach the Bridge` actionable state with Retry and the forget escape.
- [x] Implement app pause/resume behavior: no foreground service, no background scanning; on resume run a health check and forward sync.
- [x] Implement pull-to-refresh: read `live` and run a forward sync.
- [x] Map every platform exception to a named state; no raw exception text reaches the UI.
- [x] Keep last-known values dimmed and labelled when offline with cache.
- [x] Show no current probe values and one next action when offline without cache.

Remaining for this task:

- [ ] Persist the saved Bridge identity after a successful first connect (T40:
      `bridge.id`, `bridge.name`, `last_seen_ms`) and update `last_seen_ms` on
      every successful connect.
- [ ] On a cold launch with a saved Bridge, skip `SetupScreen` and start a
      preferred scan by device ID, then by name. Do not auto-connect to an
      unrelated first result.
- [ ] When the saved Bridge is found, connect and secure automatically; a valid
      stored bond must not show a passkey prompt. A stale bond takes the named
      `Forget and re-pair` path, never a silent OS prompt.
- [ ] If the saved Bridge is not found within 10 s, enter the shell on Live with
      the last-known archive and `Looking for your Bridge…` plus a manual
      `Connect` action. Do not dump the user back into the full setup flow.
- [ ] If Bluetooth is off or permission is blocked on launch, show the named
      `BLOCKED` state and its system action, not Setup.
- [ ] Observe adapter state changes **at runtime**. With the app on Live, turn
      phone Bluetooth off: the link must leave `Connected`, show the named
      blocked/offline state, and must not keep stale probe values or a
      `Bridge Connected` label. Turn Bluetooth on: resume or offer Retry.
      T37 found that an off/on cycle could leave the UI showing a stale
      `Bridge Connected` while the bridge had no central link.
- [ ] Clear the saved identity only on user-confirmed forget or factory reset;
      keep `sample`/`gap` rows as orphaned `History on this phone`.
- [ ] Replace the in-memory recent cache used by the offline state with the T41
      repository, so last-known values survive a process kill.
- [ ] Add tests for cold launch with no saved Bridge, cold launch with a saved
      Bridge present/absent after 10 s, app kill/relaunch, Bluetooth blocked at
      launch, and forget/reset clearing the saved identity.

## Out of scope
- Database schema, migrations and DAO primitives — owned by T40.
- Two-phase sync, backfill and durable cursor — owned by T41.
- Full History chart, Summary and Cooks — owned by T42.
- History empty/error matrix and copy gate — owned by T45.
- Settings shell, Bridge details, and `Sync now`/`Reconnect` placement — owned by T50/T51.
- History deletion and storage — owned by T44.
- Firmware connection/state reporting and BLE transport — owned by T27/T28; app link procedures and time sync — owned by T35.
- The formal cold-launch phone proof — owned by T46.
- Billows status surfaces — M5 (T56–T60).
- Alarms, phone notifications, foreground service, and background scanning — outside MVP; no task owns them.
- Server/cloud sync and export/share — outside MVP; no task owns them.

## Design notes
- Lifecycle states are fixed by [06 §6.3](../design/06-app.md): `UNINITIALIZED`, `SETUP`, `SCANNING`, `CONNECTING`, `PAIRING`, `SECURING`, `SYNCING`, `LIVE`, `STALE`, `RECONNECTING`, `FAILED`, `BLOCKED`.
- Later-launch rule ([06 §6.3](../design/06-app.md)): load the remembered Bridge and scan; connect automatically when found with no passkey prompt. If it is not found for 10 s, show last-known Live data with `Looking for the Bridge…` and a manual `Connect` button.
- The saved identity is the `bridge` row, not a second preferences store. `bridge.id` is the BLE identity, `bridge.name` the last observed name, and `last_seen_ms` the ordering key. `bootstrap.dart` already opens the database; T43 adds the launch branch on top of it and must not create a second store.
- The setup flow stays the owner of first pair, bond failures, stale-bond re-pair and the `History on this phone` escape. Launch auto-connect must not run a second scan loop in parallel with `SetupFlow`.
- A live notification is fresh for 90 s. 90 s–10 min is delayed/stale; after 10 min the X4 link is lost. `Aging`, `Stale`, and `Frozen` remain internal; the UI speaks in time, not taxonomy.
- No notification for 110 s → read `live`. A successful read with a fresh `age_s` returns to `LIVE`; a successful read with a quiet X4 stays `STALE`; a failed read moves to `RECONNECTING`. Any GATT disconnect moves to `RECONNECTING` even if the last sample was recent.
- Use the app's own receipt time as well as `live.age_s`, so a bad bridge clock cannot fake freshness.
- Product copy: `Updated 62s ago`, `No readings for 4 min`, `Showing saved readings`, `Bridge disconnected · last connected 2h ago`, `Bridge disconnected · nothing saved yet`, `Reconnecting… attempt 2 of 6`, `Can’t reach the Bridge`, `Looking for the Bridge…`. One status surface, not four repeated no-reading lines.
- Offline with cache: keep the chart and tiles, dim values, hide signal, and label the saved state. Offline without cache: no fake probe values, no fake zeros.
- A user pull-to-refresh or app resume cuts the reconnect wait short.
- Never spin forever silently; after six failed attempts show `Can’t reach the Bridge` with a Retry action and the forget escape.
- Bounded retry must recover when the bridge returns; no manual app restart should be required.
- Do not request battery-optimization exemptions and do not add a foreground service.
- Do not add a background service, periodic background scan, or a second reconnect loop. The launch scan is foreground and bounded to 10 s like `SetupFlow`.

## Done when
- [ ] A cold launch with a saved Bridge reaches Live without showing Setup and without a new passkey prompt.
- [ ] A saved Bridge that is absent for 10 s leaves the user on Live with `Looking for the Bridge…`, the last-known archive and a manual Connect action.
- [ ] Walking out of range, killing the app, relaunching, and power-cycling the bridge each produce the intended state.
- [ ] Each case recovers without a manual app restart or a second setup flow.
- [ ] Forget and factory reset clear the saved identity but keep orphaned `History on this phone`.
- [ ] No cached value is presented as live.
- [ ] The no-cache state has no fake probe readings.
- [ ] Widget/link tests cover fresh, stale, reconnecting, failed, offline-with-cache, offline-without-cache, saved-Bridge launch, absent-Bridge launch and blocked-at-launch states; `flutter test` passes.
- [ ] `flutter analyze` passes.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
