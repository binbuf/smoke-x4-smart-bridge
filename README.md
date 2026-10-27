# Smoke X4 Smart Bridge

Connect your **Thermoworks Smart X4** to your Android smart device using an inexpensive **ESP32 LoRa V3 Development Board**, 3D printed enclosure, and a Flutter mobile app.

## Getting Started

TODO

## Development checks

```bash
make host-test      # firmware host suite
make protocol-check # generated protocol drift
make app-check      # flutter analyze + flutter test
```

The app is Android-only; the iOS, web and desktop Flutter targets are not part of
the MVP.

## Credit

https://github.com/G-Two/smoke-x-receiver

## Notes

Not affiliated with or endorsed by ThermoWorks. Smoke X is a trademark of its owner.