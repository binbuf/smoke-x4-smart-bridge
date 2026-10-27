# Capture report — C:\Users\dan\AppData\Local\Temp\claude\D--repos-binbuf-smoke-x4-smart-bridge\12b3d770-d434-4f68-8088-1fe6fde9b970\scratchpad\capture-overnight.log → x4-passive-session

| class | packets |
| --- | ---: |
| state26 | 54 |

## Interval statistics (state messages)

- count: 53
- min/mean/max ms: 30210 / 30281 / 30630
- gaps > 45 s: 0

## Link quality

- RSSI min/mean/max dBm: -50 / -40.7 / -33

## Protocol questions (02 §2.8)

- **Q1 / Q6** — state header field 1 values: `30`×54. Never left `30`.
- **Q4** — probe `state` values seen: `0`×216
- units field values: `1`×54
- header field 3 values (role unknown; rests at `1`, moves to `2` around alarm/menu activity): `1`×54
- **Q8** — trailing `new_alarm` field never fired in this capture: `0`×54

## Suggested vectors

- `LMXC[\,30,1,1,0,959,1,99,47,0,824,0,160,32,0,829,0,160,32,0,817,0,160,32,0,0,` — first state26
