# sx_radio - SX1262 wrapper and pairing state machine (T12/T13/T16).
# Stub only in T04.
idf_component_register(
    SRCS "sx_radio.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common
    PRIV_REQUIRES log
)
