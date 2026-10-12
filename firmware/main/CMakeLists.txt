idf_component_register(
    SRCS "main.c" "boot_seq.c"
    INCLUDE_DIRS "."
    PRIV_REQUIRES app_ble app_config app_power app_time app_ui
                  cook_store smoke_x
                  bridge_event nvs_flash esp_event esp_timer
                  esp_driver_gpio esp_driver_i2c esp_driver_ledc
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)