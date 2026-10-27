# Capture report — C:\Users\dan\.claude\jobs\11ee5c24\tmp\verify-listen.txt → first-x4-contact

| class | packets |
| --- | ---: |
| state26 | 1 |

## Link quality

- RSSI min/mean/max dBm: -38 / -38.0 / -38

## Protocol questions (02 §2.8)

- **Q1 / Q6** — state header field 1 values: `30`×1. Never left `30`.
- **Q4** — probe `state` values seen: `0`×4
- units field values: `1`×1
- header field 3 values (role unknown; rests at `1`, moves to `2` around alarm/menu activity): `1`×1
- **Q8** — trailing `new_alarm` field never fired in this capture: `0`×1

## Suggested vectors

- `LMXC[\,30,1,1,0,794,0,160,32,0,782,0,160,32,0,787,0,160,32,0,803,0,160,32,0,0,` — first state26
