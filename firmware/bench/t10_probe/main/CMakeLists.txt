idf_component_register(
    SRCS "t10_probe.c"
    INCLUDE_DIRS "."
    REQUIRES ra01s esp_driver_gpio esp_timer)
