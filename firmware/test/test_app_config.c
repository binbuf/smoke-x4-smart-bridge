/* Host tests for app_config_store (F7.1–F7.3): typed round-trips over an
 * in-memory backend, the reference-compatible sx_pair blob, the v0→v1
 * adoption migration, change notifications, and PSK generation. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "app_config_store.h"
#include "test_util.h"

/* ── In-memory backend double ─────────────────────────────────────────── */

#define MEM_MAX_ENTRIES 64
#define MEM_MAX_VAL 80

typedef struct {
    char ns[16];
    char key[16];
    size_t len;
    uint8_t val[MEM_MAX_VAL];
} mem_entry_t;

typedef struct {
    mem_entry_t entries[MEM_MAX_ENTRIES];
    int count;
} mem_store_t;

static mem_entry_t *mem_find(mem_store_t *m, const char *ns, const char *key) {
    for (int i = 0; i < m->count; i++) {
        if (strcmp(m->entries[i].ns, ns) == 0 &&
            strcmp(m->entries[i].key, key) == 0) {
            return &m->entries[i];
        }
    }
    return NULL;
}

static int mem_get(void *ctx, const char *ns, const char *key, void *out,
                   size_t *len) {
    mem_entry_t *e = mem_find(ctx, ns, key);
    if (!e) {
        return APP_CONFIG_ERR_NOT_FOUND;
    }
    if (!out) {
        *len = e->len;
        return APP_CONFIG_OK;
    }
    if (*len < e->len) {
        return APP_CONFIG_ERR;
    }
    memcpy(out, e->val, e->len);
    *len = e->len;
    return APP_CONFIG_OK;
}

static int mem_set(void *ctx, const char *ns, const char *key, const void *val,
                   size_t len) {
    mem_store_t *m = ctx;
    if (len > MEM_MAX_VAL) {
        return APP_CONFIG_ERR;
    }
    mem_entry_t *e = mem_find(m, ns, key);
    if (!e) {
        if (m->count >= MEM_MAX_ENTRIES) {
            return APP_CONFIG_ERR;
        }
        e = &m->entries[m->count++];
        snprintf(e->ns, sizeof e->ns, "%s", ns);
        snprintf(e->key, sizeof e->key, "%s", key);
    }
    memcpy(e->val, val, len);
    e->len = len;
    return APP_CONFIG_OK;
}

static int mem_erase_all(void *ctx) {
    ((mem_store_t *)ctx)->count = 0;
    return APP_CONFIG_OK;
}

static mem_store_t g_mem;
static const app_config_backend_t g_backend = {
    .get = mem_get,
    .set = mem_set,
    .erase_all = mem_erase_all,
    .ctx = &g_mem,
};

/* Deterministic RNG whose sequence changes as it is consumed, so a factory
 * reset visibly regenerates the PSK. */
static uint32_t g_rng_state = 0x12345678u;
static uint32_t fake_rng(void) {
    g_rng_state = g_rng_state * 1664525u + 1013904223u;
    return g_rng_state;
}

/* ── Notification capture ─────────────────────────────────────────────── */

static int g_notify_count;
static app_config_key_t g_last_key;
static void on_change(app_config_key_t key, void *ctx) {
    (void)ctx;
    g_notify_count++;
    g_last_key = key;
}

/* ── Tests ────────────────────────────────────────────────────────────── */

