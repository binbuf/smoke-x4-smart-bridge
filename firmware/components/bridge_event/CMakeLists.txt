idf_component_register(
    SRCS "bridge_event.c" "bridge_event_guard.c"
    INCLUDE_DIRS "include"
    PRIV_REQUIRES esp_event esp_timer
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
