/*
 * test_bridge_state.c - clock, anchor persistence and live snapshot (T20).
 *
 * Drives firmware/components/bridge_state/bridge_state.c against the real
 * bridge_config core with a RAM key/value fake and a controllable monotonic
 * clock. No ESP-IDF, no flash, no board.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "bridge_config.h"
#include "bridge_state.h"
#include "test_util.h"

#define FAKE_MAX_ENTRIES 32
#define FAKE_NAME_MAX 16
#define FAKE_VALUE_MAX 64

typedef struct {
    bool used;
    char ns[FAKE_NAME_MAX];
    char key[FAKE_NAME_MAX];
    uint8_t value[FAKE_VALUE_MAX];
    size_t len;
} fake_entry_t;

typedef struct {
    fake_entry_t entries[FAKE_MAX_ENTRIES];
    int set_calls;
} fake_t;

static void fake_init(fake_t *fake) { memset(fake, 0, sizeof(*fake)); }

static fake_entry_t *fake_find(fake_t *fake, const char *ns, const char *key) {
    for (size_t i = 0; i < FAKE_MAX_ENTRIES; i++) {
        if (fake->entries[i].used && strcmp(fake->entries[i].ns, ns) == 0 &&
            strcmp(fake->entries[i].key, key) == 0) {
            return &fake->entries[i];
        }
    }
    return NULL;
}

static fake_entry_t *fake_alloc(fake_t *fake, const char *ns,
                                const char *key) {
    fake_entry_t *entry = fake_find(fake, ns, key);
    if (entry != NULL) {
        return entry;
    }
    for (size_t i = 0; i < FAKE_MAX_ENTRIES; i++) {
        if (!fake->entries[i].used) {
            entry = &fake->entries[i];
            memset(entry, 0, sizeof(*entry));
            entry->used = true;
            snprintf(entry->ns, sizeof(entry->ns), "%s", ns);
            snprintf(entry->key, sizeof(entry->key), "%s", key);
            return entry;
        }
    }
    return NULL;
}

static int fake_get(void *ctx, const char *ns, const char *key, void *dst,
                    size_t *len) {
    fake_t *fake = ctx;
    fake_entry_t *entry = fake_find(fake, ns, key);
    if (entry == NULL) {
        return BRIDGE_CONFIG_ERR_NOT_FOUND;
    }
    if (*len < entry->len) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    memcpy(dst, entry->value, entry->len);
    *len = entry->len;
    return BRIDGE_CONFIG_OK;
}

static int fake_set(void *ctx, const char *ns, const char *key, const void *src,
                    size_t len) {
    fake_t *fake = ctx;
    if (len > FAKE_VALUE_MAX) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    fake_entry_t *entry = fake_alloc(fake, ns, key);
    if (entry == NULL) {
        return BRIDGE_CONFIG_ERR_IO;
    }
    memcpy(entry->value, src, len);
    entry->len = len;
    fake->set_calls++;
    return BRIDGE_CONFIG_OK;
}

static int fake_erase(void *ctx, const char *ns, const char *key) {
    fake_t *fake = ctx;
    fake_entry_t *entry = fake_find(fake, ns, key);
    if (entry == NULL) {
        return BRIDGE_CONFIG_ERR_NOT_FOUND;
    }
    memset(entry, 0, sizeof(*entry));
    return BRIDGE_CONFIG_OK;
}

static const bridge_config_kv_ops_t kFakeOps = {
    .get = fake_get,
    .set = fake_set,
    .erase = fake_erase,
};

static uint32_t fake_random(void *ctx) {
    (void)ctx;
    return 0x12345678u;
}

static void config_init(fake_t *fake) {
    bridge_config_kv_t kv = {.ops = &kFakeOps, .ctx = fake};
    bridge_config_set_random_source(fake_random, NULL);
    CHECK_EQ_INT(bridge_config_core_init(&kv), BRIDGE_CONFIG_OK);
}

/* ---- controllable clock -------------------------------------------------- */

