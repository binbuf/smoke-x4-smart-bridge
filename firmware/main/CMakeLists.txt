idf_component_register(
    SRCS "main.c" "boot.c" "tasks.c" "housekeeping.c"
    INCLUDE_DIRS "."
    REQUIRES
        board
        ble_service
        bridge_config
        bridge_state
        esp_timer
        espcoredump
        nvs_flash
        sample_log
        sample_pipe
        sx_protocol
        sx_radio
        ui
)
