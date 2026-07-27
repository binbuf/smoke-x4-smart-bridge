/* app_config_store — the typed configuration layer (design 03 §3.6).
 *
 * Pure C11, no ESP-IDF headers: the whole schema, migration, notification,
 * and PSK-generation logic runs in the host test suite. The device binding
 * (app_config.c) supplies an NVS-backed app_config_backend_t and the
 * hardware RNG; tests supply an in-memory backend and a fake RNG.
 *
 * No other component opens NVS directly — that is the rule this component
 * exists to enforce (the reference scatters nvs_open across four files).
 */
#ifndef APP_CONFIG_STORE_H
#define APP_CONFIG_STORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define APP_CONFIG_OK 0
#define APP_CONFIG_ERR -1
#define APP_CONFIG_ERR_NOT_FOUND -2
#define APP_CONFIG_ERR_TYPE -3
#define APP_CONFIG_ERR_RANGE -4

/* Storage backend. `get` with out == NULL writes the stored size to *len and
 * returns APP_CONFIG_OK, or APP_CONFIG_ERR_NOT_FOUND. All calls return
 * APP_CONFIG_OK on success. */
typedef struct {
    int (*get)(void *ctx, const char *ns, const char *key, void *out,
               size_t *len);
    int (*set)(void *ctx, const char *ns, const char *key, const void *val,
               size_t len);
    int (*erase_all)(void *ctx);
    void *ctx;
} app_config_backend_t;

typedef enum {
    APP_CONFIG_T_U8,
    APP_CONFIG_T_U16,
    APP_CONFIG_T_U32,
    APP_CONFIG_T_U64,
    APP_CONFIG_T_I32,
    APP_CONFIG_T_STR,  /* max_len includes the terminating NUL */
    APP_CONFIG_T_BLOB, /* max_len is the capacity */
} app_config_type_t;

/* The §3.6 schema. sx_pair is deliberately absent: it is a single
 * reference-compatible blob with its own accessors below. */
