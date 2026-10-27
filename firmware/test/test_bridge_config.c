/*
 * test_bridge_config.c - typed NVS store coverage (T15).
 *
 * Drives firmware/components/bridge_config/bridge_config.c against a RAM
 * key/value fake that speaks the same byte seam as the ESP-IDF NVS adapter.
 * No ESP-IDF, no flash, no board.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "bridge_config.h"
#include "test_util.h"

#define FAKE_MAX_ENTRIES 64
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
    int fail_set_in; /* 0 = fail the next set; -1 = never */
    int set_calls;
} fake_t;

static void fake_init(fake_t *fake) {
    memset(fake, 0, sizeof(*fake));
    fake->fail_set_in = -1;
}

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

static bool fake_has(fake_t *fake, const char *ns, const char *key) {
    return fake_find(fake, ns, key) != NULL;
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
    if (fake->fail_set_in >= 0) {
        if (fake->fail_set_in == 0) {
            fake->fail_set_in = -1;
            return BRIDGE_CONFIG_ERR_IO;
        }
        fake->fail_set_in--;
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

static bridge_config_kv_t fake_kv(fake_t *fake) {
    bridge_config_kv_t kv = {.ops = &kFakeOps, .ctx = fake};
    return kv;
}

/* Deterministic random sequence so a changed generation is visible. */
typedef struct {
    uint32_t values[16];
    size_t count;
    size_t index;
} random_seq_t;

static uint32_t seq_random(void *ctx) {
    random_seq_t *seq = ctx;
    uint32_t value = seq->values[seq->index % seq->count];
    seq->index++;
    return value;
}

static int g_bond_clear_calls;

static int fake_bond_clear(void *ctx) {
    (void)ctx;
    g_bond_clear_calls++;
    return 0;
}

static void install_hooks(random_seq_t *seq) {
    bridge_config_set_random_source(seq_random, seq);
    g_bond_clear_calls = 0;
    bridge_config_set_bond_clear_hook(fake_bond_clear, NULL);
}

static bool fake_read_u16(fake_t *fake, const char *ns, const char *key,
                          uint16_t *out) {
    fake_entry_t *entry = fake_find(fake, ns, key);
    if (entry == NULL || entry->len != 2) {
        return false;
    }
    *out = (uint16_t)(entry->value[0] | (entry->value[1] << 8));
    return true;
}

static bool fake_read_u32(fake_t *fake, const char *ns, const char *key,
                          uint32_t *out) {
    fake_entry_t *entry = fake_find(fake, ns, key);
    if (entry == NULL || entry->len != 4) {
        return false;
    }
    *out = (uint32_t)entry->value[0] | ((uint32_t)entry->value[1] << 8) |
           ((uint32_t)entry->value[2] << 16) |
           ((uint32_t)entry->value[3] << 24);
    return true;
}

static bool fake_read_u8(fake_t *fake, const char *ns, const char *key,
                         uint8_t *out) {
    fake_entry_t *entry = fake_find(fake, ns, key);
    if (entry == NULL || entry->len != 1) {
        return false;
    }
    *out = entry->value[0];
    return true;
}

static uint32_t init_with(fake_t *fake, random_seq_t *seq) {
    bridge_config_kv_t kv = fake_kv(fake);
    install_hooks(seq);
    CHECK_EQ_INT(bridge_config_core_init(&kv), BRIDGE_CONFIG_OK);
    CHECK(bridge_config_ready());
    uint32_t generation = 0;
    CHECK_EQ_INT(bridge_config_get_generation(&generation), BRIDGE_CONFIG_OK);
    return generation;
}

static bridge_config_pairing_t sample_pairing(void) {
    bridge_config_pairing_t pairing;
    memset(&pairing, 0, sizeof(pairing));
    snprintf(pairing.device_id, sizeof(pairing.device_id), "LMXC[\\");
    pairing.frequency_hz = 918500000u;
    pairing.num_probes = 4;
    pairing.paired_at = 1700000000u;
    return pairing;
}

static void set_sample_device(void) {
    CHECK_EQ_INT(bridge_config_set_units(BRIDGE_CONFIG_UNITS_CELSIUS),
                 BRIDGE_CONFIG_OK);
    CHECK_EQ_INT(bridge_config_set_display_timeout(
                     BRIDGE_CONFIG_TIMEOUT_120S),
                 BRIDGE_CONFIG_OK);
    CHECK_EQ_INT(bridge_config_set_device_name("Backyard Bridge"),
                 BRIDGE_CONFIG_OK);
}

/* ---- tests --------------------------------------------------------------- */

static void test_fresh_init(void) {
    fake_t fake;
    fake_init(&fake);
    random_seq_t seq = {.values = {0x11111111u, 0x22222222u}, .count = 2};

    uint32_t generation = init_with(&fake, &seq);
    CHECK_EQ_UINT(generation, 0x11111111u);

    uint16_t version = 0;
    CHECK(fake_read_u16(&fake, BRIDGE_CONFIG_NS_META,
                        BRIDGE_CONFIG_KEY_CONFIG_VERSION, &version));
    CHECK_EQ_UINT(version, BRIDGE_CONFIG_VERSION);

    uint32_t stored_generation = 0;
    CHECK(fake_read_u32(&fake, BRIDGE_CONFIG_NS_LOG,
                        BRIDGE_CONFIG_KEY_GENERATION, &stored_generation));
    CHECK_EQ_UINT(stored_generation, generation);

    bridge_config_device_t device;
    CHECK_EQ_INT(bridge_config_get_device(&device), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(device.units, BRIDGE_CONFIG_DEFAULT_UNITS);
    CHECK_EQ_UINT(device.display_timeout_s, BRIDGE_CONFIG_DEFAULT_TIMEOUT);
    CHECK_STR_EQ(device.device_name, BRIDGE_CONFIG_DEFAULT_DEVICE_NAME);

    bridge_config_pairing_t pairing;
    CHECK_EQ_INT(bridge_config_get_pairing(&pairing), BRIDGE_CONFIG_OK);
    CHECK(!pairing.paired);

    bridge_config_stats_t stats;
    CHECK_EQ_INT(bridge_config_stats_get(&stats), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(stats.boot_count, 0u);
    CHECK_EQ_UINT(stats.packets_ok, 0u);
    CHECK_EQ_UINT(stats.packets_bad, 0u);

    uint64_t anchor = 1;
    bool valid = true;
    CHECK_EQ_INT(bridge_config_clock_get(&anchor, &valid), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(anchor, 0u);
    CHECK(!valid);

    /* A reload must not create a new generation. */
    bridge_config_kv_t kv = fake_kv(&fake);
    CHECK_EQ_INT(bridge_config_core_init(&kv), BRIDGE_CONFIG_OK);
    uint32_t reloaded = 0;
    CHECK_EQ_INT(bridge_config_get_generation(&reloaded), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(reloaded, generation);
}

static void test_round_trip_all_keys(void) {
    fake_t fake;
    fake_init(&fake);
    random_seq_t seq = {.values = {0x11111111u, 0x22222222u}, .count = 2};
    (void)init_with(&fake, &seq);

    bridge_config_pairing_t pairing = sample_pairing();
    CHECK_EQ_INT(bridge_config_set_pairing(&pairing), BRIDGE_CONFIG_OK);
    set_sample_device();
    CHECK_EQ_INT(bridge_config_set_generation(0x12345678u), BRIDGE_CONFIG_OK);
    CHECK_EQ_INT(bridge_config_clock_set(1700000100u, true), BRIDGE_CONFIG_OK);
    CHECK_EQ_INT(bridge_config_stats_set_packets_ok(42u), BRIDGE_CONFIG_OK);
    CHECK_EQ_INT(bridge_config_stats_set_packets_bad(7u), BRIDGE_CONFIG_OK);
    CHECK_EQ_INT(bridge_config_stats_note_boot(3u), BRIDGE_CONFIG_OK);

    /* Physical keys are the documented ones, including the 15-char aliases. */
    CHECK(fake_has(&fake, BRIDGE_CONFIG_NS_PAIR, "device_id"));
    CHECK(fake_has(&fake, BRIDGE_CONFIG_NS_PAIR, "frequency_hz"));
    CHECK(fake_has(&fake, BRIDGE_CONFIG_NS_PAIR, "num_probes"));
    CHECK(fake_has(&fake, BRIDGE_CONFIG_NS_PAIR, "paired_at"));
    CHECK(fake_has(&fake, BRIDGE_CONFIG_NS_DEVICE, "units"));
    CHECK(fake_has(&fake, BRIDGE_CONFIG_NS_DEVICE, "disp_timeout_s"));
    CHECK(fake_has(&fake, BRIDGE_CONFIG_NS_DEVICE, "device_name"));
    CHECK(fake_has(&fake, BRIDGE_CONFIG_NS_LOG, "generation"));
    CHECK(fake_has(&fake, BRIDGE_CONFIG_NS_LOG, "clock_anchor_s"));
    CHECK(fake_has(&fake, BRIDGE_CONFIG_NS_LOG, "clock_valid"));
    CHECK(fake_has(&fake, BRIDGE_CONFIG_NS_STATS, "boot_count"));
    CHECK(fake_has(&fake, BRIDGE_CONFIG_NS_STATS, "last_reset"));
    CHECK(fake_has(&fake, BRIDGE_CONFIG_NS_STATS, "packets_ok"));
    CHECK(fake_has(&fake, BRIDGE_CONFIG_NS_STATS, "packets_bad"));

    /* Reload from the same backend: every getter returns the written value. */
    bridge_config_kv_t kv = fake_kv(&fake);
    CHECK_EQ_INT(bridge_config_core_init(&kv), BRIDGE_CONFIG_OK);

    bridge_config_pairing_t got_pairing;
    CHECK_EQ_INT(bridge_config_get_pairing(&got_pairing), BRIDGE_CONFIG_OK);
    CHECK(got_pairing.paired);
    CHECK_STR_EQ(got_pairing.device_id, pairing.device_id);
    CHECK_EQ_UINT(got_pairing.frequency_hz, pairing.frequency_hz);
    CHECK_EQ_UINT(got_pairing.num_probes, pairing.num_probes);
    CHECK_EQ_UINT(got_pairing.paired_at, pairing.paired_at);

    bridge_config_device_t got_device;
    CHECK_EQ_INT(bridge_config_get_device(&got_device), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(got_device.units, BRIDGE_CONFIG_UNITS_CELSIUS);
    CHECK_EQ_UINT(got_device.display_timeout_s,
                  BRIDGE_CONFIG_TIMEOUT_120S);
    CHECK_STR_EQ(got_device.device_name, "Backyard Bridge");

    uint32_t generation = 0;
    CHECK_EQ_INT(bridge_config_get_generation(&generation), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(generation, 0x12345678u);

    uint64_t anchor = 0;
    bool valid = false;
    CHECK_EQ_INT(bridge_config_clock_get(&anchor, &valid), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(anchor, 1700000100u);
    CHECK(valid);

    bridge_config_stats_t stats;
    CHECK_EQ_INT(bridge_config_stats_get(&stats), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(stats.boot_count, 1u);
    CHECK_EQ_UINT(stats.last_reset_reason, 3u);
    CHECK_EQ_UINT(stats.packets_ok, 42u);
    CHECK_EQ_UINT(stats.packets_bad, 7u);
}

static void test_invalid_writes_change_nothing(void) {
    fake_t fake;
    fake_init(&fake);
    random_seq_t seq = {.values = {0x11111111u, 0x22222222u}, .count = 2};
    (void)init_with(&fake, &seq);

    bridge_config_pairing_t original = sample_pairing();
    CHECK_EQ_INT(bridge_config_set_pairing(&original), BRIDGE_CONFIG_OK);
    set_sample_device();

    static const struct {
        uint32_t frequency;
        uint8_t probes;
    } bad_pairings[] = {
        {901999999u, 4u},
        {928000001u, 4u},
        {918500000u, 3u},
        {918500000u, 0u},
    };
    for (size_t i = 0; i < sizeof(bad_pairings) / sizeof(bad_pairings[0]); i++) {
        bridge_config_pairing_t bad = original;
        bad.frequency_hz = bad_pairings[i].frequency;
        bad.num_probes = bad_pairings[i].probes;
        CHECK_EQ_INT(bridge_config_set_pairing(&bad),
                     BRIDGE_CONFIG_ERR_INVALID);
    }

    bridge_config_pairing_t bad_id = original;
    bad_id.device_id[0] = '\0';
    CHECK_EQ_INT(bridge_config_set_pairing(&bad_id),
                 BRIDGE_CONFIG_ERR_INVALID);
    snprintf(bad_id.device_id, sizeof(bad_id.device_id), "bad\nid");
    CHECK_EQ_INT(bridge_config_set_pairing(&bad_id),
                 BRIDGE_CONFIG_ERR_INVALID);

    CHECK_EQ_INT(bridge_config_set_units(2u), BRIDGE_CONFIG_ERR_INVALID);
    CHECK_EQ_INT(bridge_config_set_display_timeout(45u),
                 BRIDGE_CONFIG_ERR_INVALID);
    CHECK_EQ_INT(bridge_config_set_display_timeout(31u),
                 BRIDGE_CONFIG_ERR_INVALID);

    /* Malformed UTF-8: 0xC3 must be followed by a continuation byte. */
    static const char kBadUtf8[] = {(char)0xC3, '(', '\0'};
    CHECK_EQ_INT(bridge_config_set_device_name(kBadUtf8),
                 BRIDGE_CONFIG_ERR_INVALID);
    CHECK_EQ_INT(bridge_config_set_device_name("1234567890123456"),
                 BRIDGE_CONFIG_ERR_INVALID);
    CHECK_EQ_INT(bridge_config_set_device_name(""), BRIDGE_CONFIG_ERR_INVALID);
    static const char kControl[] = {'a', (char)0x01, '\0'};
    CHECK_EQ_INT(bridge_config_set_device_name(kControl),
                 BRIDGE_CONFIG_ERR_INVALID);

    CHECK_EQ_INT(bridge_config_clock_set(0u, true), BRIDGE_CONFIG_ERR_INVALID);

    /* Whole-record validation: a bad name must not write the valid units. */
    bridge_config_device_t bad_device;
    CHECK_EQ_INT(bridge_config_get_device(&bad_device), BRIDGE_CONFIG_OK);
    bad_device.units = BRIDGE_CONFIG_UNITS_FAHRENHEIT;
    snprintf(bad_device.device_name, sizeof(bad_device.device_name), "%s",
             kBadUtf8);
    CHECK_EQ_INT(bridge_config_set_device(&bad_device),
                 BRIDGE_CONFIG_ERR_INVALID);

    bridge_config_pairing_t got_pairing;
    CHECK_EQ_INT(bridge_config_get_pairing(&got_pairing), BRIDGE_CONFIG_OK);
    CHECK_STR_EQ(got_pairing.device_id, original.device_id);
    CHECK_EQ_UINT(got_pairing.frequency_hz, original.frequency_hz);
    CHECK_EQ_UINT(got_pairing.num_probes, original.num_probes);

    bridge_config_device_t got_device;
    CHECK_EQ_INT(bridge_config_get_device(&got_device), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(got_device.units, BRIDGE_CONFIG_UNITS_CELSIUS);
    CHECK_EQ_UINT(got_device.display_timeout_s,
                  BRIDGE_CONFIG_TIMEOUT_120S);
    CHECK_STR_EQ(got_device.device_name, "Backyard Bridge");

    /* The rejected values never reached the backend. */
    uint32_t stored_freq = 0;
    CHECK(fake_read_u32(&fake, BRIDGE_CONFIG_NS_PAIR, "frequency_hz",
                        &stored_freq));
    CHECK_EQ_UINT(stored_freq, original.frequency_hz);

    /* A backend write failure also leaves the previous value in place. */
    fake.fail_set_in = 0;
    CHECK_EQ_INT(bridge_config_set_units(BRIDGE_CONFIG_UNITS_FAHRENHEIT),
                 BRIDGE_CONFIG_ERR_IO);
    uint8_t units = 0xFFu;
    CHECK_EQ_INT(bridge_config_get_units(&units), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(units, BRIDGE_CONFIG_UNITS_CELSIUS);
}

static void test_reserved_billows_untouched(void) {
    fake_t fake;
    fake_init(&fake);
    random_seq_t seq = {.values = {0x11111111u, 0x22222222u}, .count = 2};
    (void)init_with(&fake, &seq);
    set_sample_device();

    uint8_t mode = 0xFFu;
    int16_t target = 1234;
    CHECK_EQ_INT(bridge_config_get_reserved_billows(&mode, &target),
                 BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(mode, 0u);
    CHECK_EQ_UINT((uint16_t)target, 0u);

    CHECK(!fake_has(&fake, BRIDGE_CONFIG_NS_DEVICE,
                    BRIDGE_CONFIG_KEY_BILLOWS_MODE));
    CHECK(!fake_has(&fake, BRIDGE_CONFIG_NS_DEVICE,
                    BRIDGE_CONFIG_KEY_BILLOWS_TARGET));

    CHECK_EQ_INT(bridge_config_factory_reset(), BRIDGE_CONFIG_OK);
    CHECK(!fake_has(&fake, BRIDGE_CONFIG_NS_DEVICE,
                    BRIDGE_CONFIG_KEY_BILLOWS_MODE));
    CHECK(!fake_has(&fake, BRIDGE_CONFIG_NS_DEVICE,
                    BRIDGE_CONFIG_KEY_BILLOWS_TARGET));
}

static void test_log_clear_keeps_pairing(void) {
    fake_t fake;
    fake_init(&fake);
    random_seq_t seq = {.values = {0x11111111u, 0x22222222u, 0x33333333u},
                        .count = 3};
    uint32_t before = init_with(&fake, &seq);
    bridge_config_pairing_t pairing = sample_pairing();
    CHECK_EQ_INT(bridge_config_set_pairing(&pairing), BRIDGE_CONFIG_OK);
    set_sample_device();

    uint32_t after = 0;
    CHECK_EQ_INT(bridge_config_begin_log_clear(&after), BRIDGE_CONFIG_OK);
    CHECK(after != before);

    bridge_config_log_t log;
    CHECK_EQ_INT(bridge_config_get_log(&log), BRIDGE_CONFIG_OK);
    CHECK(log.clear_pending);
    CHECK_EQ_UINT(log.generation, after);

    bridge_config_pairing_t got;
    CHECK_EQ_INT(bridge_config_get_pairing(&got), BRIDGE_CONFIG_OK);
    CHECK(got.paired);
    CHECK_STR_EQ(got.device_id, pairing.device_id);

    bridge_config_device_t device;
    CHECK_EQ_INT(bridge_config_get_device(&device), BRIDGE_CONFIG_OK);
    CHECK_STR_EQ(device.device_name, "Backyard Bridge");

    CHECK_EQ_INT(bridge_config_finish_log_clear(), BRIDGE_CONFIG_OK);
    CHECK_EQ_INT(bridge_config_get_log(&log), BRIDGE_CONFIG_OK);
    CHECK(!log.clear_pending);

    /* A reload keeps the pending clear, so a power cut can finish it. */
    CHECK_EQ_INT(bridge_config_begin_log_clear(&after), BRIDGE_CONFIG_OK);
    bridge_config_kv_t kv = fake_kv(&fake);
    CHECK_EQ_INT(bridge_config_core_init(&kv), BRIDGE_CONFIG_OK);
    CHECK_EQ_INT(bridge_config_get_log(&log), BRIDGE_CONFIG_OK);
    CHECK(log.clear_pending);
    CHECK_EQ_UINT(log.generation, after);
}

static void test_forget_phones_keeps_pairing(void) {
    fake_t fake;
    fake_init(&fake);
    random_seq_t seq = {.values = {0x11111111u, 0x22222222u}, .count = 2};
    uint32_t generation = init_with(&fake, &seq);
    bridge_config_pairing_t pairing = sample_pairing();
    CHECK_EQ_INT(bridge_config_set_pairing(&pairing), BRIDGE_CONFIG_OK);

    CHECK_EQ_INT(bridge_config_clear_bonds(), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(g_bond_clear_calls, 1);

    bridge_config_pairing_t got;
    CHECK_EQ_INT(bridge_config_get_pairing(&got), BRIDGE_CONFIG_OK);
    CHECK(got.paired);
    CHECK_STR_EQ(got.device_id, pairing.device_id);

    uint32_t after = 0;
    CHECK_EQ_INT(bridge_config_get_generation(&after), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(after, generation);

    /* Re-pairing the radio clears the Smoke X4 link, not the phones. */
    CHECK_EQ_INT(bridge_config_clear_pairing(), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(g_bond_clear_calls, 1);
}

static void test_factory_reset(void) {
    fake_t fake;
    fake_init(&fake);
    random_seq_t seq = {.values = {0x11111111u, 0x22222222u, 0x33333333u},
                        .count = 3};
    uint32_t before = init_with(&fake, &seq);
    bridge_config_pairing_t pairing = sample_pairing();
    CHECK_EQ_INT(bridge_config_set_pairing(&pairing), BRIDGE_CONFIG_OK);
    set_sample_device();
    CHECK_EQ_INT(bridge_config_clock_set(1700000100u, true), BRIDGE_CONFIG_OK);
    CHECK_EQ_INT(bridge_config_stats_set_packets_ok(42u), BRIDGE_CONFIG_OK);
    CHECK_EQ_INT(bridge_config_stats_set_packets_bad(7u), BRIDGE_CONFIG_OK);
    CHECK_EQ_INT(bridge_config_stats_note_boot(3u), BRIDGE_CONFIG_OK);

    CHECK_EQ_INT(bridge_config_factory_reset(), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(g_bond_clear_calls, 1);

    bridge_config_log_t log;
    CHECK_EQ_INT(bridge_config_get_log(&log), BRIDGE_CONFIG_OK);
    CHECK(log.generation != before);
    CHECK(log.clear_pending);
    CHECK_EQ_UINT(log.clock_anchor_s, 0u);
    CHECK(!log.clock_valid);

    bridge_config_pairing_t got_pairing;
    CHECK_EQ_INT(bridge_config_get_pairing(&got_pairing), BRIDGE_CONFIG_OK);
    CHECK(!got_pairing.paired);

    bridge_config_device_t device;
    CHECK_EQ_INT(bridge_config_get_device(&device), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(device.units, BRIDGE_CONFIG_DEFAULT_UNITS);
    CHECK_EQ_UINT(device.display_timeout_s, BRIDGE_CONFIG_DEFAULT_TIMEOUT);
    CHECK_STR_EQ(device.device_name, BRIDGE_CONFIG_DEFAULT_DEVICE_NAME);

    bridge_config_stats_t stats;
    CHECK_EQ_INT(bridge_config_stats_get(&stats), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(stats.boot_count, 0u);
    CHECK_EQ_UINT(stats.packets_ok, 0u);
    CHECK_EQ_UINT(stats.packets_bad, 0u);

    CHECK(!fake_has(&fake, BRIDGE_CONFIG_NS_PAIR, "device_id"));
    CHECK(!fake_has(&fake, BRIDGE_CONFIG_NS_PAIR, "frequency_hz"));
    CHECK(!fake_has(&fake, BRIDGE_CONFIG_NS_DEVICE, "device_name"));
    CHECK(!fake_has(&fake, BRIDGE_CONFIG_NS_STATS, "boot_count"));

    /* Layout version is metadata, not user data: it survives. */
    uint16_t version = 0;
    CHECK(fake_read_u16(&fake, BRIDGE_CONFIG_NS_META,
                        BRIDGE_CONFIG_KEY_CONFIG_VERSION, &version));
    CHECK_EQ_UINT(version, BRIDGE_CONFIG_VERSION);

    /* The new generation is persisted before the reboot, and pending stays. */
    uint32_t stored = 0;
    CHECK(fake_read_u32(&fake, BRIDGE_CONFIG_NS_LOG,
                        BRIDGE_CONFIG_KEY_GENERATION, &stored));
    CHECK_EQ_UINT(stored, log.generation);
    uint8_t pending = 0;
    CHECK(fake_read_u8(&fake, BRIDGE_CONFIG_NS_LOG, "clear_pending",
                       &pending));
    CHECK_EQ_UINT(pending, 1u);

    bridge_config_kv_t kv = fake_kv(&fake);
    CHECK_EQ_INT(bridge_config_core_init(&kv), BRIDGE_CONFIG_OK);
    uint32_t reloaded = 0;
    CHECK_EQ_INT(bridge_config_get_generation(&reloaded), BRIDGE_CONFIG_OK);
    CHECK_EQ_UINT(reloaded, log.generation);
}

static void test_factory_reset_table(void) {
    size_t count = 0;
    const bridge_config_reset_step_t *steps =
        bridge_config_factory_reset_steps(&count);
    CHECK(steps != NULL);
    CHECK(count > 0);

    bool has_device_id = false;
    bool has_timeout = false;
    bool has_last_reset = false;
    bool has_generation = false;
    bool has_pending = false;
    bool has_bonds = false;
    size_t gen_index = 0;
    size_t pending_index = 0;
    size_t bonds_index = 0;
    for (size_t i = 0; i < count; i++) {
        if (steps[i].action == BRIDGE_CONFIG_RESET_NEW_GENERATION) {
            has_generation = true;
            gen_index = i;
        } else if (steps[i].action == BRIDGE_CONFIG_RESET_SET_CLEAR_PENDING) {
            has_pending = true;
            pending_index = i;
        } else if (steps[i].action == BRIDGE_CONFIG_RESET_CLEAR_BONDS) {
            has_bonds = true;
            bonds_index = i;
        } else if (steps[i].ns != NULL && steps[i].key != NULL) {
            if (strcmp(steps[i].ns, BRIDGE_CONFIG_NS_PAIR) == 0 &&
                strcmp(steps[i].key, BRIDGE_CONFIG_KEY_DEVICE_ID) == 0) {
                has_device_id = true;
            } else if (strcmp(steps[i].ns, BRIDGE_CONFIG_NS_DEVICE) == 0 &&
                       strcmp(steps[i].key,
                              BRIDGE_CONFIG_KEY_DISPLAY_TIMEOUT) == 0) {
                has_timeout = true;
            } else if (strcmp(steps[i].ns, BRIDGE_CONFIG_NS_STATS) == 0 &&
                       strcmp(steps[i].key, BRIDGE_CONFIG_KEY_LAST_RESET) == 0) {
                has_last_reset = true;
            }
        }
    }
    CHECK(has_device_id);
    CHECK(has_timeout);
    CHECK(has_last_reset);
    CHECK(has_generation);
    CHECK(has_pending);
    CHECK(has_bonds);
    CHECK(gen_index < pending_index);
    CHECK(pending_index < bonds_index); /* config erases before the bond clear */
}

static void test_single_bad_sector_keeps_generation(void) {
    fake_t fake;
    fake_init(&fake);
    random_seq_t seq = {.values = {0x11111111u, 0x22222222u, 0x33333333u},
                        .count = 3};
    uint32_t generation = init_with(&fake, &seq);

    /*
     * T19 recovers one bad sector from the remaining headers/records. That
     * path must not call regenerate_generation(); the config store only
     * changes generation for a deliberate clear or a wholly unusable log.
     * Simulate the reboot after that recovery: the value is stable.
     */
    for (unsigned int boot = 0; boot < 3; boot++) {
        bridge_config_kv_t kv = fake_kv(&fake);
        CHECK_EQ_INT(bridge_config_core_init(&kv), BRIDGE_CONFIG_OK);
        uint32_t current = 0;
        CHECK_EQ_INT(bridge_config_get_generation(&current), BRIDGE_CONFIG_OK);
        CHECK_EQ_UINT(current, generation);
    }

    /* Whole-log corruption is the explicit T19 call that does change it. */
    uint32_t regenerated = 0;
    CHECK_EQ_INT(bridge_config_regenerate_generation(&regenerated),
                 BRIDGE_CONFIG_OK);
    CHECK(regenerated != generation);
    bridge_config_log_t log;
    CHECK_EQ_INT(bridge_config_get_log(&log), BRIDGE_CONFIG_OK);
    CHECK(!log.clear_pending); /* a corrupt log is reclaimed, not a user clear */
}

static void test_migrations(void) {
    /* Version 0 with an existing v0 pairing record: migrate and keep it. */
    fake_t fake;
    fake_init(&fake);
    random_seq_t seq = {.values = {0x11111111u, 0x22222222u}, .count = 2};
    install_hooks(&seq);
    fake_entry_t *version = fake_alloc(&fake, BRIDGE_CONFIG_NS_META,
                                       BRIDGE_CONFIG_KEY_CONFIG_VERSION);
    version->value[0] = 0;
    version->value[1] = 0;
    version->len = 2;
    bridge_config_pairing_t pairing = sample_pairing();
    bridge_config_kv_t kv = fake_kv(&fake);
    /* Write the v0 record directly: the old layout had no version gate. */
    fake_entry_t *id = fake_alloc(&fake, BRIDGE_CONFIG_NS_PAIR, "device_id");
    snprintf((char *)id->value, sizeof(id->value), "%s", pairing.device_id);
    id->len = strlen(pairing.device_id);
    fake_entry_t *freq = fake_alloc(&fake, BRIDGE_CONFIG_NS_PAIR,
                                    "frequency_hz");
    freq->value[0] = (uint8_t)(pairing.frequency_hz & 0xFFu);
    freq->value[1] = (uint8_t)((pairing.frequency_hz >> 8) & 0xFFu);
    freq->value[2] = (uint8_t)((pairing.frequency_hz >> 16) & 0xFFu);
    freq->value[3] = (uint8_t)((pairing.frequency_hz >> 24) & 0xFFu);
    freq->len = 4;
    fake_entry_t *probes = fake_alloc(&fake, BRIDGE_CONFIG_NS_PAIR,
                                      "num_probes");
    probes->value[0] = pairing.num_probes;
    probes->len = 1;

    CHECK_EQ_INT(bridge_config_core_init(&kv), BRIDGE_CONFIG_OK);
    uint16_t migrated = 0;
    CHECK(fake_read_u16(&fake, BRIDGE_CONFIG_NS_META,
                        BRIDGE_CONFIG_KEY_CONFIG_VERSION, &migrated));
    CHECK_EQ_UINT(migrated, BRIDGE_CONFIG_VERSION);
    bridge_config_pairing_t got;
    CHECK_EQ_INT(bridge_config_get_pairing(&got), BRIDGE_CONFIG_OK);
    CHECK(got.paired);
    CHECK_STR_EQ(got.device_id, pairing.device_id);
    uint32_t generation = 0;
    CHECK_EQ_INT(bridge_config_get_generation(&generation), BRIDGE_CONFIG_OK);
    CHECK(generation != 0u);

    /* A wrong-sized v0 value is scrubbed and replaced by the default. */
    fake_entry_t *bad_generation = fake_alloc(&fake, BRIDGE_CONFIG_NS_LOG,
                                              "generation");
    bad_generation->value[0] = 0xAA;
    bad_generation->len = 1;
    CHECK_EQ_INT(bridge_config_core_init(&kv), BRIDGE_CONFIG_OK);
    CHECK(fake_read_u32(&fake, BRIDGE_CONFIG_NS_LOG, "generation",
                        &(uint32_t){0}));

    /* An unreadable version is treated as unversioned, then repaired. */
    version->value[0] = 1;
    version->len = 1;
    CHECK_EQ_INT(bridge_config_core_init(&kv), BRIDGE_CONFIG_OK);
    CHECK(fake_read_u16(&fake, BRIDGE_CONFIG_NS_META,
                        BRIDGE_CONFIG_KEY_CONFIG_VERSION, &migrated));
    CHECK_EQ_UINT(migrated, BRIDGE_CONFIG_VERSION);

    /* A future layout is never guessed at or modified. */
    fake_t future;
    fake_init(&future);
    fake_entry_t *future_version = fake_alloc(
        &future, BRIDGE_CONFIG_NS_META, BRIDGE_CONFIG_KEY_CONFIG_VERSION);
    future_version->value[0] = 99;
    future_version->value[1] = 0;
    future_version->len = 2;
    fake_entry_t *name = fake_alloc(&future, BRIDGE_CONFIG_NS_DEVICE,
                                    "device_name");
    snprintf((char *)name->value, sizeof(name->value), "Keep Me");
    name->len = strlen("Keep Me");
    bridge_config_kv_t future_kv = fake_kv(&future);
    CHECK_EQ_INT(bridge_config_core_init(&future_kv),
                 BRIDGE_CONFIG_ERR_VERSION);
    CHECK(!bridge_config_ready());
    uint16_t future_stored = 0;
    CHECK(fake_read_u16(&future, BRIDGE_CONFIG_NS_META,
                        "config_version", &future_stored));
    CHECK_EQ_UINT(future_stored, 99u);
    fake_entry_t *name_after =
        fake_find(&future, BRIDGE_CONFIG_NS_DEVICE, "device_name");
    CHECK(name_after != NULL);
    CHECK_EQ_UINT(name_after->len, strlen("Keep Me"));
    CHECK(memcmp(name_after->value, "Keep Me", name_after->len) == 0);
}

static void test_arguments(void) {
    CHECK_EQ_INT(bridge_config_core_init(NULL), BRIDGE_CONFIG_ERR_INVALID);
    CHECK_EQ_INT(bridge_config_core_init(&(bridge_config_kv_t){0}),
                 BRIDGE_CONFIG_ERR_INVALID);

    bridge_config_kv_t kv = {0};
    CHECK_EQ_INT(bridge_config_core_init(&kv), BRIDGE_CONFIG_ERR_INVALID);
    CHECK_EQ_INT(bridge_config_get_pairing(NULL),
                 BRIDGE_CONFIG_ERR_INVALID);
    CHECK_EQ_INT(bridge_config_set_pairing(NULL),
                 BRIDGE_CONFIG_ERR_INVALID);
    CHECK_EQ_INT(bridge_config_get_device(NULL),
                 BRIDGE_CONFIG_ERR_INVALID);
    CHECK_EQ_INT(bridge_config_get_device_name(NULL, 0),
                 BRIDGE_CONFIG_ERR_INVALID);
    CHECK_EQ_INT(bridge_config_get_units(NULL), BRIDGE_CONFIG_ERR_INVALID);
    CHECK_EQ_INT(bridge_config_clock_get(NULL, NULL),
                 BRIDGE_CONFIG_ERR_INVALID);
    CHECK_EQ_INT(bridge_config_get_generation(NULL),
                 BRIDGE_CONFIG_ERR_INVALID);
}

int main(void) {
    test_arguments();
    test_fresh_init();
    test_round_trip_all_keys();
    test_invalid_writes_change_nothing();
    test_reserved_billows_untouched();
    test_log_clear_keeps_pairing();
    test_forget_phones_keeps_pairing();
    test_factory_reset();
    test_factory_reset_table();
    test_single_bad_sector_keeps_generation();
    test_migrations();
    return sx4_test_summary("bridge-config");
}
