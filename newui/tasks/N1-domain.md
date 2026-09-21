# N1 — Domain

**Goal:** a pure-Dart `domain/` (zero Flutter imports) that owns units, freshness,
food safety, the analysis engines, and the timeline/style content contracts. This
is the rebuilt version of the legacy engines, written fresh with new tests.

**Design:** [`newui/mock-data.js`](../mock-data.js) · [`newui/app.js`](../app.js) §4
· `newui/NOTES.md` §3–§5 · `newui/components_research_notes.md` §1, §6 · `app.old/lib/domain` (behavioural reference only).

---

## Invariants this epic must encode

| # | Invariant | Where |
|---|---|---|
| I3 | Absent ≠ zero: detached/unknown is `null`, never `0` | `ProbeReading`, `TempValue` |
| I4 | Never present stale data as current; derived values are **removed**, not greyed | `Freshness`, `canShowDerived` |
| I11 | A bridge with no clock stores `null`, never a fabricated timestamp | `Sample.unixMs` |
| I12 | Food safety is a hard gate; targets below a class floor are refused | `SafetyFloor`, `CookPlan` ctor |
| — | Poultry carryover is **always zero**; carryover is by thickness, not doneness | `carryoverFor`, `pullTempFor` |

## Tasks

| # | Task | blocked-by | verify | design |
|---|---|---|---|---|
| N1.1 | `TempValue` / units: storage canonical tenths-°F; `toDisplay(unit)` conversion only; format `72.4° F` / `22.4° C`; sentinel handling | — | H | `app.js` §2, NOTES §3.4 |
| N1.2 | `ProbeJack` (1–4), `ProbeRole` (unused/food/pit/ambient), role defaults (jack 4 = pit) | N1.1 | H | `app.js` §6, NOTES §7.2 |
| N1.3 | `Freshness` ladder: live ≤45s / aging ≤90s / stale ≤600s / frozen; `showsDerived`, `isDim` | N1.1 | H | `components_research_notes.md` I4 |
| N1.4 | `ProbeReading` freezed: attached, temp, trend, stalled, peak/low/avg, eta, spark — every absent field nullable | N1.3 | H | `mock-data.js` scenario probes |
| N1.5 | `HazardClass` + `SafetyFloor.forClass(hazard, isIntact, mode)` (USDA vs enthusiast), floors from `app.old/lib/domain` behaviour | N1.2 | H | research notes §6.3, I12 |
| N1.6 | `CookPreset` / `Doneness` ladder model (target post-rest); default medium-rare for red meat | N1.5 | H | `mock-data.js` catalog, `Start.md` |
| N1.7 | `carryoverFor(cut)` by thickness; `pullTempFor` clamped at the safety floor; poultry carryover = 0 | N1.5, N1.6 | H | `app.js` §4, NOTES §3.4 |
| N1.8 | `CookStyle` record (pit band, wrap, spritz, target, rest, timeline, `region` badge) | N1.6 | H | `mock-data.js` STYLES, NOTES §2.2 |
| N1.9 | `CookTimeline` model: `totalMin`, `stall`, `wrap`, `spritzEveryMin`, `turn`, `restMin`, `phases[]` | N1.6 | H | `mock-data.js` `normalizeTimeline`, NOTES §4 |
| N1.10 | Analysis: rate of change — OLS over 10 min; null on too few samples or >2 min gap; floor ±0.6 °F/hr → `~0` | N1.4 | H | research notes §6.2 |
| N1.11 | Analysis: ETA — OLS early, Newton cooling within 60 °F of pit; 15-min-rounded range or a **named refusal** | N1.10 | H | research notes §6.2 |
| N1.12 | Analysis: stall detection — enter \|slope\|<2 °F/hr for 30 min ∧ 140–180 °F; exit >4 °F/hr for 15 min | N1.10 | H | research notes §6.2 |
| N1.13 | Analysis: cook stats — duration, readings, gaps, pit mean/σ/min/max, time-in-band (gap time excluded), peak per probe | N1.4 | H | research notes §6.2 |
| N1.14 | LTTB decimation + chart series (split runs at gaps **before** decimation; min/max envelope for wide ranges) | N1.13 | H | research notes §6.2 |
| N1.15 | `CookPhase` arc: approaching → pullNow → resting → ready; never infers "pulled" | N1.7, N1.11 | H | research notes §6.3 |
| N1.16 | `CookPlan` constructor is the safety gate; `fromJson` re-runs it | N1.5, N1.6 | H | research notes I12, §6.3 |
| N1.17 | `CookAnnotation` window over the sample stream; verbs are metadata only (`backdate`, `split`, `merge`, `retarget`, `repeat`); `candidateAnchors` | N1.4 | H | research notes §6.3, NOTES §5.2 |
| N1.18 | `Gap` model: connectivity (recoverable) vs bufferRollover (permanent) | N1.4 | H | research notes §5.3 |
| N1.19 | `SituationFacts` → `reconcile()` priority ladder (radio/permission → identity → reachability → usefulness → staleCook → healthy); nullable = unknown | N1.3 | H | research notes §6.5 |

