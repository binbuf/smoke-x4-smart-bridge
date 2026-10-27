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
- [ ] Create a plain CMake host project under `firmware/test` that links the
      pure-C components.
- [ ] Copy the real X4 capture fixtures from `legacy/protocol/fixtures/lora/`
      into `protocol/fixtures/lora/` together with their reports.
- [ ] Add X2-era parser vectors (defensive only).
- [ ] Add malformed, foreign-ID, detached, and Celsius vectors.
- [ ] Add a RAM-backed `log_io` fake for ring tests.
- [ ] Add a test runner invoked by `ctest`.

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
- [ ] `ctest` runs green on a machine with only gcc/cmake/ninja.
- [ ] The fixtures are committed with provenance.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
