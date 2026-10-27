# sample_pipe - parser -> record -> log queue -> live snapshot (T21).
# sample_pipe.c is plain C11 (host-testable); sample_pipe_esp.c owns the static
# FreeRTOS queue, the sample_pipe task and the log_writer task.
idf_component_register(
    SRCS "sample_pipe.c" "sample_pipe_esp.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common bridge_state sample_log sx_protocol
    PRIV_REQUIRES bridge_config esp_timer freertos log sx_radio ui
)
