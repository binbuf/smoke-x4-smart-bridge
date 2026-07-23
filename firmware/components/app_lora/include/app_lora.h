/* app_lora — SX1262 wrapper over the vendored ra01s driver (design 03
 * §3.1, 01 §1.5). The testable logic (params, scanner, TX guard) lives in
 * app_lora_core.h; this is the device-facing surface. */
#ifndef APP_LORA_H
#define APP_LORA_H

#include <stdbool.h>
#include <stdint.h>

#include "app_lora_core.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*app_lora_rx_cb_t)(const char *payload, int8_t rssi,
                                 int8_t snr);

/* Initialises the radio with the §1.5 parameter block. */
int app_lora_init(void);

/* Starts the polling RX task (lora_rx per tasks.h: core 1). */
int app_lora_start(app_lora_rx_cb_t cb);

/* Retunes and resumes RX; stops any scan. */
int app_lora_set_frequency(uint32_t hz);

/* Resume/stop the 915↔920 alternating sync scan (F2.5). */
void app_lora_set_scanning(bool on);

/* Guard-checked transmit (F2.3): refused unless the sync window is open
 * and the current frequency is in band. The ONLY legitimate caller is the
 * sync handler's transmit op in smoke_x.c. */
int app_lora_start_tx(const char *payload);

#ifdef __cplusplus
}
#endif

#endif /* APP_LORA_H */
