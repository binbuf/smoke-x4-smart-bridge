# T44 — app: data use and explicit deletion

## Goal
Build the approved History & storage screen so users can see exactly what is on the phone and on the Bridge, and delete either copy only through an explicit, counted confirmation. The two archives stay separate, and nothing is ever removed automatically.

## Context (read first)
- Design: [04 §4.8](../design/04-data-and-storage.md), [06 §6.7](../design/06-app.md)
- Verification: **H/P** (host/CI plus phone) · Board required: **no / phone**
- Depends on T40 and T41.
- Copy is fixed by [12 §12.2 — Settings, setup and confirmations](../design/12-copy-and-label-review.md#settings-setup-and-confirmations); the state inventory is [13 §13.4 — Settings, Bridge details and confirmations](../design/13-ui-implementation-contract.md#settings-bridge-details-and-confirmations).
- **Post-T36 status:** the `History & storage` shell, the two-copy sections,
  the delete/clear sheets and the `readings` copy already exist in
  `settings_views.dart`/`settings_details.dart`. They are driven by controller
  fields and simulated counts. T44 wires them to the T40/T41 DAO and proves the
  boundaries; do not redesign the screen.

## Scope
- [ ] Implement the `History & storage` screen with a `History on this phone` section: readings, date range, and storage used.
- [ ] Implement the `History on the Bridge` section: readings, capacity, percentage, oldest reading, and newest reading.
- [ ] Implement one deletion flow for phone history with `Older than 30 days`, `Older than 90 days`, and `All history on this phone`.
- [ ] Confirm each deletion with the exact date range and reading count before deleting.
- [ ] Implement `Clear history on the Bridge…` with an explicit confirmation; keep phone history.
- [ ] Keep the two copies visibly separate; never merge local and Bridge counts or ranges.
- [ ] Trim or remove `gap` rows that fall inside a deleted date range.
- [ ] Use `readings` in all user-facing copy, never `records`.
- [ ] Never delete on generation change, factory reset, app relaunch, or low storage.

## Out of scope
- Database schema and DAO primitives — owned by T40.
- Sync, backfill, and generation segmentation — owned by T41.
- Settings root shell and navigation — owned by T50.
- Bridge destructive-action confirmations for power off, factory reset, and forget this phone — owned by T52; the Bridge clear command/state machine is owned by T49.
- History chart, Summary, Cooks, and their empty states — owned by T42/T45.
- Billows surfaces — M5 (T56–T60).
- Automatic deletion — outside MVP; no task owns it.
- Server/cloud sync — outside MVP; no task owns it.
- Export/share — outside MVP; no task owns it.
- Alarms and notifications — outside MVP; no task owns them.

## Design notes
- Exact section labels: `History on this phone` and `History on the Bridge`; field labels `Readings`, `Date range`, `Storage used`, `Capacity`, `Oldest reading`, `Newest reading`.
- Bridge capacity copy: “About 117 days at 30-second intervals” and “The Bridge overwrites its oldest readings automatically.” Show the “Two separate copies” notice. Bridge capacity is 338,400 readings / 6,160,384 B; the device reports `records_stored`, `min_seq`, `max_seq`, and `generation` in `stats`.
- Deletion labels: `Delete history from this phone…`; options `Older than 30 days`, `Older than 90 days`, `All history on this phone`; Bridge action `Clear history on the Bridge…`.
- A confirmation must state the exact loss in readings and the date range. If the range is empty, say so and do not issue a delete.
- Deleting phone history never commands the Bridge to delete anything. Clearing the Bridge log never deletes phone history. A generation change or factory reset is not a deletion trigger; old local segments remain readable.
- `Older than 30 days` and `Older than 90 days` are relative to the current wall clock and must honour exact boundaries in tests.
- Deleting a date range also deletes or trims `gap` rows inside it, so no stale gap outlives its samples.
- `Clear history on the Bridge…` creates a new generation, resets the Bridge sequence, and keeps pairing/config. The app keeps its old local segment and marks the generation boundary.
- Bridge clear is only available when the Bridge is reachable; when offline, show the reason and keep local deletion available.
- No automatic cleanup based on storage pressure, age, launch count, or sync state. No background deletion.

## Done when
- [ ] Deletion tests cover boundaries and trim/remove overlapping `gap` rows.
- [ ] The UI says what is local vs Bridge.
- [ ] The two copies stay separate.
- [ ] Nothing deletes automatically.
- [ ] The approved copy is used, including `readings` and not `records`.
- [ ] Widget/DAO tests and `flutter test` pass; `flutter analyze` is clean.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
