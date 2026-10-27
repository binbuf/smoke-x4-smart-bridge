/*
 * bridge_config.h - the only owner of the bridge NVS namespaces (design 03
 * section 3.7). Typed, validated getters and setters for pairing, device
 * settings, log state, the clock anchor and boot counters.
 *
 * The core (`bridge_config.c`) is plain C11 with no ESP-IDF dependency. It
 * talks to a small byte-oriented key/value seam (`bridge_config_kv_t`) so the
 * host tests run the same code against RAM. `bridge_config_nvs.c` is the
 * firmware adapter and the only file that calls nvs_open()/nvs_get_blob().
 *
 * Logical keys follow design 03 section 3.7. ESP-IDF limits an NVS key to 15
 * characters, so three long logical names have documented physical aliases
 * (see the header constants below and ADR 0023). Callers use the typed API,
 * never a raw key.
 */
#ifndef SX4_BRIDGE_CONFIG_H
#define SX4_BRIDGE_CONFIG_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Logical layout version. Bumped only when a forward migration exists. */
#define BRIDGE_CONFIG_VERSION 1u

/* NVS name limit (ESP-IDF NVS_KEY_NAME_MAX_SIZE - 1). */
#define BRIDGE_CONFIG_NVS_NAME_MAX 15u

/* Namespaces. `meta` holds config_version; it is not user data. */
#define BRIDGE_CONFIG_NS_PAIR "pair"
#define BRIDGE_CONFIG_NS_DEVICE "device"
#define BRIDGE_CONFIG_NS_LOG "log"
#define BRIDGE_CONFIG_NS_STATS "stats"
#define BRIDGE_CONFIG_NS_META "meta"

/*
 * Physical keys. Logical names that fit within 15 characters are unchanged.
 *   display_timeout_s -> disp_timeout_s
 *   last_reset_reason -> last_reset
 *   billows_target_f10 -> billows_tgt_f10 (reserved, never written)
 */
#define BRIDGE_CONFIG_KEY_CONFIG_VERSION "config_version"
#define BRIDGE_CONFIG_KEY_DEVICE_ID "device_id"
#define BRIDGE_CONFIG_KEY_FREQUENCY_HZ "frequency_hz"
#define BRIDGE_CONFIG_KEY_NUM_PROBES "num_probes"
#define BRIDGE_CONFIG_KEY_PAIRED_AT "paired_at"
#define BRIDGE_CONFIG_KEY_UNITS "units"
#define BRIDGE_CONFIG_KEY_DISPLAY_TIMEOUT "disp_timeout_s"
#define BRIDGE_CONFIG_KEY_DEVICE_NAME "device_name"
#define BRIDGE_CONFIG_KEY_BILLOWS_MODE "billows_mode"
#define BRIDGE_CONFIG_KEY_BILLOWS_TARGET "billows_tgt_f10"
#define BRIDGE_CONFIG_KEY_GENERATION "generation"
#define BRIDGE_CONFIG_KEY_CLEAR_PENDING "clear_pending"
#define BRIDGE_CONFIG_KEY_CLOCK_ANCHOR "clock_anchor_s"
#define BRIDGE_CONFIG_KEY_CLOCK_UPTIME "clock_uptime_s"
#define BRIDGE_CONFIG_KEY_CLOCK_VALID "clock_valid"
#define BRIDGE_CONFIG_KEY_BOOT_COUNT "boot_count"
#define BRIDGE_CONFIG_KEY_LAST_RESET "last_reset"
#define BRIDGE_CONFIG_KEY_PACKETS_OK "packets_ok"
#define BRIDGE_CONFIG_KEY_PACKETS_BAD "packets_bad"

/* Validation constants (design 03 section 3.7, design 05 section 5.9). */
#define BRIDGE_CONFIG_FREQUENCY_MIN_HZ 902000000u
#define BRIDGE_CONFIG_FREQUENCY_MAX_HZ 928000000u
#define BRIDGE_CONFIG_DEVICE_ID_MAX 15u
#define BRIDGE_CONFIG_DEVICE_NAME_MAX 15u
#define BRIDGE_CONFIG_NAME_BUF_SIZE 16u

#define BRIDGE_CONFIG_UNITS_CELSIUS 0u
#define BRIDGE_CONFIG_UNITS_FAHRENHEIT 1u

