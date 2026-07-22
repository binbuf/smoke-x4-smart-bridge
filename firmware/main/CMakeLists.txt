idf_component_register(
    SRCS "main.c" "boot_seq.c" "double_reset.c"
    INCLUDE_DIRS "."
    PRIV_REQUIRES bridge_event nvs_flash esp_event esp_timer
)