static void test_every_key_round_trips(void) {
    for (app_config_key_t k = 0; k < APP_CONFIG_KEY_COUNT; k++) {
        const app_config_key_info_t *info = app_config_store_key_info(k);
        CHECK(info != NULL);
        switch (info->type) {
            case APP_CONFIG_T_U8: {
                uint8_t v = 0;
                CHECK_EQ_INT(app_config_store_set_u8(k, 0xA5), APP_CONFIG_OK);
                CHECK_EQ_INT(app_config_store_get_u8(k, &v), APP_CONFIG_OK);
                CHECK_EQ_INT(v, 0xA5);
                break;
            }
            case APP_CONFIG_T_U16: {
                uint16_t v = 0;
                CHECK_EQ_INT(app_config_store_set_u16(k, 0xBEEF),
                             APP_CONFIG_OK);
                CHECK_EQ_INT(app_config_store_get_u16(k, &v), APP_CONFIG_OK);
                CHECK_EQ_INT(v, 0xBEEF);
                break;
            }
            case APP_CONFIG_T_U32: {
                uint32_t v = 0;
                CHECK_EQ_INT(app_config_store_set_u32(k, 0xDEADBEEFu),
                             APP_CONFIG_OK);
                CHECK_EQ_INT(app_config_store_get_u32(k, &v), APP_CONFIG_OK);
                CHECK(v == 0xDEADBEEFu);
                break;
            }
            case APP_CONFIG_T_U64: {
                uint64_t v = 0;
                CHECK_EQ_INT(
                    app_config_store_set_u64(k, 0x1122334455667788ull),
                    APP_CONFIG_OK);
                CHECK_EQ_INT(app_config_store_get_u64(k, &v), APP_CONFIG_OK);
                CHECK(v == 0x1122334455667788ull);
                break;
            }
            case APP_CONFIG_T_I32: {
                int32_t v = 0;
                CHECK_EQ_INT(app_config_store_set_i32(k, -12345),
                             APP_CONFIG_OK);
                CHECK_EQ_INT(app_config_store_get_i32(k, &v), APP_CONFIG_OK);
                CHECK_EQ_INT(v, -12345);
                break;
            }
            case APP_CONFIG_T_STR: {
                char buf[80];
                CHECK_EQ_INT(app_config_store_set_str(k, "rt"), APP_CONFIG_OK);
                CHECK_EQ_INT(app_config_store_get_str(k, buf, sizeof buf),
                             APP_CONFIG_OK);
                CHECK(strcmp(buf, "rt") == 0);
                /* Over-length write must be refused, not truncated. */
                char big[81];
                memset(big, 'x', sizeof big - 1);
                big[sizeof big - 1] = '\0';
                CHECK_EQ_INT(app_config_store_set_str(k, big),
                             APP_CONFIG_ERR_RANGE);
                break;
            }
            case APP_CONFIG_T_BLOB: {
                const uint8_t in[] = {1, 2, 3, 4, 5};
                uint8_t out[80];
                size_t len = sizeof out;
                CHECK_EQ_INT(app_config_store_set_blob(k, in, sizeof in),
                             APP_CONFIG_OK);
                CHECK_EQ_INT(app_config_store_get_blob(k, out, &len),
                             APP_CONFIG_OK);
                CHECK_EQ_INT((int)len, (int)sizeof in);
                CHECK(memcmp(in, out, len) == 0);
                break;
            }
        }
    }
}

