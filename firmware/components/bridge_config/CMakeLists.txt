# bridge_config - typed, validated NVS config (T15).
# bridge_config.c is plain C11 (host-testable); bridge_config_nvs.c is the
# ESP-IDF adapter and the only file that opens NVS.
idf_component_register(
    SRCS "bridge_config.c" "bridge_config_nvs.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common
    PRIV_REQUIRES log nvs_flash esp_hw_support esp_system bt
)
