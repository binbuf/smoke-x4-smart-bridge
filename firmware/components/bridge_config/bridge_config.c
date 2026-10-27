/*
 * bridge_config.c - typed, validated NVS store core (design 03 section 3.7).
 *
 * Plain C11, no ESP-IDF, no heap. The only storage dependency is the
 * byte-oriented bridge_config_kv_t seam; bridge_config_nvs.c wires it to
 * ESP-IDF NVS. Every value is validated before a write is attempted, so a bad
 * caller value returns BRIDGE_CONFIG_ERR_INVALID and changes nothing.
 */
#include "bridge_config.h"

#include <string.h>

/* ---- key-name limit guard ------------------------------------------------ */

#define KEY_LEN(key) (sizeof(key) - 1u)
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_CONFIG_VERSION) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "config_version key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_DEVICE_ID) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "device_id key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_FREQUENCY_HZ) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "frequency_hz key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_NUM_PROBES) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "num_probes key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_PAIRED_AT) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "paired_at key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_UNITS) <= BRIDGE_CONFIG_NVS_NAME_MAX,
               "units key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_DISPLAY_TIMEOUT) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "display timeout key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_DEVICE_NAME) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "device_name key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_GENERATION) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "generation key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_CLEAR_PENDING) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "clear_pending key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_CLOCK_ANCHOR) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "clock_anchor_s key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_CLOCK_VALID) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "clock_valid key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_BOOT_COUNT) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "boot_count key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_LAST_RESET) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "last_reset key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_PACKETS_OK) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "packets_ok key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_PACKETS_BAD) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "packets_bad key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_BILLOWS_MODE) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "billows_mode key too long for NVS");
_Static_assert(KEY_LEN(BRIDGE_CONFIG_KEY_BILLOWS_TARGET) <=
                   BRIDGE_CONFIG_NVS_NAME_MAX,
               "billows target key too long for NVS");

/* ---- state --------------------------------------------------------------- */

typedef struct {
    bool ready;
    bridge_config_kv_t kv;
    bridge_config_pairing_t pairing;
    bridge_config_device_t device;
    bridge_config_log_t log;
    bridge_config_stats_t stats;
} bridge_config_state_t;

static bridge_config_state_t s_state;

static bridge_config_random_fn s_random_fn;
static void *s_random_ctx;
static bridge_config_bond_clear_fn s_bond_clear_fn;
static void *s_bond_clear_ctx;

/* ---- little-endian codec ------------------------------------------------- */

static void put_u16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)(v & 0xFFu);
    p[1] = (uint8_t)((v >> 8) & 0xFFu);
}

static void put_u32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v & 0xFFu);
    p[1] = (uint8_t)((v >> 8) & 0xFFu);
    p[2] = (uint8_t)((v >> 16) & 0xFFu);
    p[3] = (uint8_t)((v >> 24) & 0xFFu);
}

static void put_u64(uint8_t *p, uint64_t v) {
    for (unsigned int i = 0; i < 8u; i++) {
        p[i] = (uint8_t)((v >> (8u * i)) & 0xFFu);
    }
}

static uint16_t get_u16(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static uint32_t get_u32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static uint64_t get_u64(const uint8_t *p) {
    uint64_t v = 0;
    for (unsigned int i = 0; i < 8u; i++) {
        v |= (uint64_t)p[i] << (8u * i);
    }
    return v;
}

/* ---- validation ---------------------------------------------------------- */

static bool valid_utf8(const char *text) {
    const uint8_t *p = (const uint8_t *)text;
    size_t remaining = strlen(text);
    while (remaining > 0) {
        uint8_t c = *p;
        if (c == 0x00u) {
            return false;
        }
        if (c < 0x80u) {
            if (c < 0x20u || c == 0x7Fu) {
                return false; /* control characters are not a name */
            }
            p++;
            remaining--;
            continue;
        }
        size_t need;
        uint32_t cp;
        if (c >= 0xC2u && c <= 0xDFu) {
            need = 1;
            cp = c & 0x1Fu;
        } else if (c >= 0xE0u && c <= 0xEFu) {
            need = 2;
            cp = c & 0x0Fu;
        } else if (c >= 0xF0u && c <= 0xF4u) {
            need = 3;
            cp = c & 0x07u;
        } else {
            return false; /* continuation byte or overlong lead */
        }
        if (remaining < need + 1u) {
            return false;
        }
        for (size_t i = 1; i <= need; i++) {
            if ((p[i] & 0xC0u) != 0x80u) {
                return false;
            }
            cp = (cp << 6) | (uint32_t)(p[i] & 0x3Fu);
        }
        if ((need == 2 && cp < 0x800u) || (need == 3 && cp < 0x10000u) ||
            cp > 0x10FFFFu || (cp >= 0xD800u && cp <= 0xDFFFu)) {
            return false; /* overlong, surrogate, or out of range */
        }
        p += need + 1u;
        remaining -= need + 1u;
    }
    return true;
}

static bool valid_device_id(const char *id) {
    size_t len = strlen(id);
    if (len == 0 || len > BRIDGE_CONFIG_DEVICE_ID_MAX) {
        return false;
    }
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)id[i];
        if (c < 0x20u || c > 0x7Eu) {
            return false; /* the wire ID is printable ASCII */
        }
    }
    return true;
}

