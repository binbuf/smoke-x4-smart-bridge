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

---

## Hand-off

Status: **done** (N6.1–N6.13 all landed). `make app.test` green (**302** tests, was
256; analyze + format check + `flutter test`); `cd app && dart test test/domain
test/data` green (**136**, was 134). Temps is now a real destination.

**Real paths**
- `app/lib/features/temps/` — the feature: `temps_page.dart` (`TempsPage`, the
  header/cards/detached/empty layout), `temp_card.dart` (`TempCard`, flags, the
  meta grid), `probe_sheet.dart` (`ProbeSheetBody`), `temps_format.dart` (pure
  projections), barrel `temps.dart`.
- `app/lib/features/shell/destinations.dart` — `TempsDestination` now returns
  `const TempsPage()`.
- `app/lib/features/shell/overlay.dart` — `DevOverlay.probe` resolves to
  `ProbeSheetBody` via `bodyBuilder`, jack parsed from the `jack` prop (default 1).
- Tests `app/test/features/temps_test.dart` (19 widget), `app/test/features/
  temps_format_test.dart` (24 pure); `app/test/golden/temps_golden_test.dart` +
  `app/test/golden/goldens/temps.golden.txt`; two new repo tests in
  `app/test/data/mock_repository_test.dart`.

**Commands that work**
- `make app.test` — analyze + format check + full `flutter test` (302 pass).
- `cd app && flutter test test/features/temps_test.dart test/features/
  temps_format_test.dart` — the N6 gate (43 pass).
- `cd app && dart test test/domain test/data` — data/domain gate (136 pass).
- `make app.golden` regenerates `temps.golden.txt` too.

**Contract facts later tasks need**
- `TempsPage` reads `snapshotProvider` + `settingsProvider`; `TempsBody` reads
  `bridgeRepositoryProvider.catalog`. Unit toggle writes
  `prefsProvider.update((s) => s.copyWith(units: next))`.
- Pure helpers in `temps_format.dart`: `attachedProbes` / `detachedProbes`
  (attached **and** role != unused vs not), `probeFor`, `cookEntryFor`,
  `updatedWord`, `probeFreshnessWord`, `kProbePhases`, `probePhaseIndex`,
  `trendFor`, `fmtTempUnit`, `tempMetaCells`, `pullForDoneness`,
  `selectedDoneness`.
- Keys: `temps-page`, `temps-header`/`temps-attached-count`/`temps-unit-toggle`,
  `temps-card-<jack>`, `temps-temp-<jack>` (a `Text.rich`, read via
  `textSpan.toPlainText()`), `temps-fresh-<jack>`, `temps-progress-<jack>`,
  `temps-meta-<label-slug>-<jack>` (e.g. `temps-meta-pull-at-1`),
  `temps-detached`/`temps-detached-<jack>`/`temps-detached-role-<jack>`,
  `temps-empty`; sheet: `probe-sheet-body`/`-header`/`-name`/`-sub`/`-temp`/
  `-spark`/`-phase`/`-phase-card`/`-stats`/`-roles`/`-doneness`/`-pull-notice`/
  `-set-target`/`probe-share`; actions are found by label (`Mark pulled`,
  `Test alarm`, `Share this probe`).
- The role/target editors call `repo.probeRole` / `repo.setTarget`; the sheet's
  "Set a target" opens `DevOverlay.setup` with `context=edit` and `jack=N`
  (N9 must honour both props).

**Deviations / decisions**
- **`probeRole(unused)` clears `attached`/`temp` (N2 behaviour)**, so after
  re-roling a jack to Unused the Live tile reads `Unplugged`, not `Unused`, and
  Temps moves it to "Not attached". The exit-gate test asserts that (I3 wins
  over the role word).
- **I4 gate is `Freshness.showsDerived` (live **or** aging)**, not the
  prototype's stricter `=== 'live'`. Matches the N5 compact tile.
- `probeFreshnessWord` reproduces the prototype exactly: `frozen → "Stale"`,
  `stale → "—"` (the `stale` rung shows no word).
- Trend labels are always `° F/hr` (the prototype never converts a rate); the
  unit toggle does convert temperatures and the pit-band readout.
- `Test alarm` and `Share this probe` only raise a shell toast (no repository
  method); N11 owns the real alarm test, N12 owns export/share.
- **I12**: the doneness chips are the assigned preset's ladder, and the "pull at
  X" notice goes through the domain's floor-clamped `pullTempFor`, so it never
  advertises a pull below a safe minimum. The plan-level refusal itself lives in
  N9 (a probe with no assigned cut offers "Set a target" → setup).
- `PhaseTrack` reproduces `app.js` exactly: crossing the target jumps to `Ready`,
  so `Resting` is never the current phase; with `pull == target`, `Pull now` is
  unreachable (unit-tested).
- `shell_router_test.dart` was updated: the generic shell behaviours (fullscreen,
  toast) now drive the Graph placeholder instead of Temps, and the Temps nav test
  asserts the real `temps-page`. The probe deep-link test now expects two
  "Probe 3" texts (sheet title + sheet header).

**Follow-ups for later tasks**
- N7 owns the real chart; `probe-sheet-spark` is the N3 `Sparkline` preview.
- N9 must honour `context=edit` + `jack` when the probe sheet's "Set a target"
  opens `DevOverlay.setup`.
- N11 owns `DevOverlay.alarmDetail` (still a placeholder) and a real "Test alarm".
- N12 owns share/export; N6 only toasts.
- N16: consider a Temps golden for `idle`/`offline` (only `running` is pinned).