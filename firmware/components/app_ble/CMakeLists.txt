# app_ble — the Bridge Control Service. The core (registry, security
# table, builders, chunker, write dispatch) is ESP-IDF-free and compiled
# into the host suite too; app_ble.c is the NimBLE-only half.
idf_component_register(
    SRCS "app_ble.c" "app_ble_core.c" "app_ble_ctrl.c" "app_ble_adv.c"
    INCLUDE_DIRS "include" "../../../protocol/gen"
    PRIV_REQUIRES app_alarm app_power app_config app_net app_time cook_store smoke_x
                  bridge_event bt esp_wifi esp_event esp_timer
                  esp_app_format
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