typedef struct {
    uint64_t now_ms;
} clock_fake_t;

static uint64_t clock_now(void *ctx) {
    clock_fake_t *clock = ctx;
    return clock->now_ms;
}

static bridge_state_time_source_t source_for(clock_fake_t *clock) {
    bridge_state_time_source_t source = {
        .uptime_ms = clock_now,
        .ctx = clock,
    };
    return source;
}

static bridge_state_sample_t sample(uint32_t seq, int16_t p1, int16_t p2,
                                    int16_t p3, int16_t p4) {
    bridge_state_sample_t s;
    memset(&s, 0, sizeof(s));
    s.seq = seq;
    s.have_seq = true;
    s.temp_f10[0] = p1;
    s.temp_f10[1] = p2;
    s.temp_f10[2] = p3;
    s.temp_f10[3] = p4;
    s.attached_mask = 0x0Fu;
    s.rssi_lora = -77;
    s.snr_lora = 8;
    return s;
}

/* ---- tests --------------------------------------------------------------- */

static void test_fresh_boot_unknown_clock(void) {
    fake_t fake;
    fake_init(&fake);
    config_init(&fake);
    clock_fake_t clock = {.now_ms = 0};

    bridge_state_time_source_t source = source_for(&clock);
    CHECK_EQ_INT(bridge_state_core_init(&source, 0), BRIDGE_STATE_OK);

    bridge_state_clock_t now;
    CHECK_EQ_INT(bridge_state_now(&now), BRIDGE_STATE_OK);
    CHECK_EQ_UINT(now.unix_s, 0u);
    CHECK(!now.valid);
    CHECK(!now.estimated);
    CHECK_EQ_UINT(now.last_anchor_uptime_s, 0u);

    sx4_sample_rec_t rec;
    memset(&rec, 0, sizeof(rec));
    rec.flags = SX4_RECORD_FLAG_PROBE1_ATTACHED | SX4_RECORD_FLAG_CLOCK_VALID;
    CHECK_EQ_INT(bridge_state_stamp_record(&rec), BRIDGE_STATE_OK);
    CHECK_EQ_UINT(rec.unix_s, 0u);
    CHECK((rec.flags & SX4_RECORD_FLAG_CLOCK_VALID) == 0u);
    CHECK((rec.flags & SX4_RECORD_FLAG_PROBE1_ATTACHED) != 0u);

    bridge_state_live_t live;
    CHECK_EQ_INT(bridge_state_snapshot(&live), BRIDGE_STATE_OK);
    CHECK((live.flags & SX4_LIVE_FLAG_CLOCK_VALID) == 0u);
    CHECK_EQ_UINT(live.battery_pct, BRIDGE_STATE_SOC_UNKNOWN);
    CHECK_EQ_INT(live.temp_f10[0], SX4_TEMP_DETACHED);
    CHECK_EQ_UINT(live.seq, 0u);
}

static void test_set_time_persists_and_advances(void) {
    fake_t fake;
    fake_init(&fake);
    config_init(&fake);
    clock_fake_t clock = {.now_ms = 0};
    int baseline = fake.set_calls;

    bridge_state_time_source_t source = source_for(&clock);
    CHECK_EQ_INT(bridge_state_core_init(&source, 0), BRIDGE_STATE_OK);

    CHECK_EQ_INT(bridge_state_set_time(1700000000u), BRIDGE_STATE_OK);
    /* First set writes the anchor pair immediately. */
    CHECK(fake.set_calls > baseline);

    bridge_config_clock_t stored;
    CHECK_EQ_INT(bridge_config_clock_get_full(&stored), BRIDGE_CONFIG_OK);
    CHECK(stored.valid);
    CHECK_EQ_UINT(stored.anchor_s, 1700000000u);
    CHECK_EQ_UINT(stored.uptime_s, 0u);

    bridge_state_clock_t now;
    CHECK_EQ_INT(bridge_state_now(&now), BRIDGE_STATE_OK);
    CHECK_EQ_UINT(now.unix_s, 1700000000u);
    CHECK(now.valid);
    CHECK(!now.estimated);

    clock.now_ms = 5000;
    CHECK_EQ_INT(bridge_state_now(&now), BRIDGE_STATE_OK);
    CHECK_EQ_UINT(now.unix_s, 1700000005u);

    sx4_sample_rec_t rec;
    memset(&rec, 0, sizeof(rec));
    CHECK_EQ_INT(bridge_state_stamp_record(&rec), BRIDGE_STATE_OK);
    CHECK_EQ_UINT(rec.unix_s, 1700000005u);
    CHECK((rec.flags & SX4_RECORD_FLAG_CLOCK_VALID) != 0u);
}

