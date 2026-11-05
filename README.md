# Smoke X4 Smart Bridge

Add Bluetooth and WiFi capabilities to your **Thermoworks Smoke X4**. Use your Android or iOS device and an inexpensive **Heltec WiFi LoRa 32 (V3)** to use as a wireless Smart Bridge to Smoke X4. See live temps, alarms, and get session cook history.

## Getting Started

Building the mobile app requires Flutter 3.47.8+ (Dart 3.13.7+). 

### Android app

```bash
cd app
flutter pub get
flutter run            # debug build on a connected device or emulator
flutter build apk      # release APK in build/app/outputs/flutter-apk/
```

Requires Android toolchain.

### iOS app

TODO

### ESP32 Bridge Firmware

Requires ESP-IDF 6.0.2 or later. Build and flash from `firmware/`:

```bash
cd firmware
idf.py -B build "-DSDKCONFIG_DEFAULTS=sdkconfig.defaults;sdkconfig.defaults.heltec-v3" build
idf.py -B build -p <PORT> flash monitor
```

Replace `<PORT>` with `COM5` on Windows, `/dev/ttyUSB0` on Linux, or
`/dev/cu.usbserial-*` on macOS.

## Credit

https://github.com/G-Two/smoke-x-receiver

## Notes

Should be compatible with Smoke X2 as well but untested.

Not affiliated with or endorsed by ThermoWorks. Smoke X is a trademark of its owner.