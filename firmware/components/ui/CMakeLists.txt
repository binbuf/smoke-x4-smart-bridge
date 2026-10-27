# ui - SSD1306 driver, pages, button and display power (T22/T23).
# Stub only in T04.
idf_component_register(
    SRCS "ui.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_common
    PRIV_REQUIRES log
)
