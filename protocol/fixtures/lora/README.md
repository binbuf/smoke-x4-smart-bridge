# Smoke X LoRa fixture corpus

Committed host-test data for the Smoke X parser. Nothing here is read by
firmware at runtime; production code only ever sees air payloads.

## Provenance

| File | Kind | Origin | Report |
|---|---|---|---|
| `x4-events-10min.loralog` | real X4 capture | Copied unchanged from `legacy/protocol/fixtures/lora/`; 2026-07-21 over-the-air capture, 918.5 MHz operating channel, probe/alarm activity | `x4-events-10min.report.md` |
| `x4-passive-session.loralog` | real X4 capture | Copied unchanged from `legacy/protocol/fixtures/lora/`; passive overnight session at the normal ~30 s cadence | `x4-passive-session.report.md` |
| `first-x4-contact.loralog` | real X4 capture | Copied unchanged from `legacy/protocol/fixtures/lora/`; first verified X4 state packet | `first-x4-contact.report.md` |
| `x4-t10-25min.loralog` | real X4 capture | T10 bench capture 2026-10-26 on the current board: sync beacon, our ACK, stock receiver ACK, 41 state frames, detach/reattach and °F→°C→°F; 918.5 MHz, `LMXC[\` | `x4-t10-25min.report.md` |
| `malformed.loralog` | adversarial corpus | Copied unchanged from `legacy/protocol/fixtures/lora/`; hand-written "must reject" payloads | header comment |
| `parser-vectors.tsv` | synthetic/transcribed vectors | X4 rows transcribed from the captures above; X2 rows from the legacy reference test corpus; foreign-ID, malformed, oversized, out-of-band and Billows-shape rows synthetic | per-row `provenance` column |

The three `.report.md` files are copied verbatim from the legacy tree. Their
headers contain the original Windows scratch paths; that is intentional
provenance, not a path this tree uses.

`malformed.loralog` has no separate report because it is not a capture. Its
header records that every payload must be rejected. `parser-vectors.tsv`
carries provenance on every row.

## Rules

- Do not edit `legacy/protocol/fixtures/lora/`; this directory is the committed
  copy.
- A new real capture must arrive with a short report (time, radio settings,
  what changed) and a row in this table.
- X2-era vectors are **defensive only**. They prove the parser does not crash or
  invent data on the old shape; they do not define supported product behaviour
  and must not drive features.
- The parser may decode an out-of-band sync; the caller must reject the
  frequency before retuning or ACKing. The `ok-out-of-band` expectation records
  that split.

## `parser-vectors.tsv`

One tab-separated vector per line; `#` starts a comment. Columns:

| Column | Meaning |
|---|---|
| `name` | stable vector identifier |
| `category` | `x4`, `x2-defensive`, `malformed`, `foreign-id`, `detached`, `celsius`, `billows`, `out-of-range` |
| `kind` | `sync` or `state` |
| `probes` | `-` for sync, `2` for X2, `4` for X4 |
| `expect` | `ok`, `reject`, or `ok-out-of-band` |
| `device_id` | expected ID, or `-` when not asserted |
| `units` | `F`, `C`, or `-` |
| `attached` | bit string, probe 1 at the left, or `-` |
| `frequency` | expected sync frequency in Hz, or `-` |
| `provenance` | `capture:<fixture>`, `legacy-reference-corpus`, `design-02`, or `synthetic-adversarial` |
| `payload` | exact ASCII air payload including the trailing comma |

The host suite `firmware/test/test_lora_corpus.c` loads this file and checks
shape, metadata and coverage. T14 uses the same corpus for the product parser.

## Running the host suite

```bash
cmake -S firmware/test -B firmware/test/build -G Ninja
cmake --build firmware/test/build
ctest --test-dir firmware/test/build --output-on-failure
```
