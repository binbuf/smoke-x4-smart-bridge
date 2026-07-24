/* app_ota_gate — design 03 §3.7's rollback health gate, as a pure
 * verdict (F14.3).
 *
 * A freshly OTA'd image is `pending verify`; boot step 16 only calls
 * esp_ota_mark_app_valid_cancel_rollback() once this passes. Fail, and
 * the NEXT reset rolls back.
 *
 * Two clauses are deliberately NOT the literal reading of §3.7, and the
 * argument for each is in docs/tasks/M6-hardening-and-release.md:
 *
 *   1. §3.7 says "LittleFS mounted, both partitions". Taken literally
 *      that can never pass — D13 declares `www` and leaves it UNFORMATTED
 *      on purpose, app_api deliberately does not mount it, and
 *      ops_www_available() returns a hardcoded false. A gate that
 *      requires a mount the product intentionally does not perform is not
 *      a safety feature, it is a brick. The clause is `cooks`.
 *
 *   2. "120 s of uptime with no panic" is only observable as THIS BOOT'S
 *      reset reason — a panic reboots, so a running image cannot report
 *      one it suffered. PANIC / TASK_WDT / INT_WDT are the image's fault
 *      and fail immediately. BROWNOUT / POWERON / SW are the world's: a
 *      pack that sagged during a Wi-Fi TX burst says nothing about
 *      whether the firmware is sound.
 */
#ifndef APP_OTA_GATE_H
#define APP_OTA_GATE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define APP_OTA_GATE_UPTIME_S 120u

/* Bit (n) set = clause n failed. */
#define APP_OTA_GATE_CLAUSE_STORAGE (1u << 0)
#define APP_OTA_GATE_CLAUSE_NET (1u << 1)
#define APP_OTA_GATE_CLAUSE_HTTPD (1u << 2)
#define APP_OTA_GATE_CLAUSE_CRASH (1u << 3)

typedef struct {
    /* The running image is awaiting confirmation. False for a
     * USB-flashed image, which has nothing to confirm. */
    bool pending_verify;
    bool storage_mounted;  /* `cooks` mounted and writable */
    bool net_settled;      /* AP started, or STA has an IP */
    bool httpd_listening;
    bool reset_was_crash;  /* panic / task WDT / interrupt WDT */
    uint32_t uptime_s;
} app_ota_gate_facts_t;

typedef enum {
    /* Not pending verify: there is nothing to confirm or roll back, and
     * doing either would be a bug. */
    APP_OTA_GATE_NOT_APPLICABLE = 0,
    APP_OTA_GATE_WAITING,
    APP_OTA_GATE_PASS,
    APP_OTA_GATE_FAIL,
} app_ota_gate_verdict_t;

/* `failed_mask` (optional) names EVERY failing clause, not just the
 * first — "the health gate failed" with no detail is the same useless
 * sentence as "invalid image". */
app_ota_gate_verdict_t app_ota_gate_eval(const app_ota_gate_facts_t *facts,
                                         uint32_t *failed_mask);

const char *app_ota_gate_verdict_str(app_ota_gate_verdict_t v);

/* Renders a mask as "storage,net,httpd,crash". Always NUL-terminates;
 * returns the number of characters written. */
size_t app_ota_gate_clauses_str(uint32_t mask, char *out, size_t cap);

#ifdef __cplusplus
}
#endif

#endif /* APP_OTA_GATE_H */