static void test_defaults_before_write(void) {
    mem_erase_all(&g_mem);
    CHECK_EQ_INT(app_config_store_init(&g_backend, fake_rng), APP_CONFIG_OK);

    uint8_t u8v = 99;
    CHECK_EQ_INT(app_config_store_get_u8(APP_CONFIG_DEV_RETENTION_MAX_SESSIONS,
                                         &u8v),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(u8v, 64);
    CHECK_EQ_INT(app_config_store_get_u8(APP_CONFIG_PROBE1_ROLE, &u8v),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(u8v, APP_CONFIG_ROLE_PIT);
    CHECK_EQ_INT(app_config_store_get_u8(APP_CONFIG_PROBE2_ROLE, &u8v),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(u8v, APP_CONFIG_ROLE_FOOD);

    uint32_t u32v = 0;
    CHECK_EQ_INT(app_config_store_get_u32(APP_CONFIG_SESSION_NEXT_ID, &u32v),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(u32v, 1);

    char buf[40];
    CHECK_EQ_INT(
        app_config_store_get_str(APP_CONFIG_NET_HOSTNAME, buf, sizeof buf),
        APP_CONFIG_OK);
    CHECK(strcmp(buf, "smokebridge") == 0);

    /* Type confusion is an error, not a coercion. */
    CHECK_EQ_INT(app_config_store_get_u8(APP_CONFIG_SESSION_NEXT_ID, &u8v),
                 APP_CONFIG_ERR_TYPE);
}

static void test_pairing_blob_matches_reference_layout(void) {
    app_config_pairing_t p = {
        .frequency = 918500000u,
        .device_id = "LMXC[\\",
        .num_probes = 4,
    };
    CHECK_EQ_INT(app_config_store_set_pairing(&p), APP_CONFIG_OK);

    /* The raw stored bytes must be exactly the reference's smoke_x_config_t:
     * LE u32 frequency @0, char[8] device_id @4, LE u32 num_probes @12. */
    mem_entry_t *e = mem_find(&g_mem, "sx_pair", "config");
    CHECK(e != NULL);
    if (e) {
        CHECK_EQ_INT((int)e->len, 16);
        CHECK_EQ_INT(e->val[0], 918500000u & 0xFF);
        CHECK_EQ_INT(e->val[1], (918500000u >> 8) & 0xFF);
        CHECK_EQ_INT(e->val[2], (918500000u >> 16) & 0xFF);
        CHECK_EQ_INT(e->val[3], (918500000u >> 24) & 0xFF);
        CHECK(memcmp(e->val + 4, "LMXC[\\\0\0", 8) == 0);
        CHECK_EQ_INT(e->val[12], 4);
        CHECK_EQ_INT(e->val[13], 0);
        CHECK_EQ_INT(e->val[14], 0);
        CHECK_EQ_INT(e->val[15], 0);
    }

    app_config_pairing_t back;
    CHECK_EQ_INT(app_config_store_get_pairing(&back), APP_CONFIG_OK);
    CHECK(back.frequency == 918500000u);
    CHECK(strcmp(back.device_id, "LMXC[\\") == 0);
    CHECK_EQ_INT(back.num_probes, 4);

    CHECK_EQ_INT(app_config_store_clear_pairing(), APP_CONFIG_OK);
    CHECK_EQ_INT(app_config_store_get_pairing(&back),
                 APP_CONFIG_ERR_NOT_FOUND);
}

static void test_reference_pairing_is_adopted(void) {
    /* A board upgraded from the reference: its NVS carries the pairing under
     * "smoke_x"/"config" and no version key. */
    mem_erase_all(&g_mem);
    uint8_t ref_blob[16] = {0};
    ref_blob[0] = 918500000u & 0xFF;
    ref_blob[1] = (918500000u >> 8) & 0xFF;
    ref_blob[2] = (918500000u >> 16) & 0xFF;
    ref_blob[3] = (918500000u >> 24) & 0xFF;
    memcpy(ref_blob + 4, "LMXC[\\", 7);
    ref_blob[12] = 4;
    CHECK_EQ_INT(
        mem_set(&g_mem, "smoke_x", "config", ref_blob, sizeof ref_blob),
        APP_CONFIG_OK);

    CHECK_EQ_INT(app_config_store_init(&g_backend, fake_rng), APP_CONFIG_OK);
    CHECK_EQ_INT(app_config_store_version(), 1);

    app_config_pairing_t p;
    CHECK_EQ_INT(app_config_store_get_pairing(&p), APP_CONFIG_OK);
    CHECK(p.frequency == 918500000u);
    CHECK(strcmp(p.device_id, "LMXC[\\") == 0);
    CHECK_EQ_INT(p.num_probes, 4);

    /* Idempotent: a second init must not re-adopt over a later unpair. */
    CHECK_EQ_INT(app_config_store_clear_pairing(), APP_CONFIG_OK);
    CHECK_EQ_INT(app_config_store_init(&g_backend, fake_rng), APP_CONFIG_OK);
    CHECK_EQ_INT(app_config_store_get_pairing(&p), APP_CONFIG_ERR_NOT_FOUND);
}

static void test_notifications_once_per_write(void) {
    CHECK_EQ_INT(app_config_store_subscribe(on_change, NULL), APP_CONFIG_OK);

    g_notify_count = 0;
    CHECK_EQ_INT(app_config_store_set_u8(APP_CONFIG_DEV_UNITS,
                                         APP_CONFIG_UNITS_C),
                 APP_CONFIG_OK);
    CHECK_EQ_INT(g_notify_count, 1);
    CHECK_EQ_INT(g_last_key, APP_CONFIG_DEV_UNITS);

    app_config_pairing_t p = {
        .frequency = 915000000u, .device_id = "ABCDEF", .num_probes = 2};
    CHECK_EQ_INT(app_config_store_set_pairing(&p), APP_CONFIG_OK);
    CHECK_EQ_INT(g_notify_count, 2);
    CHECK_EQ_INT(g_last_key, APP_CONFIG_KEY_PAIRING);

    /* A failed write must not notify. */
    CHECK_EQ_INT(app_config_store_set_u8(APP_CONFIG_SESSION_NEXT_ID, 1),
                 APP_CONFIG_ERR_TYPE);
    CHECK_EQ_INT(g_notify_count, 2);
}

static void test_psk_generation(void) {
    mem_erase_all(&g_mem);
    CHECK_EQ_INT(app_config_store_init(&g_backend, fake_rng), APP_CONFIG_OK);

    char psk[APP_CONFIG_PSK_LEN + 1];
    CHECK_EQ_INT(
        app_config_store_get_str(APP_CONFIG_NET_AP_PSK, psk, sizeof psk),
        APP_CONFIG_OK);
    CHECK_EQ_INT((int)strlen(psk), APP_CONFIG_PSK_LEN);
    for (int i = 0; i < APP_CONFIG_PSK_LEN; i++) {
        CHECK(strchr("0O1lI", psk[i]) == NULL);
        CHECK((psk[i] >= '2' && psk[i] <= '9') ||
              (psk[i] >= 'a' && psk[i] <= 'z') ||
              (psk[i] >= 'A' && psk[i] <= 'Z'));
    }

    /* Stable across reboots... */
    char again[APP_CONFIG_PSK_LEN + 1];
    CHECK_EQ_INT(app_config_store_init(&g_backend, fake_rng), APP_CONFIG_OK);
    CHECK_EQ_INT(
        app_config_store_get_str(APP_CONFIG_NET_AP_PSK, again, sizeof again),
        APP_CONFIG_OK);
    CHECK(strcmp(psk, again) == 0);

    /* ...regenerated only on factory reset. */
    CHECK_EQ_INT(app_config_store_factory_reset(), APP_CONFIG_OK);
    CHECK_EQ_INT(
        app_config_store_get_str(APP_CONFIG_NET_AP_PSK, again, sizeof again),
        APP_CONFIG_OK);
    CHECK_EQ_INT((int)strlen(again), APP_CONFIG_PSK_LEN);
    CHECK(strcmp(psk, again) != 0);
}

static void test_fresh_store_is_stamped_current(void) {
    mem_erase_all(&g_mem);
    CHECK_EQ_INT(app_config_store_init(&g_backend, fake_rng), APP_CONFIG_OK);
    CHECK_EQ_INT(app_config_store_version(), 1);
    /* No reference data existed, so nothing was adopted. */
    app_config_pairing_t p;
    CHECK_EQ_INT(app_config_store_get_pairing(&p), APP_CONFIG_ERR_NOT_FOUND);
}

int main(void) {
    CHECK_EQ_INT(app_config_store_init(&g_backend, fake_rng), APP_CONFIG_OK);
    test_every_key_round_trips();
    test_defaults_before_write();
    test_pairing_blob_matches_reference_layout();
    test_reference_pairing_is_adopted();
    test_notifications_once_per_write();
    test_psk_generation();
    test_fresh_store_is_stamped_current();
    return test_summary("test_app_config");
}
