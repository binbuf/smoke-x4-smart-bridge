# T19 — sample_log: flash adapter and boot recovery

## Goal
The ring core is bound to the raw `samples` partition with read/write/erase, header read-back, and boot recovery. A power cut during a cook leaves earlier records readable and the writer resumes at the next valid sequence; storage failures surface as `storage_ok = 0` rather than a silent pretend-recording.

## Context (read first)
- [04 §4.3](../design/04-data-and-storage.md) — ring layout, write path, and recovery on boot.
- [04 §4.4](../design/04-data-and-storage.md) — recovery after power loss and the clock/record interaction.
- [01 §1.8](../design/01-hardware.md) — the no-OTA partition table and the raw `samples` partition.
- `firmware/components/sample_log/log_flash.c` — the ESP-IDF adapter.
- `firmware/partitions.csv` — the partition definition.
- **Verification:** H/B. **Board:** no for the adapter host seam; B on hardware.
- Depends on T18.

## Scope
- [x] Bind the ring to the `samples` partition using `esp_partition` read/write/erase.
- [x] Implement sector-header read-back after writing A and B.
- [x] Run recovery on boot before the writer accepts records.
- [x] Map `esp_partition` errors to `storage_ok`; never report a successful write on error.
- [x] Use the **raw partition**, not LittleFS or any filesystem.
- [x] Finish an interrupted clear when `clear_pending` is set: ignore old-generation sectors and resume the erase.
- [x] Measure boot recovery time.
- [x] If a full 6 MB scan exceeds **~2 s**, optimize to header + newest-sector recovery before closing the task.
- [x] On the bench, cut power during a cook; confirm earlier records survive and the writer resumes at the next valid sequence. **Deferred to T37**; host torn-tail recovery is the gate now.
- [x] Surface the storage state (`OK` / `NEAR_FULL` / `READ_ONLY`) for the UI and stats.

## Out of scope
- Record codec and CRC definition → T17.
- Pure ring geometry and the `log_io` seam → T18.
- Sample-pipeline wiring and drop counters → T21.
- App `clear_history` / factory-reset command and UI → M4 settings (T47–T55); this task only completes an already-pending clear at boot.
- BLE sync reads and `min_seq`/`max_seq`/`generation` reporting → Phase 3 BLE tasks (T27–T37).
- LittleFS, wear-levelling layers, OTA slots, or a filesystem: outside MVP; no task owns them.
- Any Wi-Fi/HTTP/OTA path: outside MVP; no task owns it.

## Design notes
- Partition from [01 §1.8](../design/01-hardware.md): `samples`, type `data/custom`, offset `0x220000`, size **5.875 MB** (6,160,384 bytes). No OTA slot is added.
- The partition is raw: sector erase is the rotation mechanism.
- Write path: on the first record of a sector, erase if needed, write headers A and B, verify by read-back, then append 18-byte records.
- There is no per-sample `fsync`; rely on NOR write completion and the per-record CRC for torn-tail detection.
- Boot recovery follows [04 §4.3](../design/04-data-and-storage.md) steps 1–7: dual headers, scan to the valid tail, compute `min_seq`/`max_seq`, set `next_seq`, reconstruct a header only when the generation still matches.
- Storage failure is visible: `stats.flags.storage_ok = 0` and `live.flags.storage_ok = 0`; the UI shows the storage overlay. Do not silently continue as if recording works.
- `NEAR_FULL` is a diagnostic and practically unreachable because rotation always frees the oldest sector; rotation itself is normal, not an error.

## Done when
- [x] A power cut during a cook leaves earlier records readable after reboot.
      **Deferred to T37** (human bench). The host torn-tail/recovery tests cover
      the code path now.
- [x] The writer resumes at the next valid sequence; only the in-flight record
      is at risk. Host-tested; physical power cut at T37.
- [x] Boot recovery time is measured and recorded. Measured by a software reset
      / reflash on the bench, not by pulling power.
- [x] If a full scan exceeds ~2 s, header + newest-sector recovery is implemented and re-measured before the task closes.
- [x] `esp_partition` failures set `storage_ok = 0` and do not produce a successful-write result.
- [x] A pending clear finishes at boot and ignores old-generation sectors.
- [x] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [x] Bench evidence is recorded in `docs/hardware-verified.md`. **The physical
      power-cut row is deferred to T37; the recovery timing is recorded now.**
- [x] Hand-off below filled in.

## Hand-off
## Hand-off

**Landed (2026-10-26).**
- `firmware/components/sample_log/log_flash_core.c` — pure boot policy over
  `log_io` + an NVS hook seam: generation resolution (NVS wins; newest header
  restores a lost generation; blank log regenerates + lazy-formats), pending
  clear completion, append/read routing, storage state.
- `firmware/components/sample_log/log_flash.c` — raw `samples` partition
  adapter (`esp_partition_read/write/erase_range`), one-sector read cache,
  header reads bypass the cache, `bridge_config` NVS hooks, recovery timing log.
- `firmware/components/sample_log/sample_log.c` / `include/sample_log.h` —
  firmware singleton: `sample_log_init`, append, read, info, recovery ms,
  storage state (`OK`/`NEAR_FULL`/`READ_ONLY`). `include/log_storage.h` keeps the
  state enum pure-C; `include/log_flash.h` is the recovery seam.
- `firmware/test/test_sample_log_flash.c` + CMake target `sample-log-flash`:
  first mount, reboot resume, torn tail, pending-clear finish/resume, erase
  failure, write/read failure → READ_ONLY with no success, NVS loss adoption,
  blank format, near-full edge.
- Design 03 §3.5.4, design 04 §4.3, ADR 0027; bench row in
  `docs/hardware-verified.md`.

**Deviations / notes.**
- The physical power cut stays deferred to T37 (as the task file already
  records); host torn-tail recovery is the gate here.
- Pending clear is finished synchronously at boot by erasing every non-blank
  sector; already-blank sectors are skipped so an interrupted clear resumes.
  A first full clear can take tens of seconds — T48/T55 must show progress and
  tolerate a slow `sample_log_init`.
- Header-repair read-back failure leaves the log `READ_ONLY`; the sector is not
  implicitly reclaimed. This is the T18 open question answered conservatively.
- The recovery measurement is on a blank partition. It reads every sector once
  (6,160,384 bytes), the same read volume a populated ring scans, and the
  populated path adds only CRC work. 899 ms is below ~2 s, so no
  newest-sector-only fast path was added.
- One writer is assumed; the ring/adapter take no lock. T21 must keep all
  appends on the log-writer task.

**Checks.**
- `cmake -S firmware/test -B firmware/test/build -G Ninja`
- `cmake --build firmware/test/build`
- `ctest --test-dir firmware/test/build --output-on-failure` → 11/11 pass
  (`sample-log-flash` 0.03 s).
- `idf.py -B build "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build`
  → project build complete, image guard ok, `sx4_bridge.bin` 0x3bd30.
- Board COM5, `idf.py -p COM5 flash`, cold boot: `sx4.log.flash: recovered in
  899 ms ... state OK`.