static void test_backwards_correction_rejected(void) {
    fake_t fake;
    fake_init(&fake);
    config_init(&fake);
    clock_fake_t clock = {.now_ms = 0};
    bridge_state_time_source_t source = source_for(&clock);
    CHECK_EQ_INT(bridge_state_core_init(&source, 0), BRIDGE_STATE_OK);

    CHECK_EQ_INT(bridge_state_set_time(1700001000u), BRIDGE_STATE_OK);
    clock.now_ms = 30000; /* now 1700001030 */

    CHECK_EQ_INT(bridge_state_set_time(1700001029u), BRIDGE_STATE_ERR_TIME);
    bridge_state_clock_t now;
    CHECK_EQ_INT(bridge_state_now(&now), BRIDGE_STATE_OK);
    CHECK_EQ_UINT(now.unix_s, 1700001030u);
    CHECK(!now.estimated);

    sx4_sample_rec_t rec;
    memset(&rec, 0, sizeof(rec));
    CHECK_EQ_INT(bridge_state_stamp_record(&rec), BRIDGE_STATE_OK);
    CHECK_EQ_UINT(rec.unix_s, 1700001030u);

    /* A forward correction is accepted and applies to future records only. */
    CHECK_EQ_INT(bridge_state_set_time(1700001100u), BRIDGE_STATE_OK);
    memset(&rec, 0, sizeof(rec));
    CHECK_EQ_INT(bridge_state_stamp_record(&rec), BRIDGE_STATE_OK);
    CHECK_EQ_UINT(rec.unix_s, 1700001100u);
}

static void test_persist_cadence_not_per_sample(void) {
    fake_t fake;
    fake_init(&fake);
    config_init(&fake);
    clock_fake_t clock = {.now_ms = 0};
    bridge_state_time_source_t source = source_for(&clock);
    CHECK_EQ_INT(bridge_state_core_init(&source, 0), BRIDGE_STATE_OK);
    CHECK_EQ_INT(bridge_state_set_time(1700000000u), BRIDGE_STATE_OK);
    int after_set = fake.set_calls;

    /* Many samples and ticks inside the ten-minute window: no NVS traffic. */
    for (unsigned int i = 1; i <= 120u; i++) {
        clock.now_ms = (uint64_t)i * 1000u;
        bridge_state_sample_t s = sample(i, 100, 200, 300, 400);
        CHECK_EQ_INT(bridge_state_update(&s), BRIDGE_STATE_OK);
        CHECK_EQ_INT(bridge_state_tick(), BRIDGE_STATE_OK);
    }
    CHECK_EQ_INT(fake.set_calls, after_set);
    CHECK_EQ_UINT(clock.now_ms, 120000u);

    /* At ten minutes the anchor pair is rewritten once. */
    clock.now_ms = BRIDGE_STATE_CLOCK_PERSIST_MS;
    CHECK_EQ_INT(bridge_state_tick(), BRIDGE_STATE_OK);
    CHECK_EQ_INT(fake.set_calls, after_set + 3); /* anchor, uptime, valid */

    bridge_config_clock_t stored;
    CHECK_EQ_INT(bridge_config_clock_get_full(&stored), BRIDGE_CONFIG_OK);
    CHECK(stored.valid);
    CHECK_EQ_UINT(stored.anchor_s, 1700000000u + 600u);
    CHECK_EQ_UINT(stored.uptime_s, 600u);
}

