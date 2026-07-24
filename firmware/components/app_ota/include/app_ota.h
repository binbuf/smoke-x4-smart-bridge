/* app_ota.h — the ESP-IDF-facing half of F14.
 *
 * The decisions live in app_ota_core.h (image inspection, admission, the
 * phase machine) and app_ota_gate.h (design 03 §3.7's health gate), both
 * ESP-IDF-free and host-tested. This header is only what `main` and
 * `app_api` need.
 */
#ifndef APP_OTA_H
#define APP_OTA_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "app_ota_core.h"
#include "app_ota_gate.h"

#ifdef __cplusplus
extern "C" {
#endif

/* The three facts the gate cannot read for itself. main.c supplies them,
 * because it is the only place that knows every subsystem came up. */
typedef struct {
    bool (*storage_mounted)(void);
    bool (*net_settled)(void);
    bool (*httpd_listening)(void);
} app_ota_gate_hooks_t;

/* Boot step 16 (03 §3.4). ARMS the gate and returns immediately — the
 * verdict lands up to APP_OTA_GATE_UPTIME_S later, on an esp_timer. No
 * new task row. */
int app_ota_init(const app_ota_gate_hooks_t *hooks);

/* Current verdict, for GET /api/v1/status. `failed_mask` may be NULL. */
app_ota_gate_verdict_t app_ota_gate_state(uint32_t *failed_mask);

/* "ota_0" / "ota_1" / "factory", and whether the running image is still
 * awaiting confirmation. */
const char *app_ota_running_slot(void);
bool app_ota_pending_verify(void);

/* True once the gate has returned FAIL — ORed into app_alarm's
 * system_fault fact so the app can say the update did not confirm. */
bool app_ota_gate_failed(void);

/* The real esp_ota_* ops, for app_api's POST /ota handler. */
const app_ota_ops_t *app_ota_flash_ops(void);

/* The one upload session. Single-writer by construction: admission
 * refuses a second with 503 ota_in_progress. */
app_ota_session_t *app_ota_the_session(void);

#ifdef __cplusplus
}
#endif

#endif /* APP_OTA_H */
