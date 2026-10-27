# T25 — Bench: pair, stock receiver, power cut

## Goal
Real-hardware evidence that the bridge pairs with an actual Smoke X4 without disturbing the stock receiver, survives a mid-cook USB power cut with earlier records intact, records detached probes as sentinels, and stores canonical °F when the X4 is flipped to °C.

## Context (read first)
- [10 §10.3 B1](../design/10-test-and-release.md) — the radio and storage bench matrix.
- [02 §2.7](../design/02-smoke-x-protocol.md) — pairing rules, including that the stock receiver is independent.
- [04 §4.3](../design/04-data-and-storage.md) — power-loss recovery guarantees: earlier records are safe; only the in-flight record is at risk.
- [04 §4.4](../design/04-data-and-storage.md) — canonical time/temperature rules.
- `docs/hardware-verified.md` — the evidence file for this sitting.
- **Verification:** B (bench/board). **Board:** yes.
- Depends on T16, T19, and T21.

## Scope
- [ ] Pair the bridge with a real X4; confirm the stock receiver keeps updating.
- [ ] Start recording; pull USB power mid-cook; reboot; confirm earlier records survive and the log resumes.
- [ ] Detach a probe; confirm `---` on the OLED and the detached sentinel in the log.
- [ ] Flip the X4 between °F and °C; confirm canonical °F storage.
- [ ] Record the radio settings, test time, and what changed for each capture.
- [ ] Commit a capture or log excerpt with the results.

## Out of scope
- App-driven unpair/re-pair: that is **T55**, outside this task; the app action lives in M4 settings (T47–T55).
- Host FSM testing of the T16 pairing states → T16 (this bench sitting only confirms the real handshake).
- Full ring rotation/fill or `min_seq`/`max_seq`/`generation` over BLE → later BLE bench work in M2 (T27–T38) and M3 (T39–T46).
- A 30-minute cadence run and page walk → T26.
- 24 h soak and field cooks → M6 field hardening.
- Billows observation → M5 (T56–T60); no Billows TX/control path exists in the MVP.
- Any Wi-Fi/HTTP/OTA test: outside MVP; no task owns it.

## Design notes
- Fit the 915 MHz antenna before applying power; do not transmit into an open port.
- The stock receiver is independent of the bridge. If it stops updating during pairing, that is a failure, not a harmless side effect.
- Pairing must follow [02 §2.7](../design/02-smoke-x-protocol.md): the ACK goes on the operating frequency, and a lost link does not auto-pair to a different unit.
- Power-cut behavior: worst-case loss is the record being written. Earlier records must remain readable; the writer resumes at the next valid sequence.
- Detached is `TEMP_DETACHED` (`INT16_MIN`), never the frozen numeric temperature; the OLED shows `---`.
- Storage is always canonical tenths of °F; `source_celsius` is provenance only.
- Do not edit the legacy fixtures; put new captures under `protocol/fixtures/lora/` with a short report.
- Record every result in `docs/hardware-verified.md`, not in a chat.

## Done when
- [ ] A real X4 pairs and the stock receiver keeps updating.
- [ ] A mid-cook USB power cut leaves earlier records readable after reboot, and the log resumes.
- [ ] A detached probe shows `---` on the OLED and the sentinel in the log.
- [ ] An X4 °C/°F flip still stores canonical °F.
- [ ] Results are written in `docs/hardware-verified.md`; a capture or log excerpt is committed.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
