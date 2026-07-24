idf_component_register(
    SRCS "app_alarm.c" "app_alarm_svc.c" "alarm_cfg.c" "rules.c"
         "alarm_lid.c" "alarm_engine.c"
    INCLUDE_DIRS "include" "../../../protocol/gen"
    PRIV_REQUIRES app_config app_ota cook_store smoke_x bridge_event esp_timer
                  espcoredump
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
