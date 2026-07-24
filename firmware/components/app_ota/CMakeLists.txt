idf_component_register(
    SRCS "app_ota.c" "ota_core.c" "ota_gate.c" "ota_image.c"
    INCLUDE_DIRS "include"
    PRIV_REQUIRES app_update esp_timer esp_system
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
