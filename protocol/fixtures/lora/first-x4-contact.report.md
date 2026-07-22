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
- trailing field values (Q3 context): `0`×1
- **Q8** — `new_alarm` episodes (consecutive packets): [1] → looks EDGE-triggered

## Suggested vectors

- `LMXC[\,30,1,1,0,794,0,160,32,0,782,0,160,32,0,787,0,160,32,0,803,0,160,32,0,0,` — first state26, new_alarm set