static void test_reboot_restores_estimated_anchor(void) {
    fake_t fake;
    fake_init(&fake);
    config_init(&fake);
    clock_fake_t clock = {.now_ms = 0};
    bridge_state_time_source_t source = source_for(&clock);
    CHECK_EQ_INT(bridge_state_core_init(&source, 0), BRIDGE_STATE_OK);
    CHECK_EQ_INT(bridge_state_set_time(1700000000u), BRIDGE_STATE_OK);
    clock.now_ms = BRIDGE_STATE_CLOCK_PERSIST_MS;
    CHECK_EQ_INT(bridge_state_tick(), BRIDGE_STATE_OK);

    /* Power cycle: uptime restarts at zero, so only the anchor is known. */
    clock.now_ms = 0;
    CHECK_EQ_INT(bridge_state_core_init(&source, 0), BRIDGE_STATE_OK);
    bridge_state_clock_t now;
    CHECK_EQ_INT(bridge_state_now(&now), BRIDGE_STATE_OK);
    CHECK(now.valid);
    CHECK(now.estimated);
    CHECK_EQ_UINT(now.unix_s, 1700000600u);

    /* Same monotonic source surviving a wake advances by the uptime delta. */
    clock.now_ms = BRIDGE_STATE_CLOCK_PERSIST_MS + 50000u;
    CHECK_EQ_INT(bridge_state_core_init(&source, 0), BRIDGE_STATE_OK);
    CHECK_EQ_INT(bridge_state_now(&now), BRIDGE_STATE_OK);
    CHECK(now.estimated);
    CHECK_EQ_UINT(now.unix_s, 1700000650u);

    /* A platform-known sleep time is added when the source cannot advance. */
    clock.now_ms = 0;
    CHECK_EQ_INT(bridge_state_core_init(&source, 30), BRIDGE_STATE_OK);
    CHECK_EQ_INT(bridge_state_now(&now), BRIDGE_STATE_OK);
    CHECK(now.estimated);
    CHECK_EQ_UINT(now.unix_s, 1700000630u);
}

static void test_snapshot_updates_on_valid_sample(void) {
    fake_t fake;
    fake_init(&fake);
    config_init(&fake);
    clock_fake_t clock = {.now_ms = 1000};
    bridge_state_time_source_t source = source_for(&clock);
    CHECK_EQ_INT(bridge_state_core_init(&source, 0), BRIDGE_STATE_OK);
    CHECK_EQ_INT(bridge_state_set_time(1700000000u), BRIDGE_STATE_OK);

    bridge_state_sample_t s = sample(41, 1650, 1700, SX4_TEMP_DETACHED,
                                     SX4_TEMP_DETACHED);
    s.attached_mask = 0x03u;
    s.billows_attached = true;
    s.billows_target_f10 = 2250;
    s.billows_target_valid = true;
    CHECK_EQ_INT(bridge_state_update(&s), BRIDGE_STATE_OK);

    bridge_state_set_battery(4800, 87);
    bridge_state_set_smoke_paired(true);
    bridge_state_set_storage_ok(true);
    bridge_state_set_display_on(true);
    bridge_state_set_sync_active(true);
    bridge_state_set_billows_output(true);

    clock.now_ms += 10000u;
    bridge_state_live_t live;
    CHECK_EQ_INT(bridge_state_snapshot(&live), BRIDGE_STATE_OK);
    CHECK_EQ_UINT(live.seq, 41u);
    CHECK_EQ_INT(live.temp_f10[0], 1650);
    CHECK_EQ_INT(live.temp_f10[1], 1700);
    CHECK_EQ_INT(live.temp_f10[2], SX4_TEMP_DETACHED);
    CHECK_EQ_INT(live.temp_f10[3], SX4_TEMP_DETACHED);
    CHECK_EQ_UINT(live.attached_mask, 0x03u);
    CHECK_EQ_INT(live.age_s, 10u);
    CHECK_EQ_INT(live.rssi_lora, -77);
    CHECK_EQ_INT(live.snr_lora, 8);
    CHECK_EQ_UINT(live.battery_mv, 4800u);
    CHECK_EQ_UINT(live.battery_pct, 87u);
    CHECK_EQ_INT(live.billows_target_f10, 2250);
    CHECK(live.billows_target_valid);
    CHECK((live.flags & SX4_LIVE_FLAG_BILLOWS_ATTACHED) != 0u);
    CHECK((live.flags & SX4_LIVE_FLAG_BILLOWS_OUTPUT) != 0u);
    CHECK((live.flags & SX4_LIVE_FLAG_SMOKE_PAIRED) != 0u);
    CHECK((live.flags & SX4_LIVE_FLAG_STORAGE_OK) != 0u);
    CHECK((live.flags & SX4_LIVE_FLAG_DISPLAY_ON) != 0u);
    CHECK((live.flags & SX4_LIVE_FLAG_SYNC_ACTIVE) != 0u);
    CHECK((live.flags & SX4_LIVE_FLAG_CLOCK_VALID) != 0u);
    CHECK((live.flags & SX4_LIVE_FLAG_SMOKE_LIVE) != 0u);
    CHECK_EQ_UINT(live.uptime_s, 11u);
}