static bool valid_device_name(const char *name) {
    size_t len = strlen(name);
    return len > 0 && len <= BRIDGE_CONFIG_DEVICE_NAME_MAX && valid_utf8(name);
}

static bool valid_frequency(uint32_t hz) {
    return hz >= BRIDGE_CONFIG_FREQUENCY_MIN_HZ &&
           hz <= BRIDGE_CONFIG_FREQUENCY_MAX_HZ;
}

static bool valid_num_probes(uint8_t probes) {
    return probes == 2u || probes == 4u;
}

static bool valid_units(uint8_t units) {
    return units == BRIDGE_CONFIG_UNITS_CELSIUS ||
           units == BRIDGE_CONFIG_UNITS_FAHRENHEIT;
}

static bool valid_timeout(uint16_t seconds) {
    return seconds == BRIDGE_CONFIG_TIMEOUT_NEVER ||
           seconds == BRIDGE_CONFIG_TIMEOUT_30S ||
           seconds == BRIDGE_CONFIG_TIMEOUT_60S ||
           seconds == BRIDGE_CONFIG_TIMEOUT_120S;
}

/* ---- storage helpers ----------------------------------------------------- */

static bool kv_valid(const bridge_config_kv_t *kv) {
    return kv != NULL && kv->ops != NULL && kv->ops->get != NULL &&
           kv->ops->set != NULL && kv->ops->erase != NULL;
}

static int raw_get(const char *ns, const char *key, void *dst, size_t *len) {
    return s_state.kv.ops->get(s_state.kv.ctx, ns, key, dst, len);
}

static int raw_set(const char *ns, const char *key, const void *src,
                   size_t len) {
    return s_state.kv.ops->set(s_state.kv.ctx, ns, key, src, len);
}

static int raw_erase(const char *ns, const char *key) {
    return s_state.kv.ops->erase(s_state.kv.ctx, ns, key);
}

static bridge_config_result_t load_u8(const char *ns, const char *key,
                                      uint8_t *out) {
    uint8_t buf[1];
    size_t len = sizeof(buf);
    int rc = raw_get(ns, key, buf, &len);
    if (rc == BRIDGE_CONFIG_ERR_NOT_FOUND) {
        return BRIDGE_CONFIG_ERR_NOT_FOUND;
    }
    if (rc != BRIDGE_CONFIG_OK) {
        return (bridge_config_result_t)rc;
    }
    if (len != sizeof(buf)) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    *out = buf[0];
    return BRIDGE_CONFIG_OK;
}

static bridge_config_result_t load_u16(const char *ns, const char *key,
                                       uint16_t *out) {
    uint8_t buf[2];
    size_t len = sizeof(buf);
    int rc = raw_get(ns, key, buf, &len);
    if (rc == BRIDGE_CONFIG_ERR_NOT_FOUND) {
        return BRIDGE_CONFIG_ERR_NOT_FOUND;
    }
    if (rc != BRIDGE_CONFIG_OK) {
        return (bridge_config_result_t)rc;
    }
    if (len != sizeof(buf)) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    *out = get_u16(buf);
    return BRIDGE_CONFIG_OK;
}

static bridge_config_result_t load_u32(const char *ns, const char *key,
                                       uint32_t *out) {
    uint8_t buf[4];
    size_t len = sizeof(buf);
    int rc = raw_get(ns, key, buf, &len);
    if (rc == BRIDGE_CONFIG_ERR_NOT_FOUND) {
        return BRIDGE_CONFIG_ERR_NOT_FOUND;
    }
    if (rc != BRIDGE_CONFIG_OK) {
        return (bridge_config_result_t)rc;
    }
    if (len != sizeof(buf)) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    *out = get_u32(buf);
    return BRIDGE_CONFIG_OK;
}

static bridge_config_result_t load_u64(const char *ns, const char *key,
                                       uint64_t *out) {
    uint8_t buf[8];
    size_t len = sizeof(buf);
    int rc = raw_get(ns, key, buf, &len);
    if (rc == BRIDGE_CONFIG_ERR_NOT_FOUND) {
        return BRIDGE_CONFIG_ERR_NOT_FOUND;
    }
    if (rc != BRIDGE_CONFIG_OK) {
        return (bridge_config_result_t)rc;
    }
    if (len != sizeof(buf)) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    *out = get_u64(buf);
    return BRIDGE_CONFIG_OK;
}

static bridge_config_result_t store_u8(const char *ns, const char *key,
                                       uint8_t value) {
    return (bridge_config_result_t)raw_set(ns, key, &value, sizeof(value));
}

static bridge_config_result_t store_u16(const char *ns, const char *key,
                                        uint16_t value) {
    uint8_t buf[2];
    put_u16(buf, value);
    return (bridge_config_result_t)raw_set(ns, key, buf, sizeof(buf));
}

static bridge_config_result_t store_u32(const char *ns, const char *key,
                                        uint32_t value) {
    uint8_t buf[4];
    put_u32(buf, value);
    return (bridge_config_result_t)raw_set(ns, key, buf, sizeof(buf));
}

static bridge_config_result_t store_u64(const char *ns, const char *key,
                                        uint64_t value) {
    uint8_t buf[8];
    put_u64(buf, value);
    return (bridge_config_result_t)raw_set(ns, key, buf, sizeof(buf));
}

