idf_component_register(
    SRCS "cook_store.c" "cook_store_core.c" "cook_ring.c" "cook_lifecycle.c"
         "cook_store_task.c" "cook_novelty_log.c"
    INCLUDE_DIRS "include" "../../../protocol/gen"
    PRIV_REQUIRES app_config app_time bridge_event esp_timer
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
