# app_lora wraps the vendored ra01s driver. The submodule stays pristine:
# its source compiles INTO this component, with IDF-v6-correct requirements
# declared here instead of patching the vendor CMakeLists (F2.1).
set(RA01S_DIR ${CMAKE_CURRENT_LIST_DIR}/../../vendor/esp-idf-sx126x/components/ra01s)

idf_component_register(
    SRCS "app_lora.c" "app_lora_core.c" "${RA01S_DIR}/ra01s.c"
    INCLUDE_DIRS "include" "${RA01S_DIR}"
    REQUIRES esp_driver_spi esp_driver_gpio
    PRIV_REQUIRES esp_timer
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
# Vendored code is not our -Werror battle.
set_source_files_properties(${RA01S_DIR}/ra01s.c
    PROPERTIES COMPILE_OPTIONS "-w")
