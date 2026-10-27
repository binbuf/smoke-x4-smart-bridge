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
- [x] Implement the `History & storage` screen with a `History on this phone` section: readings, date range, and storage used.
- [x] Implement the `History on the Bridge` section: readings, capacity, percentage, oldest reading, and newest reading.
- [x] Implement one deletion flow for phone history with `Older than 30 days`, `Older than 90 days`, and `All history on this phone`.
- [x] Confirm each deletion with the exact date range and reading count before deleting.
- [x] Implement `Clear history on the Bridge…` with an explicit confirmation; keep phone history.
- [x] Keep the two copies visibly separate; never merge local and Bridge counts or ranges.
- [x] Trim or remove `gap` rows that fall inside a deleted date range.
- [x] Use `readings` in all user-facing copy, never `records`.
- [x] Never delete on generation change, factory reset, app relaunch, or low storage.

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
- [x] Deletion tests cover boundaries and trim/remove overlapping `gap` rows.
- [x] The UI says what is local vs Bridge.
- [x] The two copies stay separate.
- [x] Nothing deletes automatically.
- [x] The approved copy is used, including `readings` and not `records`.
- [x] Widget/DAO tests and `flutter test` pass; `flutter analyze` is clean.
- [x] Hand-off below filled in.

## Hand-off

Implemented T44 on top of the T40/T41 archive and the approved T36 screen.

**Landed**
- `app/lib/data/history/history_deletion.dart` — counted `HistoryDeletionPlan`
  and `HistoryDeletionService` for `Older than 30 days`, `Older than 90 days`
  and `All history on this phone`. Half-open ranges, strict cutoff (a reading
  exactly on the cutoff is kept), actual first/last reading in the plan, empty
  plans never call `deleteRange`, cursor reconciliation after deletion.
- `History & storage` now reads the real phone count/date range from `SampleDao`
  and an estimated storage figure (72 B/reading); `Storage used` is a labelled
  field. The delete sheet loads all three plans first, disables empty ranges
  (`No readings in this range`), and the confirmation repeats the exact count
  and reading span before using that same plan.
- Bridge copy reads `stats` (`records_stored`, `records_capacity`, `oldest_unix_s`,
  `newest_unix_s`, `generation`) through a new encrypted `BridgeStats` codec and
  a best-effort read on connect / quiet sync. Oldest/newest are Bridge values or
  `—`; they are never taken from the phone archive. Capacity/percentage and the
  “Two separate copies” notice remain.
- Bridge clear keeps its explicit confirmation and resets only the displayed
  Bridge figures; phone history is untouched. Phone deletions never touch the
  Bridge.
- Fixed the `SampleDao.deleteRange` right-trim path: it now updates the gap in
  place so a kept tail is not removed by the same transaction. Left+right trims
  register the inserted row so it survives the detected-in-range sweep.
- `historyRevision` bumps after deletion so History reloads; old generations stay
  readable.
- Tests: `history_deletion_test.dart` (8) covers 30/90 boundaries, all, empty
  plans, gap remove/trim, cursor recompute/clear and automatic-delete absence.
  `history_storage_widget_test.dart` (4) covers separate copies, exact
  confirmation, empty disabled ranges and clear-keeps-phone. `link_codec_test`
  pins `stats` to the generated codec.
- Docs: 04 §4.8 implementation note, 06 §6.7 note, ADR 0049.

**Deviations / boundaries kept**
- The actual `clear_history` command and generation state machine remain T49/T52.
  This task owns the confirmation, separate-copy outcome and keeps phone history.
- Storage used is an estimate (04 §4.9 midpoint), not a SQLite file-size query.
- Firmware `stats` encoding is still pending elsewhere (T47-era); the app read is
  best-effort and the screen shows `—` when unavailable.

**Checks**
- `flutter analyze` — clean.
- `flutter test` — 208/208 passed, including the new widget/DAO suites.
- No phone board run; H-only for this task.

**Next task must know**
- Use `controller.planLocalDeletion(scope)` then `applyLocalDeletion(plan)` for
  any new deletion entry point; never call the DAO directly from a screen.
- Do not add any automatic deletion path. Opening History & storage only reads.
- T49/T52 should replace `BridgeController.clearBridgeHistory()` with the real
  command/result flow while preserving the phone-copy guarantee.