static void test_liveness_timeout(void) {
    fake_t fake;
    fake_init(&fake);
    config_init(&fake);
    clock_fake_t clock = {.now_ms = 0};
    bridge_state_time_source_t source = source_for(&clock);
    CHECK_EQ_INT(bridge_state_core_init(&source, 0), BRIDGE_STATE_OK);

    bridge_state_sample_t s = sample(1, 100, 100, 100, 100);
    CHECK_EQ_INT(bridge_state_update(&s), BRIDGE_STATE_OK);

    clock.now_ms = (uint64_t)BRIDGE_STATE_LIVE_TIMEOUT_S * 1000u;
    bridge_state_live_t live;
    CHECK_EQ_INT(bridge_state_snapshot(&live), BRIDGE_STATE_OK);
    CHECK_EQ_UINT(live.age_s, BRIDGE_STATE_LIVE_TIMEOUT_S);
    CHECK((live.flags & SX4_LIVE_FLAG_SMOKE_LIVE) != 0u);

    clock.now_ms += 1000u;
    CHECK_EQ_INT(bridge_state_snapshot(&live), BRIDGE_STATE_OK);
    CHECK_EQ_UINT(live.age_s, BRIDGE_STATE_LIVE_TIMEOUT_S + 1u);
    CHECK((live.flags & SX4_LIVE_FLAG_SMOKE_LIVE) == 0u);
}

static void test_arguments(void) {
    CHECK_EQ_INT(bridge_state_core_init(NULL, 0), BRIDGE_STATE_ERR_ARGUMENT);
    CHECK_EQ_INT(bridge_state_now(NULL), BRIDGE_STATE_ERR_ARGUMENT);
    CHECK_EQ_INT(bridge_state_snapshot(NULL), BRIDGE_STATE_ERR_ARGUMENT);
    CHECK_EQ_INT(bridge_state_update(NULL), BRIDGE_STATE_ERR_ARGUMENT);
    CHECK_EQ_INT(bridge_state_stamp_record(NULL), BRIDGE_STATE_ERR_ARGUMENT);

    CHECK_EQ_INT(bridge_config_clock_set_full(NULL), BRIDGE_CONFIG_ERR_INVALID);
    bridge_config_clock_t bad = {.anchor_s = 0, .valid = true};
    CHECK_EQ_INT(bridge_config_clock_set_full(&bad),
                 BRIDGE_CONFIG_ERR_INVALID);
}