static bridge_config_result_t store_string(const char *ns, const char *key,
                                           const char *text) {
    return (bridge_config_result_t)raw_set(ns, key, text, strlen(text));
}

static bridge_config_result_t store_bool(const char *ns, const char *key,
                                         bool value) {
    return store_u8(ns, key, value ? 1u : 0u);
}

/* ---- random -------------------------------------------------------------- */

static uint32_t fallback_random(void *ctx) {
    (void)ctx;
    /* Host fallback only. The firmware adapter always installs esp_random(). */
    static uint32_t state = 0x9E3779B9u;
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

static uint32_t next_random(void) {
    bridge_config_random_fn fn = s_random_fn != NULL ? s_random_fn
                                                     : fallback_random;
    return fn(s_random_ctx);
}

static uint32_t fresh_generation(uint32_t previous) {
    uint32_t value = next_random();
    /* A clear must not keep the app cursor valid. Redraw on a collision. */
    for (unsigned int i = 0; i < 8u && value == previous; i++) {
        value = next_random();
    }
    if (value == previous) {
        value = previous ^ 0xA5A5A5A5u;
    }
    return value;
}

/* ---- data model defaults ------------------------------------------------- */

static void reset_pairing(bridge_config_pairing_t *p) {
    memset(p, 0, sizeof(*p));
}

static void reset_device(bridge_config_device_t *d) {
    memset(d, 0, sizeof(*d));
    d->units = BRIDGE_CONFIG_DEFAULT_UNITS;
    d->display_timeout_s = BRIDGE_CONFIG_DEFAULT_TIMEOUT;
    memcpy(d->device_name, BRIDGE_CONFIG_DEFAULT_DEVICE_NAME,
           sizeof(BRIDGE_CONFIG_DEFAULT_DEVICE_NAME));
}

static void reset_log_state(bridge_config_log_t *l) {
    memset(l, 0, sizeof(*l));
}

static void reset_stats(bridge_config_stats_t *st) {
    memset(st, 0, sizeof(*st));
}

static void reset_all(void) {
    reset_pairing(&s_state.pairing);
    reset_device(&s_state.device);
    reset_log_state(&s_state.log);
    reset_stats(&s_state.stats);
}

/* ---- migrations ---------------------------------------------------------- */

/*
 * v0 = the unversioned pre-T15 layout. It used the same logical keys (the
 * component never shipped, so no renamed keys exist yet). Migration scrubs a
 * value of the wrong size so the loader falls back to its default, keeps every
 * valid key, and leaves generation creation to ensure_generation().
 */
static bridge_config_result_t migrate_v0_to_v1(void) {
    static const struct {
        const char *ns;
        const char *key;
        size_t size; /* 0 = string, any non-zero size in range */
    } keys[] = {
        {BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_DEVICE_ID, 0},
        {BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_FREQUENCY_HZ, 4},
        {BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_NUM_PROBES, 1},
        {BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_PAIRED_AT, 8},
        {BRIDGE_CONFIG_NS_DEVICE, BRIDGE_CONFIG_KEY_UNITS, 1},
        {BRIDGE_CONFIG_NS_DEVICE, BRIDGE_CONFIG_KEY_DISPLAY_TIMEOUT, 2},
        {BRIDGE_CONFIG_NS_DEVICE, BRIDGE_CONFIG_KEY_DEVICE_NAME, 0},
        {BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_GENERATION, 4},
        {BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_CLEAR_PENDING, 1},
        {BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_CLOCK_ANCHOR, 8},
        {BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_CLOCK_VALID, 1},
        {BRIDGE_CONFIG_NS_STATS, BRIDGE_CONFIG_KEY_BOOT_COUNT, 4},
        {BRIDGE_CONFIG_NS_STATS, BRIDGE_CONFIG_KEY_LAST_RESET, 1},
        {BRIDGE_CONFIG_NS_STATS, BRIDGE_CONFIG_KEY_PACKETS_OK, 4},
        {BRIDGE_CONFIG_NS_STATS, BRIDGE_CONFIG_KEY_PACKETS_BAD, 4},
    };

    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
        uint8_t buf[64];
        size_t len = sizeof(buf);
        int rc = raw_get(keys[i].ns, keys[i].key, buf, &len);
        if (rc == BRIDGE_CONFIG_ERR_NOT_FOUND) {
            continue;
        }
        if (rc == BRIDGE_CONFIG_ERR_INVALID) {
            /* Backend says the stored blob is too large to be this key. */
            rc = raw_erase(keys[i].ns, keys[i].key);
            if (rc != BRIDGE_CONFIG_OK && rc != BRIDGE_CONFIG_ERR_NOT_FOUND) {
                return (bridge_config_result_t)rc;
            }
            continue;
        }
        if (rc != BRIDGE_CONFIG_OK) {
            return (bridge_config_result_t)rc;
        }
        bool bad;
        if (keys[i].size == 0) {
            bad = len == 0 || len > BRIDGE_CONFIG_NAME_BUF_SIZE - 1u;
        } else {
            bad = len != keys[i].size;
        }
        if (bad) {
            rc = raw_erase(keys[i].ns, keys[i].key);
            if (rc != BRIDGE_CONFIG_OK && rc != BRIDGE_CONFIG_ERR_NOT_FOUND) {
                return (bridge_config_result_t)rc;
            }
        }
    }
    return BRIDGE_CONFIG_OK;
}

