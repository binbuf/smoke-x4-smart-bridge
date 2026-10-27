/*
 * sample_log.c - firmware singleton over the raw-partition adapter (T19).
 *
 * Boot calls sample_log_init() (design 03 section 3.4 step 5). The writer uses
 * sample_log_append(); the UI/stats read the storage state. All storage work
 * happens in log_flash_core.c/log_flash.c; this file only owns the instance.
 */

#include "sample_log.h"

#include <string.h>

#include "esp_log.h"
#include "log_flash.h"

static const char *TAG = "sx4.log";

static log_flash_t s_flash;

esp_err_t sample_log_init(void) {
    memset(&s_flash, 0, sizeof s_flash);
    const esp_err_t err = log_flash_open_partition(&s_flash);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "storage unavailable (%s); live readings only",
                 esp_err_to_name(err));
    }
    return err;
}

bool sample_log_ready(void) { return s_flash.ready; }

sample_log_storage_state_t sample_log_storage_state(void) {
    return s_flash.storage;
}

bool sample_log_storage_ok(void) {
    return s_flash.storage != SAMPLE_LOG_STORAGE_READ_ONLY;
}

esp_err_t sample_log_append(sx4_sample_rec_t *rec) {
    if (rec == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    const sample_log_status_t status = log_flash_append(&s_flash, rec);
    switch (status) {
        case SAMPLE_LOG_OK:
            return ESP_OK;
        case SAMPLE_LOG_ERR_IO:
            ESP_LOGE(TAG, "write failed; storage is READ_ONLY until reboot");
            return ESP_FAIL;
        case SAMPLE_LOG_ERR_STATE:
            return ESP_ERR_INVALID_STATE;
        case SAMPLE_LOG_ERR_ARGUMENT:
        case SAMPLE_LOG_ERR_SIZE:
        case SAMPLE_LOG_ERR_LAYOUT:
            return ESP_ERR_INVALID_ARG;
        case SAMPLE_LOG_ERR_CRC:
        case SAMPLE_LOG_ERR_RANGE:
            break;
    }
    return ESP_ERR_INVALID_STATE;
}

esp_err_t sample_log_read_seq(uint32_t seq, sx4_sample_rec_t *out) {
    if (out == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    const sample_log_status_t status = log_flash_read_seq(&s_flash, seq, out);
    switch (status) {
        case SAMPLE_LOG_OK:
            return ESP_OK;
        case SAMPLE_LOG_ERR_IO:
            return ESP_FAIL;
        case SAMPLE_LOG_ERR_RANGE:
            return ESP_ERR_NOT_FOUND;
        case SAMPLE_LOG_ERR_CRC:
        case SAMPLE_LOG_ERR_LAYOUT:
            return ESP_ERR_INVALID_CRC;
        case SAMPLE_LOG_ERR_ARGUMENT:
            return ESP_ERR_INVALID_ARG;
        case SAMPLE_LOG_ERR_STATE:
        case SAMPLE_LOG_ERR_SIZE:
            break;
    }
    return ESP_ERR_INVALID_STATE;
}

bool sample_log_get_info(log_ring_info_t *out) {
    return log_flash_info(&s_flash, out);
}

uint32_t sample_log_recovery_ms(void) { return s_flash.recovery_ms; }

uint32_t sample_log_cleared_sectors(void) { return s_flash.erased_sectors; }
