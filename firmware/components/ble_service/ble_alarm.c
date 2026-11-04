/*
 * ble_alarm.c - pure `alarm` encoder.
 *
 * Layout knowledge lives in protocol/gen/records.h. This wrapper enforces the
 * invariants the UI relies on:
 *   - only four probe bits leave the bridge;
 *   - an acknowledged bit is only set for an active alarm;
 *   - a detached/unknown threshold stays 0.
 */
#include "ble_alarm.h"

#include <string.h>

#include "records.h"

#define ALARM_PROBE_MASK ((uint8_t)((1u << BRIDGE_STATE_NUM_PROBES) - 1u))

size_t ble_alarm_encode(const bridge_state_live_t *snapshot, uint8_t *out,
                        size_t cap) {
    sx4_alarm_t alarm;

    if (snapshot == NULL || out == NULL || cap < SX4_ALARM_SIZE) {
        return 0;
    }

    memset(&alarm, 0, sizeof(alarm));
    alarm.ver = 1;
    alarm.active_mask = (uint8_t)(snapshot->alarm_active_mask & ALARM_PROBE_MASK);
    alarm.armed_mask = (uint8_t)(snapshot->alarm_armed_mask & ALARM_PROBE_MASK);
    alarm.acked_mask =
        (uint8_t)(snapshot->alarm_acked_mask & alarm.active_mask);
    for (unsigned int i = 0; i < BRIDGE_STATE_NUM_PROBES; i++) {
        const bool attached =
            (snapshot->attached_mask & (uint8_t)(1u << i)) != 0u;
        alarm.high_f10[i] = attached ? snapshot->alarm_high_f10[i] : 0;
        alarm.low_f10[i] = attached ? snapshot->alarm_low_f10[i] : 0;
    }

    return sx4_alarm_encode(&alarm, out, cap);
}
