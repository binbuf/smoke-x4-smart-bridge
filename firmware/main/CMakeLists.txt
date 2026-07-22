idf_component_register(
    SRCS "main.c" "boot_seq.c" "double_reset.c" "bench.c"
    INCLUDE_DIRS "."
    PRIV_REQUIRES bridge_event nvs_flash esp_event esp_timer
                  esp_adc esp_wifi esp_netif
                  esp_driver_gpio esp_driver_i2c esp_driver_ledc
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
