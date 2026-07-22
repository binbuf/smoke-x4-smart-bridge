idf_component_register(
    SRCS "app_config.c" "app_config_store.c"
    INCLUDE_DIRS "include"
    PRIV_REQUIRES nvs_flash esp_hw_support
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
