/* smoke_x_ctrl — pairing, watchdog, and accounting (design 02 §2.4–§2.7). */
#include "smoke_x_ctrl.h"

#include <string.h>

#include "app_config_store.h"
#include "smoke_x_parser.h"

static const smoke_x_ops_t *s_ops;
static void *s_ctx;
static bool s_rescan_enabled;

static smoke_x_pair_state_t s_state;
static smoke_x_stats_t s_stats;

/* RAM copy of the pairing; persisted only on CONFIRMED (§2.4). */
static char s_device_id[SMOKE_X_DEVICE_ID_LEN];
static uint32_t s_frequency;

static uint64_t s_last_valid_ms; /* last accepted state message (or boot) */
static bool s_have_last_packet;
static uint64_t s_last_packet_ms; /* for the interval histogram */
static bool s_base_lost;

static void publish(smoke_x_evt_t evt, const void *payload) {
    s_ops->publish(s_ctx, evt, payload);
}

static void record_interval(uint64_t now_ms) {
    if (s_have_last_packet) {
        const uint64_t d = now_ms - s_last_packet_ms;
        const int bucket = d < 15000    ? 0
                           : d < 45000  ? 1
                           : d < 90000  ? 2
                           : d < 300000 ? 3
                                        : 4;
        s_stats.interval_hist[bucket]++;
    }
    s_have_last_packet = true;
    s_last_packet_ms = now_ms;
}

static int handle_sync(const char *payload, uint64_t now_ms) {
    if (s_state != SMOKE_X_UNPAIRED) {
        /* Once sync_received is set, further syncs are ignored until an
         * explicit unpair (§2.4). */
        s_stats.sync_ignored++;
        return -1;
    }
    smoke_x_sync_t sync;
    if (smoke_x_parser_parse_sync(payload, &sync) != 0) {
        s_stats.parse_fail++;
        return -1;
    }
    /* A corrupted sync could decode to any uint32; range-check BEFORE
     * retuning — transmitting outside the ISM band is illegal (§2.5 inv 4). */
    if (sync.frequency < SMOKE_X_RF_MIN_HZ ||
        sync.frequency > SMOKE_X_RF_MAX_HZ) {
        s_stats.parse_fail++;
        return -1;
    }
    memcpy(s_device_id, sync.device_id, sizeof s_device_id);
    s_frequency = sync.frequency;

    /* Retune first: the ACK goes out on the operating frequency, never the
     * sync channel (§2.5 inv 3). */
    if (s_ops->set_frequency(s_ctx, s_frequency) != 0) {
        return -1;
    }
    char ack[32];
    if (smoke_x_parser_format_success(s_device_id, ack, sizeof ack) < 0) {
        return -1;
    }
    /* The single permitted transmission per pairing (§2.5 inv 1). */
    (void)s_ops->transmit(s_ctx, ack);

    s_state = SMOKE_X_SYNC_RECEIVED;
    s_last_valid_ms = now_ms;
    publish(SMOKE_X_EVT_SYNCED, &sync);
    return 0;
}

static int handle_state(const char *payload, unsigned int num_probes,
                        int8_t rssi, int8_t snr, uint64_t now_ms) {
    if (s_state == SMOKE_X_UNPAIRED) {
        /* State traffic from someone else's cook while we scan. */
        s_stats.id_mismatch++;
        return -1;
    }
    smoke_x_sample_t sample;
    if (smoke_x_parser_parse_state(payload, num_probes, &sample.state) != 0) {
        s_stats.parse_fail++;
        return -1;
    }
    /* Two Smoke X units in range must not interleave into one graph
     * (F3.4): drop and count anything from a foreign device. */
    if (strncmp(sample.state.device_id, s_device_id, sizeof s_device_id) !=
        0) {
        s_stats.id_mismatch++;
        return -1;
    }

    if (s_state == SMOKE_X_SYNC_RECEIVED) {
        /* Probe count is learned from the first state message, never the
         * sync — this is the moment the pairing is persisted (§2.4). */
        app_config_pairing_t p = {
            .frequency = s_frequency,
            .num_probes = num_probes,
        };
        memcpy(p.device_id, s_device_id, sizeof p.device_id);
        if (app_config_store_set_pairing(&p) != APP_CONFIG_OK) {
            return -1;
        }
        s_state = SMOKE_X_CONFIRMED;
        publish(SMOKE_X_EVT_PAIRED, NULL);
    }

    s_stats.valid++;
    s_stats.last_rssi = rssi;
    s_stats.last_snr = snr;
    record_interval(now_ms);
    s_last_valid_ms = now_ms;
    if (s_base_lost) {
        s_base_lost = false;
        publish(SMOKE_X_EVT_BASE_FOUND, NULL);
    }

    sample.rssi = rssi;
    sample.snr = snr;
    sample.t_ms = now_ms;
    publish(SMOKE_X_EVT_SAMPLE, &sample);
    return 0;
}

