# Local override of ESP-IDF's esp_wifi component for the BLE-only image.
#
# ESP-IDF 6's bt component lists esp_wifi in REQUIRES, and esp_wifi's hidden
# CONFIG_ESP_WIFI_ENABLED symbol has no prompt and defaults to y on ESP32-S3, so
# it cannot be turned off from sdkconfig.defaults. Compiling the real component
# pulls wpa_supplicant, lwip and esp_netif into the image even though the bridge
# never initialises Wi-Fi (ADR 0034).
#
# The BLE controller needs the esp_wifi headers (esp_wifi.h/esp_wifi_types.h)
# but does not call any esp_wifi_* function. This override keeps the headers
# available and builds no Wi-Fi source. Adding any Wi-Fi call later will fail at
# link time, which is the intended boundary.
idf_component_register(
    SRCS "esp_wifi_stub.c"
    INCLUDE_DIRS
        "${IDF_PATH}/components/esp_wifi/include"
        "${IDF_PATH}/components/esp_wifi/include/local"
        "${IDF_PATH}/components/esp_wifi/wifi_apps/nan_app/include"
    REQUIRES esp_event esp_netif esp_phy esp_coex
)
