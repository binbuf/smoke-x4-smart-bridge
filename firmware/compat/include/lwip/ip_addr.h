/*
 * Minimal lwip/ip_addr.h compatibility shim.
 *
 * ESP-IDF 6's esp_wifi component ships esp_mesh.h, which unconditionally does
 * `#include "lwip/ip_addr.h"`. When CONFIG_ESP_WIFI_ENABLED is off the component
 * only compiles its inert netif stubs and lwip is not in the image, but
 * esp_common's generated esp_err_to_name.c still sees esp_mesh.h through its
 * optional requires and fails to compile without the header.
 *
 * esp_mesh.h does not actually use any lwip type from this header, so an empty
 * shim is enough. It is only on the include path to keep the BLE-only image
 * free of the real network stack (ADR 0034); no lwip symbol is linked.
 */
#ifndef SX4_COMPAT_LWIP_IP_ADDR_H
#define SX4_COMPAT_LWIP_IP_ADDR_H

#endif /* SX4_COMPAT_LWIP_IP_ADDR_H */