static bridge_config_result_t ensure_generation(void) {
    uint32_t generation = 0;
    bridge_config_result_t rc = load_u32(
        BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_GENERATION, &generation);
    if (rc == BRIDGE_CONFIG_OK) {
        s_state.log.generation = generation;
        return BRIDGE_CONFIG_OK;
    }
    if (rc != BRIDGE_CONFIG_ERR_NOT_FOUND &&
        rc != BRIDGE_CONFIG_ERR_INVALID) {
        return rc;
    }
    generation = fresh_generation(0);
    rc = store_u32(BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_GENERATION,
                   generation);
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    s_state.log.generation = generation;
    return BRIDGE_CONFIG_OK;
}

/* ---- load ---------------------------------------------------------------- */

static bridge_config_result_t load_pairing(void) {
    bridge_config_pairing_t loaded;
    reset_pairing(&loaded);
    char id[BRIDGE_CONFIG_NAME_BUF_SIZE];
    size_t len = sizeof(id);
    int rc = raw_get(BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_DEVICE_ID, id, &len);
    if (rc == BRIDGE_CONFIG_ERR_NOT_FOUND) {
        return BRIDGE_CONFIG_OK; /* unpaired */
    }
    if (rc != BRIDGE_CONFIG_OK) {
        return (bridge_config_result_t)rc;
    }
    if (len == 0 || len > BRIDGE_CONFIG_DEVICE_ID_MAX) {
        return BRIDGE_CONFIG_OK; /* corrupt pairing reads as unpaired */
    }
    id[len] = '\0';
    if (!valid_device_id(id)) {
        return BRIDGE_CONFIG_OK;
    }

    uint32_t frequency = 0;
    uint8_t probes = 0;
    uint64_t paired_at = 0;
    bridge_config_result_t frc =
        load_u32(BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_FREQUENCY_HZ,
                 &frequency);
    bridge_config_result_t prc = load_u8(
        BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_NUM_PROBES, &probes);
    bridge_config_result_t trc =
        load_u64(BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_PAIRED_AT,
                 &paired_at);
    if (frc == BRIDGE_CONFIG_ERR_IO || prc == BRIDGE_CONFIG_ERR_IO ||
        trc == BRIDGE_CONFIG_ERR_IO) {
        return BRIDGE_CONFIG_ERR_IO;
    }
    if (frc != BRIDGE_CONFIG_OK || prc != BRIDGE_CONFIG_OK ||
        !valid_frequency(frequency) || !valid_num_probes(probes)) {
        return BRIDGE_CONFIG_OK; /* incomplete/corrupt record is unpaired */
    }
    if (trc == BRIDGE_CONFIG_ERR_INVALID) {
        paired_at = 0;
    }
    loaded.paired = true;
    memcpy(loaded.device_id, id, len + 1u);
    loaded.frequency_hz = frequency;
    loaded.num_probes = probes;
    loaded.paired_at = paired_at;
    s_state.pairing = loaded;
    return BRIDGE_CONFIG_OK;
}

static bridge_config_result_t load_device(void) {
    uint8_t units = BRIDGE_CONFIG_DEFAULT_UNITS;
    bridge_config_result_t rc = load_u8(
        BRIDGE_CONFIG_NS_DEVICE, BRIDGE_CONFIG_KEY_UNITS, &units);
    if (rc == BRIDGE_CONFIG_ERR_IO) {
        return rc;
    }
    if (rc != BRIDGE_CONFIG_OK || !valid_units(units)) {
        units = BRIDGE_CONFIG_DEFAULT_UNITS;
    }

    uint16_t timeout = BRIDGE_CONFIG_DEFAULT_TIMEOUT;
    rc = load_u16(BRIDGE_CONFIG_NS_DEVICE, BRIDGE_CONFIG_KEY_DISPLAY_TIMEOUT,
                  &timeout);
    if (rc == BRIDGE_CONFIG_ERR_IO) {
        return rc;
    }
    if (rc != BRIDGE_CONFIG_OK || !valid_timeout(timeout)) {
        timeout = BRIDGE_CONFIG_DEFAULT_TIMEOUT;
    }

    char name[BRIDGE_CONFIG_NAME_BUF_SIZE];
    size_t len = sizeof(name);
    int nrc = raw_get(BRIDGE_CONFIG_NS_DEVICE, BRIDGE_CONFIG_KEY_DEVICE_NAME,
                      name, &len);
    if (nrc == BRIDGE_CONFIG_ERR_IO) {
        return BRIDGE_CONFIG_ERR_IO;
    }
    if (nrc != BRIDGE_CONFIG_OK || len == 0 ||
        len > BRIDGE_CONFIG_DEVICE_NAME_MAX) {
        memcpy(name, BRIDGE_CONFIG_DEFAULT_DEVICE_NAME,
               sizeof(BRIDGE_CONFIG_DEFAULT_DEVICE_NAME));
    } else {
        name[len] = '\0';
        if (!valid_device_name(name)) {
            memcpy(name, BRIDGE_CONFIG_DEFAULT_DEVICE_NAME,
                   sizeof(BRIDGE_CONFIG_DEFAULT_DEVICE_NAME));
        }
    }

    s_state.device.units = units;
    s_state.device.display_timeout_s = timeout;
    memcpy(s_state.device.device_name, name, sizeof(s_state.device.device_name));
    return BRIDGE_CONFIG_OK;
}

