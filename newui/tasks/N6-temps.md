# N6 — Temps

**Goal:** the per-probe "up close" screen and the probe detail sheet. Big numerals,
trend, sparkline, stats, target/pull/ETA, re-roling a jack.

**Design:** [`newui/app.js`](../app.js) §6 `viewTemps`, `tempCard`, `tempMeta`,
`overlayProbe`, `phaseTrack`, `overlayEditStart` · NOTES §7.2.

---

## Invariants this epic must encode

I3 absent ≠ zero · I4 stale removes derived · I6 every empty state has a next
step · I12 target edits re-run the safety gate.

## Tasks

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N6.1 | Header row: attached count + live/stale word + °F/°C segmented toggle | N4.3 | W | `app.js` viewTemps |
| N6.2 | `TempCard`: jack badge, name, big temp (num + dec + unit), trend chip, freshness word | N3.19, N3.9 | W | `app.js` tempCard |
| N6.3 | Flags: STALL, DONE, Grate tag; progress rule against target | N6.2 | W | `app.js` tempCard |
| N6.4 | Meta grid: grate → Pit band + In/Out; food → Target/Pull/ETA; always High/Avg | N6.2 | W | `app.js` tempMeta |
| N6.5 | Detached/unused section: "Unplugged — absent, never 0°" + Set role button | N6.2 | W | `app.js` viewTemps, I3 |
| N6.6 | Empty state when nothing attached (one action: View graph) | N6.5 | W | `app.js` viewTemps, I6 |
| N6.7 | Probe detail sheet: header (jack, avatar, catalog name), hero temp, sparkline, trend | N6.2 | W | `app.js` overlayProbe |
| N6.8 | Phase track (Approaching → Pull now → Resting → Ready) for food probes with a target | N1.15, N6.7 | W | `app.js` phaseTrack |
| N6.9 | Stats grid High/Avg/Low | N6.7 | W | `app.js` overlayProbe |
| N6.10 | Role editor: Food / Grate(pit) / Unused — reassign any jack (jack 4 default grate) | N6.7 | W | `app.js` probe-role, NOTES §7.2 |
| N6.11 | Target editor for food probes: doneness chips from the assigned preset, "pull at X" carryover notice; unassignable probe offers Set a target | N1.7, N6.10 | W | `app.js` overlayProbe |
| N6.12 | Actions: Mark pulled, Test alarm, Share this probe | N6.10 | W | `app.js` overlayProbe |
| N6.13 | Retargeting a running cook is metadata only (no sample rewrite) | N6.11 | H | I10, `app.js` set-target |

## Exit gate

Toggling a jack's role re-renders Live, Temps and the summary strip consistently;
a detached probe never renders a numeric temperature anywhere.

## Must-not-regress

I3, I4, I6, I12 and the non-destructive role/target edits.