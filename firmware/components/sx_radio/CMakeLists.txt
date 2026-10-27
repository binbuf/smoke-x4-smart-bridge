# sx_radio - SX1262 wrapper, RX task and pairing state machine (T12/T13/T16).
# sx_radio_rx.c is pure C so the host suite can exercise the parser seam.
idf_component_register(
    SRCS "sx_radio.c" "sx_radio_rx.c" "sx_radio_pair.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common ra01s
    PRIV_REQUIRES bridge_config sx_protocol esp_timer freertos log
)