## Exit gate

`dart test test/domain` green, including the named failure cases (detached ≠ 0,
stale removes ETA, poultry carryover zero, unsafe target throws, ETA refusals).
`domain/` imports nothing from `package:flutter`.

## Must-not-regress

I3, I4, I11, I12 and the carryover rule — each pinned by a test that names it.

---

## Hand-off

**Status: done.** All 19 sub-tasks are implemented as pure Dart under `app/lib/domain/`
(barrel `app/lib/domain/domain.dart`), with a new test suite in `app/test/domain/`.

**What landed**
- N1.1 `units/temp_value.dart` — `TempValue`/`TempUnit`, tenths-°F storage, `toDisplay`
  conversion only, `72.4° F` / `22.4° C`, both wire sentinels fold to absent.
- N1.2 `entities/probe.dart` — `ProbeJack` (1–4), `ProbeRole`, jack-4-is-pit default, `Probe`.
- N1.3 `entities/freshness.dart` — live/aging/stale/frozen (+ `unknown`), `showsDerived`,
  `canShowDerived`, `isDim`.
- N1.4 `entities/probe_reading.dart` — freezed `ProbeReading`; every living value nullable.
- N1.5 `plan/hazard.dart` — `HazardClass`, `SafetyMode`, `SafetyFloor.forClass`.
- N1.6 `plan/presets.dart` — `Doneness`/`DonenessLadder`/`CookPreset`, medium-rare red-meat default.
- N1.7 `carryoverFor`/`pullTempFor`/`restSecondsFor` — thickness-based, floor-clamped, poultry zero.
- N1.8 `plan/cook_style.dart`, N1.9 `plan/cook_timeline.dart` — records with JSON round-trip.
- N1.10–N1.13 `analysis/rate_of_change.dart`, `eta.dart`, `stall.dart`, `cook_stats.dart`.
- N1.14 `analysis/lttb.dart`, `chart_series.dart` — split runs before decimation, envelope.
- N1.15 `plan/cook_phase.dart`, N1.16 `plan/cook_plan.dart`, N1.17 `plan/cook_annotation.dart`.
- N1.18 `entities/gap.dart`, N1.19 `situation/situation.dart`.

**Verification (real commands, real results)**
- `cd app && dart test test/domain` → `00:01 +87: All tests passed!`
- `make app.test` (repo root) → analyze clean, format clean, `00:01 +100: All tests passed!`
- CI's purity grep holds: `app/lib/domain/` imports nothing from `package:flutter`/`dart:ui`.

Named failure tests present: absent ≠ zero, stale removes derived values, poultry carryover zero,
unsafe target throws (and `fromJson` drops a now-unsafe plan), and the five named ETA refusals.

**Deviations from the plan, and why**
1. **Test runner.** The exit gate names `dart test test/domain`, but `dart test` cannot compile
   files importing `flutter_test`. I added `test: ^1.31.0` as a direct dev dependency and made
   every `app/test/domain/*` file use `package:test`; `flutter test` still runs them (100 total).
   The N0.6 placeholder `temperature_reading` model/test was deleted as the task directed.
2. **Naming.** `ProbeJack` is an enum rather than a bare `int`, and
   `carryoverFor({hazard, thickness})` takes named params rather than a "cut" object. Behaviour
   matches `app.old/lib/domain`.
3. **`CookPlan.fromJson` hazard fallback** is `unstated` (160 °F floor), not the legacy
   `wholeMuscleRedMeat`; this closes the fallback inconsistency noted in the research notes.
4. **`Freshness.unknown`** was added beyond the four-rung ladder for "no reading at all".

**What the next task (T03 / N2 data and mocks) must know**
- N1 ships models and engines only — **no catalog, timeline or style tables**. N2 owns
  `Presets.all`, the per-cut `CookTimeline` table, the per-cut `CookStyle` table and the scenarios,
  and should build them as `CookPreset` / `CookTimeline` / `CookStyle` instances keyed by preset id.
- After editing any `@freezed` model, run `make app.gen` and commit the generated file; CI runs
  `dart run build_runner build` then `git diff --exit-code -- lib`.
- Any new test under `test/domain/` that the `dart test` gate should run must import
  `package:test`, not `flutter_test`.