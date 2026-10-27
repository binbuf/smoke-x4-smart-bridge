# board - pin definitions, battery ADC, Vext and watchdogs (T22/T24).
# board_battery.c is the pure-C curve/stats half; board_battery_esp.c owns the
# GPIO37/ADC calibration cycle.
idf_component_register(
    SRCS "board.c" "board_battery.c" "board_battery_esp.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common
    PRIV_REQUIRES esp_adc esp_driver_gpio esp_hw_support esp_rom freertos log
)
