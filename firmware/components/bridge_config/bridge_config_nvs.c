/*
 * bridge_config_nvs.c - the ESP-IDF adapter and the only code in the firmware
 * that opens NVS (design 03 section 3.1). It wraps bytes in NVS blobs and
 * installs esp_random() plus the one documented foreign namespace hook:
 * NimBLE's bond store, cleared via ble_store_clear() and never opened here.
 */
#include "bridge_config.h"

#include "esp_err.h"
#include "esp_log.h"
#include "esp_random.h"
#include "esp_system.h"
#include "nvs.h"

#if defined(CONFIG_BT_NIMBLE_ENABLED)
#include "host/ble_store.h"
#endif

static const char *TAG = "sx4.config";

/* ---- NVS byte/blob backend ---------------------------------------------- */

static int nvs_get_blob_iface(void *ctx, const char *ns, const char *key,
                              void *dst, size_t *len) {
    (void)ctx;
    if (ns == NULL || key == NULL || len == NULL || dst == NULL) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    nvs_handle_t handle;
    esp_err_t err = nvs_open(ns, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return BRIDGE_CONFIG_ERR_NOT_FOUND;
    }
    if (err != ESP_OK) {
        return BRIDGE_CONFIG_ERR_IO;
    }
    size_t size = 0;
    err = nvs_get_blob(handle, key, NULL, &size);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        nvs_close(handle);
        return BRIDGE_CONFIG_ERR_NOT_FOUND;
    }
    if (err != ESP_OK) {
        nvs_close(handle);
        return BRIDGE_CONFIG_ERR_IO;
    }
    if (size > *len) {
        nvs_close(handle);
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    if (size != 0) {
        err = nvs_get_blob(handle, key, dst, &size);
    }
    nvs_close(handle);
    if (err != ESP_OK) {
        return BRIDGE_CONFIG_ERR_IO;
    }
    *len = size;
    return BRIDGE_CONFIG_OK;
}

static int nvs_set_blob_iface(void *ctx, const char *ns, const char *key,
                              const void *src, size_t len) {
    (void)ctx;
    if (ns == NULL || key == NULL || (src == NULL && len != 0)) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    nvs_handle_t handle;
    esp_err_t err = nvs_open(ns, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        return BRIDGE_CONFIG_ERR_IO;
    }
    err = nvs_set_blob(handle, key, src, len);
    if (err == ESP_OK) {
        err = nvs_commit(handle);
    }
    nvs_close(handle);
    return err == ESP_OK ? BRIDGE_CONFIG_OK : BRIDGE_CONFIG_ERR_IO;
}

static int nvs_erase_key_iface(void *ctx, const char *ns, const char *key) {
    (void)ctx;
    if (ns == NULL || key == NULL) {
        return BRIDGE_CONFIG_ERR_INVALID;
    }
    nvs_handle_t handle;
    esp_err_t err = nvs_open(ns, NVS_READWRITE, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return BRIDGE_CONFIG_ERR_NOT_FOUND;
    }
    if (err != ESP_OK) {
        return BRIDGE_CONFIG_ERR_IO;
    }
    err = nvs_erase_key(handle, key);
    if (err == ESP_OK) {
        err = nvs_commit(handle);
    }
    nvs_close(handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return BRIDGE_CONFIG_ERR_NOT_FOUND;
    }
    return err == ESP_OK ? BRIDGE_CONFIG_OK : BRIDGE_CONFIG_ERR_IO;
}

static const bridge_config_kv_ops_t kNvsOps = {
    .get = nvs_get_blob_iface,
    .set = nvs_set_blob_iface,
    .erase = nvs_erase_key_iface,
};

/* ---- foreign namespace: NimBLE bonds ------------------------------------ */

static int esp_bond_store_clear(void *ctx) {
    (void)ctx;
#if defined(CONFIG_BT_NIMBLE_ENABLED)
    return ble_store_clear() == 0 ? 0 : -1;
#else
    /* NimBLE is not part of the image yet (T27/T30). There are no bonds. */
    ESP_LOGD(TAG, "bond store clear skipped: NimBLE not linked");
    return 0;
#endif
}

static uint32_t esp_random_wrapper(void *ctx) {
    (void)ctx;
    return esp_random();
}

esp_err_t bridge_config_init(void) {
    bridge_config_kv_t kv = {.ops = &kNvsOps, .ctx = NULL};
    bridge_config_set_random_source(esp_random_wrapper, NULL);
    bridge_config_set_bond_clear_hook(esp_bond_store_clear, NULL);

    bridge_config_result_t rc = bridge_config_core_init(&kv);
    switch (rc) {
    case BRIDGE_CONFIG_OK:
        break;
    case BRIDGE_CONFIG_ERR_VERSION:
        ESP_LOGE(TAG, "NVS layout is newer than this firmware");
        return ESP_ERR_NOT_SUPPORTED;
    case BRIDGE_CONFIG_ERR_INVALID:
        return ESP_ERR_INVALID_ARG;
    case BRIDGE_CONFIG_ERR_IO:
        return ESP_FAIL;
    default:
        return ESP_ERR_INVALID_STATE;
    }

    /* Every successful boot is counted once, with the reset reason. */
    if (bridge_config_stats_note_boot((uint8_t)esp_reset_reason()) !=
        BRIDGE_CONFIG_OK) {
        ESP_LOGW(TAG, "could not persist boot counters");
    }
    ESP_LOGI(TAG, "loaded: version %u", BRIDGE_CONFIG_VERSION);
    return ESP_OK;
}
