/* app_config_store — typed config over a pluggable backend (design 03 §3.6).
 * Pure C11; compiled into both the firmware and the host test suite. */
#include "app_config_store.h"

#include <string.h>

/* The sx_pair blob must match the reference's smoke_x_config_t exactly —
 * that is what lets an upgraded board keep its pairing. */
_Static_assert(sizeof(app_config_pairing_t) == APP_CONFIG_PAIRING_BLOB_LEN,
               "pairing blob diverged from the reference layout");
_Static_assert(offsetof(app_config_pairing_t, frequency) == 0, "layout");
_Static_assert(offsetof(app_config_pairing_t, device_id) == 4, "layout");
_Static_assert(offsetof(app_config_pairing_t, num_probes) == 12, "layout");

#define NS_PAIR "sx_pair"
#define KEY_PAIR "config"
/* Where the reference firmware kept the same 16 bytes. */
#define NS_PAIR_REFERENCE "smoke_x"
#define NS_META "meta"
#define KEY_VERSION "version"

#define MAX_SUBSCRIBERS 4

typedef struct {
    const char *ns;
    const char *key;
    app_config_type_t type;
    size_t max_len;
    uint64_t def_num;
    const char *def_str;
} key_entry_t;

static const key_entry_t k_keys[] = {
#define X(id, ns_, key_, type_, len_, dnum_, dstr_) \
    {ns_, key_, APP_CONFIG_T_##type_, len_, dnum_, dstr_},
    APP_CONFIG_KEY_TABLE(X)
#undef X
};

static const app_config_backend_t *s_backend;
static uint32_t (*s_rng)(void);
static uint16_t s_version;

static struct {
    app_config_subscriber_t cb;
    void *ctx;
} s_subs[MAX_SUBSCRIBERS];
static int s_sub_count;

static void notify(app_config_key_t k) {
    for (int i = 0; i < s_sub_count; i++) {
        s_subs[i].cb(k, s_subs[i].ctx);
    }
}

const app_config_key_info_t *app_config_store_key_info(app_config_key_t k) {
    static app_config_key_info_t info;
    if ((size_t)k >= APP_CONFIG_KEY_COUNT) {
        return NULL;
    }
    info.ns = k_keys[k].ns;
    info.key = k_keys[k].key;
    info.type = k_keys[k].type;
    info.max_len = k_keys[k].max_len;
    return &info;
}

/* ── Numeric plumbing: fixed-width little-endian on every host ───────────
 * NVS stores what we hand it; serializing explicitly keeps a blob written by
 * one architecture readable on another (and makes tests byte-exact). */

static void put_le(uint8_t *b, uint64_t v, size_t n) {
    for (size_t i = 0; i < n; i++) {
        b[i] = (uint8_t)(v >> (8 * i));
    }
}

static uint64_t get_le(const uint8_t *b, size_t n) {
    uint64_t v = 0;
    for (size_t i = 0; i < n; i++) {
        v |= (uint64_t)b[i] << (8 * i);
    }
    return v;
}

static int get_num(app_config_key_t k, app_config_type_t want, uint64_t *out) {
    if (!s_backend || (size_t)k >= APP_CONFIG_KEY_COUNT) {
        return APP_CONFIG_ERR;
    }
    const key_entry_t *e = &k_keys[k];
    if (e->type != want) {
        return APP_CONFIG_ERR_TYPE;
    }
    uint8_t buf[8];
    size_t len = e->max_len;
    int rc = s_backend->get(s_backend->ctx, e->ns, e->key, buf, &len);
    if (rc == APP_CONFIG_ERR_NOT_FOUND) {
        *out = e->def_num;
        return APP_CONFIG_OK;
    }
    if (rc != APP_CONFIG_OK || len != e->max_len) {
        return APP_CONFIG_ERR;
    }
    *out = get_le(buf, len);
    return APP_CONFIG_OK;
}

static int set_num(app_config_key_t k, app_config_type_t want, uint64_t v) {
    if (!s_backend || (size_t)k >= APP_CONFIG_KEY_COUNT) {
        return APP_CONFIG_ERR;
    }
    const key_entry_t *e = &k_keys[k];
    if (e->type != want) {
        return APP_CONFIG_ERR_TYPE;
    }
    uint8_t buf[8];
    put_le(buf, v, e->max_len);
    int rc = s_backend->set(s_backend->ctx, e->ns, e->key, buf, e->max_len);
    if (rc == APP_CONFIG_OK) {
        notify(k);
    }
    return rc;
}

int app_config_store_get_u8(app_config_key_t k, uint8_t *out) {
    uint64_t v;
    int rc = get_num(k, APP_CONFIG_T_U8, &v);
    if (rc == APP_CONFIG_OK) {
        *out = (uint8_t)v;
    }
    return rc;
}

int app_config_store_set_u8(app_config_key_t k, uint8_t v) {
    return set_num(k, APP_CONFIG_T_U8, v);
}

int app_config_store_get_u16(app_config_key_t k, uint16_t *out) {
    uint64_t v;
    int rc = get_num(k, APP_CONFIG_T_U16, &v);
    if (rc == APP_CONFIG_OK) {
        *out = (uint16_t)v;
    }
    return rc;
}

int app_config_store_set_u16(app_config_key_t k, uint16_t v) {
    return set_num(k, APP_CONFIG_T_U16, v);
}

int app_config_store_get_u32(app_config_key_t k, uint32_t *out) {
    uint64_t v;
    int rc = get_num(k, APP_CONFIG_T_U32, &v);
    if (rc == APP_CONFIG_OK) {
        *out = (uint32_t)v;
    }
    return rc;
}

int app_config_store_set_u32(app_config_key_t k, uint32_t v) {
    return set_num(k, APP_CONFIG_T_U32, v);
}

int app_config_store_get_u64(app_config_key_t k, uint64_t *out) {
    return get_num(k, APP_CONFIG_T_U64, out);
}

int app_config_store_set_u64(app_config_key_t k, uint64_t v) {
    return set_num(k, APP_CONFIG_T_U64, v);
}

int app_config_store_get_i32(app_config_key_t k, int32_t *out) {
    uint64_t v;
    int rc = get_num(k, APP_CONFIG_T_I32, &v);
    if (rc == APP_CONFIG_OK) {
        *out = (int32_t)(uint32_t)v;
    }
    return rc;
}

int app_config_store_set_i32(app_config_key_t k, int32_t v) {
    return set_num(k, APP_CONFIG_T_I32, (uint32_t)v);
}

int app_config_store_get_str(app_config_key_t k, char *buf, size_t buflen) {
    if (!s_backend || (size_t)k >= APP_CONFIG_KEY_COUNT) {
        return APP_CONFIG_ERR;
    }
    const key_entry_t *e = &k_keys[k];
    if (e->type != APP_CONFIG_T_STR) {
        return APP_CONFIG_ERR_TYPE;
    }
    size_t len = buflen;
    int rc = s_backend->get(s_backend->ctx, e->ns, e->key, buf, &len);
    if (rc == APP_CONFIG_ERR_NOT_FOUND) {
        if (strlen(e->def_str) + 1 > buflen) {
            return APP_CONFIG_ERR_RANGE;
        }
        strcpy(buf, e->def_str);
        return APP_CONFIG_OK;
    }
    if (rc != APP_CONFIG_OK || len == 0 || buf[len - 1] != '\0') {
        return APP_CONFIG_ERR;
    }
    return APP_CONFIG_OK;
}

int app_config_store_set_str(app_config_key_t k, const char *s) {
    if (!s_backend || (size_t)k >= APP_CONFIG_KEY_COUNT) {
        return APP_CONFIG_ERR;
    }
    const key_entry_t *e = &k_keys[k];
    if (e->type != APP_CONFIG_T_STR) {
        return APP_CONFIG_ERR_TYPE;
    }
    size_t n = strlen(s) + 1;
    if (n > e->max_len) {
        return APP_CONFIG_ERR_RANGE;
    }
    int rc = s_backend->set(s_backend->ctx, e->ns, e->key, s, n);
    if (rc == APP_CONFIG_OK) {
        notify(k);
    }
    return rc;
}

int app_config_store_get_blob(app_config_key_t k, void *buf, size_t *len) {
    if (!s_backend || (size_t)k >= APP_CONFIG_KEY_COUNT) {
        return APP_CONFIG_ERR;
    }
    const key_entry_t *e = &k_keys[k];
    if (e->type != APP_CONFIG_T_BLOB) {
        return APP_CONFIG_ERR_TYPE;
    }
    int rc = s_backend->get(s_backend->ctx, e->ns, e->key, buf, len);
    if (rc == APP_CONFIG_ERR_NOT_FOUND) {
        *len = 0;
        return APP_CONFIG_OK;
    }
    return rc;
}

int app_config_store_set_blob(app_config_key_t k, const void *val,
                              size_t len) {
    if (!s_backend || (size_t)k >= APP_CONFIG_KEY_COUNT) {
        return APP_CONFIG_ERR;
    }
    const key_entry_t *e = &k_keys[k];
    if (e->type != APP_CONFIG_T_BLOB) {
        return APP_CONFIG_ERR_TYPE;
    }
    if (len > e->max_len) {
        return APP_CONFIG_ERR_RANGE;
    }
    int rc = s_backend->set(s_backend->ctx, e->ns, e->key, val, len);
    if (rc == APP_CONFIG_OK) {
        notify(k);
    }
    return rc;
}

/* ── Pairing ── */

static void pairing_to_blob(const app_config_pairing_t *p,
                            uint8_t blob[APP_CONFIG_PAIRING_BLOB_LEN]) {
    put_le(blob, p->frequency, 4);
    memcpy(blob + 4, p->device_id, 8);
    put_le(blob + 12, p->num_probes, 4);
}

static void blob_to_pairing(const uint8_t blob[APP_CONFIG_PAIRING_BLOB_LEN],
                            app_config_pairing_t *p) {
    p->frequency = (uint32_t)get_le(blob, 4);
    memcpy(p->device_id, blob + 4, 8);
    p->device_id[7] = '\0';
    p->num_probes = (uint32_t)get_le(blob + 12, 4);
}

int app_config_store_get_pairing(app_config_pairing_t *out) {
    if (!s_backend) {
        return APP_CONFIG_ERR;
    }
    uint8_t blob[APP_CONFIG_PAIRING_BLOB_LEN];
    size_t len = sizeof blob;
    int rc = s_backend->get(s_backend->ctx, NS_PAIR, KEY_PAIR, blob, &len);
    if (rc != APP_CONFIG_OK) {
        return rc;
    }
    if (len != sizeof blob) {
        return APP_CONFIG_ERR;
    }
    blob_to_pairing(blob, out);
    /* A cleared pairing is stored as all-zeroes; frequency 0 is out of band
     * and means "unpaired" (the reference's own convention). */
    if (out->frequency == 0) {
        return APP_CONFIG_ERR_NOT_FOUND;
    }
    return APP_CONFIG_OK;
}

int app_config_store_set_pairing(const app_config_pairing_t *p) {
    if (!s_backend) {
        return APP_CONFIG_ERR;
    }
    uint8_t blob[APP_CONFIG_PAIRING_BLOB_LEN];
    pairing_to_blob(p, blob);
    int rc =
        s_backend->set(s_backend->ctx, NS_PAIR, KEY_PAIR, blob, sizeof blob);
    if (rc == APP_CONFIG_OK) {
        notify(APP_CONFIG_KEY_PAIRING);
    }
    return rc;
}

int app_config_store_clear_pairing(void) {
    if (!s_backend) {
        return APP_CONFIG_ERR;
    }
    /* An all-zero blob is "unpaired": frequency 0 is out of band, matching
     * the reference's frequency==0 check. */
    uint8_t blob[APP_CONFIG_PAIRING_BLOB_LEN] = {0};
    int rc =
        s_backend->set(s_backend->ctx, NS_PAIR, KEY_PAIR, blob, sizeof blob);
    if (rc == APP_CONFIG_OK) {
        notify(APP_CONFIG_KEY_PAIRING);
    }
    return rc;
}

/* ── PSK generation (F7.3) ── */

/* No 0/O, no 1/l/I: this gets read off a 128×64 OLED in a dark yard. */
static const char k_psk_alphabet[] =
    "23456789abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ";

void app_config_generate_psk(char out[APP_CONFIG_PSK_LEN + 1],
                             uint32_t (*rng)(void)) {
    const uint32_t n = sizeof k_psk_alphabet - 1;
    /* Rejection sampling: a plain modulo would bias toward the low end of
     * the alphabet. */
    const uint32_t limit = UINT32_MAX - (UINT32_MAX % n);
    for (int i = 0; i < APP_CONFIG_PSK_LEN; i++) {
        uint32_t r;
        do {
            r = rng();
        } while (r >= limit);
        out[i] = k_psk_alphabet[r % n];
    }
    out[APP_CONFIG_PSK_LEN] = '\0';
}

/* ── Migrations (F7.2) ──
 * The stored version is the number of migrations applied; each runs at most
 * once, in order, and the version is stamped after each step. */

/* v0 → v1: adopt a reference install's pairing so an upgraded board keeps
 * it. The reference kept the identical 16-byte blob under "smoke_x"/"config";
 * an unpaired or fresh board simply has nothing to adopt. */
static int migrate_v0_to_v1(void) {
    uint8_t blob[APP_CONFIG_PAIRING_BLOB_LEN];
    size_t len = sizeof blob;
    int rc =
        s_backend->get(s_backend->ctx, NS_PAIR_REFERENCE, KEY_PAIR, blob, &len);
    if (rc == APP_CONFIG_ERR_NOT_FOUND) {
        return APP_CONFIG_OK;
    }
    if (rc != APP_CONFIG_OK || len != sizeof blob) {
        return APP_CONFIG_OK; /* malformed: start unpaired, don't brick init */
    }
    size_t have = 0;
    if (s_backend->get(s_backend->ctx, NS_PAIR, KEY_PAIR, NULL, &have) ==
        APP_CONFIG_OK) {
        return APP_CONFIG_OK; /* ours already exists; never overwrite it */
    }
    return s_backend->set(s_backend->ctx, NS_PAIR, KEY_PAIR, blob, sizeof blob);
}

static int (*const k_migrations[])(void) = {
    migrate_v0_to_v1,
};

#define CURRENT_VERSION \
    ((uint16_t)(sizeof k_migrations / sizeof k_migrations[0]))

static int run_migrations(void) {
    uint8_t vbuf[2];
    size_t len = sizeof vbuf;
    uint16_t v = 0;
    int rc = s_backend->get(s_backend->ctx, NS_META, KEY_VERSION, vbuf, &len);
    if (rc == APP_CONFIG_OK && len == sizeof vbuf) {
        v = (uint16_t)get_le(vbuf, 2);
    }
    for (; v < CURRENT_VERSION; v++) {
        rc = k_migrations[v]();
        if (rc != APP_CONFIG_OK) {
            return rc;
        }
        put_le(vbuf, (uint16_t)(v + 1), 2);
        rc = s_backend->set(s_backend->ctx, NS_META, KEY_VERSION, vbuf,
                            sizeof vbuf);
        if (rc != APP_CONFIG_OK) {
            return rc;
        }
    }
    s_version = CURRENT_VERSION;
    return APP_CONFIG_OK;
}

uint16_t app_config_store_version(void) { return s_version; }

/* ── Lifecycle ── */

static int ensure_psk(void) {
    char psk[APP_CONFIG_PSK_LEN + 1];
    int rc = app_config_store_get_str(APP_CONFIG_NET_AP_PSK, psk, sizeof psk);
    if (rc == APP_CONFIG_OK && psk[0] != '\0') {
        return APP_CONFIG_OK;
    }
    app_config_generate_psk(psk, s_rng);
    return app_config_store_set_str(APP_CONFIG_NET_AP_PSK, psk);
}

int app_config_store_init(const app_config_backend_t *backend,
                          uint32_t (*rng)(void)) {
    if (!backend || !backend->get || !backend->set || !rng) {
        return APP_CONFIG_ERR;
    }
    s_backend = backend;
    s_rng = rng;
    s_version = 0;
    int rc = run_migrations();
    if (rc != APP_CONFIG_OK) {
        return rc;
    }
    return ensure_psk();
}

int app_config_store_factory_reset(void) {
    if (!s_backend || !s_backend->erase_all) {
        return APP_CONFIG_ERR;
    }
    int rc = s_backend->erase_all(s_backend->ctx);
    if (rc != APP_CONFIG_OK) {
        return rc;
    }
    return app_config_store_init(s_backend, s_rng);
}

int app_config_store_subscribe(app_config_subscriber_t cb, void *ctx) {
    if (!cb || s_sub_count >= MAX_SUBSCRIBERS) {
        return APP_CONFIG_ERR;
    }
    s_subs[s_sub_count].cb = cb;
    s_subs[s_sub_count].ctx = ctx;
    s_sub_count++;
    return APP_CONFIG_OK;
}