static void test_factory_reset_clears_anchor_pair(void) {
    fake_t fake;
    fake_init(&fake);
    config_init(&fake);
    clock_fake_t clock = {.now_ms = 0};
    bridge_state_time_source_t source = source_for(&clock);
    CHECK_EQ_INT(bridge_state_core_init(&source, 0), BRIDGE_STATE_OK);
    CHECK_EQ_INT(bridge_state_set_time(1700000000u), BRIDGE_STATE_OK);

    bridge_config_clock_t stored;
    CHECK_EQ_INT(bridge_config_clock_get_full(&stored), BRIDGE_CONFIG_OK);
    CHECK(stored.valid);

    CHECK_EQ_INT(bridge_config_factory_reset(), BRIDGE_CONFIG_OK);
    CHECK_EQ_INT(bridge_config_clock_get_full(&stored), BRIDGE_CONFIG_OK);
    CHECK(!stored.valid);
    CHECK_EQ_UINT(stored.anchor_s, 0u);
    CHECK_EQ_UINT(stored.uptime_s, 0u);

    clock.now_ms = 0;
    CHECK_EQ_INT(bridge_state_core_init(&source, 0), BRIDGE_STATE_OK);
    bridge_state_clock_t now;
    CHECK_EQ_INT(bridge_state_now(&now), BRIDGE_STATE_OK);
    CHECK(!now.valid);
    CHECK_EQ_UINT(now.unix_s, 0u);
}

static int s_change_calls;
static uint32_t s_change_seq;

static void change_hook(void *ctx) {
    (void)ctx;
    s_change_calls++;
    bridge_state_live_t live;
    if (bridge_state_snapshot(&live) == BRIDGE_STATE_OK) {
        s_change_seq = live.have_seq ? live.seq : SX4_SEQ_NONE;
    }
}

static void test_change_hook_for_live_notify(void) {
    fake_t fake;
    fake_init(&fake);
    config_init(&fake);
    clock_fake_t clock = {.now_ms = 0};
    bridge_state_time_source_t source = source_for(&clock);
    CHECK_EQ_INT(bridge_state_core_init(&source, 0), BRIDGE_STATE_OK);

    s_change_calls = 0;
    s_change_seq = 0;
    bridge_state_set_change_hook(change_hook, NULL);

    /* A new stored sample publishes once and reports its sequence. */
    bridge_state_sample_t s = sample(9, 100, 200, 300, 400);
    CHECK_EQ_INT(bridge_state_update(&s), BRIDGE_STATE_OK);
    CHECK_EQ_UINT(s_change_calls, 1u);
    CHECK_EQ_UINT(s_change_seq, 9u);

    /* Setting the same flag value is not a transition. */
    bridge_state_set_smoke_paired(true);
    CHECK_EQ_UINT(s_change_calls, 2u);
    bridge_state_set_smoke_paired(true);
    CHECK_EQ_UINT(s_change_calls, 2u);
    bridge_state_set_smoke_paired(false);
    CHECK_EQ_UINT(s_change_calls, 3u);

    /* A successful clock set changes clock_valid and notifies. */
    CHECK_EQ_INT(bridge_state_set_time(1700000000u), BRIDGE_STATE_OK);
    CHECK_EQ_UINT(s_change_calls, 4u);

    bridge_state_set_change_hook(NULL, NULL);
    bridge_state_set_display_on(true);
    CHECK_EQ_UINT(s_change_calls, 4u);
}

int main(void) {
    test_arguments();
    test_fresh_boot_unknown_clock();
    test_set_time_persists_and_advances();
    test_backwards_correction_rejected();
    test_persist_cadence_not_per_sample();
    test_reboot_restores_estimated_anchor();
    test_snapshot_updates_on_valid_sample();
    test_liveness_timeout();
    test_factory_reset_clears_anchor_pair();
    test_change_hook_for_live_notify();
    return sx4_test_summary("bridge-state");
}
