/* app_config — ESP-IDF binding for the typed store (design 03 §3.6).
 * Everything interesting lives in app_config_store.c, which is host-tested;
 * this file only supplies the NVS backend and the hardware RNG. */
#include "app_config.h"

#include "app_config_store.h"
#include "esp_random.h"
#include "nvs.h"
#include "nvs_flash.h"

static int map_err(esp_err_t err) {
    switch (err) {
        case ESP_OK:
            return APP_CONFIG_OK;
        case ESP_ERR_NVS_NOT_FOUND:
            return APP_CONFIG_ERR_NOT_FOUND;
        default:
            return APP_CONFIG_ERR;
    }
}

static int nvs_backend_get(void *ctx, const char *ns, const char *key,
                           void *out, size_t *len) {
    (void)ctx;
    nvs_handle_t h;
    esp_err_t err = nvs_open(ns, NVS_READONLY, &h);
    if (err != ESP_OK) {
        /* An untouched namespace does not exist yet — that is "unset". */
        return map_err(err);
    }
    err = nvs_get_blob(h, key, out, len);
    nvs_close(h);
    return map_err(err);
}

static int nvs_backend_set(void *ctx, const char *ns, const char *key,
                           const void *val, size_t len) {
    (void)ctx;
    nvs_handle_t h;
    esp_err_t err = nvs_open(ns, NVS_READWRITE, &h);
    if (err != ESP_OK) {
        return map_err(err);
    }
    err = nvs_set_blob(h, key, val, len);
    if (err == ESP_OK) {
        err = nvs_commit(h);
    }
    nvs_close(h);
    return map_err(err);
}

static int nvs_backend_erase_all(void *ctx) {
    (void)ctx;
    /* Factory reset erases the whole NVS partition — pairing, network,
     * probe names, everything (F11 reboots immediately after). */
    nvs_flash_deinit();
    esp_err_t err = nvs_flash_erase();
    if (err != ESP_OK) {
        return APP_CONFIG_ERR;
    }
    return map_err(nvs_flash_init());
}

static const app_config_backend_t k_nvs_backend = {
    .get = nvs_backend_get,
    .set = nvs_backend_set,
    .erase_all = nvs_backend_erase_all,
    .ctx = NULL,
};

int app_config_init(void) {
    return app_config_store_init(&k_nvs_backend, esp_random);
}
