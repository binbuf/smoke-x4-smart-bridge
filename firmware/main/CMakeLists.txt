idf_component_register(
    SRCS "main.c" "boot_seq.c" "double_reset.c" "bench.c"
    INCLUDE_DIRS "."
    PRIV_REQUIRES bridge_event nvs_flash esp_event esp_timer
                  driver esp_adc esp_wifi esp_netif
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
