# Standing work

Recurring obligations that are **not one-off tasks** and must not be closed. Each has a home, an
owner-by-default, and a trigger.

---

## V2 — The capture campaign

**Ongoing from M0 until the protocol questions close.** Real protocol work needs real packets, and
[02 §2.8](../design/02-smoke-x-protocol.md) lists eight questions that only a capture can answer.

The design's key move: **capture is a permanent background behaviour, never a session.** With one
board, flashing a special capture build costs a cook, and cooks are the scarce resource. So the
shipping firmware always keeps a RAM packet ring, a persistent novelty log, and an opt-in per-session
raw log ([02 §2.7](../design/02-smoke-x-protocol.md)).

**The consequence: most of this collects itself.** Once F4 lands in M1, items 2, 4, and 5 below are
answered by cooking dinner, with the evidence waiting at `/api/v1/debug/novelty` the next time anyone
looks.

| #   | Do this                                              | Answers                                       | Effort         | Collects itself after F4? |
| --- | ---------------------------------------------------- | --------------------------------------------- | -------------- | ------------------------- |
| 1   | Cook anything, all four probes attached              | First real X4 vectors                         | none           | ✅ **done at V2.1**       |
| 2   | Let it run overnight                                 | Q1, interval statistics, dropouts, RSSI decay | none           | ✅ yes                    |
| 3   | Unplug and replug a probe mid-cook                   | Q4 — probe `state` beyond `0`/`3`             | 10 s           | partly                    |
| 4   | Set a tight alarm band so it trips, leave it tripped | **Q8** — is `new_alarm` edge or level?        | 1 min          | ✅ yes                    |
| 5   | Flip the base between °F and °C mid-cook             | The unit-change path                          | 1 min          | ✅ yes                    |
| 6   | Re-sync the base while the bridge is unpaired        | Q2, Q6                                        | 2 min          | ✅ **done at V2.2**       |
| 7   | Short the probe jack, open it, exceed range          | The rest of **Q4**                            | bench, no cook | no — do deliberately      |
| 8   | _Borrow an X2_                                       | Q2 comparison across models                   | opportunistic  | no                        |
| 9   | _Borrow a Billows_                                   | **Q3, Q5**                                    | opportunistic  | no                        |

### Standing obligations

- **After every cook**, pull `novelty.log` and check for new reason classes. Anything new becomes a
  fixture in `protocol/fixtures/lora/` and a test case.
- **When a question closes**, update [02 §2.8](../design/02-smoke-x-protocol.md)'s status column _and_
  the confidence marker on the affected field — **[I]** → **[K]**. The confidence markers are the
  doc's most useful feature and they rot silently.
- **Item 7 is a deliberate bench task**, not something a cook produces. Schedule it into a board
  sitting.
- **Q3 and Q5 are blocked, and that is fine.** No Billows unit exists. Per D11 the fields are decoded
  and stored anyway, so a future capture reinterprets existing cooks rather than requiring new ones,
  and no v1 feature depends on them.

---

## Design document maintenance

The design docs are the contract. Three specific rots to watch for:

| Trigger                                     | Update                                                                                                      |
| ------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| A protocol question closes                  | [02 §2.3](../design/02-smoke-x-protocol.md) vectors, §2.8 status, and the field's confidence marker         |
| A bench measurement lands                   | `docs/hardware-verified.md`, and the estimate it replaces in [01](../design/01-hardware.md)                 |
| A decision is made that D1–D14 didn't cover | Add it to the log in [00](../design/00-overview.md) with its rationale — don't leave it in a PR description |

**Three boxes in `docs/hardware-verified.md` are deferred from V1.6 and must be closed later**, not
quietly forgotten:

| Deferred check                                                     | Closes at        |
| ------------------------------------------------------------------ | ---------------- |
| Free heap ≥ 150 KB with AP + NimBLE + httpd + both LittleFS mounts | F9 / F10 (M2–M3) |
| LoRa RX with BLE advertising **and** a WebSocket client streaming  | V3a (M3)         |
| OLED I²C stable at 400 kHz with BLE active                         | M3               |

---

## Continuous measurement

Not tasks — properties of CI that fail the build.

| Check                                | Threshold                           | Where                               |
| ------------------------------------ | ----------------------------------- | ----------------------------------- |
| Binary size and free-space delta     | reported on every PR                | `firmware-build.yml`                |
| `protocol/gen/**` freshness          | any diff fails                      | `protocol.yml`                      |
| `app/lib/domain/` imports no Flutter | any match fails                     | `app.yml`                           |
| Free heap during the 24 h soak       | **fail below 80 KB**                | V3, M6                              |
| Per-task stack watermarks            | logged once a minute at debug level | [01 §1.4](../design/01-hardware.md) |

Binary-size reporting earns its two lines: with 2.5 MB app slots holding Wi-Fi + BLE + httpd +
LittleFS, the day someone adds a library that doesn't fit should be the day they find out.

---

## Open decisions

| #       | Question                | Blocks                                              | Needed by |
| ------- | ----------------------- | --------------------------------------------------- | --------- |
| **Q-F** | Public repo or private? | T5 — whether the installer can live on GitHub Pages | before M6 |

Everything else is settled. If a decision in D1–D14 looks wrong during implementation, **raise it as a
question — do not quietly plan around it** ([§12.3](../design/12-task-planning-notes.md)).

---

## Board discipline

The board is a serialized resource ([11 §11.6](../design/11-roadmap-and-risks.md)). Four rules that
shape the plan rather than merely inconveniencing it:

1. **Batch `board: yes` work into sittings.** Especially V1 — the whole bench checklist in one go.
2. **When a cook is running, the board belongs to data collection, not to debugging.**
3. **Batch firmware flashes.** Each one costs the current cook.
4. **Never OTA the only board with an image that hasn't been flashed over USB first.** With no spare,
   an unbootable board is a total halt.