#define APP_CONFIG_KEY_TABLE(X)                                        \
    /*  id                      ns        key          type  max  def  \
     *                                                       len  num  def_str */ \
    X(NET_MODE, "net", "mode", U8, 1, 0, "")                           \
    X(NET_STA_SSID, "net", "sta_ssid", STR, 33, 0, "")                 \
    X(NET_STA_PSK, "net", "sta_psk", STR, 65, 0, "")                   \
    X(NET_STA_AUTH, "net", "sta_auth", U8, 1, 0, "")                   \
    X(NET_STA_USER, "net", "sta_user", STR, 33, 0, "")                 \
    X(NET_AP_SSID, "net", "ap_ssid", STR, 33, 0, "")                   \
    X(NET_AP_PSK, "net", "ap_psk", STR, 11, 0, "")                     \
    X(NET_HOSTNAME, "net", "hostname", STR, 33, 0, "smokebridge")      \
    X(DEV_UNITS, "device", "units", U8, 1, 0, "")                      \
    X(DEV_DISPLAY_TIMEOUT_S, "device", "disp_timeout", U16, 2, 60, "") \
    X(DEV_LED_ENABLED, "device", "led_enabled", U8, 1, 1, "")          \
    X(DEV_BUZZER_ENABLED, "device", "buzzer_en", U8, 1, 1, "")         \
    X(DEV_BATTERY_SAVER, "device", "batt_saver", U8, 1, 0, "")         \
    /* batt_mah is the pack's rated capacity, for the label and a future \
     * mA-draw diagnostic ONLY. SoC% is a VOLTAGE lookup (power_core      \
     * k_curve[]), capacity-independent and already correct for any       \
     * single-cell LiPo — batt_mah is deliberately NOT wired into it. */  \
    X(DEV_BATTERY_MAH, "device", "batt_mah", U16, 2, 3000, "")         \
    X(DEV_VBAT_CAL_NUM, "device", "vbat_cal_num", U16, 2, 0, "")       \
    X(DEV_VBAT_CAL_DEN, "device", "vbat_cal_den", U16, 2, 0, "")       \
    X(DEV_API_TOKEN, "device", "api_token", STR, 33, 0, "")            \
    X(DEV_RETENTION_MAX_SESSIONS, "device", "ret_max_sess", U8, 1, 64, \
      "")                                                              \
    X(DEV_RETENTION_MIN_FREE_PCT, "device", "ret_min_free", U8, 1, 10, \
      "")                                                              \
    X(PROBE1_NAME, "probes", "p1_name", STR, 17, 0, "")                \
    X(PROBE1_ROLE, "probes", "p1_role", U8, 1, 0, "")                  \
    X(PROBE1_TARGET, "probes", "p1_target", I32, 4, 0, "")             \
    X(PROBE2_NAME, "probes", "p2_name", STR, 17, 0, "")                \
    X(PROBE2_ROLE, "probes", "p2_role", U8, 1, 1, "")                  \
    X(PROBE2_TARGET, "probes", "p2_target", I32, 4, 0, "")             \
    X(PROBE3_NAME, "probes", "p3_name", STR, 17, 0, "")                \
    X(PROBE3_ROLE, "probes", "p3_role", U8, 1, 1, "")                  \
    X(PROBE3_TARGET, "probes", "p3_target", I32, 4, 0, "")             \
    X(PROBE4_NAME, "probes", "p4_name", STR, 17, 0, "")                \
    X(PROBE4_ROLE, "probes", "p4_role", U8, 1, 1, "")                  \
    X(PROBE4_TARGET, "probes", "p4_target", I32, 4, 0, "")             \
    X(SESSION_NEXT_ID, "session", "next_id", U32, 4, 1, "")            \
    X(SESSION_ACTIVE_ID, "session", "active_id", U32, 4, 0, "")        \
    X(TIME_LAST_EPOCH_MS, "time", "last_epoch_ms", U64, 8, 0, "")      \
    X(TIME_TZ_OFFSET_MIN, "time", "tz_offset_min", I32, 4, 0, "")      \
    X(TIME_SOURCE, "time", "source", U8, 1, 0, "")                     \
    X(ALARM_RULES, "alarms", "rules", BLOB, 64, 0, "")                 \
    /* MQTT / Home Assistant (05 §5.7 add-on). Wi-Fi-only, opt-in. The     \
     * password follows the sta_psk read-back discipline: it is written    \
     * here but never returned by any GET. STR max_len includes the NUL.   \
     * Plaintext mqtt:// in v1 — no TLS keys (that is a heap-budget         \
     * conversation of its own, D2/03 §3.7). */                            \
    X(MQTT_ENABLED, "mqtt", "enabled", U8, 1, 0, "")                   \
    X(MQTT_HOST, "mqtt", "host", STR, 65, 0, "")                       \
    X(MQTT_PORT, "mqtt", "port", U16, 2, 1883, "")                     \
    X(MQTT_USER, "mqtt", "user", STR, 65, 0, "")                       \
    X(MQTT_PASS, "mqtt", "pass", STR, 65, 0, "")                       \
    X(MQTT_PREFIX, "mqtt", "prefix", STR, 33, 0, "smokebridge")        \
    X(MQTT_HA_DISCOVERY, "mqtt", "ha_disc", U8, 1, 1, "")

typedef enum {
#define X(id, ns, key, type, len, dnum, dstr) APP_CONFIG_##id,
    APP_CONFIG_KEY_TABLE(X)
#undef X
        APP_CONFIG_KEY_COUNT,
    /* Pseudo-key reported to subscribers for sx_pair changes. */
    APP_CONFIG_KEY_PAIRING = APP_CONFIG_KEY_COUNT,
} app_config_key_t;

/* net/mode values */
enum { APP_CONFIG_NET_MODE_AP = 0, APP_CONFIG_NET_MODE_STA = 1 };
/* device/units values */
enum { APP_CONFIG_UNITS_F = 0, APP_CONFIG_UNITS_C = 1 };
/* probes/p*_role values (§3.6: the Smoke X does not distinguish; the user
 * does) */
