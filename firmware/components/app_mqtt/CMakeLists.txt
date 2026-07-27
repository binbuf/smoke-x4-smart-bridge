idf_component_register(
    SRCS "app_mqtt.c" "app_mqtt_core.c"
    INCLUDE_DIRS "include" "../../../protocol/gen"
    PRIV_REQUIRES app_config app_net bridge_event mqtt esp_wifi
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
