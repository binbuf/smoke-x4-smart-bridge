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