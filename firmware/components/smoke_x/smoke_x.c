/* smoke_x — device glue (F2/F3 wiring): radio ops for the controller,
 * BRIDGE_EVENT publication, novelty + packet-ring observation. All the
 * logic lives in the host-tested modules; this file only connects them. */
#include "smoke_x.h"

#include <string.h>

#include "app_config_store.h"
#include "app_lora.h"
#include "bridge_event.h"
#include "cook_novelty_log.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "record_gen.h"
#include "sdkconfig.h"

static const char *TAG = "smoke_x";

static uint64_t now_ms(void) {
    return (uint64_t)esp_timer_get_time() / 1000u;
}

/* ── Controller ops ────────────────────────────────────────────────────── */

static int ops_set_frequency(void *ctx, uint32_t hz) {
    (void)ctx;
    return app_lora_set_frequency(hz);
}

static int ops_transmit(void *ctx, const char *payload) {
    (void)ctx;
    /* The sync window exists only for the duration of this op — the ONLY
     * path that can reach TX (F2.3, 02 §2.5 invariant 1). */
    app_lora_guard_open_sync_window();
    const int rc = app_lora_start_tx(payload);
    app_lora_guard_close_sync_window();
    return rc;
}

static void ops_start_scan(void *ctx) {
    (void)ctx;
    app_lora_set_scanning(true);
}

/* Canonical storage is tenths °F; a °C-sourced packet upsamples on the
 * way in (04 §4.2: F10 = C10 × 9 / 5 + 320). */
static int16_t to_f10(int16_t v, smoke_x_units_t units) {
    if (v == SMOKE_X_TEMP_DETACHED || v == SMOKE_X_TEMP_INVALID) {
        return v;
    }
    if (units == SMOKE_X_UNITS_F) {
        return v;
    }
    return (int16_t)(((int32_t)v * 9) / 5 + 320);
}

static void publish_sample(const smoke_x_sample_t *s) {
    bridge_evt_sample_t evt = {0};
    /* Session-relative t is assigned by the cook_store drain task, which
     * knows the session start; uptime seconds ride along here. */
    evt.t_rel_s = (uint32_t)(s->t_ms / 1000u);
    evt.num_probes = s->state.num_probes;
    evt.rssi = s->rssi;
    evt.snr = s->snr;
    for (int i = 0; i < 4; i++) {
        evt.temp_f10[i] =
            i < s->state.num_probes
                ? to_f10(s->state.probes[i].temp_x10, s->state.units)
                : BRIDGE_TEMP_DETACHED;
        if (i < s->state.num_probes && s->state.probes[i].alarm_armed) {
            evt.flags |= (uint8_t)(1u << i);
        }
    }
    if (s->state.billows_attached) {
        evt.flags |= BRIDGE_SAMPLE_REC_FLAGS_BILLOWS;
    }
    if (s->state.new_alarm) {
        evt.flags |= BRIDGE_SAMPLE_REC_FLAGS_NEW_ALARM;
    }
    if (s->state.units == SMOKE_X_UNITS_C) {
        evt.flags |= BRIDGE_SAMPLE_REC_FLAGS_SOURCE_CELSIUS;
    }
    (void)bridge_event_post(BRIDGE_EVT_SAMPLE, &evt, sizeof evt);
}

static void publish_pairing(bridge_pairing_state_t state) {
    bridge_evt_pairing_t evt = {0};
    evt.state = (uint8_t)state;
    app_config_pairing_t p;
    if (app_config_store_get_pairing(&p) == APP_CONFIG_OK) {
        memcpy(evt.device_id, p.device_id, sizeof evt.device_id);
        evt.frequency_hz = p.frequency;
        evt.num_probes = (uint8_t)p.num_probes;
    }
    (void)bridge_event_post(BRIDGE_EVT_PAIRING, &evt, sizeof evt);
}

static void ops_publish(void *ctx, smoke_x_evt_t evt, const void *payload) {
    (void)ctx;
    switch (evt) {
        case SMOKE_X_EVT_SAMPLE:
            publish_sample(payload);
            break;
        case SMOKE_X_EVT_SYNCED:
            publish_pairing(BRIDGE_PAIRING_SYNCED);
            break;
        case SMOKE_X_EVT_PAIRED:
            publish_pairing(BRIDGE_PAIRING_PAIRED);
            break;
        case SMOKE_X_EVT_UNPAIRED:
        case SMOKE_X_EVT_RESCAN:
            publish_pairing(BRIDGE_PAIRING_UNPAIRED);
            break;
        case SMOKE_X_EVT_BASE_LOST: {
            uint32_t silent_s = 0;
            (void)bridge_event_post(BRIDGE_EVT_BASE_LOST, &silent_s,
                                    sizeof silent_s);
            break;
        }
        case SMOKE_X_EVT_BASE_FOUND:
            (void)bridge_event_post(BRIDGE_EVT_BASE_FOUND, NULL, 0);
            break;
    }
}

static const smoke_x_ops_t k_ops = {
    .set_frequency = ops_set_frequency,
    .transmit = ops_transmit,
    .start_scan = ops_start_scan,
    .publish = ops_publish,
};

/* ── RX path ───────────────────────────────────────────────────────────── */

static void novelty_sink(const smoke_x_novelty_entry_t *e, void *ctx) {
    (void)ctx;
    const char *reason = smoke_x_novelty_reason_name(e->reason);
    ESP_LOGI(TAG, "novelty[%s] %s: %s", reason, e->value, e->payload);
    /* Pinned persistence (F4.3): the evidence survives on /cooks. */
    (void)cook_novelty_log_append(e->t_ms, reason, e->value, e->payload);
    if (e->prev_payload[0] != '\0') {
        (void)cook_novelty_log_append(e->t_ms, reason, "prev",
                                      e->prev_payload);
    }
}

static void on_rx(const char *payload, int8_t rssi, int8_t snr) {
    const uint64_t t = now_ms();
    smoke_x_pktring_push(payload, rssi, snr, t);
    app_config_pairing_t p;
    const char *paired_id =
        app_config_store_get_pairing(&p) == APP_CONFIG_OK ? p.device_id : "";
    smoke_x_novelty_observe(payload, paired_id, rssi, snr, t);
    (void)smoke_x_ctrl_on_payload(payload, rssi, snr, t);
}

static void tick_cb(void *arg) {
    (void)arg;
    smoke_x_ctrl_tick(now_ms());
}

int smoke_x_init(void) {
    if (app_lora_init() != 0) {
        return -1;
    }
    smoke_x_pktring_reset();
    smoke_x_novelty_init(novelty_sink, NULL);
    const bool rescan =
#ifdef CONFIG_SMOKEBRIDGE_RESCAN_ENABLED
        true;
#else
        false;
#endif
    return smoke_x_ctrl_init(&k_ops, NULL, rescan, now_ms());
}

int smoke_x_start(void) {
    if (app_lora_start(on_rx) != 0) {
        return -1;
    }
    static esp_timer_handle_t tick_timer;
    const esp_timer_create_args_t args = {.callback = tick_cb,
                                          .name = "smoke_x_tick"};
    if (esp_timer_create(&args, &tick_timer) != ESP_OK) {
        return -1;
    }
    return esp_timer_start_periodic(tick_timer, 1000000) == ESP_OK ? 0 : -1;
}
