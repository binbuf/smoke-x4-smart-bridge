# Host tests

Plain CMake + CTest suite for the pure-C firmware pieces. It needs only a C11
compiler (`gcc` or `clang`), CMake and Ninja. No ESP-IDF, no board, no phone,
no network.

```bash
cmake -S firmware/test -B firmware/test/build -G Ninja
cmake --build firmware/test/build
ctest --test-dir firmware/test/build --output-on-failure
```

`make host-test` runs the same three commands. `build/` is ignored.

## What is here

| Path | Purpose |
|---|---|
| `CMakeLists.txt` | host project; links only pure-C components |
| `test_lora_corpus.c` | loads real captures and `parser-vectors.tsv`, checks shape, metadata and required coverage |
| `test_log_io_ram.c` | exercises the RAM `log_io` fake (bounds, erase, counters, torn operations) |
| `test_tasks.c` | checks the `firmware/main/tasks.h` table, stack total and 24 KiB budget |
| `test_sx_radio_rx.c` | injects real/edge-case frames into the radio-to-parser seam and checks the LoRa parameter block |
| `support/lora_corpus.*` | `.loralog` and vector-file readers for tests |
| `support/ram_log_io.*` | RAM-backed `log_io` implementation |
| `support/test_util.*` | small `CHECK` macros and summary |
| `../components/sample_log/include/log_io.h` | production byte-oriented storage seam |

`test_records` is built from `protocol/test/test_records.c` directly, so the
codec vector coverage from T02 has one owner and `ctest` is the single host
entry point. `test_tasks` compiles `../main/tasks.c` from the firmware tree; the
same header is used by the ESP-IDF build, so its `_Static_assert` and the host
test cannot drift.

## Fixtures

The corpus lives at `protocol/fixtures/lora/`. Every capture is committed with
its report; see that directory's `README.md` for provenance and the
`parser-vectors.tsv` column contract. X2-era vectors are defensive only.

The product parser (T14) and ring core (T18) should extend this suite rather
than start another build tree. The corpus reader is test-only; firmware must
never read fixture files.
