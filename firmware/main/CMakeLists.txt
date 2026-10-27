idf_component_register(
    SRCS "main.c" "boot.c" "tasks.c"
    INCLUDE_DIRS "."
    REQUIRES
        board
        ble_service
        bridge_config
        bridge_state
        espcoredump
        nvs_flash
        sample_log
        sx_protocol
        sx_radio
        ui
)
