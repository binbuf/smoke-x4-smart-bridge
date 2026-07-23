idf_component_register(
    SRCS "cook_store.c" "cook_store_core.c" "cook_ring.c" "cook_lifecycle.c"
    INCLUDE_DIRS "include" "../../../protocol/gen"
    PRIV_REQUIRES app_config
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