#define BRIDGE_CONFIG_TIMEOUT_NEVER 0u
#define BRIDGE_CONFIG_TIMEOUT_30S 30u
#define BRIDGE_CONFIG_TIMEOUT_60S 60u
#define BRIDGE_CONFIG_TIMEOUT_120S 120u

/* Defaults used until a value is written. */
#define BRIDGE_CONFIG_DEFAULT_UNITS BRIDGE_CONFIG_UNITS_FAHRENHEIT
#define BRIDGE_CONFIG_DEFAULT_TIMEOUT BRIDGE_CONFIG_TIMEOUT_60S
#define BRIDGE_CONFIG_DEFAULT_DEVICE_NAME "Smoke X4 Bridge"

/* Result codes. Non-zero leaves the previous value and the cache intact. */
typedef enum {
    BRIDGE_CONFIG_OK = 0,
    BRIDGE_CONFIG_ERR_INVALID = -1, /* failed validation: nothing written */
    BRIDGE_CONFIG_ERR_NOT_FOUND = -2,
    BRIDGE_CONFIG_ERR_IO = -3,      /* backend read/write/erase failed */
    BRIDGE_CONFIG_ERR_VERSION = -4, /* NVS layout newer than this firmware */
    BRIDGE_CONFIG_ERR_STATE = -5,   /* core_init() has not succeeded */
} bridge_config_result_t;

/*
 * Byte-oriented key/value seam. `get` takes capacity in *len and returns the
 * actual length in *len. Missing keys return BRIDGE_CONFIG_ERR_NOT_FOUND;
 * transport failures return BRIDGE_CONFIG_ERR_IO. The firmware adapter wraps
 * ESP-IDF NVS blobs; the host tests wrap RAM.
 */
typedef struct {
    int (*get)(void *ctx, const char *ns, const char *key, void *dst,
               size_t *len);
    int (*set)(void *ctx, const char *ns, const char *key, const void *src,
               size_t len);
    int (*erase)(void *ctx, const char *ns, const char *key);
} bridge_config_kv_ops_t;

typedef struct {
    const bridge_config_kv_ops_t *ops;
    void *ctx;
} bridge_config_kv_t;

/* 32-bit random source. The firmware adapter installs esp_random(). */
typedef uint32_t (*bridge_config_random_fn)(void *ctx);

/* NimBLE bond-store clear hook, owned and called by this component only. */
typedef int (*bridge_config_bond_clear_fn)(void *ctx);

typedef struct {
    bool paired; /* set by get; ignored by set */
    char device_id[BRIDGE_CONFIG_NAME_BUF_SIZE];
    uint32_t frequency_hz;
    uint8_t num_probes;
    uint64_t paired_at; /* Unix seconds; 0 = unknown */
} bridge_config_pairing_t;

typedef struct {
    uint8_t units;
    uint16_t display_timeout_s;
    char device_name[BRIDGE_CONFIG_NAME_BUF_SIZE];
} bridge_config_device_t;

typedef struct {
    uint32_t generation;
    bool clear_pending;
    uint64_t clock_anchor_s;
    /* Uptime (seconds) at which clock_anchor_s was captured. 0 = unknown.
     * Persisted with the anchor so a monotonic source that survives deep sleep
     * can advance the estimated clock after a wake (T20). */
    uint64_t clock_uptime_s;
    bool clock_valid;
} bridge_config_log_t;

typedef struct {
    uint32_t boot_count;
    uint8_t last_reset_reason;
    uint32_t packets_ok;
    uint32_t packets_bad;
} bridge_config_stats_t;

/* Factory-reset table actions. */
typedef enum {
    BRIDGE_CONFIG_RESET_NEW_GENERATION = 0, /* random generation first */
    BRIDGE_CONFIG_RESET_SET_CLEAR_PENDING,  /* then mark the clear pending */
    BRIDGE_CONFIG_RESET_ERASE,              /* erase one key */
    BRIDGE_CONFIG_RESET_CLEAR_BONDS,        /* NimBLE bond store */
} bridge_config_reset_action_t;

typedef struct {
    const char *ns;  /* NULL only for CLEAR_BONDS */
    const char *key; /* NULL for CLEAR_BONDS */
    uint8_t action;  /* bridge_config_reset_action_t */
} bridge_config_reset_step_t;

/* Install the backend and load (or migrate) everything. The backend must
 * outlive the core. Re-calling re-reads from the backend and is safe. */
bridge_config_result_t bridge_config_core_init(const bridge_config_kv_t *kv);

