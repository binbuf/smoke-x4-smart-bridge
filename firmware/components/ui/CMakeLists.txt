# ui - SSD1306 driver, pure page renderer and display power (T22/T23).
idf_component_register(
    SRCS "ui.c" "ui_render.c" "ui_sleep.c" "ssd1306_core.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common
    PRIV_REQUIRES
        board
        bridge_config
        bridge_state
        sample_log
        esp_driver_gpio
        esp_driver_i2c
        esp_timer
        freertos
        log
)
