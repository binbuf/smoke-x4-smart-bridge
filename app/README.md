# smoke_bridge

The Smoke X4 Smart Bridge companion app (Android-only for v1).

Layout follows design [08 §8.3](../docs/design/08-flutter-app.md):

```
lib/
├── main.dart            entry point → app/bootstrap.dart
├── app/                 router (go_router), theme (dark-first), bootstrap, error boundary
├── core/                Result/failure types, units, time, logging, extensions
├── domain/              pure Dart, ZERO Flutter imports (CI-enforced)
│   ├── entities/
│   └── analysis/
├── data/
│   ├── transport/       BridgeTransport + Http/Ble/Mock
│   ├── dto/             generated from protocol/ — do not edit records.g.dart
│   ├── local/           drift database
│   └── repos/
├── features/            onboarding · dashboard · sessions · alarms · settings · debug
└── platform/            network_binder · cook_service platform channels
```

- `minSdk 24`, `targetSdk 35`.
- `pubspec.lock` is committed; CI builds from it.
- Run against the fake bridge: `dart run sim` from the repo root (see `tools/sim`).

Verify locally with `flutter analyze`, `flutter test`, and
`flutter build apk --debug`.
