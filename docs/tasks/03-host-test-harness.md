# T03 — Host test harness and fixtures

## Goal
Stand up a plain CMake host test project that exercises the pure-C components
against real and adversarial capture fixtures, runnable with nothing but
gcc/cmake/ninja. This is the fast feedback loop every firmware task relies on.

## Context (read first)
- Design: [10 §10.2](../design/10-test-and-release.md)
- Verification: **H** (host/CI) · Board required: **no**
- Depends on T01.
- No board and no ESP-IDF toolchain are needed; the host project must build and
  run on a machine with only gcc/cmake/ninja.

## Scope
- [x] Create a plain CMake host project under `firmware/test` that links the
      pure-C components.
- [x] Copy the real X4 capture fixtures from `legacy/protocol/fixtures/lora/`
      into `protocol/fixtures/lora/` together with their reports.
- [x] Add X2-era parser vectors (defensive only).
- [x] Add malformed, foreign-ID, detached, and Celsius vectors.
- [x] Add a RAM-backed `log_io` fake for ring tests.
- [x] Add a test runner invoked by `ctest`.

## Out of scope
- Protocol YAML/codegen and the `live` vector test — owned by T02.
- Real-device capture sessions — owned by T10.
- Firmware build and partition table — owned by T04.
- CI wiring of these tests — owned by T08 (this task only makes `ctest` green).
- Product parser feature work — M1 (this harness is the fixture/runner seam).

## Design notes
- The host project links **pure-C components only**; no ESP-IDF dependency may
  leak into host tests.
- Fixtures are committed with provenance: each capture carries its report so
  the origin and conditions are traceable.
- X2-era vectors exist for defensive parsing only — they do not define
  supported behaviour and must not drive new features.
- Coverage must include malformed input, foreign IDs, detached probes, and
  Celsius values.
- The ring-log tests use a RAM-backed `log_io` fake rather than real flash.
- `ctest` is the entry point; keep it runnable on a bare toolchain.

## Done when
- [x] `ctest` runs green on a machine with only gcc/cmake/ninja.
- [x] The fixtures are committed with provenance.
- [x] Hand-off below filled in.

## Hand-off

### What landed

- `firmware/test/CMakeLists.txt`: plain C11 CMake project, `-Wall -Wextra
  -Werror` for GCC/Clang, CTest entry point. It links `protocol/gen/records.c`
  as `sx4_protocol_gen` and has no ESP-IDF include path or dependency. It builds
  `protocol/test/test_records.c` directly instead of duplicating the codec test.
- `firmware/test/test_lora_corpus.c`: loads the real captures and
  `parser-vectors.tsv`; checks line/class/comma consistency, known X4 values
  (918.5 MHz, device `LMXC[\`, 36+ states, 3 alarm edges, 3 frozen detached
  probes), all-malformed rejection, vector metadata, category coverage and
  report presence.
- `firmware/test/test_log_io_ram.c` plus
  `firmware/test/support/ram_log_io.{h,c}`: RAM-backed `log_io` fake with NOR
  `0xFF` erase semantics, bounds checks, call/byte counters, one-shot failure
  injection and partial (torn) write/erase.
- `firmware/components/sample_log/include/log_io.h`: the pure-C `read`/`write`/
  `erase` seam (byte offsets, sector-aligned erase, advertised capacity and
  sector size).
- `protocol/fixtures/lora/`: copied unchanged `x4-events-10min`,
  `x4-passive-session`, `first-x4-contact` and their reports, plus the legacy
  `malformed.loralog`. `README.md` records provenance and the X2-defensive rule.
- `protocol/fixtures/lora/parser-vectors.tsv`: 20 rows covering X4 baseline,
  alarm edge, sync, detached-frozen, Celsius, Billows-attached; X2 state/sync/
  detached-zeroed (defensive); foreign-ID state/sync; eight malformed cases;
  and an out-of-band 950 MHz sync marked `ok-out-of-band` (parser may decode,
  caller must reject).
- `firmware/test/README.md`, `make host-test`, ADR 0014, and design 02/03/10
  notes for the runner, corpus and seam.

### Deviations / decisions

- The product parser is not in this task (out of scope; owned by T14). The
  corpus test therefore validates fixture shape, expectations and coverage
  rather than calling `parse_state`/`parse_sync`. T14 adds parser assertions on
  the same loaded vectors; the reader API is ready for it.
- The `log_io` seam lives under `firmware/components/sample_log/include/`
  because design 03 §3.14 names it as the component seam. T18 should extend
  this header, not create a second interface. T19 maps partition errors to
  `LOG_IO_ERR_*`.
- `malformed.loralog` is copied even though it is not a real capture: design 02
  §2.9 requires the adversarial corpus and the legacy file is its source.
- Copied reports keep their original absolute scratch paths verbatim. They are
  provenance, not paths this tree uses.

### Checks run

```text
# clean host build (gcc 16.1.0, cmake 4.4.3, ninja)
cmake -S firmware/test -B firmware/test/build -G Ninja
cmake --build firmware/test/build
ctest --test-dir firmware/test/build --output-on-failure
# 3/3 tests passed: records, lora-corpus, log-io-ram

make host-test
# same three CTest tests, 3/3 passed

make protocol-check
# protocol/gen is current
```

On this bench `gcc`/`ninja` are at `C:\msys64\ucrt64\bin` and are not on the
default PowerShell PATH; the commands were run with that directory added. CI
(T08) should use the normal toolchain on PATH.

### Next task must know

- T14: use `sx4_loralog_read` / `sx4_vectors_read` from
  `firmware/test/support/lora_corpus.h`; add parser tests to this CMake tree.
- T18: implement ring geometry against `log_io.h`, use `ram_log_io` for fill,
  wrap, torn tail, dual-header and generation scenarios.
- T04: when adding component stubs, do not replace
  `firmware/components/sample_log/include/log_io.h`.
- Unrelated working-tree edits to `docs/hardware-verified.md` and
  `docs/tasks/09-board-identity-bench-rig.md` were present during this session
  and were left untouched.
