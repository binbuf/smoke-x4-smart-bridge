/*
 * ble_control.h - `control` dispatcher and `result` encoder (T29).
 *
 * The core is plain C11 and allocation-free: it parses the control envelope,
 * validates the whole op body before acting, executes the V0 ops and produces
 * one result record. The NimBLE access callback only copies the mbuf, calls
 * ble_control_handle(), then splits the encoded result at MTU-3.
 *
 * Op coverage in T29:
 *   - op 1 set_time is live and updates bridge_state;
 *   - op 6 set_billows_target is reserved and always unsupported;
 *   - ops 2,3,4,5,7 understand their body shape but answer unsupported until
 *     T48 installs the destructive handlers. Their reply-first contract is the
 *     action + delay pair in ble_control_result_t.
 */
#ifndef SX4_BLE_CONTROL_H
#define SX4_BLE_CONTROL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "records.h"

#ifdef __cplusplus
extern "C" {
#endif

/* result is five header bytes plus at most 59 detail bytes (design 05 5.6). */
#define BLE_CONTROL_DETAIL_MAX (SX4_RESULT_SIZE - 5u)

/*
 * ATT error values owned by the contract (design 05 5.5). They match NimBLE's
 * BLE_ATT_ERR_* values; ble_service.c static-asserts that at compile time.
 */
#define BLE_CONTROL_ATT_OK 0
#define BLE_CONTROL_ATT_INSUFFICIENT_ENC 0x0Fu
#define BLE_CONTROL_ATT_INSUFFICIENT_AUTHEN 0x05u

/*
 * Destructive ops reply first, then act after a short delay so the result
 * notification can leave before the link drops or the device reboots.
 * T48 registers an action handler and fills result.action for accepted ops.
 */
#define BLE_CONTROL_ACTION_DELAY_MS 250u

typedef enum {
    BLE_CONTROL_ACTION_NONE = 0,
    BLE_CONTROL_ACTION_FORGET_PHONE,
    BLE_CONTROL_ACTION_FACTORY_RESET,
    BLE_CONTROL_ACTION_POWER_OFF,
    BLE_CONTROL_ACTION_CLEAR_HISTORY,
    BLE_CONTROL_ACTION_UNPAIR_SMOKE_X,
} ble_control_action_t;

/*
 * Deferred action runner. Returns an SX4_RESULT_STATUS_* value for the log; the
 * `result` was already notified, so this cannot change it.
 */
typedef uint8_t (*ble_control_action_fn)(ble_control_action_t action, void *ctx);

typedef struct {
    uint8_t ver;    /* always 1 on the wire */
    uint8_t op;     /* echoed from the request */
    uint8_t op_id;  /* echoed unchanged from the request */
    uint8_t status; /* SX4_RESULT_STATUS_* */
    char detail[BLE_CONTROL_DETAIL_MAX + 1u]; /* NUL-terminated in RAM */
    uint8_t action;       /* ble_control_action_t; NONE for set_time */
    uint16_t action_delay_ms; /* reply-first delay before action runs */
} ble_control_result_t;

/*
 * Parse and execute one `control` write. `out` is always filled (status +
 * echoed op/op_id + a human detail) even for a malformed write. Returns
 * out->status for convenience; `out` may be NULL, in which case the call
 * returns SX4_RESULT_STATUS_INVALID.
 *
 * A write shorter than the 3-byte envelope, a wrong ver, an op body of the
 * wrong size, or a set_time body whose time is zero changes nothing.
 */
uint8_t ble_control_handle(const uint8_t *in, size_t in_len,
                           ble_control_result_t *out);

/*
 * Encode the variable result: ver, op, op_id, status, len, detail[len].
 * `detail` is truncated to 59 bytes and never splits a UTF-8 sequence.
 * Returns the encoded length (5..64) or 0 on a bad argument/short buffer.
 */
size_t ble_control_encode_result(const ble_control_result_t *result,
                                 uint8_t *out, size_t cap);

/* Human default text for each status 0..7; never the branch condition. */
const char *ble_control_status_detail(uint8_t status);

/*
 * The `control` write requires an encrypted and authenticated link. Returns
 * BLE_CONTROL_ATT_OK, BLE_CONTROL_ATT_INSUFFICIENT_ENC or
 * BLE_CONTROL_ATT_INSUFFICIENT_AUTHEN.
 */
int ble_control_write_security(bool encrypted, bool authenticated);

/* T48 seam: install the reply-first action runner (NULL unregisters). */
void ble_control_set_action_handler(ble_control_action_fn fn, void *ctx);

/* Run a deferred action after its result notification has been handed off.
 * Returns the backend status (SX4_RESULT_STATUS_OK, a failure status, or
 * UNSUPPORTED when no handler is installed). */
uint8_t ble_control_run_action(ble_control_action_t action);

#ifdef __cplusplus
}
#endif

#endif /* SX4_BLE_CONTROL_H */
