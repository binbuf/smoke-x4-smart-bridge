idf_component_register(
    SRCS "app_net.c" "app_net_core.c" "dns_shim.c" "app_net_txt.c"
    # record_gen.h: app_net_get_wire_status speaks the BLE wire enums
    # (F10.6) so app_ble never parses a status string.
    INCLUDE_DIRS "include" "../../../protocol/gen"
    PRIV_REQUIRES esp_app_format app_config bridge_event esp_wifi esp_netif esp_event
                  esp_timer lwip
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
