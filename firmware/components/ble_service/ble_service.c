#include "ble_service.h"

#include "esp_log.h"

static const char *TAG = "sx4.ble";

esp_err_t ble_service_start(void) {
    ESP_LOGD(TAG, "stub start");
    return ESP_OK;
}

esp_err_t ble_service_stop(void) {
    /* T27/T30 replace this with advertising stop, disconnect and
     * nimble_port_deinit(). The power-off path only needs the seam now. */
    ESP_LOGD(TAG, "stub stop");
    return ESP_OK;
}
