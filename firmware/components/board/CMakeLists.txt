# board - pin definitions, battery ADC, Vext and watchdogs (T24).
# Stub only in T04.
idf_component_register(
    SRCS "board.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common
    PRIV_REQUIRES log
)
