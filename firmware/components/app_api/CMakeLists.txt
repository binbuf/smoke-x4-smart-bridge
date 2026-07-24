idf_component_register(
    SRCS "app_api.c" "app_api_core.c" "app_api_sessions.c" "app_api_emit.c"
         "app_api_ws.c"
    INCLUDE_DIRS "include"
    PRIV_REQUIRES app_alarm app_power app_ble app_config app_net app_time cook_store smoke_x
                  bridge_event esp_http_server esp_timer espcoredump
                  esp_hw_support
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
