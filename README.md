# Smoke X4 Smart Bridge

Connect your **Thermoworks Smart X4** to your Android smart device using an inexpensive **ESP32 LoRa V3 Development Board**, 3D printed enclosure, and a Flutter mobile app.

## Getting Started

TODO

## Development checks

```bash
make host-test      # firmware host suite
make protocol-check # generated protocol drift
make app-check      # flutter analyze + flutter test
make capture        # fresh 3x captures of every approved screen
make design-diff    # baselines vs those captures (blend + delta)
make design-approve # accept a reviewed visual change: goldens, manifest, thumbs
```

CI (`.github/workflows/ci.yml`) runs the same checks plus the protocol
generation/drift gate, the ESP-IDF firmware build, the UI golden comparison and
the no-network/no-OTA dependency guard on every pull request.

The app is Android-only; the iOS, web and desktop Flutter targets are not part of
the MVP.

## Credit

https://github.com/G-Two/smoke-x-receiver

## Alarms

The app mirrors the Smoke X alarm state per probe: alarm on/off, high/low
setpoints, and active/acknowledged state. A new alarm opens an in-app dialog and
posts a local notification; tapping either acknowledges the Bridge/app alert.

The physical Smoke X alarm is one-way. The stock receiver cannot transmit, and
no receiver→base alarm-silence command is documented. To stop the base beeping,
press any button on the Smoke X base or its receiver. The Bridge never invents an
alarm-silence RF frame.

Local notification delivery is best-effort while Android keeps the app process
alive. A foreground service is not part of this build, so a fully killed app
cannot receive live BLE alarms until it reconnects.

After a firmware update that adds a BLE characteristic, Android may keep the old
GATT table cached. Forget this phone in the app and pair again once; history and
the Smoke X pairing are preserved.

## Notes

Not affiliated with or endorsed by ThermoWorks. Smoke X is a trademark of its owner.