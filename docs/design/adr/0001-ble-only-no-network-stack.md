# 0001 — BLE-only device with no network stack

## Status

Accepted

## Context

The phone is always the user interface for the bridge. Wi-Fi, HTTP, WebSocket,
MQTT, mDNS, a captive portal and cloud services would add provisioning, security,
discovery and RAM cost to a battery-powered recorder that has no product need for
them.

## Decision

The bridge and app communicate only over BLE. The MVP has no Wi-Fi, HTTP, WebSocket,
MQTT, mDNS, captive portal, local web UI or cloud sync. Firmware images contain no
network stack.

## Consequences

Every remote interaction is designed as a BLE characteristic or procedure. CI
fails if `http`, `web_socket`, MQTT or OTA packages are added. Diagnostics and
history are reachable only through the app and OLED, and the bridge must record
without a phone connection.
