idf_component_register(
    SRCS "t09_probe.c"
    INCLUDE_DIRS "."
    REQUIRES bt esp_driver_gpio esp_driver_i2c esp_driver_spi esp_adc
             esp_hw_support esp_timer hal)