enum {
    APP_CONFIG_ROLE_PIT = 0,
    APP_CONFIG_ROLE_FOOD = 1,
    APP_CONFIG_ROLE_AMBIENT = 2,
    APP_CONFIG_ROLE_UNUSED = 3,
};
/* time/source values */
enum {
    APP_CONFIG_TIME_NONE = 0,
    APP_CONFIG_TIME_SNTP = 1,
    APP_CONFIG_TIME_PHONE = 2,
    APP_CONFIG_TIME_STALE = 3,
};

typedef struct {
    const char *ns;
    const char *key;
    app_config_type_t type;
    size_t max_len;
} app_config_key_info_t;

const app_config_key_info_t *app_config_store_key_info(app_config_key_t k);

/* ── Pairing: the sx_pair blob ──────────────────────────────────────────
 * Byte-for-byte the reference's smoke_x_config_t (namespace "smoke_x", key
 * "config"), so an upgraded board keeps its pairing: u32 frequency @0,
 * char[8] device_id @4, u32 num_probes @12 — 16 bytes, little-endian. */
typedef struct {
    uint32_t frequency; /* Hz */
    char device_id[8];  /* NUL-terminated */
    uint32_t num_probes;
} app_config_pairing_t;

#define APP_CONFIG_PAIRING_BLOB_LEN 16

/* ── Lifecycle ── */

/* Wires the backend, runs pending migrations (v0→v1 adopts a reference
 * install's pairing), and generates the AP PSK on first boot. `rng` is the
 * entropy source for PSK generation (esp_random on device). */
int app_config_store_init(const app_config_backend_t *backend,
                          uint32_t (*rng)(void));

/* Applied-migration count of the store (0 = pre-migration/reference). */
uint16_t app_config_store_version(void);

/* Erases everything and re-runs init (fresh PSK, defaults, migrations). */
int app_config_store_factory_reset(void);

/* ── Typed access. Get returns the schema default when unset. ── */

int app_config_store_get_u8(app_config_key_t k, uint8_t *out);
int app_config_store_set_u8(app_config_key_t k, uint8_t v);
int app_config_store_get_u16(app_config_key_t k, uint16_t *out);
int app_config_store_set_u16(app_config_key_t k, uint16_t v);
int app_config_store_get_u32(app_config_key_t k, uint32_t *out);
int app_config_store_set_u32(app_config_key_t k, uint32_t v);
int app_config_store_get_u64(app_config_key_t k, uint64_t *out);
int app_config_store_set_u64(app_config_key_t k, uint64_t v);
int app_config_store_get_i32(app_config_key_t k, int32_t *out);
int app_config_store_set_i32(app_config_key_t k, int32_t v);
int app_config_store_get_str(app_config_key_t k, char *buf, size_t buflen);
int app_config_store_set_str(app_config_key_t k, const char *s);
/* *len in: capacity of buf; out: stored size (0 when unset). */
int app_config_store_get_blob(app_config_key_t k, void *buf, size_t *len);
int app_config_store_set_blob(app_config_key_t k, const void *val, size_t len);

/* ── Pairing access ── */

/* APP_CONFIG_ERR_NOT_FOUND when unpaired. */
int app_config_store_get_pairing(app_config_pairing_t *out);
int app_config_store_set_pairing(const app_config_pairing_t *p);
int app_config_store_clear_pairing(void);

/* ── Change notifications (F7.2) ──
 * Exactly one callback per successful write. Consumers subscribe instead of
 * re-reading NVS. */
typedef void (*app_config_subscriber_t)(app_config_key_t key, void *ctx);
int app_config_store_subscribe(app_config_subscriber_t cb, void *ctx);

/* ── AP PSK (F7.3) ──
 * 10 chars over an alphabet with no 0/O, 1/l/I — read off a 128×64 OLED in a
 * dark yard. Exposed for tests; init calls it on first boot. */
#define APP_CONFIG_PSK_LEN 10
void app_config_generate_psk(char out[APP_CONFIG_PSK_LEN + 1],
                             uint32_t (*rng)(void));

#ifdef __cplusplus
}
#endif

#endif /* APP_CONFIG_STORE_H */