int smoke_x_ctrl_on_payload(const char *payload, int8_t rssi, int8_t snr,
                            uint64_t now_ms) {
    if (!s_ops || !payload) {
        return -1;
    }
    const unsigned int commas = smoke_x_parser_count_commas(payload);
    if (commas == SMOKE_X_PARSER_NUM_COMMAS_SYNC) {
        return handle_sync(payload, now_ms);
    }
    const unsigned int probes = smoke_x_parser_probes_for_commas(commas);
    if (probes != 0) {
        return handle_state(payload, probes, rssi, snr, now_ms);
    }
    s_stats.unknown_commas++;
    return -1;
}

void smoke_x_ctrl_note_crc_error(void) { s_stats.crc_fail++; }

void smoke_x_ctrl_tick(uint64_t now_ms) {
    if (!s_ops || s_state != SMOKE_X_CONFIRMED) {
        return;
    }
    const uint64_t silent_ms = now_ms - s_last_valid_ms;

    if (!s_base_lost && silent_ms >= SMOKE_X_BASE_LOST_TIMEOUT_MS) {
        s_base_lost = true;
        publish(SMOKE_X_EVT_BASE_LOST, NULL);
    }

    /* Default off: silently re-pairing to a different base would be worse
     * than staying put (§2.7). Never while a cook is active. */
    if (s_rescan_enabled && silent_ms >= SMOKE_X_RESCAN_TIMEOUT_MS) {
        uint32_t active_id = 0;
        if (app_config_store_get_u32(APP_CONFIG_SESSION_ACTIVE_ID,
                                     &active_id) == APP_CONFIG_OK &&
            active_id == 0) {
            /* Resume scanning without clearing the persisted pairing; a
             * fresh sync overwrites it, silence changes nothing. */
            s_state = SMOKE_X_UNPAIRED;
            s_base_lost = false;
            publish(SMOKE_X_EVT_RESCAN, NULL);
            s_ops->start_scan(s_ctx);
        }
    }
}

int smoke_x_ctrl_unpair(void) {
    if (!s_ops) {
        return -1;
    }
    if (app_config_store_clear_pairing() != APP_CONFIG_OK) {
        return -1;
    }
    memset(s_device_id, 0, sizeof s_device_id);
    s_frequency = 0;
    s_state = SMOKE_X_UNPAIRED;
    s_base_lost = false;
    publish(SMOKE_X_EVT_UNPAIRED, NULL);
    s_ops->start_scan(s_ctx);
    return 0;
}

smoke_x_pair_state_t smoke_x_ctrl_state(void) { return s_state; }

const smoke_x_stats_t *smoke_x_ctrl_stats(void) { return &s_stats; }

uint64_t smoke_x_ctrl_last_valid_ms(void) { return s_last_valid_ms; }

bool smoke_x_ctrl_base_lost(void) { return s_base_lost; }

uint32_t smoke_x_ctrl_frequency_hz(void) { return s_frequency; }

int smoke_x_ctrl_init(const smoke_x_ops_t *ops, void *ctx,
                      bool rescan_enabled, uint64_t now_ms) {
    if (!ops || !ops->set_frequency || !ops->transmit || !ops->start_scan ||
        !ops->publish) {
        return -1;
    }
    s_ops = ops;
    s_ctx = ctx;
    s_rescan_enabled = rescan_enabled;
    memset(&s_stats, 0, sizeof s_stats);
    s_base_lost = false;
    s_have_last_packet = false;
    s_last_valid_ms = now_ms;

    app_config_pairing_t p;
    if (app_config_store_get_pairing(&p) == APP_CONFIG_OK) {
        memcpy(s_device_id, p.device_id, sizeof s_device_id);
        s_frequency = p.frequency;
        s_state = SMOKE_X_CONFIRMED;
        return s_ops->set_frequency(s_ctx, s_frequency);
    }
    memset(s_device_id, 0, sizeof s_device_id);
    s_frequency = 0;
    s_state = SMOKE_X_UNPAIRED;
    s_ops->start_scan(s_ctx);
    return 0;
}
