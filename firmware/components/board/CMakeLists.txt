# board - pin definitions, battery ADC, Vext and watchdogs (T22/T24).
idf_component_register(
    SRCS "board.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common
    PRIV_REQUIRES esp_driver_gpio esp_hw_support freertos log
)
