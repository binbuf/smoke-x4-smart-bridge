idf_component_register(
    SRCS "app_net.c" "app_net_core.c" "dns_shim.c" "app_net_txt.c"
    INCLUDE_DIRS "include"
    PRIV_REQUIRES app_config bridge_event esp_wifi esp_netif esp_event
                  esp_timer lwip
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
