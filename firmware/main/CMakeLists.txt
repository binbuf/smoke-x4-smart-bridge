idf_component_register(
    SRCS "main.c" "boot_seq.c" "double_reset.c" "bench.c"
    INCLUDE_DIRS "."
    PRIV_REQUIRES app_api app_config app_net app_time cook_store smoke_x
                  bridge_event nvs_flash esp_event esp_timer
                  esp_adc esp_wifi esp_netif
                  esp_driver_gpio esp_driver_i2c esp_driver_ledc
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