bool bridge_config_ready(void);

/* Pairing. set_pairing validates the whole record before writing any key. */
bridge_config_result_t bridge_config_get_pairing(bridge_config_pairing_t *out);
bridge_config_result_t bridge_config_set_pairing(
    const bridge_config_pairing_t *pairing);
/* Re-pair (T16): clears pairing only. Log, bonds and generation are kept. */
bridge_config_result_t bridge_config_clear_pairing(void);

/* Device settings. Reserved Billows keys have no setter and are never
 * written; get_reserved_billows reports the MVP constants (0 / 0). */
bridge_config_result_t bridge_config_get_device(bridge_config_device_t *out);
bridge_config_result_t bridge_config_set_device(
    const bridge_config_device_t *device);
bridge_config_result_t bridge_config_get_units(uint8_t *out);
bridge_config_result_t bridge_config_set_units(uint8_t units);
bridge_config_result_t bridge_config_get_display_timeout(uint16_t *out);
bridge_config_result_t bridge_config_set_display_timeout(uint16_t seconds);
bridge_config_result_t bridge_config_get_device_name(char *out, size_t out_size);
bridge_config_result_t bridge_config_set_device_name(const char *name);
bridge_config_result_t bridge_config_get_reserved_billows(uint8_t *mode,
                                                          int16_t *target_f10);

/* Log state. Pairing is never touched by any of these. */
bridge_config_result_t bridge_config_get_log(bridge_config_log_t *out);
bridge_config_result_t bridge_config_get_generation(uint32_t *out);
/* T19 only: adopt the generation recovered from the newest sector header. */
bridge_config_result_t bridge_config_set_generation(uint32_t generation);
/* T19 only: whole-log corruption. Never call for a single bad sector. */
bridge_config_result_t bridge_config_regenerate_generation(uint32_t *out);
/* New generation, then clear_pending = 1, before the caller starts erasing. */
bridge_config_result_t bridge_config_begin_log_clear(uint32_t *out);
bridge_config_result_t bridge_config_finish_log_clear(void);

/* Clock anchor (log namespace). A valid clock must have a non-zero anchor. */
bridge_config_result_t bridge_config_clock_get(uint64_t *anchor_s, bool *valid);
bridge_config_result_t bridge_config_clock_set(uint64_t anchor_s, bool valid);

/* The full {unix_s, uptime_s} anchor pair (T20). uptime_s records the device
 * uptime when anchor_s was captured; pass 0 when unknown. clock_get() above
 * reports anchor/valid only; clock_set() above stores uptime_s = 0. */
typedef struct {
    uint64_t anchor_s; /* Unix seconds; 0 = unknown */
    uint64_t uptime_s; /* device uptime at capture; 0 = unknown */
    bool valid;
} bridge_config_clock_t;
bridge_config_result_t bridge_config_clock_get_full(bridge_config_clock_t *out);
bridge_config_result_t bridge_config_clock_set_full(
    const bridge_config_clock_t *clock);

/* Boot counters. */
bridge_config_result_t bridge_config_stats_get(bridge_config_stats_t *out);
bridge_config_result_t bridge_config_stats_note_boot(uint8_t reset_reason);
bridge_config_result_t bridge_config_stats_set_packets_ok(uint32_t count);
bridge_config_result_t bridge_config_stats_set_packets_bad(uint32_t count);

/* Forget phones: clears the NimBLE bond store only. Pairing and log survive. */
bridge_config_result_t bridge_config_clear_bonds(void);

/* The single enumeration of factory-reset work, including the bond clear.
 * Order in the table is the execution order. */
const bridge_config_reset_step_t *bridge_config_factory_reset_steps(
    size_t *count);
bridge_config_result_t bridge_config_factory_reset(void);

/* Test/firmware seams. The bond hook is the only path to NimBLE's store. */
void bridge_config_set_random_source(bridge_config_random_fn fn, void *ctx);
void bridge_config_set_bond_clear_hook(bridge_config_bond_clear_fn fn,
                                       void *ctx);

#ifdef ESP_PLATFORM
#include "esp_err.h"
/* Firmware boot hook: opens NVS, installs esp_random()/NimBLE hooks, loads the
 * store and records this boot in stats. Requires nvs_flash_init(). */
esp_err_t bridge_config_init(void);
#endif

#ifdef __cplusplus
}
#endif

#endif /* SX4_BRIDGE_CONFIG_H */
