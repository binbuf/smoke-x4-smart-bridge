/*
 * esp_wifi_stub.c - deliberately empty Wi-Fi component override (T27).
 *
 * The BLE-only image must not contain Wi-Fi code. See CMakeLists.txt and
 * ADR 0034; the headers stay available for NimBLE, but there is no Wi-Fi
 * implementation to call.
 */
#include <stdint.h>

/* Keeps the archive non-empty for the IDF build system. */
const uint32_t sx4_esp_wifi_stub_marker = 0;
