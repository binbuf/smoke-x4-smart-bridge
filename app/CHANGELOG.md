# Changelog

All notable changes to the Smoke Bridge app are recorded here. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the version matches
`pubspec.yaml` (`version: x.y.z+build`).

## 1.0.0

The first release of the rebuilt companion app (`newui/` design language).

### Added

- Live, Temps, Timeline, Graph, Settings, History and Cook-detail destinations.
- Guided cooks with target/pull guidance, a reflowing temperature scale and the
  honest freshness ladder (live / aging / stale / frozen).
- Two-tier alarms: the device's nine rules are mirrored, app insights are
  advisory. Quiet hours, escalation, test alarm and delivery verdicts.
- The real bridge integration: HTTP + WebSocket and BLE transports, a
  six-lane connection race with warm-BLE failover, a drift-backed sample cache,
  and an Android foreground service for cook monitoring.
- Onboarding: the eight-step wizard with preflight, passkey coaching and a
  troubleshoot path.
- Firmware/OTA behind the Wi-Fi-only, session-guarded, auto-rollback gate;
  diagnostics and the reviewed field report.
- CSV export byte-compatible with the device's `format=csv`.

### Notes

- The bridge is a listener, never a transmitter. The app mirrors it; it never
  re-decides device alarms and never starts or stops recording.
- A temperature is never scaled to fit: the layout reflows instead.
