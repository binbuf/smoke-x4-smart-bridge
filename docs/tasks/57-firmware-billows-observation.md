# T57 — Firmware: Billows observation

## Goal
The firmware decodes Billows attachment and, only when T56 validated the relation, the target, while advertising observation-only caps and keeping no Billows transmit path.

## Context (read first)
- Design: [08 §8.4, §8.6](../design/08-billows.md); contract details in [05 §5.4, §5.9](../design/05-ble-contract.md).
- Original verification: **H/B** · **board:** no / B.
- Depends on T56, T14, T28, T22.
- T56 decides whether the candidate target relation is known. Until it is confirmed, the target is unknown; do not infer it from `max` or a default setpoint.

## Scope
- [ ] Decode `billows_attached` into `live.flags`.
- [ ] Decode the candidate target; return `billows_target_f10 = 0` until T56 confirms the relation.
- [ ] Set `caps.billows_observe = 1` and `caps.billows_control = 0`.
- [ ] Keep `billows_output` reserved and always 0.
- [ ] Keep `config.billows_mode` and `config.billows_target_f10` reserved and unwritten.
- [ ] Answer `set_billows_target` with `unsupported`.
- [ ] Keep the only LoRa TX path the pairing ACK.

## Out of scope
- Any Billows control path, target write, or Billows transmit — outside MVP; no task owns it, and T68 is receive-only.
- App UI and copy (→ T58).
- Real-unit bench verification (→ T59).
- Any LoRa transmission other than the pairing ACK — outside MVP; no task owns it.
- Wi-Fi/HTTP/OTA, notifications, web UI, user-created cook sessions, CSV/JSON export, and multi-bridge — outside MVP; no task owns them.

## Design notes
- `info.caps` b0 `billows_observe` is 1; b1 `billows_control` is **0 in the MVP**.
- `live.flags` b2 is `billows_attached`; b3 `billows_output` is reserved and always 0. Do not expose a fan-duty or fan-running claim.
- `live.billows_target_f10` is the observed target; `0` means unknown. Only encode a non-zero value after T56 has validated the relation with two or more setpoints.
- `config.billows_mode` and `config.billows_target_f10` are reserved for a future control build; the MVP writes neither.
- `control` op 6 `set_billows_target` always returns `unsupported` while `caps.billows_control = 0`.
- The only LoRa TX path is the pairing ACK; there is no Billows TX path. The invariant test must prove it, not merely assert it in review.

## Done when
- [ ] Host tests cover the attached flag, unknown/known target encoding, and an unsupported `set_billows_target`.
- [ ] The TX invariant test proves no Billows transmit path exists.
- [ ] `caps.billows_observe = 1` and `caps.billows_control = 0` are observable in the host tests.
- [ ] Hand-off below filled in.

## Hand-off
_(filled in by the implementing session: what landed, what deviated and why, what the next task must know)_
