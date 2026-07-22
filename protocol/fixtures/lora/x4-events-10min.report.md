# Capture report — C:\Users\dan\AppData\Local\Temp\claude\D--repos-binbuf-smoke-x4-smart-bridge\12b3d770-d434-4f68-8088-1fe6fde9b970\scratchpad\capture-x4-events.log → x4-events-10min

| class | packets |
| --- | ---: |
| sync6 | 1 |
| ack2 | 1 |
| state26 | 37 |

## Interval statistics (state messages)

- count: 36
- min/mean/max ms: 28970 / 32621 / 75890
- gaps > 45 s: 2

## Link quality

- RSSI min/mean/max dBm: -44 / -37.8 / -31

## Protocol questions (02 §2.8)

- **Q1 / Q6** — state header field 1 values: `30`×37. Never left `30`.
- **Q4** — probe `state` values seen: `0`×145, `3`×3
- units field values: `1`×34, `0`×3
- header field 3 values (role unknown; rests at `1`, moves to `2` around alarm/menu activity): `1`×30, `2`×7
- **Q8** — trailing `new_alarm` field `0`×34, `1`×3; episodes (consecutive packets): [1, 1, 1] → looks EDGE-triggered
- **Q2 / Q6** — sync: field0=`000000` device=`LMXC[\` frequency=918.5 MHz

## Suggested vectors

- `000000,LMXC[\,160,50,191,54,` — first sync6
- `LMXC[\,SUCCESS,` — first ack2
- `LMXC[\,30,1,1,0,811,0,160,32,0,801,0,160,32,0,807,0,160,32,0,807,0,160,32,0,0,` — first state26
- `LMXC[\,30,1,1,0,1054,0,160,32,0,797,0,160,32,0,790,0,160,32,3,809,0,160,32,0,0,` — probe state `3`
- `LMXC[\,30,1,2,0,1052,1,105,32,0,822,0,160,32,0,829,0,160,32,0,835,0,160,32,0,1,` — hdr3 `2`, new_alarm set
- `LMXC[\,30,0,1,0,381,1,37,8,0,285,0,71,0,0,288,0,71,0,0,273,0,71,0,0,0,` — units °C
