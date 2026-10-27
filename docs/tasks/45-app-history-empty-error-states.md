# T45 — app: History/data empty and error states

## Goal
Make every History and data failure honest and actionable: no readings, no readings in range, no probe data, no probes, offline with or without cache, no X4 data, sync failure, storage unavailable, and protocol mismatch. Each state names its cause, uses the approved copy, and offers one next action without fake values or raw exceptions.

## Context (read first)
- Design: [06 §6.8](../design/06-app.md), [13 §13.4 — Live](../design/13-ui-implementation-contract.md#live)
- Verification: **H** (host/CI) · Board required: **no**
- Depends on T42 and T43.
- Copy is fixed by [12 §12.2](../design/12-copy-and-label-review.md); the History state inventory is [13 §13.4 — History](../design/13-ui-implementation-contract.md#history).
- **Post-T36 status:** no-history, no-history-in-range, offline-with-cache,
  offline-without-cache, no-X4, sync-failed and storage-failure states are
  already rendered and covered by `widget_test.dart`/`live_screen_test.dart`.
  T45 owns the exhaustive matrix, the remaining no-probe/protocol-mismatch
  states and the copy audit; do not rebuild the existing states.

## Scope
- [ ] Implement and test the no-history state.
- [ ] Implement and test the no-history-in-selected-range state.
- [ ] Implement and test the no-probe-data state, including a filtered probe with no readings.
- [ ] Implement and test the no-probes state.
- [ ] Implement and test Bridge offline with cache. The banner must say
      `Showing saved readings · last reading …` even after the reconnect budget
      is exhausted; T37 found the failed state still says `Can’t reach the
      Bridge` while showing the cached chart.
- [ ] Implement and test Bridge offline without cache.
- [ ] Implement and test no X4 data.
- [ ] Implement and test sync failure.
- [ ] Implement and test storage unavailable.
- [ ] Implement and test protocol major mismatch.
- [ ] Give every state one next action with the approved label.
- [ ] Ensure the no-cache state renders no fake probe values.

## Out of scope
- Producing the underlying sync and connection states — owned by T41/T43.
- History chart, Summary, Cooks, and Cook view — owned by T42.
- History deletion and storage counts — owned by T44.
- Setup, permission, scan, and pairing failures — owned by T33.
- Settings and Bridge-action failure states — owned by T50–T52.
- The full UI state/accessibility/copy gate — owned by T54.
- Billows empty/lost states — M5 (T58).
- Alarms, phone notifications, export/share, and cloud sync — outside MVP; no task owns them.

## Design notes
- Every failure names its cause and offers one next action. Use the exact rows from [06 §6.8](../design/06-app.md):

| State | Copy | Action |
|---|---|---|
| No history | `No readings yet` / “The Bridge records whenever it’s on and paired with the Smoke X4.” | `View Live` |
| No history in range | `No readings in this range` / “Probe 3 has no readings in this range. Try another range or show all probes.” | `Show all probes` |
| No probe data (filtered probe) | No line and no zero; Summary shows `—` / `No data` | `Show all probes` |
| No probes | `No probes connected` / “Plug a probe into the Smoke X4 to see a reading.” | Bridge details |
| Offline with cache | `Showing saved readings · last reading 20 min ago` | `Retry` |
| Offline, no cache | `Bridge disconnected · nothing saved yet` | `Retry` |
| No X4 data | `No data from Smoke X4` / “The Bridge is connected but isn’t receiving data from the Smoke X4. Put the Smoke X4 in SYNC mode and keep it in range of the Bridge.” | `Pairing steps` (X4 warning dialog) |
| Sync failed | `History sync failed` / “Live readings are still updating. Retry when the Bluetooth connection is stable.” | `Retry sync` |
| Storage unavailable | `Not recording` / “Live readings are available, but the Bridge can’t save them. Check the Bridge’s storage.” | Bridge details |
| Protocol major mismatch | `Update the app to use this Bridge` / “The Bridge hasn’t been changed.” | `Update app` (+ saved history / learn more) |

- Map platform exceptions to these named states. No raw exception, stack trace, or platform error string reaches UI.
- Offline with cache keeps the chart usable, dims values, and labels them saved. Offline without cache shows no current probe values, no fake zeros, and one next action.
- The no-X4 notice is one inline status surface, not four repeated no-reading lines, and must not imply the Bridge itself is offline.
- Metadata must not claim four probes when none have data.
- A range with no data must not render an empty chart frame with invented axes values; it says `No readings in this range` and offers the next action.
- Use `readings`, never `records`, in user copy.

## Done when
- [ ] A widget test covers each row in 06 §6.8 and every relevant state in 13 §13.4.
- [ ] No raw exception text is rendered.
- [ ] The no-cache and no-X4 notices are honest.
- [ ] `flutter test` passes; `flutter analyze` is clean.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