static bridge_config_result_t load_log_and_clock(void) {
    uint8_t pending = 0;
    bridge_config_result_t rc = load_u8(
        BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_CLEAR_PENDING, &pending);
    if (rc == BRIDGE_CONFIG_ERR_IO) {
        return rc;
    }
    s_state.log.clear_pending =
        (rc == BRIDGE_CONFIG_OK && pending != 0u) ? true : false;

    uint64_t anchor = 0;
    rc = load_u64(BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_CLOCK_ANCHOR,
                  &anchor);
    if (rc == BRIDGE_CONFIG_ERR_IO) {
        return rc;
    }
    if (rc != BRIDGE_CONFIG_OK) {
        anchor = 0;
    }

    uint8_t clock_valid = 0;
    rc = load_u8(BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_CLOCK_VALID,
                 &clock_valid);
    if (rc == BRIDGE_CONFIG_ERR_IO) {
        return rc;
    }
    s_state.log.clock_anchor_s = anchor;
    s_state.log.clock_valid =
        (rc == BRIDGE_CONFIG_OK && clock_valid != 0u && anchor != 0u);
    return BRIDGE_CONFIG_OK;
}

static bridge_config_result_t load_stats(void) {
    bridge_config_stats_t loaded;
    reset_stats(&loaded);
    bridge_config_result_t rc = load_u32(
        BRIDGE_CONFIG_NS_STATS, BRIDGE_CONFIG_KEY_BOOT_COUNT,
        &loaded.boot_count);
    if (rc == BRIDGE_CONFIG_ERR_IO) {
        return rc;
    }
    rc = load_u8(BRIDGE_CONFIG_NS_STATS, BRIDGE_CONFIG_KEY_LAST_RESET,
                 &loaded.last_reset_reason);
    if (rc == BRIDGE_CONFIG_ERR_IO) {
        return rc;
    }
    rc = load_u32(BRIDGE_CONFIG_NS_STATS, BRIDGE_CONFIG_KEY_PACKETS_OK,
                  &loaded.packets_ok);
    if (rc == BRIDGE_CONFIG_ERR_IO) {
        return rc;
    }
    rc = load_u32(BRIDGE_CONFIG_NS_STATS, BRIDGE_CONFIG_KEY_PACKETS_BAD,
                  &loaded.packets_bad);
    if (rc == BRIDGE_CONFIG_ERR_IO) {
        return rc;
    }
    s_state.stats = loaded;
    return BRIDGE_CONFIG_OK;
}

/* ---- public core --------------------------------------------------------- */

bridge_config_result_t bridge_config_core_init(const bridge_config_kv_t *kv) {
    if (!kv_valid(kv)) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    s_state.ready = false;
    s_state.kv = *kv;
    reset_all();

    uint16_t version = 0;
    bridge_config_result_t rc = load_u16(
        BRIDGE_CONFIG_NS_META, BRIDGE_CONFIG_KEY_CONFIG_VERSION, &version);
    if (rc == BRIDGE_CONFIG_ERR_IO) {
        return rc;
    }
    if (rc == BRIDGE_CONFIG_ERR_INVALID) {
        version = 0; /* unreadable version is treated as unversioned */
    }

    if (version > BRIDGE_CONFIG_VERSION) {
        /* Never guess at a future layout; leave every byte untouched. */
        return BRIDGE_CONFIG_ERR_VERSION;
    }

    if (version < BRIDGE_CONFIG_VERSION) {
        if (version == 0) {
            rc = migrate_v0_to_v1();
            if (rc != BRIDGE_CONFIG_OK) {
                return rc;
            }
        }
        rc = ensure_generation();
        if (rc != BRIDGE_CONFIG_OK) {
            return rc;
        }
        rc = store_u16(BRIDGE_CONFIG_NS_META, BRIDGE_CONFIG_KEY_CONFIG_VERSION,
                       (uint16_t)BRIDGE_CONFIG_VERSION);
        if (rc != BRIDGE_CONFIG_OK) {
            return rc;
        }
    } else {
        rc = ensure_generation();
        if (rc != BRIDGE_CONFIG_OK) {
            return rc;
        }
    }

    rc = load_pairing();
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    rc = load_device();
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    rc = load_log_and_clock();
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    rc = load_stats();
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }

    s_state.ready = true;
    return BRIDGE_CONFIG_OK;
}

bool bridge_config_ready(void) { return s_state.ready; }

bridge_config_result_t bridge_config_get_pairing(
    bridge_config_pairing_t *out) {
    if (out == NULL) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    *out = s_state.pairing;
    return BRIDGE_CONFIG_OK;
}

static bridge_config_result_t erase_pairing_keys(void) {
    static const char *const keys[] = {
        BRIDGE_CONFIG_KEY_DEVICE_ID,
        BRIDGE_CONFIG_KEY_FREQUENCY_HZ,
        BRIDGE_CONFIG_KEY_NUM_PROBES,
        BRIDGE_CONFIG_KEY_PAIRED_AT,
    };
    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
        int rc = raw_erase(BRIDGE_CONFIG_NS_PAIR, keys[i]);
        if (rc != BRIDGE_CONFIG_OK && rc != BRIDGE_CONFIG_ERR_NOT_FOUND) {
            return (bridge_config_result_t)rc;
        }
    }
    return BRIDGE_CONFIG_OK;
}

