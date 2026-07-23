idf_component_register(
    SRCS "app_net.c" "app_net_core.c"
    INCLUDE_DIRS "include"
    PRIV_REQUIRES app_config
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
