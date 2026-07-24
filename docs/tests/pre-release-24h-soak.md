# Pre-release test — the 24-hour diagnostic soak

**Status: DEFERRED.** To be run as a **final gate before tagging v1.0.0**.

On 2026-07-23 we chose to run the *offline functional* test first (bridge on the
3000 mAh pack + phone, no dev PC — see `hardware-verified.md` → "Offline
functional test"), and hold this diagnostic soak for the final pre-release pass.
The offline test proves the product **works** standalone; this soak proves it
**survives** 24 h and produces the evidence that closes the open heap question.

## What this closes

- **V3.3** (M6) — the 24-hour soak: heap, stacks, counters, reconnects.
- **V1.5** — real runtime on the 3000 mAh pack. Never measured: no current meter
  was ever available, so `hardware-verified.md` carries only estimates
  (~145 mA AP / ~70 mA STA modem-sleep).
- **The open heap-target design question** (`hardware-verified.md` → "Open design
  question — the heap target"): 150 KB target vs a measured `min_free_heap`
  ≈ 69–80 KB, stable and leak-free.

## Why it is run WIRED, not offline

`tools/soak` polls `/status` + `/debug/tasks` over HTTP from a machine on the
network. **Fully offline there is nothing recording the heap trend, stack
margins, or reconnect counts, and a brownout leaves no trace at all** (no panic,
no coredump — the board just powers off). That is the exact gap that made the
offline test unsuitable for *diagnostics*. So this test is deliberately wired:

- Bridge on the **release image**, flashed **over USB first**
  (`idf.py -B build/heltec-v3 '-DSDKCONFIG=sdkconfig.heltec-v3' -p COMx flash`).
  Never OTA the only board with an image not first flashed over USB — §12.6 rule 8.
- Bridge on a network (the `landing` test router is fine); a machine on the same
  network to run the soak.
- A real cook running (or a replay of `protocol/fixtures/overnight-18h.smk`),
  **all four probes**, phone bonded + connected, and ideally a WebSocket client
  streaming — everything the product does at once (the V3a.1 load profile).

## Run

```
dart run soak --host <bridge-ip> --hours 24 --trace soak.ndjson
```

Commit the NDJSON trace **and** `tools/soak`'s generated report as the evidence
that closes V3.3.

## Pass criteria — fixed in advance, do NOT tune to fit

| Criterion | Threshold |
| --- | --- |
| `min_free_heap` | ≥ 80 KB throughout |
| `free_heap` least-squares slope | ≥ −256 B/h (no leak) |
| `largest_free_block` | ≥ 32 KB (fragmentation — a total can't see it) |
| every task stack margin | ≥ 512 B |

## Battery runtime — measured for free, no meter needed

F12 now reads the pack on real hardware (verified 2026-07-23: 4062 mV → 89 % SoC),
and the soak's `/status` trace already carries `power.soc_pct`. **Run at least one
leg on battery** (unplug USB) and read the real runtime off the SoC decline
instead of estimating. This answers V1.5 empirically and, cross-checked against
the estimates, tells us whether an unattended cook on the pack is a real product
capability or needs the mains adapter.

## Verdict

- **All four criteria hold** → the 150 KB target was wrong (option 1 of the open
  question); correct `01 §1.4` to the measured floor and close the heap question.
- **Any fail** → the buffer-count / concurrency-cap conversation, now with a 24 h
  trace to argue from rather than a snapshot.
- **Record the measured battery runtime** against the ~145 mA / ~70 mA estimates,
  and mark V1.5 resolved.

Then V4.3 (the on-target release checklist) and the v1.0.0 tag — **the human's to
create; no agent tags or pushes.**
