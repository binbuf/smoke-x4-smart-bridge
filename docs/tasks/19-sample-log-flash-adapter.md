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
- [ ] Bind the ring to the `samples` partition using `esp_partition` read/write/erase.
- [ ] Implement sector-header read-back after writing A and B.
- [ ] Run recovery on boot before the writer accepts records.
- [ ] Map `esp_partition` errors to `storage_ok`; never report a successful write on error.
- [ ] Use the **raw partition**, not LittleFS or any filesystem.
- [ ] Finish an interrupted clear when `clear_pending` is set: ignore old-generation sectors and resume the erase.
- [ ] Measure boot recovery time.
- [ ] If a full 6 MB scan exceeds **~2 s**, optimize to header + newest-sector recovery before closing the task.
- [ ] On the bench, cut power during a cook; confirm earlier records survive and the writer resumes at the next valid sequence.
- [ ] Surface the storage state (`OK` / `NEAR_FULL` / `READ_ONLY`) for the UI and stats.

## Out of scope
- Record codec and CRC definition → T17.
- Pure ring geometry and the `log_io` seam → T18.
- Sample-pipeline wiring and drop counters → T21.
- App `clear_history` / factory-reset command and UI → M4 settings (T47–T55); this task only completes an already-pending clear at boot.
- BLE sync reads and `min_seq`/`max_seq`/`generation` reporting → Phase 3 BLE tasks (T27–T38).
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
- [ ] A power cut during a cook leaves earlier records readable after reboot.
- [ ] The writer resumes at the next valid sequence; only the in-flight record is at risk.
- [ ] Boot recovery time is measured and recorded.
- [ ] If a full scan exceeds ~2 s, header + newest-sector recovery is implemented and re-measured before the task closes.
- [ ] `esp_partition` failures set `storage_ok = 0` and do not produce a successful-write result.
- [ ] A pending clear finishes at boot and ignores old-generation sectors.
- [ ] Host tests pass:
  ```bash
  cmake -S firmware/test -B firmware/test/build -G Ninja
  cmake --build firmware/test/build
  ctest --test-dir firmware/test/build
  ```
- [ ] Bench evidence is recorded in `docs/hardware-verified.md`.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
