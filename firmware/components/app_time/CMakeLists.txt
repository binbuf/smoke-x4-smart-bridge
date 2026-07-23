idf_component_register(
    SRCS "app_time.c" "app_time_core.c"
    INCLUDE_DIRS "include"
    PRIV_REQUIRES app_config bridge_event esp_timer
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
