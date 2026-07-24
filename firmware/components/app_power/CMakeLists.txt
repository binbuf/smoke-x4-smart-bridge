idf_component_register(
    SRCS "app_power.c" "power_core.c" "power_svc.c"
    INCLUDE_DIRS "include" "../../../protocol/gen"
    PRIV_REQUIRES app_config bridge_event cook_store esp_adc esp_driver_gpio
                  esp_timer esp_rom
)

# Our code builds warning-clean; IDF components are not our battle.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
