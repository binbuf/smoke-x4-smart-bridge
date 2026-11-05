# Smoke X4 Smart Bridge

Add new wireless smart capabilities to your **Thermoworks Smoke X4** BBQ meat thermometer using your Android or iOS device with a Flutter app and an inexpensive **ESP32 LoRa V3 Development Board** allows your smart device to get live temps, alarms, and see session history.

## Getting Started

### Android app

Requires Flutter 3.47.8+ (Dart 3.13.7+) with the Android toolchain.

```bash
cd app
flutter pub get
flutter run            # debug build on a connected phone or emulator
flutter build apk      # release APK in build/app/outputs/flutter-apk/
```

`make app-check` from the repository root runs the analyzer and tests.

### iOS app

TODO

### Firmware (ESP32-S3 over USB)

Requires ESP-IDF 6.0.2 and the Heltec WiFi LoRa 32 V3 connected over USB.
Activate ESP-IDF first (`export.sh` or `export.ps1`), then build and flash from
`firmware/`:

```bash
cd firmware
idf.py -B build "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build
idf.py -B build -p <PORT> flash monitor
```

Replace `<PORT>` with `COM5` on Windows, `/dev/ttyUSB0` on Linux, or
`/dev/cu.usbserial-*` on macOS. Press `Ctrl+]` to exit the monitor.

## Credit

https://github.com/G-Two/smoke-x-receiver

## Notes

Not affiliated with or endorsed by ThermoWorks. Smoke X is a trademark of its owner.