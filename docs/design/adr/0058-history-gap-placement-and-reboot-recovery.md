# 0058 — Gap time mapping, range-scoped History and reboot recovery

**Status:** accepted (T46a)

## Context

The T46 full-history bench found five app-side defects that shared one cause:
History and Live read a wider or differently-timed source than the state they
display.

- A stored `gap` row was drawn at `detected_ms` (when the app learned of the
  loss), not over the missing `from_seq..to_seq` period.
- Cooks and `Since cook start` scanned the whole archive, so a 117-day ring
  produced one 115-day "cook" and enabled the sort in ranges with no cook.
- The permanent-loss banner looked at the whole archive, not the visible range.
- Live sparklines read only the session's in-memory store, so a cold launch
  claimed `No history yet` beside a durable archive.
- A Bridge reboot could leave a stale `Connected` + `Not paired` Live snapshot
  because Android kept the GATT link marked connected after the CCCB state was
  lost; nothing re-armed the `live` notification.

## Decision

1. **Sequence → time.** `HistoryArchive` reads every `gap` row and maps its
   `from_seq`/`to_seq` onto the time axis with the stored readings that flank
   the range (`SampleDao.samplesAroundSeq`). `detected_ms` is never a chart
   position. A gap outside the visible range is not drawn and does not raise
   the permanent-loss banner.
2. **One visible window.** `HistoryArchive.load` computes gaps, cooks,
   cook-gap spans and the loss flag from the same `[startMs, endMs)` window.
   `probeStatsInRange` remains the exact Summary source.
3. **Gap labels.** A permanent-loss (`Not synced`) band keeps its label even
   when the missing period is only a few pixels wide at the current zoom; a
   narrow inferred hole is not labelled. The permanent-loss explanation stays
   the range-scoped banner below the chart.
4. **Sparklines are archive views.** `prepareLaunch` seeds the in-memory
   sparkline window from `SampleDao` once, anchored at the newest stored
   reading when the archive is older than an hour. No extra timer or sync path
   is introduced; live notifications and sync batches keep replacing the same
   sequence.
5. **Saved identity before connect.** An offline launch takes the display name
   and short id from the saved `bridge` row (or `—`), never a fixture default.
6. **Reboot recovery.** The 110 s health check re-arms the `live` notification
   after reading `live`. A peripheral reboot that keeps the GATT link up
   therefore recovers live values and the X4 pairing without a process restart.
7. **Blocked is not syncing.** Entering `ConnectionPhase.blocked` clears
   `syncState`/progress, and Live renders the blocked notice as the only sync
   surface.

## Consequences

- A 24 h view of a full ring shows only the cooks and losses inside those 24 h;
  the full archive remains reachable through Custom range.
- Gap placement needs a stored reading on at least one side. A gap with no
  surviving neighbours (e.g. deleted rows) is not drawn; it is not re-invented.
- The Live sparkline can end at the newest saved reading rather than wall-clock
  now. When offline this is the honest "last recorded hour"; the banner still
  names the reading age.
- `samplesAroundSeq` adds two indexed queries per stored gap in the window.
  The gap table is small and the read model is bounded, so this stays off the
  per-sample path.
