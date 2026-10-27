# 0014 — Host test harness seams and fixture corpus

Status: accepted (T03)

## Context

Every later pure-C task needs a fast feedback loop without a board or the
ESP-IDF toolchain. T02 already produced committed generated codecs and a C
codec test under `protocol/test/`. T14 will port the parser and T18 the ring
core; both need real and adversarial vectors plus a storage fake.

## Decision

- `firmware/test` is a plain CMake/C11 project. `ctest` is the host entry
  point. It links only pure-C sources and never includes an ESP-IDF header.
- The generated codec is built as a host library from `protocol/gen/records.c`.
  `protocol/test/test_records.c` is compiled directly into the suite rather
  than copied, so the T02 vectors have one owner.
- Real captures are copied from `legacy/protocol/fixtures/lora/` to
  `protocol/fixtures/lora/` with their reports. A directory `README.md` records
  origin, conditions and the difference between real captures, adversarial
  data and synthetic vectors.
- Synthetic and transcribed vectors live in `parser-vectors.tsv`, one
  tab-separated row per vector with category, expected outcome, device ID,
  units, attached mask, frequency and provenance. X2 rows are defensive only.
- The `log_io` seam (`read`, `write`, `erase`, byte offsets, sector-aligned
  erase, advertised capacity/sector size) lives in
  `firmware/components/sample_log/include/log_io.h`. The RAM fake and its
  failure/torn-operation injection live under `firmware/test/support/`.
- `make host-test` is a convenience wrapper around the same CMake/CTest
  commands; CI (T08) is not required to use make.

## Consequences

- T14 consumes the corpus and vector reader; it adds parser tests to this tree.
- T18 implements ring geometry against `log_io.h` and uses `ram_log_io` for
  fill/wrap/torn-tail/dual-header scenarios. T19 supplies the esp_partition
  adapter and must map errors to the `LOG_IO_ERR_*` values.
- Adding a real capture requires a report and a README table row; adding a
  synthetic vector requires provenance in the TSV.
- Host tests may never read `legacy/` at build or test time; a clean clone has
  only `protocol/fixtures/lora/`.
