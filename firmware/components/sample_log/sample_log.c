#include "sample_log.h"

#include "esp_log.h"

static const char *TAG = "sx4.log";

esp_err_t sample_log_init(void) {
    ESP_LOGD(TAG, "stub init");
    return ESP_OK;
}
