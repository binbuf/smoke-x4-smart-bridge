/*
 * ble_live.c - pure `live` encoder (T28).
 *
 * Everything here is plain C11 and allocation-free: the same code serves the
 * GATT read fallback, the notification producer and the host byte-vector test.
 */
#include "ble_live.h"

#include <string.h>

#include "records.h"

size_t ble_live_encode(const bridge_state_live_t *snapshot, uint8_t *out,
                       size_t cap) {
    sx4_live_t live;

    if (snapshot == NULL || out == NULL || cap < SX4_LIVE_SIZE) {
        return 0;
    }

    memset(&live, 0, sizeof(live));
    live.flags =
        (uint8_t)(snapshot->flags & (uint8_t)~SX4_LIVE_FLAG_BILLOWS_OUTPUT);
    for (unsigned int i = 0; i < BRIDGE_STATE_NUM_PROBES; i++) {
        const bool attached =
            (snapshot->attached_mask & (uint8_t)(1u << i)) != 0u;
        live.temp[i] = attached ? snapshot->temp_f10[i]
                                : (int16_t)SX4_TEMP_DETACHED;
    }
    live.seq = snapshot->have_seq ? snapshot->seq : (uint32_t)SX4_SEQ_NONE;
    live.billows_target_f10 =
        snapshot->billows_target_valid ? snapshot->billows_target_f10 : 0;
    live.battery_pct = snapshot->battery_pct;
    live.rssi_lora = snapshot->rssi_lora;
    live.age_s = snapshot->age_s;

    return sx4_live_encode(&live, out, cap);
}