static bridge_config_result_t restore_pairing(
    const bridge_config_pairing_t *old) {
    if (old->paired) {
        bridge_config_result_t rc = store_string(
            BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_DEVICE_ID, old->device_id);
        if (rc != BRIDGE_CONFIG_OK) {
            return rc;
        }
        rc = store_u32(BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_FREQUENCY_HZ,
                       old->frequency_hz);
        if (rc != BRIDGE_CONFIG_OK) {
            return rc;
        }
        rc = store_u8(BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_NUM_PROBES,
                      old->num_probes);
        if (rc != BRIDGE_CONFIG_OK) {
            return rc;
        }
        return store_u64(BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_PAIRED_AT,
                         old->paired_at);
    }
    return erase_pairing_keys();
}

bridge_config_result_t bridge_config_set_pairing(
    const bridge_config_pairing_t *pairing) {
    if (pairing == NULL) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    /* Validate the complete record before the first write. */
    if (!valid_device_id(pairing->device_id) ||
        !valid_frequency(pairing->frequency_hz) ||
        !valid_num_probes(pairing->num_probes)) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }

    bridge_config_pairing_t old = s_state.pairing;
    bridge_config_result_t rc = store_string(
        BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_DEVICE_ID,
        pairing->device_id);
    if (rc == BRIDGE_CONFIG_OK) {
        rc = store_u32(BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_FREQUENCY_HZ,
                       pairing->frequency_hz);
    }
    if (rc == BRIDGE_CONFIG_OK) {
        rc = store_u8(BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_NUM_PROBES,
                      pairing->num_probes);
    }
    if (rc == BRIDGE_CONFIG_OK) {
        rc = store_u64(BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_PAIRED_AT,
                       pairing->paired_at);
    }
    if (rc != BRIDGE_CONFIG_OK) {
        (void)restore_pairing(&old);
        return BRIDGE_CONFIG_ERR_IO;
    }

    bridge_config_pairing_t loaded;
    reset_pairing(&loaded);
    loaded.paired = true;
    memcpy(loaded.device_id, pairing->device_id, strlen(pairing->device_id) + 1u);
    loaded.frequency_hz = pairing->frequency_hz;
    loaded.num_probes = pairing->num_probes;
    loaded.paired_at = pairing->paired_at;
    s_state.pairing = loaded;
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_clear_pairing(void) {
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    bridge_config_result_t rc = erase_pairing_keys();
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    reset_pairing(&s_state.pairing);
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_get_device(bridge_config_device_t *out) {
    if (out == NULL) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    *out = s_state.device;
    return BRIDGE_CONFIG_OK;
}

static bridge_config_result_t restore_device(const bridge_config_device_t *old) {
    bridge_config_result_t rc =
        store_u8(BRIDGE_CONFIG_NS_DEVICE, BRIDGE_CONFIG_KEY_UNITS, old->units);
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    rc = store_u16(BRIDGE_CONFIG_NS_DEVICE,
                   BRIDGE_CONFIG_KEY_DISPLAY_TIMEOUT,
                   old->display_timeout_s);
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    return store_string(BRIDGE_CONFIG_NS_DEVICE,
                        BRIDGE_CONFIG_KEY_DEVICE_NAME, old->device_name);
}

bridge_config_result_t bridge_config_set_device(
    const bridge_config_device_t *device) {
    if (device == NULL) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    if (!valid_units(device->units) ||
        !valid_timeout(device->display_timeout_s) ||
        !valid_device_name(device->device_name)) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    bridge_config_device_t old = s_state.device;
    bridge_config_result_t rc = restore_device(device);
    if (rc != BRIDGE_CONFIG_OK) {
        (void)restore_device(&old);
        return BRIDGE_CONFIG_ERR_IO;
    }
    s_state.device = *device;
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_get_units(uint8_t *out) {
    if (out == NULL) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    *out = s_state.device.units;
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_set_units(uint8_t units) {
    if (!valid_units(units)) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    bridge_config_result_t rc =
        store_u8(BRIDGE_CONFIG_NS_DEVICE, BRIDGE_CONFIG_KEY_UNITS, units);
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    s_state.device.units = units;
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_get_display_timeout(uint16_t *out) {
    if (out == NULL) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    *out = s_state.device.display_timeout_s;
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_set_display_timeout(uint16_t seconds) {
    if (!valid_timeout(seconds)) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    bridge_config_result_t rc = store_u16(
        BRIDGE_CONFIG_NS_DEVICE, BRIDGE_CONFIG_KEY_DISPLAY_TIMEOUT, seconds);
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    s_state.device.display_timeout_s = seconds;
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_get_device_name(char *out,
                                                     size_t out_size) {
    if (out == NULL || out_size == 0) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    size_t len = strlen(s_state.device.device_name);
    if (out_size < len + 1u) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    memcpy(out, s_state.device.device_name, len + 1u);
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_set_device_name(const char *name) {
    if (name == NULL || !valid_device_name(name)) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    bridge_config_result_t rc = store_string(
        BRIDGE_CONFIG_NS_DEVICE, BRIDGE_CONFIG_KEY_DEVICE_NAME, name);
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    memset(s_state.device.device_name, 0, sizeof(s_state.device.device_name));
    memcpy(s_state.device.device_name, name, strlen(name));
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_get_reserved_billows(uint8_t *mode,
                                                          int16_t *target_f10) {
    /* Reserved in the MVP: report constants, never open the reserved keys. */
    if (mode != NULL) {
        *mode = 0;
    }
    if (target_f10 != NULL) {
        *target_f10 = 0;
    }
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_get_log(bridge_config_log_t *out) {
    if (out == NULL) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    *out = s_state.log;
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_get_generation(uint32_t *out) {
    if (out == NULL) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    *out = s_state.log.generation;
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_set_generation(uint32_t generation) {
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    bridge_config_result_t rc = store_u32(
        BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_GENERATION, generation);
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    s_state.log.generation = generation;
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_regenerate_generation(uint32_t *out) {
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    uint32_t generation = fresh_generation(s_state.log.generation);
    bridge_config_result_t rc = store_u32(
        BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_GENERATION, generation);
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    s_state.log.generation = generation;
    if (out != NULL) {
        *out = generation;
    }
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_begin_log_clear(uint32_t *out) {
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    uint32_t old_generation = s_state.log.generation;
    uint32_t generation = fresh_generation(old_generation);
    /* Generation is on flash before the caller erases anything. */
    bridge_config_result_t rc = store_u32(
        BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_GENERATION, generation);
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    rc = store_bool(BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_CLEAR_PENDING,
                    true);
    if (rc != BRIDGE_CONFIG_OK) {
        (void)store_u32(BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_GENERATION,
                        old_generation);
        return rc;
    }
    s_state.log.generation = generation;
    s_state.log.clear_pending = true;
    if (out != NULL) {
        *out = generation;
    }
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_finish_log_clear(void) {
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    bridge_config_result_t rc = store_bool(
        BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_CLEAR_PENDING, false);
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    s_state.log.clear_pending = false;
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_clock_get(uint64_t *anchor_s,
                                               bool *valid) {
    if (anchor_s == NULL || valid == NULL) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    *anchor_s = s_state.log.clock_anchor_s;
    *valid = s_state.log.clock_valid;
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_clock_set(uint64_t anchor_s, bool valid) {
    if (valid && anchor_s == 0) {
        return BRIDGE_CONFIG_ERR_INVALID; /* 0 is "unknown", not a valid time */
    }
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    uint64_t old_anchor = s_state.log.clock_anchor_s;
    bridge_config_result_t rc = store_u64(
        BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_CLOCK_ANCHOR, anchor_s);
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    rc = store_bool(BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_CLOCK_VALID,
                    valid);
    if (rc != BRIDGE_CONFIG_OK) {
        (void)store_u64(BRIDGE_CONFIG_NS_LOG,
                        BRIDGE_CONFIG_KEY_CLOCK_ANCHOR, old_anchor);
        return rc;
    }
    s_state.log.clock_anchor_s = anchor_s;
    s_state.log.clock_valid = valid;
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_stats_get(bridge_config_stats_t *out) {
    if (out == NULL) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    *out = s_state.stats;
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_stats_note_boot(uint8_t reset_reason) {
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    uint32_t old_count = s_state.stats.boot_count;
    uint32_t count = old_count + 1u;
    bridge_config_result_t rc = store_u32(
        BRIDGE_CONFIG_NS_STATS, BRIDGE_CONFIG_KEY_BOOT_COUNT, count);
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    rc = store_u8(BRIDGE_CONFIG_NS_STATS, BRIDGE_CONFIG_KEY_LAST_RESET,
                  reset_reason);
    if (rc != BRIDGE_CONFIG_OK) {
        (void)store_u32(BRIDGE_CONFIG_NS_STATS,
                        BRIDGE_CONFIG_KEY_BOOT_COUNT, old_count);
        return rc;
    }
    s_state.stats.boot_count = count;
    s_state.stats.last_reset_reason = reset_reason;
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_stats_set_packets_ok(uint32_t count) {
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    bridge_config_result_t rc = store_u32(
        BRIDGE_CONFIG_NS_STATS, BRIDGE_CONFIG_KEY_PACKETS_OK, count);
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    s_state.stats.packets_ok = count;
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_stats_set_packets_bad(uint32_t count) {
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    bridge_config_result_t rc = store_u32(
        BRIDGE_CONFIG_NS_STATS, BRIDGE_CONFIG_KEY_PACKETS_BAD, count);
    if (rc != BRIDGE_CONFIG_OK) {
        return rc;
    }
    s_state.stats.packets_bad = count;
    return BRIDGE_CONFIG_OK;
}

bridge_config_result_t bridge_config_clear_bonds(void) {
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    if (s_bond_clear_fn == NULL) {
        return BRIDGE_CONFIG_OK; /* no NimBLE in the build yet */
    }
    return s_bond_clear_fn(s_bond_clear_ctx) == 0 ? BRIDGE_CONFIG_OK
                                                 : BRIDGE_CONFIG_ERR_IO;
}

/* ---- factory reset ------------------------------------------------------- */

static const bridge_config_reset_step_t k_reset_steps[] = {
    {BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_GENERATION,
     BRIDGE_CONFIG_RESET_NEW_GENERATION},
    {BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_CLEAR_PENDING,
     BRIDGE_CONFIG_RESET_SET_CLEAR_PENDING},
    {BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_DEVICE_ID,
     BRIDGE_CONFIG_RESET_ERASE},
    {BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_FREQUENCY_HZ,
     BRIDGE_CONFIG_RESET_ERASE},
    {BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_NUM_PROBES,
     BRIDGE_CONFIG_RESET_ERASE},
    {BRIDGE_CONFIG_NS_PAIR, BRIDGE_CONFIG_KEY_PAIRED_AT,
     BRIDGE_CONFIG_RESET_ERASE},
    {BRIDGE_CONFIG_NS_DEVICE, BRIDGE_CONFIG_KEY_UNITS,
     BRIDGE_CONFIG_RESET_ERASE},
    {BRIDGE_CONFIG_NS_DEVICE, BRIDGE_CONFIG_KEY_DISPLAY_TIMEOUT,
     BRIDGE_CONFIG_RESET_ERASE},
    {BRIDGE_CONFIG_NS_DEVICE, BRIDGE_CONFIG_KEY_DEVICE_NAME,
     BRIDGE_CONFIG_RESET_ERASE},
    /* Reserved Billows keys are never written by the MVP; erasing them here
     * keeps one reset list if a future control build ever stores them. */
    {BRIDGE_CONFIG_NS_DEVICE, BRIDGE_CONFIG_KEY_BILLOWS_MODE,
     BRIDGE_CONFIG_RESET_ERASE},
    {BRIDGE_CONFIG_NS_DEVICE, BRIDGE_CONFIG_KEY_BILLOWS_TARGET,
     BRIDGE_CONFIG_RESET_ERASE},
    {BRIDGE_CONFIG_NS_STATS, BRIDGE_CONFIG_KEY_BOOT_COUNT,
     BRIDGE_CONFIG_RESET_ERASE},
    {BRIDGE_CONFIG_NS_STATS, BRIDGE_CONFIG_KEY_LAST_RESET,
     BRIDGE_CONFIG_RESET_ERASE},
    {BRIDGE_CONFIG_NS_STATS, BRIDGE_CONFIG_KEY_PACKETS_OK,
     BRIDGE_CONFIG_RESET_ERASE},
    {BRIDGE_CONFIG_NS_STATS, BRIDGE_CONFIG_KEY_PACKETS_BAD,
     BRIDGE_CONFIG_RESET_ERASE},
    {BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_CLOCK_ANCHOR,
     BRIDGE_CONFIG_RESET_ERASE},
    {BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_CLOCK_VALID,
     BRIDGE_CONFIG_RESET_ERASE},
    /* The documented foreign namespace is cleared only through our wrapper. */
    {NULL, NULL, BRIDGE_CONFIG_RESET_CLEAR_BONDS},
};

const bridge_config_reset_step_t *bridge_config_factory_reset_steps(
    size_t *count) {
    if (count != NULL) {
        *count = sizeof(k_reset_steps) / sizeof(k_reset_steps[0]);
    }
    return k_reset_steps;
}

bridge_config_result_t bridge_config_factory_reset(void) {
    if (!s_state.ready) {
        return BRIDGE_CONFIG_ERR_STATE;
    }
    bool io_error = false;
    reset_pairing(&s_state.pairing);
    reset_device(&s_state.device);
    reset_stats(&s_state.stats);
    s_state.log.clock_anchor_s = 0;
    s_state.log.clock_valid = false;

    for (size_t i = 0;
         i < sizeof(k_reset_steps) / sizeof(k_reset_steps[0]); i++) {
        const bridge_config_reset_step_t *step = &k_reset_steps[i];
        switch ((bridge_config_reset_action_t)step->action) {
        case BRIDGE_CONFIG_RESET_NEW_GENERATION: {
            uint32_t generation = 0;
            if (bridge_config_regenerate_generation(&generation) !=
                BRIDGE_CONFIG_OK) {
                return BRIDGE_CONFIG_ERR_IO;
            }
            break;
        }
        case BRIDGE_CONFIG_RESET_SET_CLEAR_PENDING: {
            bridge_config_result_t rc = store_bool(
                BRIDGE_CONFIG_NS_LOG, BRIDGE_CONFIG_KEY_CLEAR_PENDING, true);
            if (rc != BRIDGE_CONFIG_OK) {
                return BRIDGE_CONFIG_ERR_IO;
            }
            s_state.log.clear_pending = true;
            break;
        }
        case BRIDGE_CONFIG_RESET_ERASE: {
            int rc = raw_erase(step->ns, step->key);
            if (rc != BRIDGE_CONFIG_OK && rc != BRIDGE_CONFIG_ERR_NOT_FOUND) {
                io_error = true;
            }
            break;
        }
        case BRIDGE_CONFIG_RESET_CLEAR_BONDS:
            if (bridge_config_clear_bonds() != BRIDGE_CONFIG_OK) {
                io_error = true;
            }
            break;
        default:
            io_error = true;
            break;
        }
    }
    return io_error ? BRIDGE_CONFIG_ERR_IO : BRIDGE_CONFIG_OK;
}

/* ---- hooks --------------------------------------------------------------- */

void bridge_config_set_random_source(bridge_config_random_fn fn, void *ctx) {
    s_random_fn = fn;
    s_random_ctx = ctx;
}

void bridge_config_set_bond_clear_hook(bridge_config_bond_clear_fn fn,
                                       void *ctx) {
    s_bond_clear_fn = fn;
    s_bond_clear_ctx = ctx;
}
